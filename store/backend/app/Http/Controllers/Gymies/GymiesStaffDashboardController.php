<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Services\FraudDetectionService;
use App\Services\InvitationCodeService;
use App\Services\OnboardingService;
use App\Services\TrialExtensionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Gymies Staff Dashboard Controller
 * ──────────────────────────────────
 * Endpoints voor het medewerkers dashboard.
 * Alle endpoints vereisen staff role.
 *
 * API Response Convention: {success?: bool, message?: string, data?: mixed}
 *
 * Routes:
 * GET    /staff/dashboard           → dashboard stats
 * GET    /staff/pending-reviews     → trainers wachtend op review
 * POST   /staff/review/{trainerId}  → trainer goedkeuren/afwijzen
 * GET    /staff/trials              → trial overzicht
 * POST   /staff/trials/{id}/extend  → trial verlengen
 * GET    /staff/audit-log           → audit trail
 * GET    /staff/invitation-codes    → codes overzicht
 * POST   /staff/invitation-codes    → nieuwe code aanmaken
 * DELETE /staff/invitation-codes/{id} → code deactiveren
 */
final class GymiesStaffDashboardController extends Controller
{
    use GymiesAuditTrait;

    /**
     * Dashboard statistieken voor staff.
     */
    public function dashboard(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $stats = [
            'pending_reviews' => 0,
            'active_trainers' => 0,
            'trials_expiring_soon' => 0,
            'suspended_trainers' => 0,
            'invitation_codes_active' => 0,
        ];

        if (Schema::hasTable('gymies_trainer_profiles')) {
            $stats['pending_reviews'] = (int) DB::table('gymies_trainer_profiles')
                ->where('onboarding_status', 'pending_review')
                ->count();

            $stats['active_trainers'] = (int) DB::table('gymies_trainer_profiles')
                ->where('onboarding_status', 'active')
                ->count();

            $stats['suspended_trainers'] = (int) DB::table('gymies_trainer_profiles')
                ->where('onboarding_status', 'suspended')
                ->count();

            $stats['trials_expiring_soon'] = (int) DB::table('gymies_trainer_profiles')
                ->whereNotNull('trial_ends_at')
                ->where('trial_ends_at', '<=', now()->addDays(7))
                ->where('trial_ends_at', '>', now())
                ->whereIn('onboarding_status', ['approved', 'active'])
                ->count();
        }

        if (Schema::hasTable('gymies_invitation_codes')) {
            $stats['invitation_codes_active'] = (int) DB::table('gymies_invitation_codes')
                ->where('is_active', true)
                ->count();
        }

        if (Schema::hasTable('gymies_support_tickets')) {
            $stats['open_tickets'] = (int) DB::table('gymies_support_tickets')
                ->whereIn('status', ['new', 'in_progress'])
                ->count();
        }

        return response()->json(['data' => $stats]);
    }

    /**
     * Trainers wachtend op review.
     */
    public function pendingReviews(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $page = max(1, (int) $request->query('page', 1));
        $perPage = max(5, min(100, (int) $request->input('per_page', 20)));

        $query = DB::table('gymies_trainer_profiles')
            ->where('onboarding_status', 'pending_review')
            ->orderBy('updated_at');

        $total = $query->count();
        $trainers = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        // Verrijk met user gegevens
        $enriched = $trainers->map(function ($trainer) {
            $user = DB::table('gymies_users')->where('id', $trainer->user_id ?? 0)->first();
            $trainer->user_name = $user ? trim((($user->first_name ?? '') . ' ' . ($user->last_name ?? '')) ?: '') : '';
            $trainer->user_email = $user ? ($user->email ?? '') : '';
            $trainer->submitted_at = $trainer->updated_at;
            return $trainer;
        });

        return response()->json([
            'data'     => $enriched,
            'total'    => $total,
            'page'     => $page,
            'per_page' => $perPage,
        ]);
    }

    /**
     * Trainer goedkeuren of afwijzen.
     */
    public function reviewTrainer(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $action = $request->input('action'); // 'approve' of 'reject'
        $reason = $request->input('reason', '');

        if (!in_array($action, ['approve', 'reject'], true)) {
            return response()->json(['message' => 'Actie moet "approve" of "reject" zijn.'], 422);
        }

        $id = (int) $trainerId;
        if ($id <= 0) {
            return response()->json(['message' => 'Ongeldig trainer ID.'], 422);
        }

        if ($action === 'approve') {
            $result = OnboardingService::approve($id, (int) $staff->id, $reason ?: null);
        } else {
            if (empty($reason)) {
                return response()->json(['message' => 'Reden is verplicht bij afwijzing.'], 422);
            }
            $result = OnboardingService::reject($id, (int) $staff->id, $reason);
        }

        if (!($result['success'] ?? false)) {
            return response()->json(['message' => $result['error'] ?? 'Actie mislukt.'], 422);
        }

        return response()->json(['data' => $result]);
    }

    /**
     * Trainer schorsen.
     */
    public function suspendTrainer(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $reason = $request->input('reason', '');
        if (empty($reason)) {
            return response()->json(['message' => 'Reden is verplicht bij schorsing.'], 422);
        }

        $result = OnboardingService::suspend((int) $trainerId, (int) $staff->id, $reason);

        if (!($result['success'] ?? false)) {
            return response()->json(['message' => $result['error'] ?? 'Schorsing mislukt.'], 422);
        }

        return response()->json(['data' => $result]);
    }

    /**
     * Trainer heractiveren.
     */
    public function reactivateTrainer(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $reason = $request->input('reason', '');
        $result = OnboardingService::reactivate((int) $trainerId, (int) $staff->id, $reason ?: null);

        if (!($result['success'] ?? false)) {
            return response()->json(['message' => $result['error'] ?? 'Heractivatie mislukt.'], 422);
        }

        return response()->json(['data' => $result]);
    }

    /**
     * Trial overzicht (alle trainers met trials).
     */
    public function trialOverview(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $page = max(1, (int) $request->query('page', 1));
        $perPage = min(50, max(1, (int) $request->query('per_page', 25)));

        $data = TrialExtensionService::trialOverview($page, $perPage);

        return response()->json($data);
    }

    /**
     * Trial verlengen.
     */
    public function extendTrial(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $days = (int) $request->input('days', 0);
        $reason = $request->input('reason', '');

        if (!in_array($days, [7, 14, 30], true)) {
            return response()->json(['message' => 'Kies 7, 14 of 30 dagen.'], 422);
        }

        $result = TrialExtensionService::extend((int) $trainerId, (int) $staff->id, $days, $reason ?: null);

        if (!($result['success'] ?? false)) {
            return response()->json(['message' => $result['error'] ?? 'Verlenging mislukt.'], 422);
        }

        return response()->json(['data' => $result]);
    }

    /**
     * Check of trial verlengd kan worden + activity score.
     */
    public function trialExtendability(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $data = TrialExtensionService::canExtend((int) $trainerId);

        return response()->json(['data' => $data]);
    }

    /**
     * Audit log.
     */
    public function auditLog(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_staff_audit_log')) {
            return response()->json(['data' => [], 'total' => 0]);
        }

        $page = max(1, (int) $request->query('page', 1));
        $perPage = min(100, max(1, (int) $request->query('per_page', 50)));
        $action = $request->query('action');
        $staffFilter = $request->query('staff_id');

        $query = DB::table('gymies_staff_audit_log')
            ->orderByDesc('created_at');

        if ($action) {
            $actionEscaped = str_replace(['%', '_'], ['\%', '\_'], $action);
            $query->where('action', 'like', $actionEscaped . '%');
        }
        if ($staffFilter) {
            $query->where('staff_id', (int) $staffFilter);
        }

        $total = $query->count();
        $data = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        // Decode metadata JSON
        $data = $data->map(function ($row) {
            $row->metadata = json_decode($row->metadata ?? '{}', true);
            // Verrijk met staff naam
            $staffUser = DB::table('gymies_users')->where('id', $row->staff_id)->first();
            $row->staff_name = $staffUser ? trim((($staffUser->first_name ?? '') . ' ' . ($staffUser->last_name ?? '')) ?: '') : '';
            return $row;
        });

        return response()->json([
            'data'     => $data,
            'total'    => $total,
            'page'     => $page,
            'per_page' => $perPage,
        ]);
    }

    /**
     * Uitnodigingscodes overzicht.
     */
    public function invitationCodes(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $page = max(1, (int) $request->query('page', 1));
        $perPage = min(50, max(1, (int) $request->query('per_page', 25)));
        $source = $request->query('source');

        $data = InvitationCodeService::list($page, $perPage, $source);

        return response()->json($data);
    }

    /**
     * Nieuwe uitnodigingscode aanmaken.
     */
    public function createInvitationCode(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $source = $request->input('source', 'staff');
        $maxUses = max(1, (int) $request->input('max_uses', 1));
        $expiryDays = $request->input('expiry_days') ? (int) $request->input('expiry_days') : null;

        if (!in_array($source, ['staff', 'promo', 'partner'], true)) {
            return response()->json(['message' => 'Ongeldige bron. Kies: staff, promo, partner.'], 422);
        }

        $result = InvitationCodeService::generate(
            createdBy: (int) $staff->id,
            source: $source,
            maxUses: $maxUses,
            expiryDays: $expiryDays
        );

        if (!($result['success'] ?? false)) {
            return response()->json(['message' => $result['error'] ?? 'Aanmaken mislukt.'], 422);
        }

        return response()->json(['data' => $result], 201);
    }

    /**
     * Uitnodigingscode deactiveren.
     */
    public function deactivateInvitationCode(Request $request, string $codeId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $result = InvitationCodeService::deactivate((int) $codeId, (int) $staff->id);

        if (!($result['success'] ?? false)) {
            return response()->json(['message' => 'Deactiveren mislukt.'], 422);
        }

        return response()->json(['data' => ['deactivated' => true]]);
    }

    // ─── Fraud Detection ─────────────────────────────────────────

    /**
     * Fraud check uitvoeren voor een specifieke trainer.
     */
    public function fraudCheck(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $id = (int) $trainerId;
        if ($id <= 0) {
            return response()->json(['message' => 'Ongeldig trainer ID.'], 422);
        }

        $result = FraudDetectionService::check($id);

        // Audit trail
        if (Schema::hasTable('gymies_staff_audit_log')) {
            DB::table('gymies_staff_audit_log')->insert([
                'staff_id'    => $staff->id,
                'action'      => 'fraud.manual_check',
                'target_type' => 'TrainerProfile',
                'target_id'   => $id,
                'metadata'    => json_encode([
                    'risk_level' => $result['risk_level'] ?? 'unknown',
                    'blocks'     => count($result['blocks'] ?? []),
                    'warnings'   => count($result['warnings'] ?? []),
                ]),
                'ip_address'  => $request->ip(),
                'created_at'  => now(),
                'updated_at'  => now(),
            ]);
        }

        return response()->json(['data' => $result]);
    }

    // ─── Feature Flags Beheer ───────────────────────────────────

    /**
     * Alle feature flags ophalen (voor staff dashboard).
     */
    public function featureFlags(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $flags = GymiesFeatureFlags::allDetailed();

        // Groepeer per categorie
        $grouped = [];
        foreach ($flags as $flag) {
            $cat = $flag['category'] ?? 'general';
            $grouped[$cat][] = $flag;
        }

        return response()->json([
            'data'    => $flags,
            'grouped' => $grouped,
        ]);
    }

    /**
     * Feature flag updaten (enabled/value).
     */
    public function updateFeatureFlag(Request $request, string $key): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        // Alleen admin mag flags wijzigen
        $role = $staff->role ?? '';
        if ($role !== 'admin') {
            return response()->json(['message' => 'Alleen admins mogen feature flags wijzigen.'], 403);
        }

        $data = [];

        if ($request->has('enabled')) {
            $data['enabled'] = (bool) $request->input('enabled');
        }
        if ($request->has('value')) {
            $data['value'] = $request->input('value');
        }
        if ($request->has('rollout_percentage')) {
            $pct = (float) $request->input('rollout_percentage');
            $data['rollout_percentage'] = max(0, min(100, $pct));
        }

        if (empty($data)) {
            return response()->json(['message' => 'Geen wijzigingen opgegeven.'], 422);
        }

        $success = GymiesFeatureFlags::update($key, $data);
        if (!$success) {
            return response()->json(['message' => 'Flag niet gevonden of update mislukt.'], 404);
        }

        // Audit trail
        if (Schema::hasTable('gymies_staff_audit_log')) {
            DB::table('gymies_staff_audit_log')->insert([
                'staff_id'    => $staff->id,
                'action'      => 'feature_flag.updated',
                'target_type' => 'FeatureFlag',
                'target_id'   => 0,
                'metadata'    => json_encode([
                    'key'     => $key,
                    'changes' => $data,
                ]),
                'ip_address'  => $request->ip(),
                'created_at'  => now(),
                'updated_at'  => now(),
            ]);
        }

        return response()->json(['data' => ['updated' => true, 'key' => $key]]);
    }

    // ─── Support Ticket Beheer ──────────────────────────────────

    /**
     * Support tickets lijst met filters, zoeken, sortering en paginatie.
     *
     * Query params:
     *   status          - filter op status (new, in_progress, waiting_customer, resolved)
     *   priority        - filter op prioriteit (low, medium, high, critical)
     *   category        - filter op categorie
     *   q               - zoek in subject, email, naam, berichten
     *   assigned_to_me  - boolean, alleen mijn tickets
     *   sort            - created_at_desc (default), created_at_asc, priority, status, updated
     *   page / per_page - paginatie
     */
    public function staffTickets(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['data' => [], 'total' => 0, 'page' => 1, 'per_page' => 25]);
        }

        $page    = max(1, (int) $request->query('page', 1));
        $perPage = min(50, max(1, (int) $request->query('per_page', 25)));
        $status  = trim((string) $request->query('status', ''));
        $priority = trim((string) $request->query('priority', ''));
        $category = trim((string) $request->query('category', ''));
        $q       = trim((string) $request->query('q', ''));
        $qLike   = $q !== '' ? '%' . addcslashes($q, '%_\\') . '%' : '';
        $assignedToMe = filter_var($request->query('assigned_to_me'), FILTER_VALIDATE_BOOLEAN);
        $sortInput = trim((string) $request->query('sort', 'created_at_desc'));

        // Validate sort parameter: only allow whitelisted values
        $allowedSortValues = ['created_at_asc', 'created_at_desc', 'priority', 'status', 'updated'];
        $sort = in_array($sortInput, $allowedSortValues, true) ? $sortInput : 'created_at_desc';

        $select = [
            't.id', 't.user_id', 'u.email as user_email',
            DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as user_name"),
            't.subject', 't.category', 't.priority', 't.status', 't.assigned_to_user_id',
            'a.email as assigned_email',
            DB::raw("CONCAT(COALESCE(a.first_name,''), ' ', COALESCE(a.last_name,'')) as assigned_name"),
            't.created_at', 't.updated_at', 't.resolved_at',
        ];

        if (Schema::hasColumn('gymies_support_tickets', 'close_reason')) {
            $select[] = 't.close_reason';
        }
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $select[] = 't.submitter_name';
            $select[] = 't.submitter_email';
        }

        $query = DB::table('gymies_support_tickets as t')
            ->leftJoin('gymies_users as u', 'u.id', '=', 't.user_id')
            ->leftJoin('gymies_users as a', 'a.id', '=', 't.assigned_to_user_id')
            ->select($select);

        // Filters
        if ($status !== '') {
            $query->where('t.status', $status);
        }
        if ($priority !== '') {
            $query->where('t.priority', $priority);
        }
        if ($category !== '') {
            $query->where('t.category', $category);
        }
        if ($assignedToMe) {
            $query->where('t.assigned_to_user_id', (int) $staff->id);
        }

        // Zoeken in subject, email, naam, berichten
        if ($qLike !== '') {
            $ticketIdsFromMessages = [];
            if (Schema::hasTable('gymies_support_ticket_messages')) {
                $ticketIdsFromMessages = DB::table('gymies_support_ticket_messages')
                    ->where('message', 'like', $qLike)
                    ->pluck('ticket_id')
                    ->unique()
                    ->values()
                    ->all();
            }
            $query->where(function ($w) use ($qLike, $ticketIdsFromMessages): void {
                $w->where('t.subject', 'like', $qLike)
                    ->orWhere('u.email', 'like', $qLike)
                    ->orWhere('u.first_name', 'like', $qLike)
                    ->orWhere('u.last_name', 'like', $qLike);
                if (count($ticketIdsFromMessages) > 0) {
                    $w->orWhereIn('t.id', $ticketIdsFromMessages);
                }
            });
        }

        // Sortering (with validated sort parameter to prevent injection)
        switch ($sort) {
            case 'created_at_asc':
                $query->orderBy('t.created_at');
                break;
            case 'priority':
                $query->orderByRaw("FIELD(t.priority, 'critical', 'high', 'medium', 'low')")
                      ->orderByDesc('t.created_at');
                break;
            case 'status':
                $query->orderByRaw("FIELD(t.status, 'new', 'in_progress', 'waiting_customer', 'resolved')")
                      ->orderByDesc('t.created_at');
                break;
            case 'updated':
                $query->orderByDesc('t.updated_at');
                break;
            case 'created_at_desc':
            default:
                $query->orderByDesc('t.created_at');
                break;
        }

        $total = $query->count();
        $data  = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        // SLA berekening: uren sinds aanmaak voor open tickets
        $data = $data->map(function ($ticket) {
            if (in_array($ticket->status, ['new', 'in_progress'], true)) {
                $created = strtotime($ticket->created_at);
                $hoursOpen = $created ? round((time() - $created) / 3600, 1) : 0;
                $slaHours = GymiesFeatureFlags::getInt('review_sla_hours', 48);
                $ticket->sla_hours_open = $hoursOpen;
                $ticket->sla_breached = $hoursOpen > $slaHours;
            } else {
                $ticket->sla_hours_open = null;
                $ticket->sla_breached = false;
            }
            return $ticket;
        });

        return response()->json([
            'data'     => $data,
            'total'    => $total,
            'page'     => $page,
            'per_page' => $perPage,
        ]);
    }

    /**
     * Detail van een support ticket inclusief berichten.
     * Staff ziet alle berichten inclusief interne notities.
     */
    public function staffTicketDetail(Request $request, string $ticketId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $id = (int) $ticketId;
        if ($id <= 0) {
            return response()->json(['message' => 'Ongeldig ticket ID.'], 422);
        }

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Support tabel ontbreekt.'], 422);
        }

        $ticket = DB::table('gymies_support_tickets as t')
            ->leftJoin('gymies_users as u', 'u.id', '=', 't.user_id')
            ->leftJoin('gymies_users as a', 'a.id', '=', 't.assigned_to_user_id')
            ->where('t.id', $id)
            ->select([
                't.*',
                'u.email as user_email',
                DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as user_name"),
                'a.email as assigned_email',
                DB::raw("CONCAT(COALESCE(a.first_name,''), ' ', COALESCE(a.last_name,'')) as assigned_name"),
            ])
            ->first();

        if (!$ticket) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        // Berichten ophalen (inclusief interne notities voor staff)
        $messages = [];
        if (Schema::hasTable('gymies_support_ticket_messages')) {
            $messages = DB::table('gymies_support_ticket_messages as m')
                ->leftJoin('gymies_users as mu', 'mu.id', '=', 'm.author_user_id')
                ->where('m.ticket_id', $id)
                ->orderBy('m.id')
                ->select([
                    'm.*',
                    'mu.email as author_email',
                    DB::raw("CONCAT(COALESCE(mu.first_name,''), ' ', COALESCE(mu.last_name,'')) as author_name"),
                    'mu.role as author_role',
                ])
                ->get()
                ->toArray();
        }

        // SLA info
        if (in_array($ticket->status, ['new', 'in_progress'], true)) {
            $created = strtotime($ticket->created_at);
            $slaHours = GymiesFeatureFlags::getInt('review_sla_hours', 48);
            $ticket->sla_hours_open = $created ? round((time() - $created) / 3600, 1) : 0;
            $ticket->sla_breached = ($ticket->sla_hours_open ?? 0) > $slaHours;
        }

        return response()->json([
            'data'     => $ticket,
            'messages' => $messages,
        ]);
    }

    /**
     * Support ticket bijwerken (status, prioriteit, toewijzing, categorie, tags).
     */
    public function staffUpdateTicket(Request $request, string $ticketId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $id = (int) $ticketId;
        if ($id <= 0) {
            return response()->json(['message' => 'Ongeldig ticket ID.'], 422);
        }

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Support tabel ontbreekt.'], 422);
        }

        $ticket = DB::table('gymies_support_tickets')->where('id', $id)->first();
        if (!$ticket) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        $update = ['updated_at' => now()];
        $changes = [];

        // Status
        $validStatuses = ['new', 'in_progress', 'waiting_customer', 'resolved'];
        if ($request->has('status') && in_array($request->input('status'), $validStatuses, true)) {
            $newStatus = (string) $request->input('status');
            $changes['old_status'] = $ticket->status;
            $changes['new_status'] = $newStatus;
            $update['status'] = $newStatus;
            $update['resolved_at'] = $newStatus === 'resolved' ? now() : null;
            if (Schema::hasColumn('gymies_support_tickets', 'close_reason') && $newStatus === 'resolved') {
                $update['close_reason'] = trim((string) $request->input('close_reason', '')) ?: null;
            }
        }

        // Prioriteit
        $validPriorities = ['low', 'medium', 'high', 'critical'];
        if ($request->has('priority') && in_array($request->input('priority'), $validPriorities, true)) {
            $changes['old_priority'] = $ticket->priority ?? 'medium';
            $changes['new_priority'] = (string) $request->input('priority');
            $update['priority'] = (string) $request->input('priority');
        }

        // Toewijzing (-1 = claim/assign to self)
        if ($request->has('assigned_to_user_id')) {
            $assignId = $request->input('assigned_to_user_id');
            if ((int) $assignId === -1) {
                // Claim: wijs toe aan huidige staff
                $assignedToId = (int) $staff->id;
            } else {
                $assignedToId = ($assignId === null || $assignId === '' || (int) $assignId < 1) ? null : (int) $assignId;
            }
            if (Schema::hasColumn('gymies_support_tickets', 'assigned_to_user_id')) {
                $update['assigned_to_user_id'] = $assignedToId;
                $changes['assigned_to'] = $assignedToId;
            }
        }

        // Categorie
        if ($request->has('category')) {
            $update['category'] = trim((string) $request->input('category')) ?: null;
            $changes['category'] = $update['category'];
        }

        if (count($update) <= 1) {
            return response()->json(['message' => 'Geen wijzigingen opgegeven.'], 422);
        }

        DB::table('gymies_support_tickets')->where('id', $id)->update($update);

        // Audit trail
        $reason = trim((string) $request->input('reason', ''));
        $this->auditLog((int) $staff->id, 'support_ticket.updated', 'SupportTicket', $id, array_merge(
            $changes,
            $reason !== '' ? ['reason' => $reason] : []
        ), $request->ip());

        return response()->json(['data' => ['updated' => true, 'ticket_id' => $id]]);
    }

    /**
     * Bericht toevoegen aan support ticket (intern of extern).
     * Extern: klant krijgt e-mail notificatie.
     * Intern: alleen zichtbaar voor staff.
     */
    public function staffAddTicketMessage(Request $request, string $ticketId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $id = (int) $ticketId;
        if ($id <= 0) {
            return response()->json(['message' => 'Ongeldig ticket ID.'], 422);
        }

        $messageBody = trim((string) $request->input('message', ''));
        if ($messageBody === '' || mb_strlen($messageBody) > 5000) {
            return response()->json(['message' => 'Bericht is verplicht (max 5000 tekens).'], 422);
        }

        if (!Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Berichten tabel ontbreekt.'], 422);
        }

        // Controleer of ticket bestaat
        if (!DB::table('gymies_support_tickets')->where('id', $id)->exists()) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        $isInternal = $request->boolean('is_internal', true);

        $msgId = DB::table('gymies_support_ticket_messages')->insertGetId([
            'ticket_id'      => $id,
            'author_user_id' => (int) $staff->id,
            'message'        => $messageBody,
            'is_internal'    => $isInternal ? 1 : 0,
            'created_at'     => now(),
        ]);

        // Update ticket timestamp en status
        $ticketUpdate = ['updated_at' => now()];
        $currentStatus = DB::table('gymies_support_tickets')->where('id', $id)->value('status');
        if ($currentStatus === 'new' && !$isInternal) {
            $ticketUpdate['status'] = 'in_progress';
        }
        DB::table('gymies_support_tickets')->where('id', $id)->update($ticketUpdate);

        // Extern bericht: stuur e-mail notificatie naar klant
        if (!$isInternal) {
            $this->sendStaffTicketReplyEmail($id, $messageBody);

            // Push notificatie naar ticket-eigenaar
            try {
                $ticket = DB::table('gymies_support_tickets')->where('id', $id)->first();
                $ticketUserId = (int) ($ticket->user_id ?? 0);
                $ticketSubject = (string) ($ticket->subject ?? 'Ticket #' . $id);
                if ($ticketUserId > 0) {
                    (new \App\Services\OnboardingNotificationService())->notifyUserTicketReply(
                        $ticketUserId, $id, $ticketSubject
                    );
                }
            } catch (\Throwable $e) {
                Log::warning('Push notify failed: ticket.reply', ['error' => $e->getMessage()]);
            }
        }

        // Audit trail
        $this->auditLog((int) $staff->id, 'support_ticket.message_added', 'SupportTicket', $id, [
            'message_id' => $msgId,
            'is_internal' => $isInternal,
            'length'      => mb_strlen($messageBody),
        ], $request->ip());

        return response()->json(['data' => ['id' => (string) $msgId]], 201);
    }

    /**
     * Support ticket statistieken voor het dashboard.
     */
    public function staffTicketStats(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['data' => [
                'total' => 0, 'new' => 0, 'in_progress' => 0,
                'waiting_customer' => 0, 'resolved' => 0,
                'assigned_to_me' => 0, 'unassigned' => 0,
                'sla_breached' => 0, 'categories' => [],
            ]]);
        }

        $slaHours = GymiesFeatureFlags::getInt('review_sla_hours', 48);

        $stats = [
            'total'    => (int) DB::table('gymies_support_tickets')->count(),
            'new'      => (int) DB::table('gymies_support_tickets')->where('status', 'new')->count(),
            'in_progress' => (int) DB::table('gymies_support_tickets')->where('status', 'in_progress')->count(),
            'waiting_customer' => (int) DB::table('gymies_support_tickets')->where('status', 'waiting_customer')->count(),
            'resolved' => (int) DB::table('gymies_support_tickets')->where('status', 'resolved')->count(),
            'assigned_to_me' => (int) DB::table('gymies_support_tickets')
                ->where('assigned_to_user_id', (int) $staff->id)
                ->whereIn('status', ['new', 'in_progress', 'waiting_customer'])
                ->count(),
            'unassigned' => (int) DB::table('gymies_support_tickets')
                ->whereNull('assigned_to_user_id')
                ->whereIn('status', ['new', 'in_progress'])
                ->count(),
            'sla_breached' => (int) DB::table('gymies_support_tickets')
                ->whereIn('status', ['new', 'in_progress'])
                ->where('created_at', '<', now()->subHours($slaHours))
                ->count(),
        ];

        // Categorieën met counts
        $categories = DB::table('gymies_support_tickets')
            ->select('category', DB::raw('COUNT(*) as count'))
            ->whereIn('status', ['new', 'in_progress', 'waiting_customer'])
            ->groupBy('category')
            ->orderByDesc('count')
            ->get()
            ->map(fn ($r) => ['category' => $r->category ?? 'geen', 'count' => (int) $r->count])
            ->toArray();

        $stats['categories'] = $categories;

        return response()->json(['data' => $stats]);
    }

    // ─── Support Helpers ─────────────────────────────────────────

    /**
     * Stuur e-mail notificatie naar klant bij extern staff antwoord.
     */
    private function sendStaffTicketReplyEmail(int $ticketId, string $messageBody): void
    {
        try {
            $ticket = DB::table('gymies_support_tickets')->where('id', $ticketId)->first();
            if (!$ticket || !($ticket->user_id ?? null)) {
                return;
            }
            $user = DB::table('gymies_users')->where('id', $ticket->user_id)->first();
            if (!$user || !($user->email ?? null)) {
                return;
            }

            $name = trim(($user->first_name ?? '') . ' ' . ($user->last_name ?? '')) ?: 'Klant';

            if (class_exists(\App\Mail\SendGymiesNotificationEmail::class)) {
                \App\Mail\SendGymiesNotificationEmail::sendOrQueue(
                    toEmail: $user->email,
                    subject: 'Reactie op je supportticket: ' . ($ticket->subject ?? '#' . $ticketId),
                    templateKey: 'support_reply',
                    templateData: [
                        'name'     => $name,
                        'subject'  => $ticket->subject ?? '',
                        'message'  => mb_substr($messageBody, 0, 500),
                        'ticketId' => $ticketId,
                    ]
                );
            }

            // Sync naar conversation als module beschikbaar
            if (class_exists(\App\Helpers\GymiesSupportSync::class)) {
                \App\Helpers\GymiesSupportSync::syncAdminReplyToConversation($ticketId, $messageBody);
            }
        } catch (\Throwable $e) {
            Log::warning('Staff ticket reply email mislukt: ' . $e->getMessage());
        }
    }

    /**
     * Audit log helper — schrijf naar gymies_staff_audit_log.
     */
    private function auditLog(int $staffId, string $action, string $targetType, int $targetId, array $metadata, ?string $ip = null): void
    {
        if (!Schema::hasTable('gymies_staff_audit_log')) {
            return;
        }
        DB::table('gymies_staff_audit_log')->insert([
            'staff_id'    => $staffId,
            'action'      => $action,
            'target_type' => $targetType,
            'target_id'   => $targetId,
            'metadata'    => json_encode($metadata),
            'ip_address'  => $ip,
            'created_at'  => now(),
            'updated_at'  => now(),
        ]);
    }

    // ─── Staff Chat (Intern) ────────────────────────────────────

    /**
     * Self-healing: maak gymies_staff_chat_messages tabel als die niet bestaat.
     */
    private function ensureStaffChatTable(): void
    {
        if (Schema::hasTable('gymies_staff_chat_messages')) {
            return;
        }
        DB::statement("
            CREATE TABLE IF NOT EXISTS gymies_staff_chat_messages (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                sender_id BIGINT UNSIGNED NOT NULL,
                channel VARCHAR(50) NOT NULL DEFAULT 'general',
                message TEXT NOT NULL,
                created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_channel_created (channel, created_at),
                INDEX idx_sender (sender_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ");
    }

    /**
     * Chat berichten ophalen per kanaal, met paginatie.
     *
     * Query params:
     *   channel  - kanaal naam (default: 'general')
     *   before   - message ID, laad berichten vóór dit ID (voor infinite scroll)
     *   limit    - max berichten (default 50, max 100)
     */
    public function staffChatMessages(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureStaffChatTable();

        $channel = trim((string) $request->query('channel', 'general')) ?: 'general';
        $before  = (int) $request->query('before', 0);
        $limit   = min(100, max(1, (int) $request->query('limit', 50)));

        $query = DB::table('gymies_staff_chat_messages as m')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'm.sender_id')
            ->where('m.channel', $channel)
            ->select([
                'm.id', 'm.sender_id', 'm.channel', 'm.message', 'm.created_at',
                'u.email as sender_email',
                DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as sender_name"),
                'u.role as sender_role',
            ])
            ->orderByDesc('m.id')
            ->limit($limit);

        if ($before > 0) {
            $query->where('m.id', '<', $before);
        }

        $messages = $query->get()->reverse()->values();

        // Beschikbare kanalen met ongelezen indicator
        $channels = DB::table('gymies_staff_chat_messages')
            ->select('channel', DB::raw('MAX(created_at) as last_message_at'), DB::raw('COUNT(*) as total_messages'))
            ->groupBy('channel')
            ->orderByDesc('last_message_at')
            ->get();

        return response()->json([
            'data'     => $messages,
            'channel'  => $channel,
            'channels' => $channels,
            'has_more' => $messages->count() === $limit,
        ]);
    }

    /**
     * Chat bericht versturen.
     */
    public function staffChatSend(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureStaffChatTable();

        $message = trim((string) $request->input('message', ''));
        $channel = trim((string) $request->input('channel', 'general')) ?: 'general';

        if ($message === '' || mb_strlen($message) > 2000) {
            return response()->json(['message' => 'Bericht is verplicht (max 2000 tekens).'], 422);
        }

        // Valideer kanaalnaam: alleen letters, cijfers, hyphens
        if (!preg_match('/^[a-z0-9\-]{1,50}$/', $channel)) {
            return response()->json(['message' => 'Ongeldige kanaalnaam.'], 422);
        }

        $msgId = DB::table('gymies_staff_chat_messages')->insertGetId([
            'sender_id'  => (int) $staff->id,
            'channel'    => $channel,
            'message'    => $message,
            'created_at' => now(),
        ]);

        // Verrijk met sender info voor directe response
        $name = trim(($staff->first_name ?? '') . ' ' . ($staff->last_name ?? ''));

        return response()->json([
            'data' => [
                'id'          => $msgId,
                'sender_id'   => (int) $staff->id,
                'sender_name' => $name,
                'sender_email'=> $staff->email ?? '',
                'channel'     => $channel,
                'message'     => $message,
                'created_at'  => now()->toIso8601String(),
            ],
        ], 201);
    }

    /**
     * Beschikbare chat kanalen ophalen.
     */
    public function staffChatChannels(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureStaffChatTable();

        $channels = DB::table('gymies_staff_chat_messages')
            ->select('channel', DB::raw('MAX(created_at) as last_message_at'), DB::raw('COUNT(*) as total_messages'))
            ->groupBy('channel')
            ->orderByDesc('last_message_at')
            ->get();

        // Altijd 'general' tonen, ook als er nog geen berichten zijn
        $hasGeneral = $channels->contains('channel', 'general');
        if (!$hasGeneral) {
            $channels->prepend((object) [
                'channel'          => 'general',
                'last_message_at'  => null,
                'total_messages'   => 0,
            ]);
        }

        return response()->json(['data' => $channels]);
    }

    // ─── H.1: Trainer Detail View ──────────────────────────────

    /**
     * Uitgebreid profiel van een trainer voor staff review.
     * Inclusief documenten, etalage, bedrijfsgegevens, subscription, onboarding progress.
     */
    public function staffTrainerDetail(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $id = (int) $trainerId;
        if ($id <= 0) {
            return response()->json(['message' => 'Ongeldig trainer ID.'], 422);
        }

        // Trainer profiel
        $profile = DB::table('gymies_trainer_profiles')->where('id', $id)->first();
        if (!$profile) {
            return response()->json(['message' => 'Trainer niet gevonden.'], 404);
        }

        $userId = $profile->user_id ?? 0;
        $user = DB::table('gymies_users')->where('id', $userId)->first();

        $data = [
            'id'                => $id,
            'user_id'           => $userId,
            'user_name'         => trim(($user->first_name ?? '') . ' ' . ($user->last_name ?? '')),
            'user_email'        => $user->email ?? '',
            'phone'             => $user->phone ?? '',
            'role'              => $user->role ?? '',
            'registered_at'     => $user->created_at ?? '',
            'onboarding_status' => $profile->onboarding_status ?? 'incomplete',
            'company_name'      => $profile->company_name ?? '',
            'kvk_number'        => $profile->kvk_number ?? '',
            'iban'              => $profile->iban ?? '',
            'vat_number'        => $profile->vat_number ?? '',
            'bio'               => $profile->bio ?? '',
            'specialties'       => json_decode($profile->specialties ?? '[]', true),
            'trial_ends_at'     => $profile->trial_ends_at ?? null,
            'subscription_plan' => $profile->subscription_plan ?? null,
            'review_reason'     => $profile->review_reason ?? '',
            'reviewed_by'       => $profile->reviewed_by ?? null,
            'reviewed_at'       => $profile->reviewed_at ?? null,
        ];

        // Documenten
        $data['documents'] = [];
        if (Schema::hasTable('gymies_document_uploads')) {
            $docs = DB::table('gymies_document_uploads')
                ->where('user_id', $userId)
                ->orderByDesc('created_at')
                ->get();
            $data['documents'] = $docs->map(fn ($d) => [
                'id'                => $d->id,
                'document_category' => $d->document_category ?? 'other',
                'filename'          => $d->original_filename ?? $d->filename ?? '',
                'verified_at'       => $d->verified_at ?? null,
                'rejected_at'       => $d->rejected_at ?? null,
                'created_at'        => $d->created_at ?? '',
            ])->toArray();
        }

        // Subscription info
        $data['subscription'] = null;
        if (Schema::hasTable('gymies_subscriptions')) {
            $sub = DB::table('gymies_subscriptions')
                ->where('trainer_user_id', $userId)
                ->orderByDesc('created_at')
                ->first();
            if ($sub) {
                $data['subscription'] = [
                    'status'     => $sub->status ?? '',
                    'plan'       => $sub->plan ?? '',
                    'amount'     => $sub->amount ?? '',
                    'interval'   => $sub->interval ?? '',
                    'started_at' => $sub->created_at ?? '',
                    'ends_at'    => $sub->ends_at ?? null,
                ];
            }
        }

        // Mollie info
        $data['mollie_status'] = $profile->mollie_onboarding_status ?? 'not_started';
        $data['has_mollie_profile'] = !empty($profile->mollie_profile_id);

        // Etalage completeness
        $etalageFields = ['bio', 'specialties', 'profile_photo', 'hourly_rate'];
        $filled = 0;
        foreach ($etalageFields as $field) {
            if (!empty($profile->$field)) $filled++;
        }
        $data['etalage_completeness'] = (int) round(($filled / count($etalageFields)) * 100);

        // Trial extensions
        $data['trial_extensions'] = [];
        if (Schema::hasTable('gymies_trial_extensions')) {
            $data['trial_extensions'] = DB::table('gymies_trial_extensions as te')
                ->leftJoin('gymies_users as su', 'su.id', '=', 'te.staff_id')
                ->where('te.trainer_profile_id', $id)
                ->orderByDesc('te.created_at')
                ->select([
                    'te.*',
                    DB::raw("CONCAT(COALESCE(su.first_name,''), ' ', COALESCE(su.last_name,'')) as staff_name"),
                ])
                ->limit(20)
                ->get()
                ->map(function ($ext) {
                    $ext->activity_snapshot = json_decode($ext->activity_snapshot ?? '{}', true);
                    return $ext;
                })
                ->toArray();
        }

        // Audit trail
        $this->auditLog((int) $staff->id, 'trainer.detail_viewed', 'TrainerProfile', $id, [], $request->ip());

        return response()->json(['data' => $data]);
    }

    // ─── H.2: Trainer Zoeken & Filteren ─────────────────────────

    /**
     * Alle trainers met zoeken, filteren op status, paginatie.
     */
    public function staffTrainers(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['data' => [], 'total' => 0, 'page' => 1, 'per_page' => 25]);
        }

        $page    = max(1, (int) $request->query('page', 1));
        $perPage = min(50, max(1, (int) $request->query('per_page', 25)));
        $status  = trim((string) $request->query('status', ''));
        $q       = trim((string) $request->query('q', ''));
        $qLike   = $q !== '' ? '%' . addcslashes($q, '%_\\') . '%' : '';
        $sort    = trim((string) $request->query('sort', 'newest'));

        $query = DB::table('gymies_trainer_profiles as tp')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'tp.user_id')
            ->select([
                'tp.id', 'tp.user_id', 'tp.onboarding_status', 'tp.company_name',
                'tp.kvk_number', 'tp.subscription_plan', 'tp.trial_ends_at',
                'tp.created_at', 'tp.updated_at',
                'u.email',
                DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as user_name"),
            ]);

        // Status filter
        $validStatuses = ['incomplete', 'pending_review', 'approved', 'active', 'rejected', 'suspended'];
        if ($status !== '' && in_array($status, $validStatuses, true)) {
            $query->where('tp.onboarding_status', $status);
        }

        // Zoeken
        if ($qLike !== '') {
            $query->where(function ($w) use ($qLike): void {
                $w->where('u.first_name', 'like', $qLike)
                    ->orWhere('u.last_name', 'like', $qLike)
                    ->orWhere('u.email', 'like', $qLike)
                    ->orWhere('tp.company_name', 'like', $qLike)
                    ->orWhere('tp.kvk_number', 'like', $qLike);
            });
        }

        // Sortering
        switch ($sort) {
            case 'oldest':
                $query->orderBy('tp.created_at');
                break;
            case 'name':
                $query->orderBy('u.first_name')->orderBy('u.last_name');
                break;
            case 'status':
                $query->orderByRaw("FIELD(tp.onboarding_status, 'pending_review', 'incomplete', 'approved', 'active', 'suspended', 'rejected')");
                break;
            default:
                $query->orderByDesc('tp.created_at');
                break;
        }

        $total = $query->count();
        $data  = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        return response()->json([
            'data'     => $data,
            'total'    => $total,
            'page'     => $page,
            'per_page' => $perPage,
        ]);
    }

    // ─── H.3: Bookings Monitor ──────────────────────────────────

    /**
     * Boekingen overzicht: vandaag, morgen, problemen.
     */
    public function staffBookingsMonitor(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $todayStart = now()->startOfDay()->toDateTimeString();
        $todayEnd   = now()->endOfDay()->toDateTimeString();
        $tomorrowStart = now()->addDay()->startOfDay()->toDateTimeString();
        $tomorrowEnd   = now()->addDay()->endOfDay()->toDateTimeString();

        $result = [
            'today' => [], 'tomorrow' => [],
            'stats' => [
                'today_count' => 0, 'tomorrow_count' => 0,
                'no_shows' => 0, 'cancellations_today' => 0,
                'payment_failures' => 0,
            ],
        ];

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => $result]);
        }

        // Vandaag
        $today = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->whereBetween('b.scheduled_at', [$todayStart, $todayEnd])
            ->select([
                'b.id', 'b.status', 'b.scheduled_at', 'b.duration_minutes',
                'b.trainer_user_id', 'b.client_user_id',
                DB::raw("CONCAT(COALESCE(t.first_name,''), ' ', COALESCE(t.last_name,'')) as trainer_name"),
                DB::raw("CONCAT(COALESCE(c.first_name,''), ' ', COALESCE(c.last_name,'')) as client_name"),
                'b.payment_status',
            ])
            ->orderBy('b.scheduled_at')
            ->limit(100)
            ->get();

        $result['today'] = $today;
        $result['stats']['today_count'] = $today->count();

        // Morgen
        $tomorrow = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->whereBetween('b.scheduled_at', [$tomorrowStart, $tomorrowEnd])
            ->select([
                'b.id', 'b.status', 'b.scheduled_at', 'b.duration_minutes',
                'b.trainer_user_id', 'b.client_user_id',
                DB::raw("CONCAT(COALESCE(t.first_name,''), ' ', COALESCE(t.last_name,'')) as trainer_name"),
                DB::raw("CONCAT(COALESCE(c.first_name,''), ' ', COALESCE(c.last_name,'')) as client_name"),
            ])
            ->orderBy('b.scheduled_at')
            ->limit(100)
            ->get();

        $result['tomorrow'] = $tomorrow;
        $result['stats']['tomorrow_count'] = $tomorrow->count();

        // Problemen
        $result['stats']['no_shows'] = (int) DB::table('gymies_bookings')
            ->where('status', 'no_show')
            ->whereBetween('scheduled_at', [$todayStart, $todayEnd])
            ->count();

        $result['stats']['cancellations_today'] = (int) DB::table('gymies_bookings')
            ->whereIn('status', ['cancelled', 'cancelled_by_trainer', 'cancelled_by_client'])
            ->whereBetween('updated_at', [$todayStart, $todayEnd])
            ->count();

        $result['stats']['payment_failures'] = (int) DB::table('gymies_bookings')
            ->whereIn('status', ['payment_failed', 'failed'])
            ->where('created_at', '>=', now()->subDays(7)->toDateTimeString())
            ->count();

        return response()->json(['data' => $result]);
    }

    // ─── H.4: Onboarding Pipeline ───────────────────────────────

    /**
     * Trainers per onboarding status voor pipeline view.
     */
    public function staffOnboardingPipeline(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['data' => ['stages' => []]]);
        }

        $stages = ['incomplete', 'pending_review', 'approved', 'active'];
        $pipeline = [];

        foreach ($stages as $status) {
            $trainers = DB::table('gymies_trainer_profiles as tp')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'tp.user_id')
                ->where('tp.onboarding_status', $status)
                ->select([
                    'tp.id', 'tp.user_id', 'tp.onboarding_status', 'tp.company_name',
                    'tp.subscription_plan', 'tp.trial_ends_at', 'tp.updated_at',
                    DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as user_name"),
                    'u.email',
                ])
                ->orderByDesc('tp.updated_at')
                ->limit(25)
                ->get();

            // Verrijk met docs status
            $trainerIds = $trainers->pluck('user_id')->toArray();
            $docsCount = [];
            if (!empty($trainerIds) && Schema::hasTable('gymies_document_uploads')) {
                $docsCount = DB::table('gymies_document_uploads')
                    ->whereIn('user_id', $trainerIds)
                    ->selectRaw('user_id, COUNT(*) as total, SUM(CASE WHEN verified_at IS NOT NULL THEN 1 ELSE 0 END) as verified')
                    ->groupBy('user_id')
                    ->pluck(DB::raw("CONCAT(total, '/', verified)"), 'user_id')
                    ->toArray();
            }

            $enriched = $trainers->map(function ($t) use ($docsCount) {
                $docInfo = $docsCount[$t->user_id] ?? '0/0';
                $parts = explode('/', $docInfo);
                $t->docs_total = (int) ($parts[0] ?? 0);
                $t->docs_verified = (int) ($parts[1] ?? 0);
                return $t;
            });

            $pipeline[] = [
                'status' => $status,
                'label'  => match ($status) {
                    'incomplete'     => 'Incompleet',
                    'pending_review' => 'Wacht op Review',
                    'approved'       => 'Goedgekeurd',
                    'active'         => 'Actief',
                    default          => $status,
                },
                'count'   => (int) DB::table('gymies_trainer_profiles')->where('onboarding_status', $status)->count(),
                'trainers' => $enriched,
            ];
        }

        // Suspended/rejected apart
        $suspended = (int) DB::table('gymies_trainer_profiles')->where('onboarding_status', 'suspended')->count();
        $rejected  = (int) DB::table('gymies_trainer_profiles')->where('onboarding_status', 'rejected')->count();

        return response()->json([
            'data' => [
                'stages'    => $pipeline,
                'suspended' => $suspended,
                'rejected'  => $rejected,
            ],
        ]);
    }

    // ─── H.5: Canned Responses ──────────────────────────────────

    /**
     * Self-healing: canned responses tabel.
     */
    private function ensureCannedResponsesTable(): void
    {
        if (Schema::hasTable('gymies_staff_canned_responses')) {
            return;
        }
        DB::statement("
            CREATE TABLE IF NOT EXISTS gymies_staff_canned_responses (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                title VARCHAR(100) NOT NULL,
                body TEXT NOT NULL,
                category VARCHAR(50) NOT NULL DEFAULT 'general',
                created_by BIGINT UNSIGNED NOT NULL,
                created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_category (category)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ");
    }

    public function staffCannedResponses(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureCannedResponsesTable();

        $category = trim((string) $request->query('category', ''));

        $query = DB::table('gymies_staff_canned_responses as cr')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'cr.created_by')
            ->select([
                'cr.*',
                DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as created_by_name"),
            ])
            ->orderBy('cr.category')
            ->orderBy('cr.title');

        if ($category !== '') {
            $query->where('cr.category', $category);
        }

        return response()->json(['data' => $query->get()]);
    }

    public function staffCreateCannedResponse(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureCannedResponsesTable();

        $title = trim((string) $request->input('title', ''));
        $body  = trim((string) $request->input('body', ''));
        $category = trim((string) $request->input('category', 'general'));

        if ($title === '' || $body === '') {
            return response()->json(['message' => 'Titel en tekst zijn verplicht.'], 422);
        }

        $id = DB::table('gymies_staff_canned_responses')->insertGetId([
            'title'      => $title,
            'body'       => $body,
            'category'   => $category,
            'created_by' => (int) $staff->id,
            'created_at' => now(),
        ]);

        $this->auditLog((int) $staff->id, 'canned_response.created', 'CannedResponse', (int) $id, [
            'title' => $title, 'category' => $category,
        ], $request->ip());

        return response()->json(['data' => ['id' => $id, 'title' => $title]], 201);
    }

    public function staffDeleteCannedResponse(Request $request, string $responseId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureCannedResponsesTable();

        $id = (int) $responseId;
        DB::table('gymies_staff_canned_responses')->where('id', $id)->delete();

        $this->auditLog((int) $staff->id, 'canned_response.deleted', 'CannedResponse', $id, [], $request->ip());

        return response()->json(['data' => ['deleted' => true]]);
    }

    // ─── H.6: Geschillen Overzicht ──────────────────────────────

    /**
     * Open geschillen voor staff first-line afhandeling.
     */
    public function staffDisputes(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['data' => [], 'total' => 0]);
        }

        $page    = max(1, (int) $request->query('page', 1));
        $perPage = min(50, max(1, (int) $request->query('per_page', 25)));
        $status  = trim((string) $request->query('status', ''));

        $query = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'd.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'd.trainer_user_id')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->select([
                'd.id', 'd.booking_id', 'd.reason', 'd.status', 'd.resolution',
                'd.created_at', 'd.updated_at', 'd.resolved_at',
                DB::raw("CONCAT(COALESCE(c.first_name,''), ' ', COALESCE(c.last_name,'')) as client_name"),
                'c.email as client_email',
                DB::raw("CONCAT(COALESCE(t.first_name,''), ' ', COALESCE(t.last_name,'')) as trainer_name"),
                'b.scheduled_at as booking_date', 'b.status as booking_status',
            ])
            ->orderByDesc('d.created_at');

        if ($status !== '') {
            $query->where('d.status', $status);
        }

        $total = $query->count();
        $data  = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        return response()->json([
            'data'     => $data,
            'total'    => $total,
            'page'     => $page,
            'per_page' => $perPage,
        ]);
    }

    // ─── H.7: Auto-assign Tickets ───────────────────────────────

    /**
     * Wijs ongeassigneerde nieuwe tickets automatisch toe (round-robin).
     * Wordt aangeroepen door cron of handmatig via endpoint.
     */
    public function staffAutoAssignTickets(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!GymiesFeatureFlags::isEnabled('ticket_auto_assign')) {
            return response()->json(['data' => ['assigned' => 0, 'message' => 'Auto-assign is uitgeschakeld.']]);
        }

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['data' => ['assigned' => 0]]);
        }

        // Zoek alle staff members
        $staffMembers = DB::table('gymies_users')
            ->whereIn('role', ['admin', 'staff', 'medewerker'])
            ->pluck('id')
            ->toArray();

        if (empty($staffMembers)) {
            return response()->json(['data' => ['assigned' => 0, 'message' => 'Geen staff beschikbaar.']]);
        }

        // Tel open tickets per staff member
        $ticketCounts = DB::table('gymies_support_tickets')
            ->whereIn('assigned_to_user_id', $staffMembers)
            ->whereIn('status', ['new', 'in_progress'])
            ->selectRaw('assigned_to_user_id, COUNT(*) as cnt')
            ->groupBy('assigned_to_user_id')
            ->pluck('cnt', 'assigned_to_user_id')
            ->toArray();

        // Unassigned nieuwe tickets
        $unassigned = DB::table('gymies_support_tickets')
            ->where('status', 'new')
            ->whereNull('assigned_to_user_id')
            ->orderBy('created_at')
            ->limit(50)
            ->pluck('id')
            ->toArray();

        $assigned = 0;
        foreach ($unassigned as $ticketId) {
            // Kies staff met minste tickets (round-robin)
            $minCount = PHP_INT_MAX;
            $bestStaff = $staffMembers[0];
            foreach ($staffMembers as $sid) {
                $count = $ticketCounts[$sid] ?? 0;
                if ($count < $minCount) {
                    $minCount = $count;
                    $bestStaff = $sid;
                }
            }

            DB::table('gymies_support_tickets')->where('id', $ticketId)->update([
                'assigned_to_user_id' => $bestStaff,
                'updated_at'          => now(),
            ]);

            $ticketCounts[$bestStaff] = ($ticketCounts[$bestStaff] ?? 0) + 1;
            $assigned++;
        }

        $this->auditLog((int) $staff->id, 'tickets.auto_assigned', 'SupportTicket', 0, [
            'count' => $assigned,
        ], $request->ip());

        return response()->json(['data' => ['assigned' => $assigned]]);
    }

    // ─── H.8: Extension History ─────────────────────────────────

    /**
     * Verlengingshistorie per trainer.
     */
    public function staffTrialExtensions(Request $request, string $trainerId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $id = (int) $trainerId;
        if (!Schema::hasTable('gymies_trial_extensions')) {
            return response()->json(['data' => []]);
        }

        $extensions = DB::table('gymies_trial_extensions as te')
            ->leftJoin('gymies_users as su', 'su.id', '=', 'te.staff_id')
            ->where('te.trainer_profile_id', $id)
            ->orderByDesc('te.created_at')
            ->select([
                'te.id', 'te.days', 'te.reason', 'te.old_trial_end', 'te.new_trial_end',
                'te.activity_score', 'te.created_at',
                DB::raw("CONCAT(COALESCE(su.first_name,''), ' ', COALESCE(su.last_name,'')) as staff_name"),
            ])
            ->limit(50)
            ->get();

        return response()->json(['data' => $extensions]);
    }

    // ─── H.9: Chat Read Positions ───────────────────────────────

    /**
     * Self-healing: chat read positions tabel.
     */
    private function ensureChatReadPositionsTable(): void
    {
        if (Schema::hasTable('gymies_staff_chat_read_positions')) {
            return;
        }
        DB::statement("
            CREATE TABLE IF NOT EXISTS gymies_staff_chat_read_positions (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                user_id BIGINT UNSIGNED NOT NULL,
                channel VARCHAR(50) NOT NULL DEFAULT 'general',
                last_read_message_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
                updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uk_user_channel (user_id, channel)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ");
    }

    /**
     * Markeer berichten als gelezen voor huidig kanaal.
     */
    public function staffChatMarkRead(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureChatReadPositionsTable();
        $this->ensureStaffChatTable();

        $channel   = trim((string) $request->input('channel', 'general')) ?: 'general';
        $messageId = (int) $request->input('message_id', 0);

        // Als geen message_id meegegeven, pak het laatste bericht
        if ($messageId <= 0) {
            $messageId = (int) (DB::table('gymies_staff_chat_messages')
                ->where('channel', $channel)
                ->max('id') ?? 0);
        }

        if ($messageId > 0) {
            DB::table('gymies_staff_chat_read_positions')->updateOrInsert(
                ['user_id' => (int) $staff->id, 'channel' => $channel],
                ['last_read_message_id' => $messageId, 'updated_at' => now()]
            );
        }

        return response()->json(['data' => ['marked_read' => true, 'message_id' => $messageId]]);
    }

    /**
     * Ongelezen counts per kanaal voor huidige user.
     */
    public function staffChatUnreadCounts(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureChatReadPositionsTable();
        $this->ensureStaffChatTable();

        $userId = (int) $staff->id;

        // Alle kanalen met hun laatste bericht ID
        $channels = DB::table('gymies_staff_chat_messages')
            ->selectRaw('channel, MAX(id) as last_message_id, COUNT(*) as total')
            ->groupBy('channel')
            ->get();

        // Read positions van deze user
        $readPositions = DB::table('gymies_staff_chat_read_positions')
            ->where('user_id', $userId)
            ->pluck('last_read_message_id', 'channel')
            ->toArray();

        $result = [];
        foreach ($channels as $ch) {
            $lastRead = $readPositions[$ch->channel] ?? 0;
            $unread = (int) DB::table('gymies_staff_chat_messages')
                ->where('channel', $ch->channel)
                ->where('id', '>', $lastRead)
                ->where('sender_id', '!=', $userId) // Eigen berichten niet meetellen
                ->count();

            $result[] = [
                'channel'         => $ch->channel,
                'unread'          => $unread,
                'last_message_id' => (int) $ch->last_message_id,
                'total'           => (int) $ch->total,
            ];
        }

        return response()->json(['data' => $result]);
    }

    // ─── H.10: Dashboard Stats Uitbreiden ───────────────────────
    // (Al geïmplementeerd in bestaand dashboard() method — uitgebreid hieronder)

    /**
     * Uitgebreide dashboard stats met warnings.
     */
    public function staffDashboardExtended(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $todayStart = now()->startOfDay()->toDateTimeString();
        $todayEnd   = now()->endOfDay()->toDateTimeString();

        $stats = [];

        // Registraties vandaag
        $stats['registrations_today'] = (int) DB::table('gymies_users')
            ->whereBetween('created_at', [$todayStart, $todayEnd])
            ->count();

        // Bookings vandaag
        $stats['bookings_today'] = 0;
        if (Schema::hasTable('gymies_bookings')) {
            $stats['bookings_today'] = (int) DB::table('gymies_bookings')
                ->whereBetween('scheduled_at', [$todayStart, $todayEnd])
                ->count();
        }

        // Tickets vandaag
        $stats['tickets_today'] = 0;
        if (Schema::hasTable('gymies_support_tickets')) {
            $stats['tickets_today'] = (int) DB::table('gymies_support_tickets')
                ->whereBetween('created_at', [$todayStart, $todayEnd])
                ->count();
        }

        // SLA breached
        $slaHours = GymiesFeatureFlags::getInt('review_sla_hours', 48);
        $stats['sla_breached'] = 0;
        if (Schema::hasTable('gymies_support_tickets')) {
            $stats['sla_breached'] = (int) DB::table('gymies_support_tickets')
                ->whereIn('status', ['new', 'in_progress'])
                ->where('created_at', '<', now()->subHours($slaHours))
                ->count();
        }

        // Payment failures (7 dagen)
        $stats['payment_failures_7d'] = 0;
        if (Schema::hasTable('gymies_bookings')) {
            $stats['payment_failures_7d'] = (int) DB::table('gymies_bookings')
                ->whereIn('status', ['payment_failed', 'failed'])
                ->where('created_at', '>=', now()->subDays(7)->toDateTimeString())
                ->count();
        }

        // Warnings
        $warnings = [];
        if (($stats['sla_breached'] ?? 0) > 0) {
            $warnings[] = ['key' => 'sla_breached', 'count' => $stats['sla_breached'], 'label' => 'Tickets over SLA', 'color' => 'red'];
        }
        if (($stats['payment_failures_7d'] ?? 0) > 0) {
            $warnings[] = ['key' => 'payment_failures', 'count' => $stats['payment_failures_7d'], 'label' => 'Betaalproblemen (7d)', 'color' => 'orange'];
        }
        $stats['warnings'] = $warnings;

        return response()->json(['data' => $stats]);
    }

    // ─── H.11: Audit Export ─────────────────────────────────────

    /**
     * Exporteer audit log als CSV.
     */
    public function staffAuditExport(Request $request): \Illuminate\Http\Response|JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_staff_audit_log')) {
            return response()->json(['message' => 'Geen audit data.'], 404);
        }

        $action     = $request->query('action');
        $staffFilter = $request->query('staff_id');
        $dateFrom   = $request->query('date_from');
        $dateTo     = $request->query('date_to');

        $query = DB::table('gymies_staff_audit_log as a')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'a.staff_id')
            ->select([
                'a.id', 'a.action', 'a.target_type', 'a.target_id',
                'a.metadata', 'a.ip_address', 'a.created_at',
                DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as staff_name"),
                'u.email as staff_email',
            ])
            ->orderByDesc('a.created_at');

        if ($action) $query->where('a.action', 'like', $action . '%');
        if ($staffFilter) $query->where('a.staff_id', (int) $staffFilter);
        if ($dateFrom) $query->where('a.created_at', '>=', $dateFrom);
        if ($dateTo) $query->where('a.created_at', '<=', $dateTo . ' 23:59:59');

        $rows = $query->limit(5000)->get();

        // CSV formula injection sanitization function
        $sanitizeCsvValue = function ($val) {
            $val = (string) $val;
            if (preg_match('/^[=+\-@\t\r]/', $val)) {
                return "'" . $val; // Prefix with single quote to prevent formula injection
            }
            return $val;
        };

        // Genereer CSV
        $csv = "ID,Actie,Medewerker,Email,Target,Target ID,Metadata,IP,Datum\n";
        foreach ($rows as $row) {
            $csv .= implode(',', [
                $sanitizeCsvValue($row->id),
                '"' . str_replace('"', '""', $sanitizeCsvValue($row->action)) . '"',
                '"' . str_replace('"', '""', $sanitizeCsvValue($row->staff_name)) . '"',
                $sanitizeCsvValue($row->staff_email ?? ''),
                $sanitizeCsvValue($row->target_type),
                $sanitizeCsvValue($row->target_id),
                '"' . str_replace('"', '""', $sanitizeCsvValue($row->metadata ?? '')) . '"',
                $sanitizeCsvValue($row->ip_address ?? ''),
                $sanitizeCsvValue($row->created_at),
            ]) . "\n";
        }

        $this->auditLog((int) $staff->id, 'audit.exported', 'AuditLog', 0, [
            'rows' => $rows->count(),
            'filters' => compact('action', 'staffFilter', 'dateFrom', 'dateTo'),
        ], $request->ip());

        return response($csv, 200, [
            'Content-Type'        => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="audit-export-' . date('Y-m-d') . '.csv"',
        ]);
    }

    // ─── H.12: Flag Wijzigingshistorie ──────────────────────────
    // (Geïntegreerd in bestaand featureFlags endpoint — uitgebreid hieronder)

    /**
     * Feature flags met laatst-gewijzigd info uit audit log.
     */
    public function staffFeatureFlagsExtended(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $flags = GymiesFeatureFlags::allDetailed();

        // Haal laatste wijziging per flag uit audit log
        $lastChanges = [];
        if (Schema::hasTable('gymies_staff_audit_log')) {
            $auditEntries = DB::table('gymies_staff_audit_log as a')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'a.staff_id')
                ->where('a.action', 'feature_flag.updated')
                ->orderByDesc('a.created_at')
                ->select([
                    'a.metadata', 'a.created_at',
                    DB::raw("CONCAT(COALESCE(u.first_name,''), ' ', COALESCE(u.last_name,'')) as staff_name"),
                ])
                ->limit(100)
                ->get();

            foreach ($auditEntries as $entry) {
                $meta = json_decode($entry->metadata ?? '{}', true);
                $flagKey = $meta['key'] ?? '';
                if ($flagKey !== '' && !isset($lastChanges[$flagKey])) {
                    $lastChanges[$flagKey] = [
                        'changed_by' => $entry->staff_name,
                        'changed_at' => $entry->created_at,
                        'changes'    => $meta['changes'] ?? [],
                    ];
                }
            }
        }

        // Voeg toe aan flags
        foreach ($flags as &$flag) {
            $key = $flag['key'] ?? '';
            $flag['last_change'] = $lastChanges[$key] ?? null;
        }

        // Groepeer per categorie
        $grouped = [];
        foreach ($flags as $flag) {
            $cat = $flag['category'] ?? 'general';
            $grouped[$cat][] = $flag;
        }

        return response()->json([
            'data'    => $flags,
            'grouped' => $grouped,
        ]);
    }

    // ═══════════════════════════════════════════════════════════════
    // ─── Fase I: Ontbrekende Staff Features ─────────────────────
    // ═══════════════════════════════════════════════════════════════

    // ─── I.1: Geschillen Oplossen + Berichten ───────────────────

    /**
     * Geschil oplossen door staff.
     */
    public function staffResolveDispute(Request $request, string $disputeId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'resolution_type' => 'required|in:client,trainer,split',
            'reason'          => 'required|string|max:500',
        ]);

        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['message' => 'Disputes niet beschikbaar.'], 503);
        }

        $id = (int) $disputeId;
        $d = DB::table('gymies_disputes')->where('id', $id)->first();
        if (!$d || !in_array((string) ($d->status ?? ''), ['open', 'in_progress'], true)) {
            return response()->json(['message' => 'Dispute niet gevonden of al afgehandeld.'], 404);
        }

        $resolutionType = (string) $request->input('resolution_type');
        $reason = trim((string) $request->input('reason'));

        $update = ['status' => 'resolved', 'resolution_notes' => $reason, 'closed_at' => now()];
        if (Schema::hasColumn('gymies_disputes', 'resolution_type')) {
            $update['resolution_type'] = $resolutionType;
        }
        if (Schema::hasColumn('gymies_disputes', 'resolved_by_user_id')) {
            $update['resolved_by_user_id'] = (int) $staff->id;
        }
        DB::table('gymies_disputes')->where('id', $id)->update($update);

        // Booking cancel bij client-gelijk
        $bookingId = (int) ($d->booking_id ?? 0);
        if ($resolutionType === 'client' && $bookingId > 0) {
            $b = DB::table('gymies_bookings')->where('id', $bookingId)->first();
            if ($b && !in_array((string) ($b->status ?? ''), ['cancelled', 'completed'], true)) {
                DB::table('gymies_bookings')->where('id', $bookingId)->update([
                    'status' => 'cancelled', 'updated_at' => now(), 'cancelled_at' => now(),
                ]);
            }
        }

        // Release payout hold
        if (Schema::hasTable('gymies_payouts') && Schema::hasColumn('gymies_payouts', 'is_held')) {
            DB::table('gymies_payouts')
                ->where('booking_id', $bookingId)->where('is_held', 1)
                ->update(['is_held' => 0, 'released_at' => now()]);
        }

        $this->auditLog((int) $staff->id, 'staff.dispute.resolved', 'dispute', $id, [
            'resolution_type' => $resolutionType, 'reason' => $reason, 'booking_id' => $bookingId,
        ]);

        // Push notificatie naar beide partijen
        try {
            $clientUid = (int) ($d->client_user_id ?? 0);
            $trainerUid = (int) ($d->trainer_user_id ?? 0);
            // Fallback: haal IDs op vanuit de booking als dispute die niet direct heeft
            if (($clientUid === 0 || $trainerUid === 0) && $bookingId > 0) {
                $bk = DB::table('gymies_bookings')->where('id', $bookingId)->first();
                if ($bk) {
                    $clientUid = $clientUid ?: (int) ($bk->client_user_id ?? 0);
                    $trainerUid = $trainerUid ?: (int) ($bk->trainer_user_id ?? 0);
                }
            }
            if ($clientUid > 0 || $trainerUid > 0) {
                (new \App\Services\OnboardingNotificationService())->notifyDisputeResolved(
                    $clientUid, $trainerUid, $id, $resolutionType
                );
            }
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: dispute.resolved', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => 'Geschil opgelost.']);
    }

    /**
     * Bericht toevoegen aan dispute thread.
     */
    public function staffAddDisputeMessage(Request $request, string $disputeId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate(['message' => 'required|string|max:2000']);

        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['message' => 'Disputes niet beschikbaar.'], 503);
        }

        $id = (int) $disputeId;
        $d = DB::table('gymies_disputes')->where('id', $id)->first();
        if (!$d) return response()->json(['message' => 'Dispute niet gevonden.'], 404);

        // Zorg dat dispute_messages tabel bestaat
        if (!Schema::hasTable('gymies_dispute_messages')) {
            return response()->json(['message' => 'Dispute berichten tabel ontbreekt.'], 503);
        }

        $msgId = DB::table('gymies_dispute_messages')->insertGetId([
            'dispute_id'   => $id,
            'user_id'      => (int) $staff->id,
            'message'      => trim((string) $request->input('message')),
            'sender_type'  => 'staff',
            'created_at'   => now(),
        ]);

        // Update dispute status naar in_progress als het open was
        if (($d->status ?? '') === 'open') {
            DB::table('gymies_disputes')->where('id', $id)->update(['status' => 'in_progress', 'updated_at' => now()]);
        }

        // Push notificatie naar beide partijen van het geschil
        try {
            $clientUid = (int) ($d->client_user_id ?? 0);
            $trainerUid = (int) ($d->trainer_user_id ?? 0);
            $staffName = $staff->name ?? 'Gymies Support';
            foreach (array_filter([$clientUid, $trainerUid]) as $recipientId) {
                (new \App\Services\OnboardingNotificationService())->notifyDisputeMessage(
                    $recipientId, $id, $staffName
                );
            }
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: dispute.message', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message_id' => $msgId]);
    }

    /**
     * Dispute detail met berichten.
     */
    public function staffDisputeDetail(Request $request, string $disputeId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['message' => 'Disputes niet beschikbaar.'], 503);
        }

        $id = (int) $disputeId;
        $d = DB::table('gymies_disputes')->where('id', $id)->first();
        if (!$d) return response()->json(['message' => 'Dispute niet gevonden.'], 404);

        $result = (array) $d;

        // Verrijk met namen
        $client = DB::table('gymies_users')->where('id', $d->client_user_id ?? 0)->first();
        $trainer = DB::table('gymies_users')->where('id', $d->trainer_user_id ?? 0)->first();
        $result['client_name'] = trim(($client->first_name ?? '') . ' ' . ($client->last_name ?? '')) ?: ($client->display_name ?? '');
        $result['trainer_name'] = trim(($trainer->first_name ?? '') . ' ' . ($trainer->last_name ?? '')) ?: ($trainer->display_name ?? '');

        // Booking info
        if ($d->booking_id ?? 0) {
            $result['booking'] = DB::table('gymies_bookings')->where('id', (int) $d->booking_id)->first();
        }

        // Berichten
        $messages = [];
        if (Schema::hasTable('gymies_dispute_messages')) {
            $messages = DB::table('gymies_dispute_messages as m')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'm.user_id')
                ->where('m.dispute_id', $id)
                ->orderBy('m.created_at')
                ->get(['m.*', 'u.display_name as sender_name'])
                ->toArray();
        }
        $result['messages'] = $messages;

        return response()->json($result);
    }

    // ─── I.2: Ticket Aanmaken ───────────────────────────────────

    /**
     * Ticket aanmaken namens klant of trainer.
     */
    public function staffCreateTicket(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'subject'     => 'required|string|max:255',
            'description' => 'required|string|max:5000',
            'user_id'     => 'nullable|integer|min:1',
            'priority'    => 'nullable|in:low,medium,high,urgent',
            'category'    => 'nullable|string|max:100',
        ]);

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Tickets tabel niet beschikbaar.'], 503);
        }

        $userId = $request->input('user_id') ? (int) $request->input('user_id') : null;

        // Valideer dat user bestaat als opgegeven
        if ($userId && !DB::table('gymies_users')->where('id', $userId)->exists()) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        $ticketId = DB::table('gymies_support_tickets')->insertGetId([
            'user_id'            => $userId,
            'subject'            => trim((string) $request->input('subject')),
            'description'        => trim((string) $request->input('description')),
            'status'             => 'new',
            'priority'           => $request->input('priority', 'medium'),
            'category'           => $request->input('category'),
            'assigned_to_user_id' => (int) $staff->id,
            'created_by_staff_id' => (int) $staff->id,
            'created_at'         => now(),
            'updated_at'         => now(),
        ]);

        $this->auditLog((int) $staff->id, 'staff.ticket.created', 'ticket', (int) $ticketId, [
            'subject'  => (string) $request->input('subject'),
            'user_id'  => $userId,
            'priority' => $request->input('priority', 'medium'),
        ]);

        // Push notificatie naar alle staff
        try {
            (new \App\Services\OnboardingNotificationService())->notifyStaffNewTicket(
                (int) $ticketId,
                (string) $request->input('subject'),
                $user->name ?? 'Onbekend'
            );
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: staff.ticket.created', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'ticket_id' => $ticketId], 201);
    }

    // ─── I.3: Booking Annuleren + Herschikken ───────────────────

    /**
     * Booking annuleren door staff.
     */
    public function staffCancelBooking(Request $request, string $bookingId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate(['reason' => 'required|string|max:500']);

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }

        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) return response()->json(['message' => 'Boeking niet gevonden.'], 404);

        if (in_array((string) ($b->status ?? ''), ['cancelled', 'completed'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet meer geannuleerd worden.'], 422);
        }

        $update = ['status' => 'cancelled', 'updated_at' => now(), 'cancelled_at' => now()];
        if (Schema::hasColumn('gymies_bookings', 'cancelled_by_user_id')) {
            $update['cancelled_by_user_id'] = (int) $staff->id;
        }
        DB::table('gymies_bookings')->where('id', $id)->update($update);

        $this->auditLog((int) $staff->id, 'staff.booking.cancelled', 'booking', $id, [
            'reason' => (string) $request->input('reason'),
        ]);

        // Push notificatie naar trainer + client
        try {
            (new \App\Services\OnboardingNotificationService())->notifyBookingCancelled(
                $id,
                (int) ($b->trainer_user_id ?? 0),
                (int) ($b->client_user_id ?? 0),
                (string) $request->input('reason')
            );
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: booking.cancelled', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => 'Boeking geannuleerd.']);
    }

    /**
     * Booking herschikken door staff.
     */
    public function staffRescheduleBooking(Request $request, string $bookingId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'scheduled_at' => 'required|date',
            'reason'       => 'required|string|max:500',
        ]);

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }

        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) return response()->json(['message' => 'Boeking niet gevonden.'], 404);

        if (in_array((string) ($b->status ?? ''), ['cancelled', 'completed'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet verplaatst worden.'], 422);
        }

        $oldAt = $b->scheduled_at;
        $newAt = (string) $request->input('scheduled_at');

        DB::table('gymies_bookings')->where('id', $id)->update([
            'scheduled_at' => $newAt, 'updated_at' => now(),
        ]);

        $this->auditLog((int) $staff->id, 'staff.booking.rescheduled', 'booking', $id, [
            'reason' => (string) $request->input('reason'),
            'old_scheduled_at' => $oldAt, 'new_scheduled_at' => $newAt,
        ]);

        // Push notificatie naar trainer + client
        try {
            (new \App\Services\OnboardingNotificationService())->notifyBookingRescheduled(
                $id,
                (int) ($b->trainer_user_id ?? 0),
                (int) ($b->client_user_id ?? 0),
                $newAt
            );
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: booking.rescheduled', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => 'Boeking verplaatst.']);
    }

    /**
     * Booking detail ophalen (volledige info).
     */
    public function staffBookingDetail(Request $request, string $bookingId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }

        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) return response()->json(['message' => 'Boeking niet gevonden.'], 404);

        $result = (array) $b;

        // Verrijk met namen
        $client = DB::table('gymies_users')->where('id', $b->client_user_id ?? 0)->first();
        $trainer = DB::table('gymies_users')->where('id', $b->trainer_user_id ?? 0)->first();
        $result['client_name'] = trim(($client->first_name ?? '') . ' ' . ($client->last_name ?? '')) ?: ($client->display_name ?? '');
        $result['trainer_name'] = trim(($trainer->first_name ?? '') . ' ' . ($trainer->last_name ?? '')) ?: ($trainer->display_name ?? '');
        $result['client_email'] = $client->email ?? '';
        $result['trainer_email'] = $trainer->email ?? '';

        // Betaalinfo
        if (Schema::hasTable('gymies_payments')) {
            $result['payments'] = DB::table('gymies_payments')
                ->where('booking_id', $id)->orderByDesc('created_at')
                ->get()->toArray();
        }

        return response()->json($result);
    }

    // ─── I.4: Refund / Credit ───────────────────────────────────

    /**
     * Refund of credit toekennen bij booking problemen.
     * Staff kan alleen wallet_credit en partial_refund (max €50). Full refund = admin-only.
     */
    public function staffRefundOrCredit(Request $request, string $bookingId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'type'         => 'required|in:partial_refund,wallet_credit',
            'amount_cents' => 'required|integer|min:1|max:5000', // max €50 voor staff
            'reason'       => 'required|string|max:500',
        ]);

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }

        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) return response()->json(['message' => 'Boeking niet gevonden.'], 404);

        $type = (string) $request->input('type');
        $amountCents = (int) $request->input('amount_cents');
        $reason = trim((string) $request->input('reason'));
        $bookingAmountCents = (int) ($b->amount_cents ?? 0);

        if ($amountCents > $bookingAmountCents) {
            $amountCents = $bookingAmountCents;
        }

        $clientUserId = (int) ($b->client_user_id ?? 0);
        $refundStatus = 'pending';

        // Wallet credit: direct toevoegen
        if ($type === 'wallet_credit') {
            if (!Schema::hasTable('gymies_wallet_transactions') || !Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
                return response()->json(['message' => 'Wallet niet beschikbaar.'], 503);
            }
            DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
            $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);

            $walletInsert = [
                'user_id'             => $clientUserId,
                'amount_cents'        => $amountCents,
                'balance_after_cents' => $newBalance,
                'booking_id'          => $id,
                'reason'              => $reason,
                'reference_type'      => 'staff_refund_credit',
                'admin_user_id'       => (int) $staff->id,
                'created_at'          => now(),
            ];
            if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                $walletInsert['expires_at'] = now()->addYear()->toDateString();
            }
            DB::table('gymies_wallet_transactions')->insert($walletInsert);
            $refundStatus = 'completed';
        }

        // Log refund
        if (Schema::hasTable('gymies_admin_refunds')) {
            DB::table('gymies_admin_refunds')->insert([
                'booking_id'      => $id,
                'client_user_id'  => $clientUserId,
                'type'            => $type,
                'amount_cents'    => $amountCents,
                'status'          => $refundStatus,
                'reason'          => $reason,
                'created_by_user_id' => (int) $staff->id,
                'created_at'      => now(),
            ]);
        }

        $this->auditLog((int) $staff->id, 'staff.refund.issued', 'booking', $id, [
            'type' => $type, 'amount_cents' => $amountCents, 'reason' => $reason,
        ]);

        // Push notificatie naar client
        try {
            if ($clientUserId > 0) {
                (new \App\Services\OnboardingNotificationService())->notifyRefundProcessed(
                    $clientUserId, $type, $amountCents, $id
                );
            }
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: refund.processed', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => 'Refund/credit verwerkt.', 'amount_cents' => $amountCents]);
    }

    // ─── I.5: Trainer Documenten Goedkeuren/Afkeuren ────────────

    /**
     * Trainer document goedkeuren of afkeuren.
     */
    public function staffReviewDocument(Request $request, string $documentId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'status' => 'required|in:approved,rejected',
            'reason' => 'nullable|string|max:500',
        ]);

        if (!Schema::hasTable('gymies_trainer_documents')) {
            return response()->json(['message' => 'Documenten tabel niet beschikbaar.'], 503);
        }

        $id = (int) $documentId;
        $doc = DB::table('gymies_trainer_documents')->where('id', $id)->first();
        if (!$doc) return response()->json(['message' => 'Document niet gevonden.'], 404);

        $newStatus = (string) $request->input('status');

        $update = [
            'status'          => $newStatus,
            'reviewed_by'     => (int) $staff->id,
            'reviewed_at'     => now(),
            'updated_at'      => now(),
        ];
        if ($newStatus === 'rejected' && $request->filled('reason')) {
            $update['rejection_reason'] = trim((string) $request->input('reason'));
        }

        DB::table('gymies_trainer_documents')->where('id', $id)->update($update);

        $this->auditLog((int) $staff->id, 'staff.document.' . $newStatus, 'document', $id, [
            'user_id'       => $doc->user_id ?? 0,
            'document_type' => $doc->document_type ?? '',
            'reason'        => $request->input('reason'),
        ]);

        // Push notificatie naar trainer
        try {
            $trainerUserId = (int) ($doc->user_id ?? 0);
            if ($trainerUserId > 0) {
                (new \App\Services\OnboardingNotificationService())->notifyDocumentReviewed(
                    $trainerUserId,
                    (string) ($doc->document_type ?? 'document'),
                    $newStatus,
                    $newStatus === 'rejected' ? $request->input('reason') : null
                );
            }
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: document.reviewed', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => "Document $newStatus."]);
    }

    // ─── I.6: Trainer Notities ──────────────────────────────────

    /**
     * Self-healing: staff notities tabel.
     */
    private function ensureStaffNotesTable(): void
    {
        if (Schema::hasTable('gymies_staff_notes')) return;
        try {
            DB::statement("
                CREATE TABLE IF NOT EXISTS gymies_staff_notes (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    user_id BIGINT UNSIGNED NOT NULL COMMENT 'Trainer/klant user_id',
                    author_id BIGINT UNSIGNED NOT NULL COMMENT 'Staff user_id',
                    note TEXT NOT NULL,
                    is_pinned TINYINT(1) DEFAULT 0,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    KEY idx_staff_notes_user (user_id),
                    KEY idx_staff_notes_author (author_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('ensureStaffNotesTable failed', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Notities ophalen voor een trainer/gebruiker.
     */
    public function staffTrainerNotes(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $this->ensureStaffNotesTable();

        $id = (int) $userId;
        $notes = DB::table('gymies_staff_notes as n')
            ->leftJoin('gymies_users as a', 'a.id', '=', 'n.author_id')
            ->where('n.user_id', $id)
            ->orderByDesc('n.created_at')
            ->get(['n.id', 'n.note', 'n.is_pinned', 'n.created_at', 'a.display_name as author_name']);

        return response()->json(['data' => $notes]);
    }

    /**
     * Notitie toevoegen bij trainer/gebruiker.
     */
    public function staffAddTrainerNote(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate(['note' => 'required|string|max:5000']);

        $this->ensureStaffNotesTable();

        $id = (int) $userId;
        if (!DB::table('gymies_users')->where('id', $id)->exists()) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        $noteId = DB::table('gymies_staff_notes')->insertGetId([
            'user_id'    => $id,
            'author_id'  => (int) $staff->id,
            'note'       => trim((string) $request->input('note')),
            'created_at' => now(),
        ]);

        $this->auditLog((int) $staff->id, 'staff.note.added', 'user', $id, ['note_id' => $noteId]);

        return response()->json(['success' => true, 'note_id' => $noteId], 201);
    }

    // ─── I.7: Nudge Push Notificatie ────────────────────────────

    /**
     * Push notificatie (nudge) sturen naar individuele trainer/klant.
     */
    public function staffSendNudge(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'user_id'    => 'required|integer|min:1',
            'title'      => 'required|string|max:255',
            'body'       => 'required|string|max:2000',
            'nudge_type' => 'nullable|in:push,reminder',
        ]);

        $userId = (int) $request->input('user_id');
        if (!DB::table('gymies_users')->where('id', $userId)->exists()) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        $nudgeType = $request->input('nudge_type', 'push');

        // Log nudge (admin_nudges tabel hergebruiken als die bestaat)
        if (Schema::hasTable('gymies_admin_nudges')) {
            DB::table('gymies_admin_nudges')->insert([
                'user_id'            => $userId,
                'nudge_type'         => $nudgeType,
                'title'              => trim((string) $request->input('title')),
                'body'               => trim((string) $request->input('body')),
                'created_by_user_id' => (int) $staff->id,
                'created_at'         => now(),
            ]);
        }

        // Push notificatie via OnboardingNotificationService
        try {
            $notifier = new \App\Services\OnboardingNotificationService();
            $notifier->sendPush($userId, (string) $request->input('title'), (string) $request->input('body'));
        } catch (\Throwable $e) {
            Log::warning('staffSendNudge push failed', ['error' => $e->getMessage()]);
        }

        $this->auditLog((int) $staff->id, 'staff.nudge.sent', 'user', $userId, [
            'nudge_type' => $nudgeType, 'title' => (string) $request->input('title'),
        ]);

        return response()->json(['success' => true, 'message' => 'Nudge verstuurd.']);
    }

    // ─── I.8: Trainer-Klant Chat Inzien ─────────────────────────

    /**
     * Read-only: conversations tussen trainer en klant bekijken voor support context.
     */
    public function staffViewConversation(Request $request, string $conversationId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_conversations') || !Schema::hasTable('gymies_conversation_messages')) {
            return response()->json(['message' => 'Berichten systeem niet beschikbaar.'], 503);
        }

        $id = (int) $conversationId;
        $conv = DB::table('gymies_conversations')->where('id', $id)->first();
        if (!$conv) return response()->json(['message' => 'Gesprek niet gevonden.'], 404);

        $result = (array) $conv;

        // Participant namen
        $user1 = DB::table('gymies_users')->where('id', $conv->user_id_1 ?? 0)->first();
        $user2 = DB::table('gymies_users')->where('id', $conv->user_id_2 ?? 0)->first();
        $result['user1_name'] = $user1->display_name ?? '';
        $result['user2_name'] = $user2->display_name ?? '';

        // Berichten (laatste 50)
        $limit = min((int) $request->query('limit', 50), 100);
        $messages = DB::table('gymies_conversation_messages as m')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'm.sender_id')
            ->where('m.conversation_id', $id)
            ->orderByDesc('m.created_at')
            ->limit($limit)
            ->get(['m.id', 'm.sender_id', 'm.message', 'm.created_at', 'u.display_name as sender_name'])
            ->reverse()->values()->toArray();

        $result['messages'] = $messages;

        $this->auditLog((int) $staff->id, 'staff.conversation.viewed', 'conversation', $id, []);

        return response()->json($result);
    }

    /**
     * Conversations zoeken op user_id (voor support bij ticket/dispute).
     */
    public function staffUserConversations(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_conversations')) {
            return response()->json(['data' => []]);
        }

        $id = (int) $userId;
        $convs = DB::table('gymies_conversations as c')
            ->where('c.user_id_1', $id)->orWhere('c.user_id_2', $id)
            ->orderByDesc('c.updated_at')
            ->limit(20)
            ->get();

        $enriched = $convs->map(function ($c) use ($id) {
            $otherId = ($c->user_id_1 ?? 0) == $id ? ($c->user_id_2 ?? 0) : ($c->user_id_1 ?? 0);
            $other = DB::table('gymies_users')->where('id', $otherId)->first();
            $c->other_user_name = $other->display_name ?? '';
            $c->other_user_email = $other->email ?? '';

            // Laatste bericht
            if (Schema::hasTable('gymies_conversation_messages')) {
                $last = DB::table('gymies_conversation_messages')
                    ->where('conversation_id', $c->id)
                    ->orderByDesc('created_at')->first(['message', 'created_at']);
                $c->last_message = $last->message ?? '';
                $c->last_message_at = $last->created_at ?? '';
            }
            return $c;
        });

        return response()->json(['data' => $enriched]);
    }

    // ─── I.9: Groepslessen Monitor ──────────────────────────────

    /**
     * Groepslessen overzicht (vandaag + aankomende week).
     */
    public function staffGroupSessions(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_group_sessions')) {
            return response()->json(['message' => 'Groepslessen niet beschikbaar.'], 503);
        }

        $now = now();
        $weekEnd = now()->addDays(7);

        $sessions = DB::table('gymies_group_sessions as gs')
            ->leftJoin('gymies_users as t', 't.id', '=', 'gs.trainer_user_id')
            ->whereBetween('gs.scheduled_at', [$now->startOfDay(), $weekEnd->endOfDay()])
            ->orderBy('gs.scheduled_at')
            ->get([
                'gs.id', 'gs.title', 'gs.scheduled_at', 'gs.status', 'gs.price_cents',
                'gs.min_participants', 'gs.max_participants', 'gs.trainer_user_id',
                't.display_name as trainer_name',
            ]);

        // Verrijk met deelnemersaantallen
        $enriched = $sessions->map(function ($s) {
            if (Schema::hasTable('gymies_group_session_participants')) {
                $s->participant_count = (int) DB::table('gymies_group_session_participants')
                    ->where('group_session_id', $s->id)
                    ->where('status', 'confirmed')
                    ->count();
            } else {
                $s->participant_count = 0;
            }
            return $s;
        });

        // Stats
        $todayCount = $enriched->filter(fn ($s) => \Carbon\Carbon::parse($s->scheduled_at)->isToday())->count();
        $lowEnrollment = $enriched->filter(fn ($s) => $s->participant_count < ($s->min_participants ?? 1))->count();

        return response()->json([
            'data' => $enriched,
            'stats' => [
                'today' => $todayCount,
                'this_week' => $enriched->count(),
                'low_enrollment' => $lowEnrollment,
            ],
        ]);
    }

    /**
     * Groepsles detail met deelnemerslijst.
     */
    public function staffGroupSessionDetail(Request $request, string $sessionId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_group_sessions')) {
            return response()->json(['message' => 'Groepslessen niet beschikbaar.'], 503);
        }

        $id = (int) $sessionId;
        $session = DB::table('gymies_group_sessions')->where('id', $id)->first();
        if (!$session) return response()->json(['message' => 'Groepsles niet gevonden.'], 404);

        $result = (array) $session;

        // Trainer naam
        $trainer = DB::table('gymies_users')->where('id', $session->trainer_user_id ?? 0)->first();
        $result['trainer_name'] = $trainer->display_name ?? '';

        // Deelnemers
        if (Schema::hasTable('gymies_group_session_participants')) {
            $participants = DB::table('gymies_group_session_participants as p')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'p.user_id')
                ->where('p.group_session_id', $id)
                ->get(['p.id', 'p.user_id', 'p.status', 'p.created_at', 'u.display_name as name', 'u.email']);
            $result['participants'] = $participants->toArray();
        }

        // Waitlist
        if (Schema::hasTable('gymies_group_session_waitlist')) {
            $waitlist = DB::table('gymies_group_session_waitlist as w')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'w.user_id')
                ->where('w.group_session_id', $id)
                ->get(['w.id', 'w.user_id', 'w.created_at', 'u.display_name as name']);
            $result['waitlist'] = $waitlist->toArray();
        }

        return response()->json($result);
    }

    // ─── I.10: Betalingen Overzicht (read-only) ─────────────────

    /**
     * Recente betalingen/transacties overzicht voor staff.
     */
    public function staffPaymentsOverview(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_payments')) {
            return response()->json(['data' => [], 'stats' => []]);
        }

        $page = max(1, (int) $request->query('page', 1));
        $perPage = min(50, max(10, (int) $request->query('per_page', 25)));
        $status = trim((string) $request->query('status', ''));

        $query = DB::table('gymies_payments as p')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'p.user_id')
            ->orderByDesc('p.created_at');

        if ($status !== '') {
            $query->where('p.status', $status);
        }

        $total = $query->count();
        $payments = $query->offset(($page - 1) * $perPage)->limit($perPage)
            ->get([
                'p.id', 'p.booking_id', 'p.user_id', 'p.amount_cents', 'p.status',
                'p.payment_method', 'p.mollie_payment_id', 'p.created_at',
                'c.display_name as client_name', 'c.email as client_email',
            ]);

        // Stats (vandaag)
        $todayStart = now()->startOfDay();
        $todayTotal = (int) DB::table('gymies_payments')
            ->where('created_at', '>=', $todayStart)->where('status', 'paid')
            ->sum('amount_cents');
        $todayCount = (int) DB::table('gymies_payments')
            ->where('created_at', '>=', $todayStart)->where('status', 'paid')
            ->count();
        $failedToday = (int) DB::table('gymies_payments')
            ->where('created_at', '>=', $todayStart)->where('status', 'failed')
            ->count();

        return response()->json([
            'data'     => $payments,
            'total'    => $total,
            'page'     => $page,
            'per_page' => $perPage,
            'stats'    => [
                'today_revenue_cents' => $todayTotal,
                'today_count'         => $todayCount,
                'today_failed'        => $failedToday,
            ],
        ]);
    }

    // ─── I.11: Subscription Beheer ──────────────────────────────

    /**
     * Subscription toewijzen aan trainer.
     */
    public function staffAssignSubscription(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'plan_id' => 'required|integer|min:1',
            'reason'  => 'required|string|max:500',
        ]);

        if (!Schema::hasTable('gymies_subscriptions') || !Schema::hasTable('gymies_plans')) {
            return response()->json(['message' => 'Subscriptions niet beschikbaar.'], 503);
        }

        $uid = (int) $userId;
        if (!DB::table('gymies_users')->where('id', $uid)->exists()) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        $planId = (int) $request->input('plan_id');
        $plan = DB::table('gymies_plans')->where('id', $planId)->first();
        if (!$plan) return response()->json(['message' => 'Plan niet gevonden.'], 404);

        // Check bestaande actieve subscription
        $existing = DB::table('gymies_subscriptions')
            ->where('user_id', $uid)->whereIn('status', ['active', 'trialing'])
            ->first();

        if ($existing) {
            // Update bestaande
            DB::table('gymies_subscriptions')->where('id', $existing->id)->update([
                'plan_id'    => $planId,
                'updated_at' => now(),
            ]);
        } else {
            // Nieuwe subscription
            DB::table('gymies_subscriptions')->insert([
                'user_id'    => $uid,
                'plan_id'    => $planId,
                'status'     => 'active',
                'started_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        $this->auditLog((int) $staff->id, 'staff.subscription.assigned', 'user', $uid, [
            'plan_id' => $planId, 'plan_name' => $plan->name ?? '', 'reason' => (string) $request->input('reason'),
        ]);

        // Push notificatie naar trainer
        try {
            (new \App\Services\OnboardingNotificationService())->notifySubscriptionChanged(
                $uid, 'assigned', $plan->name ?? null
            );
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: subscription.assigned', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => 'Subscription toegewezen.']);
    }

    /**
     * Subscription pauzeren/hervatten.
     */
    public function staffToggleSubscription(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'action' => 'required|in:pause,resume',
            'reason' => 'required|string|max:500',
        ]);

        if (!Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['message' => 'Subscriptions niet beschikbaar.'], 503);
        }

        $uid = (int) $userId;
        $action = (string) $request->input('action');
        $sub = DB::table('gymies_subscriptions')
            ->where('user_id', $uid)
            ->whereIn('status', $action === 'pause' ? ['active'] : ['paused'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen actieve/gepauzeerde subscription gevonden.'], 404);
        }

        $newStatus = $action === 'pause' ? 'paused' : 'active';
        DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
            'status' => $newStatus, 'updated_at' => now(),
        ]);

        $this->auditLog((int) $staff->id, "staff.subscription.$action", 'user', $uid, [
            'subscription_id' => $sub->id, 'reason' => (string) $request->input('reason'),
        ]);

        // Push notificatie naar trainer
        try {
            (new \App\Services\OnboardingNotificationService())->notifySubscriptionChanged(
                $uid, $action === 'pause' ? 'paused' : 'resumed', null
            );
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: subscription.' . $action, ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => "Subscription $action uitgevoerd."]);
    }

    // ─── I.12: Ticket Samenvoegen + Escalatie ───────────────────

    /**
     * Twee tickets samenvoegen (merge).
     */
    public function staffMergeTickets(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate([
            'primary_ticket_id'   => 'required|integer|min:1',
            'secondary_ticket_id' => 'required|integer|min:1',
        ]);

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Tickets niet beschikbaar.'], 503);
        }

        $primaryId = (int) $request->input('primary_ticket_id');
        $secondaryId = (int) $request->input('secondary_ticket_id');

        if ($primaryId === $secondaryId) {
            return response()->json(['message' => 'Kan een ticket niet met zichzelf mergen.'], 422);
        }

        $primary = DB::table('gymies_support_tickets')->where('id', $primaryId)->first();
        $secondary = DB::table('gymies_support_tickets')->where('id', $secondaryId)->first();

        if (!$primary || !$secondary) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        // Verplaats berichten van secondary naar primary
        if (Schema::hasTable('gymies_support_ticket_messages')) {
            DB::table('gymies_support_ticket_messages')
                ->where('ticket_id', $secondaryId)
                ->update(['ticket_id' => $primaryId]);
        }

        // Sluit secondary ticket
        DB::table('gymies_support_tickets')->where('id', $secondaryId)->update([
            'status'     => 'closed',
            'updated_at' => now(),
        ]);

        // Voeg merge notitie toe als bericht
        if (Schema::hasTable('gymies_support_ticket_messages')) {
            DB::table('gymies_support_ticket_messages')->insert([
                'ticket_id'   => $primaryId,
                'user_id'     => (int) $staff->id,
                'message'     => "[Systeem] Ticket #$secondaryId is samengevoegd met dit ticket.",
                'is_internal' => true,
                'created_at'  => now(),
            ]);
        }

        $this->auditLog((int) $staff->id, 'staff.ticket.merged', 'ticket', $primaryId, [
            'merged_ticket_id' => $secondaryId,
        ]);

        return response()->json(['success' => true, 'message' => "Ticket #$secondaryId samengevoegd met #$primaryId."]);
    }

    /**
     * Ticket escaleren naar admin.
     */
    public function staffEscalateTicket(Request $request, string $ticketId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $request->validate(['reason' => 'required|string|max:500']);

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Tickets niet beschikbaar.'], 503);
        }

        $id = (int) $ticketId;
        $ticket = DB::table('gymies_support_tickets')->where('id', $id)->first();
        if (!$ticket) return response()->json(['message' => 'Ticket niet gevonden.'], 404);

        $update = ['priority' => 'urgent', 'updated_at' => now()];
        if (Schema::hasColumn('gymies_support_tickets', 'escalated_at')) {
            $update['escalated_at'] = now();
        }
        if (Schema::hasColumn('gymies_support_tickets', 'escalated_by')) {
            $update['escalated_by'] = (int) $staff->id;
        }
        DB::table('gymies_support_tickets')->where('id', $id)->update($update);

        // Intern bericht
        if (Schema::hasTable('gymies_support_ticket_messages')) {
            DB::table('gymies_support_ticket_messages')->insert([
                'ticket_id'   => $id,
                'user_id'     => (int) $staff->id,
                'message'     => '[Escalatie] ' . trim((string) $request->input('reason')),
                'is_internal' => true,
                'created_at'  => now(),
            ]);
        }

        $this->auditLog((int) $staff->id, 'staff.ticket.escalated', 'ticket', $id, [
            'reason' => (string) $request->input('reason'),
        ]);

        // Push notificatie naar admins
        try {
            (new \App\Services\OnboardingNotificationService())->notifyAdminTicketEscalated(
                $id,
                (string) ($ticket->subject ?? 'Ticket #' . $id),
                (string) $request->input('reason')
            );
        } catch (\Throwable $e) {
            Log::warning('Push notify failed: ticket.escalated', ['error' => $e->getMessage()]);
        }

        return response()->json(['success' => true, 'message' => 'Ticket geëscaleerd naar urgent.']);
    }

    // ─── I.13: Gym/Studio Overzicht (read-only) ─────────────────

    /**
     * Gym/studio overzicht met trainers.
     */
    public function staffGymsOverview(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_organisations')) {
            return response()->json(['data' => [], 'total' => 0]);
        }

        $page = max(1, (int) $request->query('page', 1));
        $perPage = 25;

        $total = (int) DB::table('gymies_organisations')->count();
        $orgs = DB::table('gymies_organisations')
            ->orderBy('name')
            ->offset(($page - 1) * $perPage)->limit($perPage)
            ->get();

        $enriched = $orgs->map(function ($org) {
            $org->member_count = 0;
            $org->trainer_count = 0;
            if (Schema::hasTable('gymies_organisation_members')) {
                $org->member_count = (int) DB::table('gymies_organisation_members')
                    ->where('organisation_id', $org->id)->count();
                $org->trainer_count = (int) DB::table('gymies_organisation_members')
                    ->where('organisation_id', $org->id)->where('role', 'trainer')->count();
            }
            return $org;
        });

        return response()->json(['data' => $enriched, 'total' => $total, 'page' => $page]);
    }

    // ─── FIX #82: Gym Revenue Analytics ─────────────────────────

    /**
     * Gym revenue analytics endpoint.
     * Queries bookings where organisation_id = gymId, grouped by month.
     * Returns: monthly_revenue[], total_revenue, active_trainers_count, total_bookings
     */
    public function gymRevenueAnalytics(Request $request, string $gymId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []], 503);
        }

        $gymId = (int) $gymId;

        // Maandelijkse omzet
        $monthlyRevenue = DB::table('gymies_bookings')
            ->where('organisation_id', $gymId)
            ->whereIn('status', ['completed', 'confirmed'])
            ->selectRaw("DATE_FORMAT(scheduled_at, '%Y-%m') as month, SUM(price_cents) as revenue_cents")
            ->groupByRaw("DATE_FORMAT(scheduled_at, '%Y-%m')")
            ->orderBy('month', 'desc')
            ->limit(12)
            ->get();

        // Totale omzet
        $totalRevenue = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $gymId)
            ->whereIn('status', ['completed', 'confirmed'])
            ->sum('price_cents') ?? 0;

        // Actieve trainers
        $activeTrainers = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $gymId)
            ->distinct('trainer_user_id')
            ->count('trainer_user_id');

        // Totaal bookings
        $totalBookings = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $gymId)
            ->count();

        return response()->json([
            'monthly_revenue' => $monthlyRevenue->map(function ($row) {
                return [
                    'month' => $row->month,
                    'revenue_cents' => (int) $row->revenue_cents,
                ];
            }),
            'total_revenue' => $totalRevenue,
            'active_trainers_count' => $activeTrainers,
            'total_bookings' => $totalBookings,
        ]);
    }

    // ─── FIX #83: Bulk Member Import ───────────────────────────

    /**
     * Bulk member import endpoint.
     * Accepts JSON array of {name, email, role}.
     * Validates each entry, inserts into gymies_gym_teams.
     * Returns: imported_count, skipped_count, errors[]
     */
    public function gymBulkImportMembers(Request $request, string $gymId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_gym_teams')) {
            return response()->json(['message' => 'Gym teams table not available.'], 503);
        }

        $members = $request->input('members', []);
        if (!is_array($members)) {
            return response()->json(['message' => 'Members must be an array.'], 422);
        }

        $gymId = (int) $gymId;
        $imported = 0;
        $skipped = 0;
        $errors = [];

        foreach ($members as $idx => $member) {
            $name = trim((string) ($member['name'] ?? ''));
            $email = trim((string) ($member['email'] ?? ''));
            $role = trim((string) ($member['role'] ?? 'member'));

            if (!$name || !$email) {
                $errors[] = "Row {$idx}: name and email required";
                $skipped++;
                continue;
            }

            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
                $errors[] = "Row {$idx}: invalid email";
                $skipped++;
                continue;
            }

            // Probeer in te voegen
            try {
                DB::table('gymies_gym_teams')->insert([
                    'gym_id' => $gymId,
                    'name' => $name,
                    'email' => $email,
                    'role' => in_array($role, ['manager', 'coordinator', 'member']) ? $role : 'member',
                    'created_at' => now(),
                ]);
                $imported++;
            } catch (\Throwable $e) {
                $errors[] = "Row {$idx}: " . $e->getMessage();
                $skipped++;
            }
        }

        return response()->json([
            'imported_count' => $imported,
            'skipped_count' => $skipped,
            'errors' => $errors,
        ]);
    }

    // ─── FIX #88: Gym Occupancy Stats ──────────────────────────

    /**
     * Gym occupancy endpoint.
     * Current bookings today, peak hours, capacity utilization.
     */
    public function gymOccupancyStats(Request $request, string $gymId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []], 503);
        }

        $gymId = (int) $gymId;
        $today = now()->startOfDay();

        // Vandaag's bookings
        $todayBookings = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $gymId)
            ->whereDate('scheduled_at', $today)
            ->count();

        // Piekuren (meeste bookings per uur)
        $peakHours = DB::table('gymies_bookings')
            ->where('organisation_id', $gymId)
            ->whereDate('scheduled_at', $today)
            ->selectRaw("HOUR(scheduled_at) as hour, COUNT(*) as count")
            ->groupByRaw("HOUR(scheduled_at)")
            ->orderBy('count', 'desc')
            ->limit(3)
            ->get();

        // Capaciteit (aangenomen max 50 bookings per dag)
        $maxCapacity = 50;
        $utilization = min(100, ($todayBookings / $maxCapacity) * 100);

        return response()->json([
            'current_bookings_today' => $todayBookings,
            'peak_hours' => $peakHours->map(function ($row) {
                return [
                    'hour' => (int) $row->hour,
                    'bookings' => (int) $row->count,
                ];
            }),
            'capacity_utilization_percent' => round($utilization, 2),
        ]);
    }

    // ─── FIX #90: Ambassador Dashboard Data ────────────────────

    /**
     * Ambassador dashboard data endpoint.
     * Queries gymies_referrals where referrer_user_id = userId.
     * Returns: total_referrals, successful_conversions, pending_referrals, total_commission_cents
     */
    public function ambassadorDashboard(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_referrals')) {
            return response()->json(['data' => []], 503);
        }

        $userId = (int) $userId;

        // Totaal referrals
        $totalReferrals = (int) DB::table('gymies_referrals')
            ->where('referrer_user_id', $userId)
            ->limit(1000)
            ->count();

        // Geslaagde conversies
        $successfulConversions = (int) DB::table('gymies_referrals')
            ->where('referrer_user_id', $userId)
            ->where('status', 'completed')
            ->limit(1000)
            ->count();

        // Ausstehende referrals
        $pendingReferrals = (int) DB::table('gymies_referrals')
            ->where('referrer_user_id', $userId)
            ->where('status', 'pending')
            ->limit(1000)
            ->count();

        // Totale commissie
        $totalCommission = (int) DB::table('gymies_referrals')
            ->where('referrer_user_id', $userId)
            ->limit(1000)
            ->sum('reward_cents') ?? 0;

        return response()->json([
            'total_referrals' => $totalReferrals,
            'successful_conversions' => $successfulConversions,
            'pending_referrals' => $pendingReferrals,
            'total_commission_cents' => $totalCommission,
        ]);
    }

    // ─── FIX #94: Ambassador Payout History ────────────────────

    /**
     * Ambassador payout history endpoint.
     * Query gymies_ambassador_profiles + related payouts.
     */
    public function ambassadorPayoutHistory(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        if (!Schema::hasTable('gymies_ambassador_profiles')) {
            return response()->json(['data' => [], 'total' => 0], 503);
        }

        $userId = (int) $userId;

        // Ambassador profile
        $profile = DB::table('gymies_ambassador_profiles')
            ->where('user_id', $userId)
            ->first();

        if (!$profile) {
            return response()->json([
                'message' => 'Ambassador profile not found.',
                'data' => [],
                'total' => 0,
            ], 404);
        }

        // Payout history (aanname: gymies_payout_requests table)
        $payouts = [];
        if (Schema::hasTable('gymies_payout_requests')) {
            $payouts = DB::table('gymies_payout_requests')
                ->where('user_id', $userId)
                ->orderBy('created_at', 'desc')
                ->limit(50)
                ->get();
        }

        return response()->json([
            'profile' => $profile,
            'payouts' => $payouts,
            'total' => count($payouts),
        ]);
    }

    // ─── I.14: Trainer Earnings Report ──────────────────────────

    /**
     * Fix 64: Trainer earnings dashboard endpoint.
     * Returns: total_earned, pending_payouts, monthly_breakdown array
     */
    public function trainerEarningsReport(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $trainerId = (int) $userId;
        if ($trainerId <= 0) {
            return response()->json(['message' => 'Ongeldig trainer ID.'], 422);
        }

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => [
                'total_earned' => 0,
                'pending_payouts' => 0,
                'monthly_breakdown' => [],
            ]]);
        }

        $year = (int) $request->query('year', now()->year);

        $bookings = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereYear('scheduled_at', $year)
            ->where('status', 'completed')
            ->select(
                DB::raw('MONTH(scheduled_at) as month'),
                DB::raw('SUM(amount_cents) as total_cents'),
                DB::raw('COUNT(*) as count')
            )
            ->groupBy(DB::raw('MONTH(scheduled_at)'))
            ->get();

        $totalEarned = (int) ($bookings->sum('total_cents') ?? 0);

        $pendingPayouts = 0;
        if (Schema::hasTable('gymies_payouts')) {
            $pendingPayouts = (int) DB::table('gymies_payouts')
                ->where('trainer_user_id', $trainerId)
                ->where('status', 'pending')
                ->sum('amount_cents');
        }

        $monthlyBreakdown = $bookings->map(function ($row) {
            return [
                'month' => (int) $row->month,
                'total_cents' => (int) $row->total_cents,
                'booking_count' => (int) $row->count,
            ];
        })->toArray();

        return response()->json([
            'data' => [
                'total_earned' => $totalEarned,
                'pending_payouts' => $pendingPayouts,
                'monthly_breakdown' => $monthlyBreakdown,
            ],
        ]);
    }

    // ─── I.15: Trainer Profile Completeness ─────────────────────

    /**
     * Fix 65: Profile completeness endpoint.
     * Checks: bio, photo_url, kvk_number, iban, specializations
     */
    public function trainerProfileCompleteness(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $trainerId = (int) $userId;
        if ($trainerId <= 0) {
            return response()->json(['message' => 'Ongeldig trainer ID.'], 422);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['data' => [
                'percentage_complete' => 0,
                'missing_fields' => ['profile_not_found'],
            ]]);
        }

        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerId)
            ->first();

        if (!$profile) {
            return response()->json(['data' => [
                'percentage_complete' => 0,
                'missing_fields' => ['no_profile'],
            ]]);
        }

        $fields = ['bio', 'photo_url', 'kvk_number', 'iban', 'specializations'];
        $missingFields = [];

        foreach ($fields as $field) {
            if (empty($profile->{$field})) {
                $missingFields[] = $field;
            }
        }

        $complete = count($fields) - count($missingFields);
        $percentage = (int) (($complete / count($fields)) * 100);

        return response()->json([
            'data' => [
                'percentage_complete' => $percentage,
                'missing_fields' => $missingFields,
            ],
        ]);
    }

    // ─── I.16: Trainer Tax Report ───────────────────────────────

    /**
     * Fix 67: Tax report endpoint.
     * Returns: gross_revenue, net_payouts, vat_amount (21%), total_bookings_count
     */
    public function trainerTaxReport(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $trainerId = (int) $userId;
        if ($trainerId <= 0) {
            return response()->json(['message' => 'Ongeldig trainer ID.'], 422);
        }

        $year = (int) $request->query('year', now()->year);

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => [
                'gross_revenue' => 0,
                'net_payouts' => 0,
                'vat_amount' => 0,
                'total_bookings_count' => 0,
            ]]);
        }

        $bookings = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereYear('scheduled_at', $year)
            ->where('status', 'completed')
            ->select(
                DB::raw('SUM(amount_cents) as total_cents'),
                DB::raw('COUNT(*) as count')
            )
            ->first();

        $grossRevenue = (int) ($bookings->total_cents ?? 0);
        $bookingCount = (int) ($bookings->count ?? 0);

        $netPayouts = 0;
        if (Schema::hasTable('gymies_payouts')) {
            $netPayouts = (int) DB::table('gymies_payouts')
                ->where('trainer_user_id', $trainerId)
                ->whereYear('created_at', $year)
                ->where('status', 'completed')
                ->sum('amount_cents');
        }

        $vatAmount = (int) ($grossRevenue * 0.21);

        return response()->json([
            'data' => [
                'gross_revenue' => $grossRevenue,
                'net_payouts' => $netPayouts,
                'vat_amount' => $vatAmount,
                'total_bookings_count' => $bookingCount,
            ],
        ]);
    }

    // ─── I.17: Trainer Booking Stats ────────────────────────────

    /**
     * Fix 69: Trainer booking stats.
     * Returns: pending_count, confirmed_count, cancelled_count, acceptance_rate, avg_response_time
     */
    public function trainerBookingStats(Request $request, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $trainerId = (int) $userId;
        if ($trainerId <= 0) {
            return response()->json(['message' => 'Ongeldig trainer ID.'], 422);
        }

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => [
                'pending_count' => 0,
                'confirmed_count' => 0,
                'cancelled_count' => 0,
                'acceptance_rate' => 0.0,
                'avg_response_time_minutes' => 0,
            ]]);
        }

        $pendingCount = (int) DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('status', 'pending')
            ->count();

        $confirmedCount = (int) DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('status', 'confirmed')
            ->count();

        $cancelledCount = (int) DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('status', 'cancelled')
            ->count();

        $totalBookings = $pendingCount + $confirmedCount + $cancelledCount;
        $acceptanceRate = $totalBookings > 0 ? ($confirmedCount / $totalBookings) : 0.0;

        $avgResponseTime = 0;
        if (Schema::hasColumn('gymies_bookings', 'confirmed_at') && Schema::hasColumn('gymies_bookings', 'created_at')) {
            $result = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->where('status', 'confirmed')
                ->whereNotNull('confirmed_at')
                ->select(DB::raw('AVG(TIMESTAMPDIFF(MINUTE, created_at, confirmed_at)) as avg_minutes'))
                ->first();

            $avgResponseTime = (int) ($result->avg_minutes ?? 0);
        }

        return response()->json([
            'data' => [
                'pending_count' => $pendingCount,
                'confirmed_count' => $confirmedCount,
                'cancelled_count' => $cancelledCount,
                'acceptance_rate' => round($acceptanceRate, 2),
                'avg_response_time_minutes' => $avgResponseTime,
            ],
        ]);
    }

    // ─── Feature 1: Churn Prediction ────────────────────────────

    /**
     * Churn prediction rapport voor een gym.
     */
    public function gymChurnReport(Request $request, string $gymId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $orgId = (int) $gymId;
        $service = new \App\Services\ChurnPredictionService();

        // Optioneel herberekenen
        if ($request->boolean('recalculate', false)) {
            $service->recalculateForOrganisation($orgId);
        }

        if (!Schema::hasTable('gymies_churn_scores')) {
            return response()->json(['data' => [], 'summary' => ['high' => 0, 'medium' => 0, 'low' => 0]]);
        }

        $scores = DB::table('gymies_churn_scores as cs')
            ->leftJoin('gymies_users as u', 'cs.user_id', '=', 'u.id')
            ->where('cs.organisation_id', $orgId)
            ->orderByDesc('cs.score')
            ->limit(200)
            ->get([
                'cs.user_id', 'cs.score', 'cs.frequency_drop_score', 'cs.days_inactive_score',
                'cs.consistency_score', 'cs.contract_end_score', 'cs.cancellation_score',
                'cs.signals_json', 'cs.last_booking_at', 'cs.calculated_at',
                'u.display_name', 'u.email', 'u.avatar_url',
            ]);

        $high = $scores->where('score', '>=', 61)->count();
        $medium = $scores->whereBetween('score', [31, 60])->count();
        $low = $scores->where('score', '<=', 30)->count();

        return response()->json([
            'data' => $scores->map(fn($s) => [
                'user_id' => (string) $s->user_id,
                'name' => $s->display_name ?? 'Onbekend',
                'email' => $s->email ?? '',
                'avatar_url' => $s->avatar_url ?? null,
                'score' => (int) $s->score,
                'risk_level' => $s->score >= 61 ? 'high' : ($s->score >= 31 ? 'medium' : 'low'),
                'frequency_drop' => (int) $s->frequency_drop_score,
                'days_inactive' => (int) $s->days_inactive_score,
                'consistency' => (int) $s->consistency_score,
                'contract_end' => (int) $s->contract_end_score,
                'cancellation_rate' => (int) $s->cancellation_score,
                'last_booking_at' => $s->last_booking_at,
                'calculated_at' => $s->calculated_at,
            ])->values(),
            'summary' => ['high' => $high, 'medium' => $medium, 'low' => $low],
        ]);
    }

    /**
     * Cron: herbereken churn scores voor alle organisaties.
     */
    public function cronRecalculateChurnScores(): JsonResponse
    {
        $service = new \App\Services\ChurnPredictionService();
        $orgIds = DB::table('gymies_organisations')->where('is_active', true)->pluck('id');
        $totalRecalculated = 0;

        foreach ($orgIds as $orgId) {
            $totalRecalculated += $service->recalculateForOrganisation((int) $orgId);
        }

        return response()->json(['success' => true, 'recalculated' => $totalRecalculated]);
    }

    // ─── Activity Heatmap ───────────────────────────────────────

    /**
     * GET staff/activity-heatmap?date=YYYY-MM-DD
     * Returns per-region activity scores for Google Maps heatmap overlay.
     * Score = 50% booking density + 30% trainer utilization + 20% payment activity.
     * Normalized against 4-week historical average per weekday per hour.
     */
    public function staffActivityHeatmap(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        GymiesLaunchGateService::ensureSchema();

        try {
        $dateStr = $request->input('date', date('Y-m-d'));
        $date    = date('Y-m-d', strtotime($dateStr));
        // Validate date is a real date and within reasonable range (last 365 days to today)
        if (!$date || $date === '1970-01-01' || strtotime($date) === false) {
            $date = date('Y-m-d');
        }
        $minDate = date('Y-m-d', strtotime('-365 days'));
        if ($date < $minDate || $date > date('Y-m-d')) {
            $date = date('Y-m-d');
        }
        $dayOfWeek = (int) date('N', strtotime($date)); // 1=Mon … 7=Sun
        $isToday   = ($date === date('Y-m-d'));
        $currentHour = $isToday ? (int) date('H') : 23;

        // ── Fetch all regions with coordinates ──
        $regions = DB::table('gymies_launch_regions')
            ->whereNotNull('latitude')
            ->whereNotNull('longitude')
            ->get();

        if ($regions->isEmpty()) {
            return response()->json([
                'success' => true,
                'date'    => $date,
                'regions' => [],
                'totals'  => ['total_bookings' => 0, 'total_payments' => 0, 'active_trainers' => 0, 'active_regions' => 0],
            ]);
        }

        $slugs = $regions->pluck('slug')->toArray();

        if (empty($slugs)) {
            return response()->json([
                'success' => true, 'date' => $date, 'regions' => [],
                'totals'  => ['total_bookings' => 0, 'total_payments' => 0, 'active_trainers' => 0, 'active_regions' => 0],
            ]);
        }

        // Helper: parameterized placeholders for JSON IN clause with COALESCE for null safety
        $slugPlaceholders = implode(',', array_fill(0, count($slugs), '?'));
        $jsonSlugWhere = "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(meta, '$.region_slug')), '') IN ($slugPlaceholders)";
        $jsonSlugWhereUser = "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(u.meta, '$.region_slug')), '') IN ($slugPlaceholders)";
        $jsonSlugSelect = "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(meta, '$.region_slug')), '') as region_slug";
        $jsonSlugSelectUser = "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(u.meta, '$.region_slug')), '') as region_slug";

        // ── Current day bookings per region per hour ──
        $bookingsRaw = DB::table('gymies_bookings')
            ->select(
                DB::raw($jsonSlugSelect),
                DB::raw('HOUR(scheduled_at) as hour'),
                DB::raw('COUNT(*) as cnt')
            )
            ->whereDate('scheduled_at', $date)
            ->whereRaw($jsonSlugWhere, $slugs)
            ->groupBy('region_slug', DB::raw('HOUR(scheduled_at)'))
            ->get();

        $bookingsByRegionHour = [];
        foreach ($bookingsRaw as $row) {
            $bookingsByRegionHour[$row->region_slug][$row->hour] = (int) $row->cnt;
        }

        // ── Fallback: bookings without region meta → match via trainer's region ──
        $bookingsNoRegion = DB::table('gymies_bookings as b')
            ->join('gymies_users as u', 'b.trainer_user_id', '=', 'u.id')
            ->select(
                DB::raw($jsonSlugSelectUser),
                DB::raw('HOUR(b.scheduled_at) as hour'),
                DB::raw('COUNT(*) as cnt')
            )
            ->whereDate('b.scheduled_at', $date)
            ->whereRaw("(JSON_EXTRACT(b.meta, '$.region_slug') IS NULL OR COALESCE(JSON_UNQUOTE(JSON_EXTRACT(b.meta, '$.region_slug')), '') = '')")
            ->whereRaw($jsonSlugWhereUser, $slugs)
            ->groupBy('region_slug', DB::raw('HOUR(b.scheduled_at)'))
            ->get();

        foreach ($bookingsNoRegion as $row) {
            if (!$row->region_slug) continue;
            $bookingsByRegionHour[$row->region_slug][$row->hour] =
                ($bookingsByRegionHour[$row->region_slug][$row->hour] ?? 0) + (int) $row->cnt;
        }

        // ── 4-week historical average for same weekday per hour per region ──
        $histStart = date('Y-m-d', strtotime("$date -28 days"));
        $histEnd   = date('Y-m-d', strtotime("$date -1 day"));

        $historicalRaw = DB::table('gymies_bookings')
            ->select(
                DB::raw($jsonSlugSelect),
                DB::raw('HOUR(scheduled_at) as hour'),
                DB::raw('COUNT(*) as cnt'),
                DB::raw('COUNT(DISTINCT DATE(scheduled_at)) as day_count')
            )
            ->whereBetween(DB::raw('DATE(scheduled_at)'), [$histStart, $histEnd])
            ->whereRaw("DAYOFWEEK(scheduled_at) = DAYOFWEEK(?)", [$date])
            ->whereRaw($jsonSlugWhere, $slugs)
            ->groupBy('region_slug', DB::raw('HOUR(scheduled_at)'))
            ->get();

        $histAvgByRegionHour = [];
        foreach ($historicalRaw as $row) {
            $dayCount = max((int) $row->day_count, 1);
            $histAvgByRegionHour[$row->region_slug][$row->hour] = (float) $row->cnt / $dayCount;
        }

        // ── Trainer counts per region (active trainers) ──
        $trainerCounts = DB::table('gymies_users')
            ->select(
                DB::raw($jsonSlugSelect),
                DB::raw('COUNT(*) as cnt')
            )
            ->where('role', 'trainer')
            ->where('status', 'active')
            ->whereRaw($jsonSlugWhere, $slugs)
            ->groupBy('region_slug')
            ->pluck('cnt', 'region_slug')
            ->toArray();

        // ── Trainer utilization: trainers with bookings today per hour ──
        $trainerUtilRaw = DB::table('gymies_bookings')
            ->select(
                DB::raw($jsonSlugSelect),
                DB::raw('HOUR(scheduled_at) as hour'),
                DB::raw('COUNT(DISTINCT trainer_user_id) as active_trainers')
            )
            ->whereDate('scheduled_at', $date)
            ->whereRaw($jsonSlugWhere, $slugs)
            ->groupBy('region_slug', DB::raw('HOUR(scheduled_at)'))
            ->get();

        $trainerUtilByRegionHour = [];
        foreach ($trainerUtilRaw as $row) {
            $trainerUtilByRegionHour[$row->region_slug][$row->hour] = (int) $row->active_trainers;
        }

        // ── Payment activity per region per hour ──
        $paymentsRaw = DB::table('gymies_payments')
            ->select(
                DB::raw($jsonSlugSelect),
                DB::raw('HOUR(created_at) as hour'),
                DB::raw('COUNT(*) as cnt')
            )
            ->whereDate('created_at', $date)
            ->where('status', 'paid')
            ->whereRaw($jsonSlugWhere, $slugs)
            ->groupBy('region_slug', DB::raw('HOUR(created_at)'))
            ->get();

        $paymentsByRegionHour = [];
        foreach ($paymentsRaw as $row) {
            $paymentsByRegionHour[$row->region_slug][$row->hour] = (int) $row->cnt;
        }

        // ── Fallback payments via booking's trainer region ──
        $paymentsNoRegion = DB::table('gymies_payments as p')
            ->join('gymies_bookings as b', function ($join) {
                $join->on(DB::raw("JSON_UNQUOTE(JSON_EXTRACT(p.meta, '$.booking_id'))"), '=', DB::raw('CAST(b.id AS CHAR)'));
            })
            ->join('gymies_users as u', 'b.trainer_user_id', '=', 'u.id')
            ->select(
                DB::raw($jsonSlugSelectUser),
                DB::raw('HOUR(p.created_at) as hour'),
                DB::raw('COUNT(*) as cnt')
            )
            ->whereDate('p.created_at', $date)
            ->where('p.status', 'paid')
            ->whereRaw("(JSON_EXTRACT(p.meta, '$.region_slug') IS NULL OR JSON_UNQUOTE(JSON_EXTRACT(p.meta, '$.region_slug')) = '')")
            ->whereRaw($jsonSlugWhereUser, $slugs)
            ->groupBy('region_slug', DB::raw('HOUR(p.created_at)'))
            ->get();

        foreach ($paymentsNoRegion as $row) {
            if (!$row->region_slug) continue;
            $paymentsByRegionHour[$row->region_slug][$row->hour] =
                ($paymentsByRegionHour[$row->region_slug][$row->hour] ?? 0) + (int) $row->cnt;
        }

        // ── Client counts per region ──
        $clientCounts = DB::table('gymies_users')
            ->select(
                DB::raw($jsonSlugSelect),
                DB::raw('COUNT(*) as cnt')
            )
            ->where('role', 'client')
            ->where('status', 'active')
            ->whereRaw($jsonSlugWhere, $slugs)
            ->groupBy('region_slug')
            ->pluck('cnt', 'region_slug')
            ->toArray();

        // ── Build per-region response ──
        $totalBookings  = 0;
        $totalPayments  = 0;
        $allActiveTrainers = 0;
        $activeRegionCount = 0;

        $regionData = $regions->map(function ($region) use (
            $bookingsByRegionHour, $histAvgByRegionHour, $trainerCounts,
            $trainerUtilByRegionHour, $paymentsByRegionHour, $clientCounts,
            $currentHour, $isToday, &$totalBookings, &$totalPayments,
            &$allActiveTrainers, &$activeRegionCount
        ) {
            $slug          = $region->slug;
            $trainersTotal = $trainerCounts[$slug] ?? 0;
            $clientsTotal  = $clientCounts[$slug] ?? 0;

            // Calculate per-hour scores (0..1)
            $hourlyScores = [];
            $regionBookingsSum  = 0;
            $regionPaymentsSum  = 0;
            $regionPeakScore    = 0.0;
            $regionPeakHour     = 0;

            for ($h = 0; $h < 24; $h++) {
                $bookings    = $bookingsByRegionHour[$slug][$h] ?? 0;
                $histAvg     = $histAvgByRegionHour[$slug][$h] ?? 0;
                $activeTr    = $trainerUtilByRegionHour[$slug][$h] ?? 0;
                $payments    = $paymentsByRegionHour[$slug][$h] ?? 0;

                $regionBookingsSum += $bookings;
                $regionPaymentsSum += $payments;

                // ── Booking density score (0..1) ──
                // Compare current bookings vs historical average
                // If no history, use absolute thresholds
                if ($histAvg > 0) {
                    $bookingScore = min($bookings / ($histAvg * 2), 1.0);
                } else {
                    // No historical data: use absolute scale (10 bookings/hr = max)
                    $bookingScore = min($bookings / 10, 1.0);
                }

                // ── Trainer utilization score (0..1) ──
                if ($trainersTotal > 0) {
                    $utilScore = min($activeTr / $trainersTotal, 1.0);
                } else {
                    $utilScore = 0.0;
                }

                // ── Payment activity score (0..1) ──
                // Normalize: 5+ payments/hr = max activity
                $paymentScore = min($payments / 5, 1.0);

                // ── Weighted composite score ──
                $score = ($bookingScore * 0.50) + ($utilScore * 0.30) + ($paymentScore * 0.20);
                $score = round(min(max($score, 0.0), 1.0), 3);

                $hourlyScores[$h] = [
                    'hour'              => $h,
                    'score'             => $score,
                    'bookings'          => $bookings,
                    'payments'          => $payments,
                    'active_trainers'   => $activeTr,
                    'historical_avg'    => round($histAvg, 1),
                    'booking_score'     => round($bookingScore, 3),
                    'utilization_score' => round($utilScore, 3),
                    'payment_score'     => round($paymentScore, 3),
                ];

                if ($score > $regionPeakScore) {
                    $regionPeakScore = $score;
                    $regionPeakHour  = $h;
                }
            }

            // Current hour data
            $currentScore    = $hourlyScores[$currentHour]['score'] ?? 0;
            $currentBookings = $hourlyScores[$currentHour]['bookings'] ?? 0;
            $currentPayments = $hourlyScores[$currentHour]['payments'] ?? 0;
            $currentUtil     = $hourlyScores[$currentHour]['active_trainers'] ?? 0;

            $totalBookings     += $regionBookingsSum;
            $totalPayments     += $regionPaymentsSum;
            $allActiveTrainers += $trainersTotal;
            if ($currentScore > 0) $activeRegionCount++;

            // Color bucket
            $color = 'green';
            if ($currentScore > 0.75) $color = 'purple';
            elseif ($currentScore > 0.50) $color = 'red';
            elseif ($currentScore > 0.25) $color = 'orange';

            return [
                'slug'                  => $slug,
                'city'                  => $region->city,
                'status'                => $region->status,
                'latitude'              => (float) $region->latitude,
                'longitude'             => (float) $region->longitude,
                'trainers_count'        => $trainersTotal,
                'clients_count'         => $clientsTotal,
                'current_hour'          => $currentHour,
                'current_score'         => $currentScore,
                'current_color'         => $color,
                'current_bookings'      => $currentBookings,
                'current_payments'      => $currentPayments,
                'current_active_trainers' => $currentUtil,
                'trainer_utilization'   => $trainersTotal > 0 ? round($currentUtil / $trainersTotal, 2) : 0,
                'peak_score'            => $regionPeakScore,
                'peak_hour'             => $regionPeakHour,
                'day_bookings_total'    => $regionBookingsSum,
                'day_payments_total'    => $regionPaymentsSum,
                'hourly_scores'         => array_values($hourlyScores),
            ];
        })->toArray();

        // Sort: most active first
        usort($regionData, fn($a, $b) => $b['current_score'] <=> $a['current_score']);

        return response()->json([
            'success' => true,
            'date'    => $date,
            'is_live' => $isToday,
            'current_hour' => $currentHour,
            'regions' => $regionData,
            'totals'  => [
                'total_bookings'   => $totalBookings,
                'total_payments'   => $totalPayments,
                'active_trainers'  => $allActiveTrainers,
                'active_regions'   => $activeRegionCount,
                'total_regions'    => count($regionData),
            ],
        ]);

        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('staffActivityHeatmap failed', ['error' => $e->getMessage(), 'trace' => $e->getTraceAsString()]);
            }
            return response()->json([
                'success' => false,
                'message' => 'Heatmap data kon niet worden geladen.',
                'regions' => [],
                'totals'  => ['total_bookings' => 0, 'total_payments' => 0, 'active_trainers' => 0, 'active_regions' => 0],
            ], 500);
        }
    }

    // ─── Launch Regions Management ───────────────────────────────

    /**
     * GET staff/regions
     * Returns all regions with full stats: city, slug, status, trainers_count, clients_count,
     * waitlist_count, bookings_this_week, ratio (clients/trainers), min_trainers_to_open,
     * opened_at. Sorted by status (open first, then invite_only, waitlist, closed) then by city.
     * Include readiness evaluation per region.
     */
    public function getRegions(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        GymiesLaunchGateService::ensureSchema();

        $regions = DB::table('gymies_launch_regions')
            ->orderByRaw("FIELD(status, 'open', 'invite_only', 'waitlist', 'closed')")
            ->orderBy('city', 'asc')
            ->get();

        $result = $regions->map(function ($region) {
            $readiness = GymiesLaunchGateService::evaluateRegionReadiness($region->slug);

            return [
                'id' => (int) $region->id,
                'city' => $region->city,
                'slug' => $region->slug,
                'province' => $region->province,
                'status' => $region->status,
                'trainers_count' => (int) $region->trainers_count,
                'clients_count' => (int) $region->clients_count,
                'waitlist_count' => (int) $region->waitlist_count,
                'bookings_this_week' => (int) $region->bookings_this_week,
                'ratio' => $region->trainers_count > 0
                    ? round((int) $region->clients_count / (int) $region->trainers_count, 2)
                    : 0,
                'latitude' => $region->latitude ? (float) $region->latitude : null,
                'longitude' => $region->longitude ? (float) $region->longitude : null,
                'min_trainers_to_open' => (int) $region->min_trainers_to_open,
                'max_client_trainer_ratio' => (int) $region->max_client_trainer_ratio,
                'opened_at' => $region->opened_at,
                'created_at' => $region->created_at,
                'updated_at' => $region->updated_at,
                'readiness' => [
                    'ready' => $readiness['ready'],
                    'recommendation' => $readiness['recommendation'],
                    'trainers' => $readiness['trainers'],
                    'clients' => $readiness['clients'],
                    'ratio' => $readiness['ratio'],
                    'bookings_week' => $readiness['bookings_week'],
                ],
            ];
        });

        return response()->json(['data' => $result]);
    }

    /**
     * GET staff/regions/{slug}
     * Returns: full region data + top 10 trainers in region (name, bookings count, rating) +
     * waitlist size by role + recent 7 days booking trend (array of daily counts) +
     * invite codes stats (total generated, total used) + growth data (new trainers/clients per week for last 4 weeks).
     */
    public function getRegionDetail(Request $request, string $slug): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        GymiesLaunchGateService::ensureSchema();

        $slug = trim((string) $slug);
        $region = DB::table('gymies_launch_regions')
            ->where('slug', $slug)
            ->first();

        if (!$region) {
            return response()->json(['message' => 'Regio niet gevonden.'], 404);
        }

        // Top 10 trainers in region
        $trainers = [];
        if (Schema::hasTable('gymies_trainer_profiles') && Schema::hasTable('gymies_bookings')) {
            $trainers = DB::table('gymies_trainer_profiles as tp')
                ->select(
                    'tp.user_id',
                    'u.first_name',
                    'u.last_name',
                    DB::raw('COUNT(b.id) as bookings_count'),
                    DB::raw('AVG(b.rating) as rating')
                )
                ->join('gymies_users as u', 'tp.user_id', '=', 'u.id')
                ->leftJoin('gymies_bookings as b', 'tp.user_id', '=', 'b.trainer_user_id')
                ->whereRaw('LOWER(tp.city) LIKE ?', [strtolower($slug) . '%'])
                ->groupBy('tp.user_id', 'u.first_name', 'u.last_name')
                ->orderByDesc('bookings_count')
                ->limit(10)
                ->get()
                ->map(function ($t) {
                    return [
                        'user_id' => (int) $t->user_id,
                        'name' => trim(($t->first_name ?? '') . ' ' . ($t->last_name ?? '')),
                        'bookings_count' => (int) ($t->bookings_count ?? 0),
                        'rating' => $t->rating ? round((float) $t->rating, 2) : null,
                    ];
                });
        }

        // Waitlist size by role
        $waitlistByRole = DB::table('gymies_waitlist')
            ->where('region_slug', $slug)
            ->where('status', 'waiting')
            ->select('role', DB::raw('COUNT(*) as count'))
            ->groupBy('role')
            ->get()
            ->mapWithKeys(fn ($row) => [$row->role => (int) $row->count]);

        // Recent 7 days booking trend
        $bookingTrend = [];
        if (Schema::hasTable('gymies_bookings')) {
            for ($i = 6; $i >= 0; $i--) {
                $date = now()->subDays($i)->toDateString();
                $count = (int) DB::table('gymies_bookings')
                    ->whereDate('scheduled_at', $date)
                    ->count();
                $bookingTrend[] = [
                    'date' => $date,
                    'count' => $count,
                ];
            }
        }

        // Invite codes stats
        $inviteStats = DB::table('gymies_invite_codes')
            ->where('region_slug', $slug)
            ->select(
                DB::raw('COUNT(*) as total_generated'),
                DB::raw('SUM(uses_count) as total_used')
            )
            ->first();

        $inviteStats = [
            'total_generated' => (int) ($inviteStats?->total_generated ?? 0),
            'total_used' => (int) ($inviteStats?->total_used ?? 0),
        ];

        // Growth data: new trainers/clients per week for last 4 weeks
        $growth = [];
        if (Schema::hasTable('gymies_trainer_profiles')) {
            for ($w = 3; $w >= 0; $w--) {
                $weekStart = now()->subWeeks($w)->startOfWeek();
                $weekEnd = now()->subWeeks($w)->endOfWeek();

                $newTrainers = (int) DB::table('gymies_trainer_profiles')
                    ->whereRaw('LOWER(city) LIKE ?', [strtolower($slug) . '%'])
                    ->whereBetween('created_at', [$weekStart, $weekEnd])
                    ->count();

                $newClients = 0;
                if (Schema::hasTable('gymies_users')) {
                    $newClients = (int) DB::table('gymies_users')
                        ->whereRaw('LOWER(city) LIKE ?', [strtolower($slug) . '%'])
                        ->whereIn('role', ['klant', 'client'])
                        ->whereBetween('created_at', [$weekStart, $weekEnd])
                        ->count();
                }

                $growth[] = [
                    'week' => $weekStart->format('Y-W'),
                    'new_trainers' => $newTrainers,
                    'new_clients' => $newClients,
                ];
            }
        }

        return response()->json([
            'data' => [
                'id' => (int) $region->id,
                'city' => $region->city,
                'slug' => $region->slug,
                'province' => $region->province,
                'status' => $region->status,
                'trainers_count' => (int) $region->trainers_count,
                'clients_count' => (int) $region->clients_count,
                'waitlist_count' => (int) $region->waitlist_count,
                'bookings_this_week' => (int) $region->bookings_this_week,
                'ratio' => $region->trainers_count > 0
                    ? round((int) $region->clients_count / (int) $region->trainers_count, 2)
                    : 0,
                'latitude' => $region->latitude ? (float) $region->latitude : null,
                'longitude' => $region->longitude ? (float) $region->longitude : null,
                'min_trainers_to_open' => (int) $region->min_trainers_to_open,
                'max_client_trainer_ratio' => (int) $region->max_client_trainer_ratio,
                'opened_at' => $region->opened_at,
                'created_at' => $region->created_at,
                'updated_at' => $region->updated_at,
                'top_trainers' => $trainers,
                'waitlist_by_role' => $waitlistByRole->toArray(),
                'booking_trend_7d' => $bookingTrend,
                'invite_codes_stats' => $inviteStats,
                'growth_4w' => $growth,
            ],
        ]);
    }

    /**
     * PUT staff/regions/{slug}
     * Can update: status, min_trainers_to_open, max_client_trainer_ratio.
     * When status changes to 'open': set opened_at, trigger activateWaitlistForRegion().
     * When status changes to 'closed': revoke all active invite codes for this region.
     */
    public function updateRegionStatus(Request $request, string $slug): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        GymiesLaunchGateService::ensureSchema();

        $slug = trim((string) $slug);
        $region = DB::table('gymies_launch_regions')
            ->where('slug', $slug)
            ->first();

        if (!$region) {
            return response()->json(['message' => 'Regio niet gevonden.'], 404);
        }

        $updateData = [];
        $newStatus = $request->input('status');
        $minTrainers = $request->input('min_trainers_to_open');
        $maxRatio = $request->input('max_client_trainer_ratio');

        if ($minTrainers !== null) {
            $minTrainers = (int) $minTrainers;
            if ($minTrainers < 0) {
                return response()->json(['message' => 'min_trainers_to_open moet >= 0 zijn.'], 422);
            }
            $updateData['min_trainers_to_open'] = $minTrainers;
        }

        if ($maxRatio !== null) {
            $maxRatio = (int) $maxRatio;
            if ($maxRatio < 1) {
                return response()->json(['message' => 'max_client_trainer_ratio moet >= 1 zijn.'], 422);
            }
            $updateData['max_client_trainer_ratio'] = $maxRatio;
        }

        if ($newStatus !== null) {
            $newStatus = (string) $newStatus;
            if (!in_array($newStatus, ['closed', 'waitlist', 'invite_only', 'open'], true)) {
                return response()->json(['message' => 'Ongeldig status. Kies uit: closed, waitlist, invite_only, open'], 422);
            }

            $updateData['status'] = $newStatus;

            // Trigger: status changes to 'open'
            if ($newStatus === 'open' && $region->status !== 'open') {
                $updateData['opened_at'] = now();
                // Activate waitlist after update
            }

            // Trigger: status changes to 'closed'
            if ($newStatus === 'closed' && $region->status !== 'closed') {
                // Revoke all active invite codes for this region
                DB::table('gymies_invite_codes')
                    ->where('region_slug', $slug)
                    ->where('status', 'active')
                    ->update(['status' => 'revoked', 'updated_at' => now()]);
            }
        }

        if (empty($updateData)) {
            return response()->json(['message' => 'Geen velden opgegeven om bij te werken.'], 422);
        }

        $updateData['updated_at'] = now();

        DB::table('gymies_launch_regions')
            ->where('slug', $slug)
            ->update($updateData);

        // If status changed to 'open', activate waitlist
        if ($newStatus === 'open' && $region->status !== 'open') {
            $activated = GymiesLaunchGateService::activateWaitlistForRegion($slug);
            Log::info('[StaffDashboard] Activated waitlist for region', [
                'slug' => $slug,
                'activated_count' => $activated,
            ]);
        }

        $updated = DB::table('gymies_launch_regions')
            ->where('slug', $slug)
            ->first();

        $readiness = GymiesLaunchGateService::evaluateRegionReadiness($slug);

        return response()->json([
            'data' => [
                'id' => (int) $updated->id,
                'city' => $updated->city,
                'slug' => $updated->slug,
                'province' => $updated->province,
                'status' => $updated->status,
                'trainers_count' => (int) $updated->trainers_count,
                'clients_count' => (int) $updated->clients_count,
                'waitlist_count' => (int) $updated->waitlist_count,
                'bookings_this_week' => (int) $updated->bookings_this_week,
                'ratio' => $updated->trainers_count > 0
                    ? round((int) $updated->clients_count / (int) $updated->trainers_count, 2)
                    : 0,
                'min_trainers_to_open' => (int) $updated->min_trainers_to_open,
                'max_client_trainer_ratio' => (int) $updated->max_client_trainer_ratio,
                'opened_at' => $updated->opened_at,
                'created_at' => $updated->created_at,
                'updated_at' => $updated->updated_at,
                'readiness' => [
                    'ready' => $readiness['ready'],
                    'recommendation' => $readiness['recommendation'],
                ],
            ],
            'message' => 'Regio bijgewerkt.',
        ]);
    }

    /**
     * POST staff/regions
     * Required: city, slug (auto-generate from city if not provided).
     * Optional: province, status (default 'closed'), min_trainers_to_open, max_client_trainer_ratio.
     * Slug format: lowercase, hyphens, no spaces (e.g., "Amsterdam" → "amsterdam", "Den Haag" → "den-haag").
     * Validate unique slug.
     */
    public function createRegion(Request $request): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        GymiesLaunchGateService::ensureSchema();

        $city = trim((string) ($request->input('city') ?? ''));
        $slug = trim((string) ($request->input('slug') ?? ''));

        if (empty($city)) {
            return response()->json(['message' => 'Stad (city) is verplicht.'], 422);
        }

        // Auto-generate slug from city if not provided
        if (empty($slug)) {
            $slug = Str::slug($city, '-');
        } else {
            $slug = Str::slug($slug, '-');
        }

        // Validate slug uniqueness
        if (DB::table('gymies_launch_regions')->where('slug', $slug)->exists()) {
            return response()->json(['message' => 'Slug "' . $slug . '" bestaat al.'], 422);
        }

        $province = trim((string) ($request->input('province') ?? '')) ?: null;
        $status = (string) ($request->input('status') ?? 'closed');
        $minTrainers = (int) ($request->input('min_trainers_to_open') ?? 5);
        $maxRatio = (int) ($request->input('max_client_trainer_ratio') ?? 15);

        if (!in_array($status, ['closed', 'waitlist', 'invite_only', 'open'], true)) {
            return response()->json(['message' => 'Ongeldig status. Kies uit: closed, waitlist, invite_only, open'], 422);
        }

        if ($minTrainers < 0) {
            return response()->json(['message' => 'min_trainers_to_open moet >= 0 zijn.'], 422);
        }

        if ($maxRatio < 1) {
            return response()->json(['message' => 'max_client_trainer_ratio moet >= 1 zijn.'], 422);
        }

        // Auto-resolve coordinates from city name
        $coords = GymiesLaunchGateService::getCityCoordinates($city);

        $insertData = [
            'city' => $city,
            'slug' => $slug,
            'province' => $province,
            'status' => $status,
            'min_trainers_to_open' => $minTrainers,
            'max_client_trainer_ratio' => $maxRatio,
            'trainers_count' => 0,
            'clients_count' => 0,
            'waitlist_count' => 0,
            'bookings_this_week' => 0,
            'opened_at' => $status === 'open' ? now() : null,
            'created_at' => now(),
            'updated_at' => now(),
        ];

        if ($coords) {
            $insertData['latitude'] = $coords['lat'];
            $insertData['longitude'] = $coords['lng'];
        }

        DB::table('gymies_launch_regions')->insert($insertData);

        $created = DB::table('gymies_launch_regions')
            ->where('slug', $slug)
            ->first();

        Log::info('[StaffDashboard] Created new region', [
            'city' => $city,
            'slug' => $slug,
            'status' => $status,
        ]);

        return response()->json([
            'data' => [
                'id' => (int) $created->id,
                'city' => $created->city,
                'slug' => $created->slug,
                'province' => $created->province,
                'status' => $created->status,
                'trainers_count' => 0,
                'clients_count' => 0,
                'waitlist_count' => 0,
                'bookings_this_week' => 0,
                'ratio' => 0,
                'min_trainers_to_open' => (int) $created->min_trainers_to_open,
                'max_client_trainer_ratio' => (int) $created->max_client_trainer_ratio,
                'opened_at' => $created->opened_at,
                'created_at' => $created->created_at,
                'updated_at' => $created->updated_at,
            ],
            'message' => 'Regio aangemaakt.',
        ], 201);
    }

    // ─── Staff Role Check ────────────────────────────────────────

    /**
     * Controleer of de ingelogde gebruiker staff is.
     * Returns user object of JsonResponse met 403.
     */
    private function requireStaff(Request $request): object
    {
        $user = $request->attributes->get('gymies_user');

        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        // Staff roles: admin, staff, medewerker
        $role = $user->role ?? '';
        if (!in_array($role, ['admin', 'staff', 'medewerker'], true)) {
            return response()->json(['message' => 'Alleen medewerkers hebben toegang.'], 403);
        }

        return $user;
    }

    // ─── Feature 3: Ambassador personal endpoints ───────────────
    // VERWIJDERD: myAmbassadorStats, myAmbassadorReferrals, myAmbassadorPayouts,
    // requestAmbassadorPayout zijn verplaatst naar GymiesAmbassadorController
    // (unified system: gymies_ambassadors + gymies_ambassador_conversions).
    // Routes me/ambassador/* wijzen nu naar GymiesAmbassadorController::myStats/myReferrals/myPayouts/myRequestPayout.

    // ─── Feature 4: Trainer Community Chat ──────────────────────

    /**
     * GET me/gym-chats — groepschats waar ik lid van ben.
     */
    public function myGymChats(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) return response()->json(['message' => 'Unauthorized'], 401);

        \App\Http\Controllers\Gymies\GymiesSchemaEnsure::ensureTrainerCommunityTables();

        $chats = DB::table('gymies_gym_group_chat_members as m')
            ->join('gymies_gym_group_chats as c', 'm.group_chat_id', '=', 'c.id')
            ->where('m.user_id', (int) $user->id)
            ->where('c.is_active', true)
            ->get(['c.id', 'c.name', 'c.organisation_id', 'm.is_muted', 'm.joined_at']);

        // Laatste bericht per chat
        $chatIds = $chats->pluck('id')->toArray();
        $lastMessages = [];
        if (!empty($chatIds)) {
            $rows = DB::table('gymies_gym_group_chat_messages as msg')
                ->join('gymies_users as u', 'msg.sender_user_id', '=', 'u.id')
                ->whereIn('msg.group_chat_id', $chatIds)
                ->whereRaw('msg.id = (SELECT MAX(m2.id) FROM gymies_gym_group_chat_messages m2 WHERE m2.group_chat_id = msg.group_chat_id)')
                ->get(['msg.group_chat_id', 'msg.message', 'msg.created_at', 'u.display_name as sender_name']);
            foreach ($rows as $r) {
                $lastMessages[$r->group_chat_id] = $r;
            }
        }

        return response()->json(['data' => $chats->map(fn($c) => [
            'id' => (string) $c->id,
            'name' => $c->name,
            'organisation_id' => (string) $c->organisation_id,
            'is_muted' => (bool) $c->is_muted,
            'joined_at' => $c->joined_at,
            'last_message' => isset($lastMessages[$c->id]) ? [
                'message' => mb_substr($lastMessages[$c->id]->message, 0, 100),
                'sender_name' => $lastMessages[$c->id]->sender_name,
                'created_at' => $lastMessages[$c->id]->created_at,
            ] : null,
        ])->values()]);
    }

    /**
     * GET me/gym-chats/{chatId}/messages — berichten ophalen.
     */
    public function gymChatMessages(Request $request, string $chatId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) return response()->json(['message' => 'Unauthorized'], 401);

        $id = (int) $chatId;

        // Verify membership
        $isMember = DB::table('gymies_gym_group_chat_members')
            ->where('group_chat_id', $id)->where('user_id', (int) $user->id)->exists();
        if (!$isMember) return response()->json(['message' => 'Geen lid van deze chat.'], 403);

        $messages = DB::table('gymies_gym_group_chat_messages as msg')
            ->join('gymies_users as u', 'msg.sender_user_id', '=', 'u.id')
            ->where('msg.group_chat_id', $id)
            ->orderByDesc('msg.created_at')
            ->limit(100)
            ->get(['msg.id', 'msg.message', 'msg.sender_user_id', 'msg.created_at', 'u.display_name as sender_name', 'u.avatar_url']);

        return response()->json(['data' => $messages->map(fn($m) => [
            'id' => (string) $m->id,
            'message' => $m->message,
            'sender_user_id' => (string) $m->sender_user_id,
            'sender_name' => $m->sender_name ?? 'Onbekend',
            'avatar_url' => $m->avatar_url ?? null,
            'is_mine' => (int) $m->sender_user_id === (int) $user->id,
            'created_at' => $m->created_at,
        ])->values()]);
    }

    /**
     * POST me/gym-chats/{chatId}/messages — bericht sturen.
     */
    public function sendGymChatMessage(Request $request, string $chatId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) return response()->json(['message' => 'Unauthorized'], 401);

        $request->validate(['message' => 'required|string|max:2000']);
        $id = (int) $chatId;

        $isMember = DB::table('gymies_gym_group_chat_members')
            ->where('group_chat_id', $id)->where('user_id', (int) $user->id)->exists();
        if (!$isMember) return response()->json(['message' => 'Geen lid van deze chat.'], 403);

        $msgId = DB::table('gymies_gym_group_chat_messages')->insertGetId([
            'group_chat_id' => $id,
            'sender_user_id' => (int) $user->id,
            'message' => trim((string) $request->input('message')),
            'created_at' => now(),
        ]);

        // Push naar alle leden (behalve afzender en gemute leden)
        try {
            $recipientIds = DB::table('gymies_gym_group_chat_members')
                ->where('group_chat_id', $id)
                ->where('user_id', '!=', (int) $user->id)
                ->where('is_muted', false)
                ->pluck('user_id')
                ->toArray();

            $chatName = DB::table('gymies_gym_group_chats')->where('id', $id)->value('name') ?? 'Groepschat';
            $senderName = $user->display_name ?? $user->name ?? 'Trainer';

            foreach ($recipientIds as $recipientId) {
                FcmPushHelper::sendToUser(
                    (int) $recipientId,
                    "{$senderName} in {$chatName}",
                    mb_substr(trim((string) $request->input('message')), 0, 100),
                    ['type' => 'trainer_community_message', 'action' => 'new_message', 'screen' => 'trainer_community', 'group_chat_id' => (string) $id]
                );
            }
        } catch (\Throwable $e) {
            Log::warning('Community chat push failed', ['error' => $e->getMessage()]);
        }

        return response()->json(['data' => ['id' => (string) $msgId]], 201);
    }

    /**
     * POST me/gym-chats/{chatId}/mute — notificaties dempen/ontdempen.
     */
    public function toggleGymChatMute(Request $request, string $chatId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) return response()->json(['message' => 'Unauthorized'], 401);

        $id = (int) $chatId;
        $member = DB::table('gymies_gym_group_chat_members')
            ->where('group_chat_id', $id)->where('user_id', (int) $user->id)->first();
        if (!$member) return response()->json(['message' => 'Geen lid van deze chat.'], 403);

        $newMuted = !((bool) $member->is_muted);
        DB::table('gymies_gym_group_chat_members')
            ->where('id', $member->id)
            ->update(['is_muted' => $newMuted]);

        return response()->json(['success' => true, 'is_muted' => $newMuted]);
    }

    /**
     * GET me/gym-trainers — alle trainers in mijn gym (voor 1-op-1 chat).
     */
    public function myGymTrainers(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) return response()->json(['message' => 'Unauthorized'], 401);

        $userId = (int) $user->id;

        if (!Schema::hasTable('gymies_gym_teams')) {
            return response()->json(['data' => []]);
        }

        // Vind mijn organisatie(s)
        $myOrgIds = DB::table('gymies_gym_teams')
            ->where('user_id', $userId)->pluck('organisation_id')->toArray();

        if (empty($myOrgIds)) {
            return response()->json(['data' => []]);
        }

        $trainers = DB::table('gymies_gym_teams as gt')
            ->join('gymies_users as u', 'gt.user_id', '=', 'u.id')
            ->whereIn('gt.organisation_id', $myOrgIds)
            ->where('gt.user_id', '!=', $userId)
            ->distinct()
            ->get(['u.id', 'u.display_name', 'u.avatar_url', 'u.email']);

        return response()->json(['data' => $trainers->map(fn($t) => [
            'user_id' => (string) $t->id,
            'name' => $t->display_name ?? 'Trainer',
            'avatar_url' => $t->avatar_url ?? null,
        ])->values()]);
    }

    // ─── Multi-locatie endpoints ─────────────────────────────────

    /**
     * GET /staff/gyms/{orgId}/locations — Alle locaties van een organisatie.
     */
    public function gymLocations(Request $request, string $orgId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        GymiesSchemaEnsure::ensureGymLocationsTable();

        $locations = DB::table('gymies_gym_locations')
            ->where('organisation_id', (int) $orgId)
            ->orderBy('name')
            ->get();

        $result = $locations->map(function ($loc) {
            $memberCount = (int) DB::table('gymies_gym_teams')
                ->where('organisation_id', $loc->organisation_id)
                ->where('location_id', $loc->id)
                ->count();

            $trainerCount = (int) DB::table('gymies_trainer_profiles as tp')
                ->join('gymies_gym_teams as gt', 'tp.user_id', '=', 'gt.user_id')
                ->where('gt.organisation_id', $loc->organisation_id)
                ->where('gt.location_id', $loc->id)
                ->count();

            return [
                'id' => (string) $loc->id,
                'name' => $loc->name ?? 'Locatie',
                'address' => $loc->address ?? '',
                'city' => $loc->city ?? '',
                'capacity' => (int) ($loc->capacity ?? 0),
                'lat' => $loc->lat ?? null,
                'lng' => $loc->lng ?? null,
                'trainer_count' => $trainerCount,
                'member_count' => $memberCount,
            ];
        })->values();

        return response()->json(['data' => $result]);
    }

    /**
     * GET /staff/gyms/{orgId}/locations/{locId}/stats — Statistieken per locatie.
     */
    public function gymLocationStats(Request $request, string $orgId, string $locId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $orgId = (int) $orgId;
        $locId = (int) $locId;
        $today = now()->toDateString();
        $weekAgo = now()->subDays(7)->toDateString();
        $monthStart = now()->startOfMonth()->toDateString();

        $bookingsToday = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->where('location_id', $locId)
            ->whereDate('scheduled_at', $today)
            ->count();

        $bookingsWeek = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->where('location_id', $locId)
            ->whereDate('scheduled_at', '>=', $weekAgo)
            ->count();

        $revenueMtd = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->where('location_id', $locId)
            ->whereDate('scheduled_at', '>=', $monthStart)
            ->where('status', 'completed')
            ->sum('price_cents');

        // Capaciteit
        $location = DB::table('gymies_gym_locations')->where('id', $locId)->first();
        $capacity = (int) ($location->capacity ?? 100);
        $activeMembers = (int) DB::table('gymies_gym_teams')
            ->where('organisation_id', $orgId)
            ->where('location_id', $locId)
            ->count();
        $occupancyRate = $capacity > 0 ? round(($activeMembers / $capacity) * 100, 1) : 0;

        // Populaire uren (top 5)
        $popularHours = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->where('location_id', $locId)
            ->whereDate('scheduled_at', '>=', $weekAgo)
            ->selectRaw('HOUR(scheduled_at) as hour, COUNT(*) as count')
            ->groupBy('hour')
            ->orderByDesc('count')
            ->limit(5)
            ->get()
            ->map(fn($row) => ['hour' => (int) $row->hour, 'count' => (int) $row->count])
            ->values();

        return response()->json([
            'occupancy_rate' => $occupancyRate,
            'bookings_today' => $bookingsToday,
            'bookings_week' => $bookingsWeek,
            'revenue_mtd' => $revenueMtd,
            'popular_hours' => $popularHours,
        ]);
    }

    /**
     * POST /staff/gyms/{orgId}/trainers/{userId}/transfer — Trainer verplaatsen.
     */
    public function transferTrainer(Request $request, string $orgId, string $userId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $targetLocationId = $request->input('target_location_id');
        if (empty($targetLocationId)) {
            return response()->json(['error' => 'target_location_id is verplicht.'], 422);
        }

        $orgId = (int) $orgId;
        $userId = (int) $userId;
        $targetLocationId = (int) $targetLocationId;

        // Controleer of locatie bij dezelfde org hoort
        $locationExists = DB::table('gymies_gym_locations')
            ->where('id', $targetLocationId)
            ->where('organisation_id', $orgId)
            ->exists();

        if (!$locationExists) {
            return response()->json(['error' => 'Doellocatie bestaat niet voor deze organisatie.'], 404);
        }

        DB::table('gymies_gym_teams')
            ->where('user_id', $userId)
            ->where('organisation_id', $orgId)
            ->update(['location_id' => $targetLocationId, 'updated_at' => now()]);

        $this->auditLog('transfer_trainer', $request, [
            'trainer_user_id' => $userId,
            'org_id' => $orgId,
            'target_location_id' => $targetLocationId,
        ]);

        return response()->json(['success' => true, 'message' => 'Trainer succesvol overgeplaatst.']);
    }

    /**
     * POST /staff/gyms/{orgId}/group-sessions/{sessionId}/duplicate — Groepsles dupliceren.
     */
    public function duplicateGroupSession(Request $request, string $orgId, string $sessionId): JsonResponse
    {
        $staff = $this->requireStaff($request);
        if ($staff instanceof JsonResponse) return $staff;

        $targetLocationId = $request->input('target_location_id');
        if (empty($targetLocationId)) {
            return response()->json(['error' => 'target_location_id is verplicht.'], 422);
        }

        $orgId = (int) $orgId;
        $sessionId = (int) $sessionId;
        $targetLocationId = (int) $targetLocationId;

        // Haal originele sessie op
        $original = DB::table('gymies_group_sessions')->where('id', $sessionId)->first();
        if (!$original) {
            return response()->json(['error' => 'Groepsles niet gevonden.'], 404);
        }

        // Dupliceer naar nieuwe locatie
        $newId = DB::table('gymies_group_sessions')->insertGetId([
            'trainer_id' => $original->trainer_id,
            'organisation_id' => $orgId,
            'location_id' => $targetLocationId,
            'title' => $original->title,
            'description' => $original->description ?? null,
            'max_participants' => $original->max_participants,
            'scheduled_at' => $original->scheduled_at,
            'duration_minutes' => $original->duration_minutes,
            'price_cents' => $original->price_cents,
            'status' => 'scheduled',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->auditLog('duplicate_group_session', $request, [
            'original_session_id' => $sessionId,
            'new_session_id' => $newId,
            'org_id' => $orgId,
            'target_location_id' => $targetLocationId,
        ]);

        return response()->json(['success' => true, 'new_session_id' => (string) $newId]);
    }
}
