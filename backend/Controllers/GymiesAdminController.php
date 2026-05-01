<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Gymies\Traits\AdminBookingsTrait;
use App\Http\Controllers\Gymies\Traits\AdminFinanceTrait;
use App\Http\Controllers\Gymies\Traits\AdminOrganisationsTrait;
use App\Http\Controllers\Gymies\Traits\AdminPlansTrait;
use App\Http\Controllers\Gymies\Traits\AdminTicketsTrait;
use App\Traits\GymiesRequireAdminTrait;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

final class GymiesAdminController extends Controller
{
    use GymiesRequireAdminTrait;
    use AdminBookingsTrait;
    use AdminFinanceTrait;
    use AdminOrganisationsTrait;
    use AdminPlansTrait;
    use AdminTicketsTrait;

    public function overview(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        $todayStart = now()->startOfDay()->toDateTimeString();
        $todayEnd = now()->endOfDay()->toDateTimeString();
        $yesterday = now()->subDay()->toDateTimeString();

        $users = (int) DB::table('gymies_users')->count();
        $trainers = (int) DB::table('gymies_users')->where('role', 'trainer')->count();
        $customers = (int) DB::table('gymies_users')->where('role', 'klant')->count();
        $gyms = Schema::hasTable('gymies_organisations')
            ? (int) DB::table('gymies_organisations')->count()
            : 0;
        $openTickets = Schema::hasTable('gymies_support_tickets')
            ? (int) DB::table('gymies_support_tickets')->whereIn('status', ['new', 'in_progress', 'waiting_customer'])->count()
            : 0;
        $failedPayments = Schema::hasTable('gymies_bookings')
            ? (int) DB::table('gymies_bookings')->whereIn('status', ['payment_failed', 'failed'])->count()
            : 0;
        $refunded = Schema::hasTable('gymies_bookings')
            ? (int) DB::table('gymies_bookings')->whereIn('status', ['refunded', 'refund_completed', 'cancelled_refunded'])->count()
            : 0;

        $usersToday = (int) DB::table('gymies_users')->whereBetween('created_at', [$todayStart, $todayEnd])->count();
        $ticketsToday = Schema::hasTable('gymies_support_tickets')
            ? (int) DB::table('gymies_support_tickets')->whereBetween('created_at', [$todayStart, $todayEnd])->count()
            : 0;
        $bookingsToday = Schema::hasTable('gymies_bookings')
            ? (int) DB::table('gymies_bookings')->whereBetween('created_at', [$todayStart, $todayEnd])->count()
            : 0;
        $ticketsOpenOver24h = Schema::hasTable('gymies_support_tickets')
            ? (int) DB::table('gymies_support_tickets')
                ->whereIn('status', ['new', 'in_progress', 'waiting_customer'])
                ->where('created_at', '<', $yesterday)
                ->count()
            : 0;
        $pendingPayoutsCount = Schema::hasTable('gymies_payouts')
            ? (int) DB::table('gymies_payouts')->whereIn('status', ['pending', 'failed'])->count()
            : 0;

        $warnings = [];
        if ($ticketsOpenOver24h > 0) {
            $warnings[] = ['key' => 'tickets_open_over_24h', 'count' => $ticketsOpenOver24h, 'label' => 'Tickets open > 24 uur'];
        }
        if ($failedPayments > 0) {
            $warnings[] = ['key' => 'failed_payments', 'count' => $failedPayments, 'label' => 'Mislukte betalingen'];
        }

        return response()->json([
            'data' => [
                'users_count' => $users,
                'trainers_count' => $trainers,
                'customers_count' => $customers,
                'gyms_count' => $gyms,
                'open_tickets_count' => $openTickets,
                'failed_payments_count' => $failedPayments,
                'refunded_count' => $refunded,
                'users_today' => $usersToday,
                'tickets_today' => $ticketsToday,
                'bookings_today' => $bookingsToday,
                'tickets_open_over_24h' => $ticketsOpenOver24h,
                'pending_payouts_count' => $pendingPayoutsCount,
                'warnings' => $warnings,
            ],
        ]);
    }

    public function users(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $q = mb_substr(trim((string) $request->query('q', '')), 0, 255);
        $role = trim((string) $request->query('role', ''));
        $status = trim((string) $request->query('status', ''));
        $isAdminFilter = filter_var($request->query('is_admin'), FILTER_VALIDATE_BOOLEAN);
        $limit = min(max((int) $request->query('limit', 100), 1), 500);

        $hasIsAdmin = Schema::hasColumn('gymies_users', 'is_admin');
        $hasIsSuspended = Schema::hasColumn('gymies_users', 'is_suspended');
        $hasSuspendedAt = Schema::hasColumn('gymies_users', 'suspended_at');
        $hasDeletedAt = Schema::hasColumn('gymies_users', 'deleted_at');
        $hasFirstName = Schema::hasColumn('gymies_users', 'first_name');
        $hasLastName = Schema::hasColumn('gymies_users', 'last_name');
        $hasPhone = Schema::hasColumn('gymies_users', 'phone');

        $select = [
            'id',
            'email',
            'display_name',
            'role',
            $hasIsAdmin ? DB::raw('COALESCE(is_admin, 0) as is_admin') : DB::raw('0 as is_admin'),
            $hasIsSuspended ? DB::raw('COALESCE(is_suspended, 0) as is_suspended') : DB::raw('0 as is_suspended'),
            $hasSuspendedAt ? 'suspended_at' : DB::raw('NULL as suspended_at'),
            $hasDeletedAt ? 'deleted_at' : DB::raw('NULL as deleted_at'),
            'created_at',
        ];
        if ($hasFirstName) {
            $select[] = 'first_name';
        }
        if ($hasLastName) {
            $select[] = 'last_name';
        }
        if ($hasPhone) {
            $select[] = 'phone';
        }

        $query = DB::table('gymies_users')
            ->select($select)
            ->orderByDesc('id');
        if ($q !== '') {
            $qEsc = str_replace(['%', '_', '\\'], ['\\%', '\\_', '\\\\'], $q);
            $query->where(function ($w) use ($qEsc, $hasFirstName, $hasLastName, $hasPhone): void {
                $w->where('email', 'like', "%{$qEsc}%")
                    ->orWhere('display_name', 'like', "%{$qEsc}%");
                if ($hasPhone) {
                    $w->orWhere('phone', 'like', "%{$qEsc}%");
                }
                if ($hasFirstName) {
                    $w->orWhere('first_name', 'like', "%{$qEsc}%");
                }
                if ($hasLastName) {
                    $w->orWhere('last_name', 'like', "%{$qEsc}%");
                }
            });
        }
        if ($role !== '') {
            $query->where('role', $role);
        }
        if ($isAdminFilter && $hasIsAdmin) {
            $query->where('is_admin', 1);
        }
        if ($status === 'active') {
            if ($hasDeletedAt) {
                $query->whereNull('deleted_at');
            }
            if ($hasIsSuspended) {
                $query->where(function ($x): void {
                    $x->whereNull('is_suspended')->orWhere('is_suspended', 0);
                });
            }
        } elseif ($status === 'inactive') {
            if ($hasDeletedAt) {
                $query->whereNotNull('deleted_at');
            } else {
                return response()->json(['data' => []]);
            }
        } elseif ($status === 'suspended') {
            if ($hasIsSuspended || $hasSuspendedAt) {
                $query->where(function ($w) use ($hasIsSuspended, $hasSuspendedAt): void {
                    if ($hasIsSuspended) {
                        $w->where('is_suspended', 1);
                    }
                    if ($hasSuspendedAt) {
                        $hasIsSuspended ? $w->orWhereNotNull('suspended_at') : $w->whereNotNull('suspended_at');
                    }
                });
            } else {
                return response()->json(['data' => []]);
            }
        }

        $rows = $query->limit($limit)->get();

        return response()->json(['data' => $rows]);
    }

    public function updateUserStatus(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate([
            'status' => 'required|in:active,inactive,suspended',
            'reason' => 'required|string|max:500',
        ]);
        $target = (string) $request->input('status');
        $id = (int) $userId;
        $user = DB::table('gymies_users')->where('id', $id)->first();
        if (!$user) {
            return response()->json(['message' => 'User niet gevonden.'], 404);
        }

        $update = ['updated_at' => now()];
        if ($target === 'active') {
            if (Schema::hasColumn('gymies_users', 'deleted_at')) {
                $update['deleted_at'] = null;
            }
            if (Schema::hasColumn('gymies_users', 'is_suspended')) {
                $update['is_suspended'] = 0;
            }
            if (Schema::hasColumn('gymies_users', 'suspended_at')) {
                $update['suspended_at'] = null;
            }
        } elseif ($target === 'inactive') {
            if (Schema::hasColumn('gymies_users', 'deleted_at')) {
                $update['deleted_at'] = now();
            }
        } else {
            if (Schema::hasColumn('gymies_users', 'is_suspended')) {
                $update['is_suspended'] = 1;
            }
            if (Schema::hasColumn('gymies_users', 'suspended_at')) {
                $update['suspended_at'] = now();
            }
        }

        DB::table('gymies_users')->where('id', $id)->update($update);

        $this->audit((int) $admin->id, 'admin_user_status_updated', 'user', $id, [
            'reason' => (string) $request->input('reason'),
            'status' => $target,
        ]);

        return response()->json(['ok' => true]);
    }

    public function forceLogoutAll(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate(['reason' => 'required|string|max:500']);
        $id = (int) $userId;
        $query = DB::table('gymies_sessions')->where('user_id', $id);
        $deleted = Schema::hasColumn('gymies_sessions', 'revoked_at')
            ? $query->update(['revoked_at' => now()])
            : $query->delete();
        $this->audit((int) $admin->id, 'admin_user_force_logout_all', 'user', $id, [
            'deleted_sessions' => (int) $deleted,
            'reason' => (string) $request->input('reason'),
        ]);

        return response()->json(['ok' => true, 'revoked_sessions' => (int) $deleted]);
    }

    /**
     * Shadow login / impersonation: admin krijgt een tijdelijke sessie als de doelgebruiker.
     * Verplichte reden; wordt gelogd in audit.
     */
    public function impersonate(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate(['reason' => 'required|string|max:500']);
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $id = (int) $userId;
        $target = DB::table('gymies_users')->where('id', $id)->first();
        if (!$target) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }
        if ((int) $target->id === (int) $admin->id) {
            return response()->json(['message' => 'Je kunt niet als jezelf inloggen.'], 422);
        }

        $token = bin2hex(random_bytes(32));
        $expiresAt = now()->addHours(2);
        $sessionPayload = [
            'user_id' => $id,
            'token' => $token,
            'expires_at' => $expiresAt,
        ];
        if (Schema::hasColumn('gymies_sessions', 'ip_address')) {
            $sessionPayload['ip_address'] = $request->ip();
        }
        if (Schema::hasColumn('gymies_sessions', 'user_agent')) {
            $sessionPayload['user_agent'] = mb_substr((string) ($request->userAgent() ?? 'Gymies-Admin-Impersonation'), 0, 255);
        }
        if (Schema::hasColumn('gymies_sessions', 'revoked_at')) {
            $sessionPayload['revoked_at'] = null;
        }
        DB::table('gymies_sessions')->insert($sessionPayload);

        $this->audit((int) $admin->id, 'admin_impersonation_start', 'user', $id, [
            'reason' => (string) $request->input('reason'),
            'target_email' => (string) $target->email,
        ]);

        $userArray = [
            'id' => (string) $target->id,
            'email' => (string) $target->email,
            'display_name' => $target->display_name ?? null,
            'role' => (string) $target->role,
        ];
        if (Schema::hasColumn('gymies_users', 'first_name')) {
            $userArray['first_name'] = $target->first_name ?? null;
        }
        if (Schema::hasColumn('gymies_users', 'last_name')) {
            $userArray['last_name'] = $target->last_name ?? null;
        }

        return response()->json([
            'user' => $userArray,
            'token' => $token,
            'expires_at' => $expiresAt->toIso8601String(),
        ]);
    }

    /** Contentmoderatie: lijst profielen in wachtrij (pending_review). */
    public function moderationProfiles(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_trainer_profiles') || !Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_trainer_profiles as p')
            ->join('gymies_users as u', 'u.id', '=', 'p.user_id')
            ->where('p.moderation_status', 'pending_review')
            ->orderBy('p.updated_at')
            ->get([
                'p.user_id',
                'p.id as profile_id',
                'p.bio',
                'p.specialty',
                'p.avatar_url',
                'p.region',
                'p.updated_at',
                'u.email',
                'u.display_name',
            ]);
        $data = $rows->map(fn ($r) => [
            'user_id' => (string) $r->user_id,
            'profile_id' => (string) $r->profile_id,
            'email' => (string) $r->email,
            'display_name' => $r->display_name ?? $r->email ?? '',
            'bio' => $r->bio,
            'specialty' => $r->specialty,
            'avatar_url' => $r->avatar_url,
            'region' => $r->region,
            'updated_at' => $r->updated_at,
        ])->all();
        return response()->json(['data' => $data]);
    }

    /** Profiel goedkeuren. */
    public function moderationApprove(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId) || !Schema::hasTable('gymies_trainer_profiles') || !Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }
        $id = (int) $userId;
        $updated = DB::table('gymies_trainer_profiles')
            ->where('user_id', $id)
            ->update([
                'moderation_status' => 'approved',
                'moderation_reviewed_at' => now(),
                'moderation_reviewed_by_user_id' => (int) $admin->id,
                'moderation_reject_reason' => null,
            ]);
        if ($updated === 0) {
            return response()->json(['message' => 'Geen trainerprofiel gevonden.'], 404);
        }
        $this->audit((int) $admin->id, 'admin_moderation_approve', 'user', $id, []);
        return response()->json(['ok' => true]);
    }

    /** Profiel afkeuren (met reden). */
    public function moderationReject(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate(['reason' => 'required|string|max:500']);
        if (!$this->isPositiveId($userId) || !Schema::hasTable('gymies_trainer_profiles') || !Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }
        $id = (int) $userId;
        $reason = trim((string) $request->input('reason'));
        $updated = DB::table('gymies_trainer_profiles')
            ->where('user_id', $id)
            ->update([
                'moderation_status' => 'rejected',
                'moderation_reviewed_at' => now(),
                'moderation_reviewed_by_user_id' => (int) $admin->id,
                'moderation_reject_reason' => $reason,
            ]);
        if ($updated === 0) {
            return response()->json(['message' => 'Geen trainerprofiel gevonden.'], 404);
        }
        $this->audit((int) $admin->id, 'admin_moderation_reject', 'user', $id, ['reason' => $reason]);
        return response()->json(['ok' => true]);
    }

    /** Shadow ranking: kwaliteitsscore (0–100) zetten voor zoekresultaten. */
    public function moderationQualityScore(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate(['quality_score' => 'required|integer|min:0|max:100']);
        if (!$this->isPositiveId($userId) || !Schema::hasTable('gymies_trainer_profiles') || !Schema::hasColumn('gymies_trainer_profiles', 'quality_score')) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }
        $id = (int) $userId;
        $score = (int) $request->input('quality_score');
        $updated = DB::table('gymies_trainer_profiles')->where('user_id', $id)->update(['quality_score' => $score]);
        if ($updated === 0) {
            return response()->json(['message' => 'Geen trainerprofiel gevonden.'], 404);
        }
        $this->audit((int) $admin->id, 'admin_moderation_quality_score', 'user', $id, ['quality_score' => $score]);
        return response()->json(['ok' => true, 'quality_score' => $score]);
    }

    /** Gebruikersdetail: gegevens + aantallen tickets/boekingen + recente notities. */
    public function userDetail(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $id = (int) $userId;
        $user = DB::table('gymies_users')->where('id', $id)->first();
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }
        $data = [
            'id' => (string) $user->id,
            'email' => (string) $user->email,
            'display_name' => $user->display_name ?? null,
            'role' => (string) $user->role,
            'created_at' => $user->created_at,
        ];
        if (Schema::hasColumn('gymies_users', 'phone')) {
            $data['phone'] = $user->phone ?? null;
        }
        if (Schema::hasColumn('gymies_users', 'is_admin')) {
            $data['is_admin'] = (bool) ($user->is_admin ?? false);
        }
        if (Schema::hasColumn('gymies_users', 'is_suspended')) {
            $data['is_suspended'] = (bool) ($user->is_suspended ?? false);
        }
        if (Schema::hasColumn('gymies_users', 'suspended_at')) {
            $data['suspended_at'] = $user->suspended_at ?? null;
        }
        if (Schema::hasColumn('gymies_users', 'deleted_at')) {
            $data['deleted_at'] = $user->deleted_at ?? null;
        }
        if (Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
            $data['wallet_balance_cents'] = (int) ($user->wallet_balance_cents ?? 0);
        }
        $data['tickets_count'] = Schema::hasTable('gymies_support_tickets')
            ? (int) DB::table('gymies_support_tickets')->where('user_id', $id)->count()
            : 0;
        $data['bookings_count'] = Schema::hasTable('gymies_bookings')
            ? (int) DB::table('gymies_bookings')->where('client_user_id', $id)->orWhere('trainer_user_id', $id)->count()
            : 0;
        if (Schema::hasTable('gymies_sessions')) {
            $lastSession = DB::table('gymies_sessions')->where('user_id', $id)->orderByDesc('created_at')->first();
            $data['last_session_at'] = $lastSession->created_at ?? null;
        } else {
            $data['last_session_at'] = null;
        }
        if (Schema::hasTable('gymies_admin_user_notes')) {
            $data['notes'] = DB::table('gymies_admin_user_notes as n')
                ->leftJoin('gymies_users as a', 'a.id', '=', 'n.author_user_id')
                ->where('n.user_id', $id)
                ->orderByDesc('n.created_at')
                ->limit(50)
                ->get(['n.id', 'n.note', 'n.created_at', 'a.display_name as author_name'])
                ->all();
        } else {
            $data['notes'] = [];
        }
        $data['recent_bookings'] = [];
        if (Schema::hasTable('gymies_bookings')) {
            $data['recent_bookings'] = DB::table('gymies_bookings as b')
                ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
                ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
                ->where(function ($q) use ($id): void {
                    $q->where('b.client_user_id', $id)->orWhere('b.trainer_user_id', $id);
                })
                ->orderByDesc('b.scheduled_at')
                ->limit(5)
                ->get([
                    'b.id', 'b.status', 'b.scheduled_at', 'b.amount_cents',
                    DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                    DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                ])
                ->all();
        }
        $data['open_tickets'] = [];
        if (Schema::hasTable('gymies_support_tickets')) {
            $data['open_tickets'] = DB::table('gymies_support_tickets')
                ->where('user_id', $id)
                ->whereIn('status', ['new', 'in_progress', 'waiting_customer'])
                ->orderByDesc('id')
                ->limit(10)
                ->get(['id', 'subject', 'status', 'priority', 'created_at'])
                ->all();
        }
        $data['packages'] = [];
        if (Schema::hasTable('gymies_packages')) {
            $hasSessionsUsed = Schema::hasColumn('gymies_packages', 'sessions_used');
            $hasFrozen = Schema::hasColumn('gymies_packages', 'frozen_until');
            $select = ['id', 'name', 'sessions_count', 'total_cents'];
            if ($hasSessionsUsed) {
                $select[] = 'sessions_used';
            }
            if ($hasFrozen) {
                $select[] = 'frozen_until';
                $select[] = 'frozen_reason';
            }
            $data['packages'] = DB::table('gymies_packages')
                ->where('trainer_user_id', $id)
                ->orderByDesc('id')
                ->get($select)
                ->all();
        }
        if ((string) $user->role === 'trainer' && Schema::hasTable('gymies_trainer_profiles')) {
            $profile = DB::table('gymies_trainer_profiles')->where('user_id', $id)->first();
            if ($profile && Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
                $data['trainer_moderation_status'] = $profile->moderation_status ?? null;
                $data['trainer_moderation_reviewed_at'] = $profile->moderation_reviewed_at ?? null;
                $data['trainer_moderation_reject_reason'] = $profile->moderation_reject_reason ?? null;
            }
            if ($profile && Schema::hasColumn('gymies_trainer_profiles', 'quality_score')) {
                $data['trainer_quality_score'] = $profile->quality_score !== null ? (int) $profile->quality_score : null;
            }
            if ($profile && Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                $data['subscription_plan'] = $profile->subscription_plan ?? null;
            }
            $data['has_active_subscription'] = Schema::hasTable('gymies_subscriptions')
                ? DB::table('gymies_subscriptions')
                    ->where('trainer_user_id', $id)
                    ->whereIn('status', ['active', 'trialing'])
                    ->exists()
                : false;
        } else {
            $data['subscription_plan'] = null;
            $data['has_active_subscription'] = false;
        }
        return response()->json(['data' => $data]);
    }

    public function userNotes(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        if (!Schema::hasTable('gymies_admin_user_notes')) {
            return response()->json(['data' => []]);
        }
        $id = (int) $userId;
        $rows = DB::table('gymies_admin_user_notes as n')
            ->leftJoin('gymies_users as a', 'a.id', '=', 'n.author_user_id')
            ->where('n.user_id', $id)
            ->orderByDesc('n.created_at')
            ->get(['n.id', 'n.note', 'n.created_at', 'a.display_name as author_name']);
        return response()->json(['data' => $rows]);
    }

    public function addUserNote(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate(['note' => 'required|string|max:5000']);
        if (!Schema::hasTable('gymies_admin_user_notes')) {
            return response()->json(['message' => 'User notes tabel ontbreekt.'], 503);
        }
        $id = (int) $userId;
        if (!DB::table('gymies_users')->where('id', $id)->exists()) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }
        $noteId = DB::table('gymies_admin_user_notes')->insertGetId([
            'user_id' => $id,
            'author_user_id' => (int) $admin->id,
            'note' => trim((string) $request->input('note')),
            'created_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_user_note_added', 'user', $id, ['note_id' => $noteId]);
        return response()->json(['data' => ['id' => (string) $noteId]], 201);
    }

    /** Export gebruikers als CSV (e-mail, naam, rol, aanmaakdatum). */
    public function usersExport(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $q = mb_substr(trim((string) $request->query('q', '')), 0, 255);
        $role = trim((string) $request->query('role', ''));
        $limit = min(max((int) $request->query('limit', 5000), 1), 10000);
        $select = ['id', 'email', 'display_name', 'role', 'created_at'];
        if (Schema::hasColumn('gymies_users', 'first_name')) {
            $select[] = 'first_name';
        }
        if (Schema::hasColumn('gymies_users', 'last_name')) {
            $select[] = 'last_name';
        }
        if (Schema::hasColumn('gymies_users', 'phone')) {
            $select[] = 'phone';
        }
        $query = DB::table('gymies_users')
            ->select($select)
            ->orderByDesc('id');
        if ($q !== '') {
            $qEsc = str_replace(['%', '_', '\\'], ['\\%', '\\_', '\\\\'], $q);
            $query->where(function ($w) use ($qEsc): void {
                $w->where('email', 'like', "%{$qEsc}%")
                    ->orWhere('display_name', 'like', "%{$qEsc}%");
                if (Schema::hasColumn('gymies_users', 'phone')) {
                    $w->orWhere('phone', 'like', "%{$qEsc}%");
                }
                if (Schema::hasColumn('gymies_users', 'first_name')) {
                    $w->orWhere('first_name', 'like', "%{$qEsc}%");
                }
                if (Schema::hasColumn('gymies_users', 'last_name')) {
                    $w->orWhere('last_name', 'like', "%{$qEsc}%");
                }
            });
        }
        if ($role !== '') {
            $query->where('role', $role);
        }
        $rows = $query->limit($limit)->get();
        $lines = ["id;email;display_name;role;created_at"];
        foreach ($rows as $r) {
            $lines[] = sprintf(
                "%s;%s;%s;%s;%s",
                $r->id,
                str_replace([';', "\r", "\n"], [' ', ' ', ' '], (string) $r->email),
                str_replace([';', "\r", "\n"], [' ', ' ', ' '], (string) ($r->display_name ?? '')),
                $r->role ?? '',
                $r->created_at ?? ''
            );
        }
        return response()->json(['data' => ['csv' => implode("\n", $lines)]]);
    }

    public function addAvailabilityOverride(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'trainer_user_id' => 'required|integer|min:1',
            'exception_date' => 'required|date',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_availability_exceptions')) {
            return response()->json(['message' => 'Availability exceptions tabel ontbreekt.'], 503);
        }
        $trainerId = (int) $request->input('trainer_user_id');
        $date = $request->input('exception_date');
        $reason = (string) $request->input('reason');

        $id = DB::table('gymies_availability_exceptions')->insertGetId([
            'trainer_user_id' => $trainerId,
            'exception_date' => $date,
            'is_available' => 0,
            'start_time' => null,
            'end_time' => null,
            'created_at' => now(),
        ]);

        $affected = 0;
        if (Schema::hasTable('gymies_bookings')) {
            $affected = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->whereIn('status', ['pending', 'confirmed'])
                ->whereRaw('DATE(scheduled_at) = ?', [$date])
                ->count();
        }

        $this->audit((int) $admin->id, 'admin_availability_override', 'availability_exception', (int) $id, [
            'trainer_user_id' => $trainerId,
            'exception_date' => $date,
            'reason' => $reason,
            'affected_bookings' => $affected,
        ]);
        return response()->json([
            'ok' => true,
            'exception_id' => (string) $id,
            'affected_bookings' => $affected,
        ], 201);
    }

    /** Pakket: sessies aanpassen of bevriezen (admin). */
    public function updatePackageAdmin(Request $request, string $packageId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($packageId)) {
            return response()->json(['message' => 'Ongeldige package id.'], 422);
        }
        $request->validate([
            'sessions_used_delta' => 'nullable|integer',
            'frozen_until' => 'nullable|date',
            'frozen_reason' => 'nullable|string|max:255',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_packages')) {
            return response()->json(['message' => 'Packages niet beschikbaar.'], 503);
        }
        $id = (int) $packageId;
        $p = DB::table('gymies_packages')->where('id', $id)->first();
        if (!$p) {
            return response()->json(['message' => 'Pakket niet gevonden.'], 404);
        }
        $update = [];
        if ($request->has('sessions_used_delta') && Schema::hasColumn('gymies_packages', 'sessions_used')) {
            $delta = (int) $request->input('sessions_used_delta');
            $current = (int) ($p->sessions_used ?? 0);
            $newVal = max(0, min($current + $delta, (int) $p->sessions_count));
            $update['sessions_used'] = $newVal;
        }
        if ($request->has('frozen_until') && Schema::hasColumn('gymies_packages', 'frozen_until')) {
            $update['frozen_until'] = $request->input('frozen_until') ?: null;
            $update['frozen_reason'] = $request->input('frozen_reason') ?: null;
        }
        if ($update !== []) {
            DB::table('gymies_packages')->where('id', $id)->update($update);
        }
        $this->audit((int) $admin->id, 'admin_package_updated', 'package', $id, [
            'reason' => (string) $request->input('reason'),
            'updates' => $update,
        ]);
        return response()->json(['ok' => true]);
    }

    /** Bulk: wijs alle onbeantwoorde tickets van gisteren toe aan medewerker. */
    public function bulkAssignTicketsFromYesterday(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'assigned_to_user_id' => 'required|integer|min:1',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['updated' => 0]);
        }
        $yesterday = now()->subDay()->format('Y-m-d');
        $ticketIds = DB::table('gymies_support_tickets')
            ->whereIn('status', ['new', 'in_progress'])
            ->whereRaw('DATE(created_at) = ?', [$yesterday])
            ->pluck('id')
            ->all();
        if (count($ticketIds) === 0) {
            return response()->json(['updated' => 0, 'message' => 'Geen tickets van gisteren.']);
        }
        $hasAssigned = Schema::hasColumn('gymies_support_tickets', 'assigned_to_user_id');
        if (!$hasAssigned) {
            return response()->json(['updated' => 0]);
        }
        DB::table('gymies_support_tickets')->whereIn('id', $ticketIds)->update([
            'assigned_to_user_id' => (int) $request->input('assigned_to_user_id'),
            'status' => 'in_progress',
            'updated_at' => now(),
        ]);
        foreach ($ticketIds as $tid) {
            $this->audit((int) $admin->id, 'admin_bulk_ticket_assign_yesterday', 'support_ticket', (int) $tid, [
                'reason' => (string) $request->input('reason'),
            ]);
        }
        return response()->json(['ok' => true, 'updated' => count($ticketIds)]);
    }

    /** Lijst trainers met pending payout (voor herinnering). */
    public function trainersWithPendingPayout(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_payouts as p')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'p.trainer_user_id')
            ->where('p.status', 'pending')
            ->select(['p.id', 'p.trainer_user_id', 'p.amount_cents', 'p.created_at', 'u.email as trainer_email', 'u.display_name as trainer_name'])
            ->get()
            ->all();
        return response()->json(['data' => $rows]);
    }

    /** Lijst broadcasts (banners, onderhoudsmodus). */
    public function broadcastsIndex(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_broadcasts')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_broadcasts')
            ->orderByDesc('id')
            ->limit(100)
            ->get(['id', 'type', 'title', 'message', 'severity', 'target_role', 'target_region', 'active_from', 'active_until', 'created_at'])
            ->all();
        return response()->json(['data' => $rows]);
    }

    /** Broadcast aanmaken (banner of maintenance). */
    public function broadcastStore(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'type' => 'required|in:banner,maintenance',
            'title' => 'nullable|string|max:255',
            'message' => 'required|string|max:2000',
            'severity' => 'nullable|in:info,warning,critical',
            'active_until' => 'nullable|date',
        ]);
        if (!Schema::hasTable('gymies_broadcasts')) {
            return response()->json(['message' => 'Broadcasts-tabel niet beschikbaar. Draai alter_gymies_broadcasts.sql.'], 503);
        }
        $id = DB::table('gymies_broadcasts')->insertGetId([
            'type' => $request->input('type'),
            'title' => $request->input('title') ? trim((string) $request->input('title')) : null,
            'message' => trim((string) $request->input('message')),
            'severity' => $request->input('severity') ?? 'info',
            'active_until' => $request->input('active_until') ? $request->input('active_until') : null,
            'created_by_user_id' => (int) $admin->id,
            'created_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_broadcast_created', 'broadcast', (int) $id, [
            'type' => $request->input('type'),
            'severity' => $request->input('severity') ?? 'info',
        ]);
        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    /** Broadcast deactiveren (verwijderen). */
    public function broadcastDestroy(Request $request, string $id): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($id)) {
            return response()->json(['message' => 'Ongeldige id.'], 422);
        }
        if (!Schema::hasTable('gymies_broadcasts')) {
            return response()->json(['message' => 'Broadcasts niet beschikbaar.'], 503);
        }
        $row = DB::table('gymies_broadcasts')->where('id', (int) $id)->first();
        if (!$row) {
            return response()->json(['message' => 'Broadcast niet gevonden.'], 404);
        }
        DB::table('gymies_broadcasts')->where('id', (int) $id)->delete();
        $this->audit((int) $admin->id, 'admin_broadcast_deleted', 'broadcast', (int) $id, ['type' => $row->type]);
        return response()->json(['ok' => true]);
    }

    public function securityEvents(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $attempts = Schema::hasTable('gymies_auth_attempts')
            ? DB::table('gymies_auth_attempts')->orderByDesc('id')->limit(200)->get()
            : collect();
        $rateLimits = Schema::hasTable('gymies_rate_limit_events')
            ? DB::table('gymies_rate_limit_events')->orderByDesc('id')->limit(200)->get()
            : collect();
        $apiErrors = Schema::hasTable('gymies_api_error_logs')
            ? DB::table('gymies_api_error_logs')->orderByDesc('id')->limit(200)->get()
            : collect();

        $attempts = $attempts->map(function ($a) {
            $arr = (array) $a;
            $arr['country_code'] = $this->ipToCountryCode($arr['ip_address'] ?? '');
            return (object) $arr;
        });
        $rateLimits = $rateLimits->map(function ($r) {
            $arr = (array) $r;
            $arr['country_code'] = $this->ipToCountryCode($arr['ip_address'] ?? '');
            return (object) $arr;
        });

        return response()->json([
            'data' => [
                'auth_attempts' => $attempts,
                'rate_limit_events' => $rateLimits,
                'api_errors' => $apiErrors,
            ],
        ]);
    }

    private function ipToCountryCode(string $ip): ?string
    {
        if ($ip === '' || $ip === '127.0.0.1' || str_starts_with($ip, '192.168.') || str_starts_with($ip, '10.')) {
            return null;
        }
        $url = 'http://ip-api.com/json/' . urlencode($ip) . '?fields=countryCode';
        $ctx = stream_context_create(['http' => ['timeout' => 1.5]]);
        $raw = @file_get_contents($url, false, $ctx);
        if ($raw === false) {
            return null;
        }
        $data = json_decode($raw, true);
        return isset($data['countryCode']) ? (string) $data['countryCode'] : null;
    }

    public function ipAllowlist(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_admin_ip_allowlist')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_admin_ip_allowlist')->orderByDesc('id')->get();

        return response()->json(['data' => $rows]);
    }

    public function addIpAllowlist(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'ip_pattern' => 'required|string|max:64',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_admin_ip_allowlist')) {
            return response()->json(['message' => 'IP allowlist tabel ontbreekt.'], 422);
        }
        $id = DB::table('gymies_admin_ip_allowlist')->insertGetId([
            'ip_pattern' => trim((string) $request->input('ip_pattern')),
            'status' => 'active',
            'created_by_user_id' => (int) $admin->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_ip_allowlist_added', 'admin_ip_allowlist', (int) $id, [
            'reason' => (string) $request->input('reason'),
        ]);

        return response()->json(['ok' => true], 201);
    }

    public function removeIpAllowlist(Request $request, string $id): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($id)) {
            return response()->json(['message' => 'Ongeldige id.'], 422);
        }
        $request->validate(['reason' => 'required|string|max:500']);
        if (!Schema::hasTable('gymies_admin_ip_allowlist')) {
            return response()->json(['message' => 'IP allowlist tabel ontbreekt.'], 422);
        }
        $row = DB::table('gymies_admin_ip_allowlist')->where('id', (int) $id)->first();
        $oldValues = $row ? ['status' => (string) $row->status, 'ip_pattern' => (string) $row->ip_pattern] : null;
        DB::table('gymies_admin_ip_allowlist')->where('id', (int) $id)->update([
            'status' => 'inactive',
            'updated_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_ip_allowlist_removed', 'admin_ip_allowlist', (int) $id, [
            'reason' => (string) $request->input('reason'),
        ], $oldValues);

        return response()->json(['ok' => true]);
    }

    /** Global search: gebruikers (e-mail, naam), boekingen (id), organisaties (naam). */
    public function search(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $q = mb_substr(trim((string) $request->query('q', '')), 0, 255);
        $users = [];
        $bookings = [];
        $tickets = [];
        $organisations = [];
        $qEsc = str_replace(['%', '_', '\\'], ['\\%', '\\_', '\\\\'], $q);
        $like = strlen($q) >= 2 ? '%' . $qEsc . '%' : null;
        if ($like !== null) {
            $users = DB::table('gymies_users')
                ->select(['id', 'email', 'display_name', 'role'])
                ->where(function ($w) use ($like): void {
                    $w->where('email', 'like', $like)
                        ->orWhere('display_name', 'like', $like);
                })
                ->orderByDesc('id')
                ->limit(15)
                ->get()
                ->all();
        }
        if (ctype_digit($q)) {
            $id = (int) $q;
            if (Schema::hasTable('gymies_bookings')) {
                $bookings = DB::table('gymies_bookings as b')
                    ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
                    ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
                    ->where('b.id', $id)
                    ->get([
                        'b.id', 'b.status', 'b.scheduled_at',
                        DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                        DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                    ])
                    ->all();
            }
            if (Schema::hasTable('gymies_support_tickets')) {
                $tickets = DB::table('gymies_support_tickets as t')
                    ->leftJoin('gymies_users as u', 'u.id', '=', 't.user_id')
                    ->where('t.id', $id)
                    ->get([
                        't.id', 't.subject', 't.status', 't.priority', 't.created_at',
                        DB::raw('COALESCE(u.display_name, u.email) as user_email'),
                    ])
                    ->all();
            }
        }
        if ($like !== null && Schema::hasTable('gymies_organisations')) {
            $organisations = DB::table('gymies_organisations')
                ->where('name', 'like', $like)
                ->orderByDesc('id')
                ->limit(10)
                ->get(['id', 'name', 'status'])
                ->all();
        }
        return response()->json([
            'data' => [
                'users' => $users,
                'bookings' => $bookings,
                'tickets' => $tickets,
                'organisations' => $organisations,
            ],
        ]);
    }

    /** Draai een audit-actie terug (alleen ondersteunde acties, bijv. IP allowlist opnieuw actief). */
    public function auditRevert(Request $request, string $auditId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($auditId)) {
            return response()->json(['message' => 'Ongeldige audit id.'], 422);
        }
        $request->validate(['reason' => 'required|string|max:500']);
        if (!Schema::hasTable('gymies_audit_log')) {
            return response()->json(['message' => 'Auditlog niet beschikbaar.'], 503);
        }
        $audit = DB::table('gymies_audit_log')->where('id', (int) $auditId)->first();
        if (!$audit) {
            return response()->json(['message' => 'Auditregel niet gevonden.'], 404);
        }
        $action = (string) $audit->action;
        $entityType = (string) $audit->entity_type;
        $entityId = (int) $audit->entity_id;
        $oldValues = $audit->old_values ? json_decode((string) $audit->old_values, true) : null;
        if ($action === 'admin_ip_allowlist_removed' && $entityType === 'admin_ip_allowlist' && is_array($oldValues) && ($oldValues['status'] ?? '') === 'active') {
            if (!Schema::hasTable('gymies_admin_ip_allowlist')) {
                return response()->json(['message' => 'IP allowlist tabel ontbreekt.'], 503);
            }
            DB::table('gymies_admin_ip_allowlist')->where('id', $entityId)->update([
                'status' => 'active',
                'updated_at' => now(),
            ]);
            $this->audit((int) $admin->id, 'admin_audit_reverted', 'audit_log', (int) $auditId, [
                'reverted_action' => $action,
                'entity_type' => $entityType,
                'entity_id' => $entityId,
                'reason' => (string) $request->input('reason'),
            ]);
            return response()->json(['ok' => true, 'message' => 'IP weer actief gemaakt.']);
        }
        return response()->json(['message' => 'Deze actie kan niet worden teruggedraaid.'], 422);
    }

    public function audits(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_audit_log')) {
            return response()->json(['data' => []]);
        }
        $q = trim((string) $request->query('q', ''));
        $action = trim((string) $request->query('action', ''));
        $dateFrom = trim((string) $request->query('date_from', ''));
        $dateTo = trim((string) $request->query('date_to', ''));
        $userId = $request->query('user_id') ? (int) $request->query('user_id') : null;
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);
        $query = DB::table('gymies_audit_log as a')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'a.user_id')
            ->orderByDesc('a.id')
            ->select([
                'a.id',
                'a.user_id',
                'u.email as actor_email',
                'a.action',
                'a.entity_type',
                'a.entity_id',
                'a.old_values',
                'a.new_values',
                'a.ip_address',
                'a.created_at',
            ]);
        if ($action !== '') {
            $query->where('a.action', $action);
        }
        if ($userId !== null && $userId > 0) {
            $query->where('a.user_id', $userId);
        }
        if ($dateFrom !== '') {
            $query->where('a.created_at', '>=', $dateFrom);
        }
        if ($dateTo !== '') {
            $query->where('a.created_at', '<=', $dateTo . ' 23:59:59');
        }
        if ($q !== '') {
            $query->where(function ($w) use ($q): void {
                $w->where('u.email', 'like', "%{$q}%")
                    ->orWhere('a.action', 'like', "%{$q}%")
                    ->orWhere('a.entity_type', 'like', "%{$q}%");
            });
        }

        return response()->json(['data' => $query->limit($limit)->get()]);
    }

    /** Export auditlog als CSV (voor compliance). */
    public function auditsExport(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_audit_log')) {
            return response()->json(['data' => ['csv' => '']]);
        }
        $action = trim((string) $request->query('action', ''));
        $dateFrom = trim((string) $request->query('date_from', ''));
        $dateTo = trim((string) $request->query('date_to', ''));
        $limit = min(max((int) $request->query('limit', 5000), 1), 10000);
        $query = DB::table('gymies_audit_log as a')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'a.user_id')
            ->orderByDesc('a.id')
            ->select(['a.id', 'a.user_id', 'u.email as actor_email', 'a.action', 'a.entity_type', 'a.entity_id', 'a.ip_address', 'a.created_at']);
        if ($action !== '') {
            $query->where('a.action', $action);
        }
        if ($dateFrom !== '') {
            $query->where('a.created_at', '>=', $dateFrom);
        }
        if ($dateTo !== '') {
            $query->where('a.created_at', '<=', $dateTo . ' 23:59:59');
        }
        $rows = $query->limit($limit)->get();
        $lines = ['id;user_id;actor_email;action;entity_type;entity_id;ip_address;created_at'];
        foreach ($rows as $r) {
            $lines[] = sprintf(
                "%s;%s;%s;%s;%s;%s;%s;%s",
                $r->id,
                $r->user_id ?? '',
                str_replace([';', "\r", "\n"], [' ', ' ', ' '], (string) ($r->actor_email ?? '')),
                str_replace([';', "\r", "\n"], [' ', ' ', ' '], (string) ($r->action ?? '')),
                $r->entity_type ?? '',
                $r->entity_id ?? '',
                $r->ip_address ?? '',
                $r->created_at ?? ''
            );
        }
        return response()->json(['data' => ['csv' => implode("\n", $lines)]]);
    }

    /** Bulk: gebruikersstatus wijzigen. */
    public function bulkUsersStatus(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'user_ids' => 'required|array',
            'user_ids.*' => 'integer|min:1',
            'status' => 'required|in:active,inactive,suspended',
            'reason' => 'required|string|max:500',
        ]);
        $ids = array_map('intval', $request->input('user_ids', []));
        $ids = array_unique(array_filter($ids));
        if (count($ids) > 100) {
            return response()->json(['message' => 'Maximaal 100 gebruikers per bulkactie.'], 422);
        }
        $target = (string) $request->input('status');
        $reason = (string) $request->input('reason');
        $updated = 0;
        foreach ($ids as $id) {
            $user = DB::table('gymies_users')->where('id', $id)->first();
            if (!$user) {
                continue;
            }
            $update = ['updated_at' => now()];
            if ($target === 'active') {
                if (Schema::hasColumn('gymies_users', 'deleted_at')) {
                    $update['deleted_at'] = null;
                }
                if (Schema::hasColumn('gymies_users', 'is_suspended')) {
                    $update['is_suspended'] = 0;
                }
                if (Schema::hasColumn('gymies_users', 'suspended_at')) {
                    $update['suspended_at'] = null;
                }
            } elseif ($target === 'inactive' && Schema::hasColumn('gymies_users', 'deleted_at')) {
                $update['deleted_at'] = now();
            } elseif ($target === 'suspended') {
                if (Schema::hasColumn('gymies_users', 'is_suspended')) {
                    $update['is_suspended'] = 1;
                }
                if (Schema::hasColumn('gymies_users', 'suspended_at')) {
                    $update['suspended_at'] = now();
                }
            }
            DB::table('gymies_users')->where('id', $id)->update($update);
            $this->audit((int) $admin->id, 'admin_bulk_user_status', 'user', $id, ['status' => $target, 'reason' => $reason]);
            $updated++;
        }
        return response()->json(['ok' => true, 'updated' => $updated]);
    }

    /** Bulk: tickets status/priority wijzigen. */
    public function bulkTickets(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'ticket_ids' => 'required|array',
            'ticket_ids.*' => 'integer|min:1',
            'status' => 'nullable|in:new,in_progress,waiting_customer,resolved',
            'priority' => 'nullable|in:low,medium,high,critical',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['updated' => 0]);
        }
        $ids = array_map('intval', $request->input('ticket_ids', []));
        $ids = array_unique(array_filter($ids));
        if (count($ids) > 50) {
            return response()->json(['message' => 'Maximaal 50 tickets per bulkactie.'], 422);
        }
        $updates = [];
        if ($request->filled('status')) {
            $updates['status'] = (string) $request->input('status');
            if ($updates['status'] === 'resolved') {
                $updates['resolved_at'] = now();
            }
        }
        if ($request->filled('priority')) {
            $updates['priority'] = (string) $request->input('priority');
        }
        if ($updates === []) {
            return response()->json(['message' => 'Geen velden om bij te werken.'], 422);
        }
        $updates['updated_at'] = now();
        DB::table('gymies_support_tickets')->whereIn('id', $ids)->update($updates);
        foreach ($ids as $tid) {
            $this->audit((int) $admin->id, 'admin_bulk_ticket_update', 'support_ticket', (int) $tid, [
                'reason' => (string) $request->input('reason'),
                'changes' => $updates,
            ]);
        }
        return response()->json(['ok' => true, 'updated' => count($ids)]);
    }

    /** Bulk: betalingsstatus wijzigen. */
    public function bulkPayoutsStatus(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['updated' => 0]);
        }
        $request->validate([
            'payout_ids' => 'required|array',
            'payout_ids.*' => 'integer|min:1',
            'status' => 'required|in:pending,paid,failed',
            'reason' => 'required|string|max:500',
        ]);
        $ids = array_map('intval', $request->input('payout_ids', []));
        $ids = array_unique(array_filter($ids));
        if (count($ids) > 50) {
            return response()->json(['message' => 'Maximaal 50 betalingen per bulkactie.'], 422);
        }
        $status = (string) $request->input('status');
        $updated = 0;
        foreach ($ids as $id) {
            $p = DB::table('gymies_payouts')->where('id', $id)->first();
            if (!$p) {
                continue;
            }
            $update = ['status' => $status, 'updated_at' => now()];
            if ($status === 'paid') {
                $update['paid_at'] = now();
            }
            DB::table('gymies_payouts')->where('id', $id)->update($update);
            $this->audit((int) $admin->id, 'admin_bulk_payout_status', 'payout', $id, [
                'reason' => (string) $request->input('reason'),
                'new_status' => $status,
            ]);
            $updated++;
        }
        return response()->json(['ok' => true, 'updated' => $updated]);
    }

    /** Opgeslagen views (filters) voor admin dashboards. */
    public function savedViews(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_admin_saved_views')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_admin_saved_views')
            ->where('created_by_user_id', (int) $admin->id)
            ->orderByDesc('id')
            ->get();
        return response()->json(['data' => $rows]);
    }

    public function storeSavedView(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'view_name' => 'required|string|max:255',
            'view_data' => 'required|json',
        ]);
        if (!Schema::hasTable('gymies_admin_saved_views')) {
            return response()->json(['message' => 'Saved views tabel ontbreekt.'], 503);
        }
        $id = DB::table('gymies_admin_saved_views')->insertGetId([
            'created_by_user_id' => (int) $admin->id,
            'view_name' => trim((string) $request->input('view_name')),
            'view_data' => (string) $request->input('view_data'),
            'created_at' => now(),
        ]);
        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    public function destroySavedView(Request $request, string $viewId): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($viewId)) {
            return response()->json(['message' => 'Ongeldige view id.'], 422);
        }
        if (!Schema::hasTable('gymies_admin_saved_views')) {
            return response()->json(['message' => 'Saved views tabel ontbreekt.'], 503);
        }
        DB::table('gymies_admin_saved_views')->where('id', (int) $viewId)->where('created_by_user_id', (int) $admin->id)->delete();
        return response()->json(['ok' => true]);
    }

    /** Notitiebljokken (snelkoppelingen voor admin communicatie). */
    public function noteTemplates(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_admin_note_templates')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_admin_note_templates')
            ->where('created_by_user_id', (int) $admin->id)
            ->orWhereNull('created_by_user_id')
            ->orderByDesc('id')
            ->get();
        return response()->json(['data' => $rows]);
    }

    /** Winstgevendheid (margin % per trainer/package). */
    public function profitabilityOverview(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }
        $month = trim((string) $request->query('month', ''));
        $start = $month !== '' ? \Illuminate\Support\Carbon::parse($month . '-01') : now()->startOfMonth();
        $end = $start->copy()->endOfMonth();
        $bookings = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->whereBetween('b.scheduled_at', [$start, $end])
            ->whereIn('b.status', ['confirmed', 'completed', 'no_show'])
            ->selectRaw('t.id as trainer_id, t.display_name as trainer_name, COUNT(*) as booking_count, SUM(b.amount_cents) as total_cents')
            ->groupBy('t.id', 't.display_name')
            ->get();
        return response()->json([
            'data' => [
                'month' => $start->format('Y-m'),
                'trainers' => $bookings->map(fn ($r) => [
                    'trainer_id' => (string) $r->trainer_id,
                    'trainer_name' => (string) $r->trainer_name,
                    'booking_count' => (int) $r->booking_count,
                    'total_cents' => (int) ($r->total_cents ?? 0),
                    'platform_fee_cents' => (int) round(($r->total_cents ?? 0) * 0.12),
                ])->all(),
            ],
        ]);
    }

    public function profitabilitySettings(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_system_settings')) {
            return response()->json(['data' => ['platform_fee_percent' => 12]]);
        }
        $setting = DB::table('gymies_system_settings')->where('setting_key', 'platform_fee_percent')->first();
        return response()->json(['data' => [
            'platform_fee_percent' => $setting ? (int) $setting->setting_value : 12,
        ]]);
    }

    public function updateProfitabilitySettings(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate(['platform_fee_percent' => 'required|integer|min:0|max:100']);
        if (!Schema::hasTable('gymies_system_settings')) {
            return response()->json(['message' => 'System settings tabel ontbreekt.'], 503);
        }
        $value = (int) $request->input('platform_fee_percent');
        DB::table('gymies_system_settings')->updateOrInsert(
            ['setting_key' => 'platform_fee_percent'],
            ['setting_value' => (string) $value]
        );
        return response()->json(['ok' => true, 'platform_fee_percent' => $value]);
    }

    /** Media beheer: banner, logo, logo klein. */

    /**
     * Upload media site (banner/logo/sm_logo).
     */
    public function uploadSiteMedia(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate(['file' => 'required|image|max:2048', 'type' => 'required|in:banner,logo,sm_logo']);
        $file = $request->file('file');
        if (!$file) {
            return response()->json(['message' => 'Geen bestand geüpload.'], 422);
        }
        $type = (string) $request->input('type');
        $filename = 'site_' . $type . '_' . now()->timestamp . '.' . $file->getClientOriginalExtension();
        try {
            Storage::disk('public')->put('media/' . $filename, $file->get());
            $url = Storage::disk('public')->url('media/' . $filename);
            if (!Schema::hasTable('gymies_system_settings')) {
                return response()->json(['data' => ['url' => $url]]);
            }
            $key = 'site_' . $type . '_url';
            DB::table('gymies_system_settings')->updateOrInsert(
                ['setting_key' => $key],
                ['setting_value' => $url]
            );
            $this->audit((int) $admin->id, 'admin_site_media_uploaded', 'site_media', 0, ['type' => $type, 'filename' => $filename]);
            return response()->json(['data' => ['url' => $url]], 201);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Upload mislukt: ' . $e->getMessage()], 500);
        }
    }

    /**
     * Fetch huidigte site media
     */
    public function updateSiteMedia(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.security.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_system_settings')) {
            return response()->json(['data' => []]);
        }
        $types = ['banner', 'logo', 'sm_logo'];
        $media = [];
        foreach ($types as $type) {
            $setting = DB::table('gymies_system_settings')->where('setting_key', 'site_' . $type . '_url')->first();
            $media[$type] = $setting ? (string) $setting->setting_value : null;
        }
        return response()->json(['data' => $media]);
    }

    /** Haal setting-waarde op (private helper). */
    private function getSetting(string $key): ?string
    {
        if (!Schema::hasTable('gymies_system_settings')) {
            return null;
        }
        $setting = DB::table('gymies_system_settings')->where('setting_key', $key)->first();
        return $setting ? (string) $setting->setting_value : null;
    }

    /** Trainer drop-off alerts: wie is inactief de afgelopen X dagen. */

    public function trainerDropoffAlerts(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_availability_slots')) {
            return response()->json(['data' => []]);
        }
        $cutoff = now()->subDays(10)->toDateTimeString();
        $trainers = DB::table('gymies_availability_slots as s')
            ->leftJoin('gymies_users as u', 'u.id', '=', 's.user_id')
            ->where('u.role', 'trainer')
            ->selectRaw('u.id, u.display_name, u.email, MAX(s.start_at) as last_slot')
            ->groupBy('u.id', 'u.display_name', 'u.email')
            ->having('last_slot', '<', $cutoff)
            ->limit(100)
            ->get();
        return response()->json(['data' => $trainers]);
    }

    public function sendNudge(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate(['message' => 'required|string|max:500']);
        $id = (int) $userId;
        $user = DB::table('gymies_users')->where('id', $id)->first();
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }
        $this->audit((int) $admin->id, 'admin_nudge_sent', 'user', $id, [
            'message' => (string) $request->input('message'),
        ]);
        return response()->json(['ok' => true]);
    }

    /** Chat leakage: signaling berichten buiten het platform om. */

    public function chatLeakageFlags(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_chat_messages') && !Schema::hasTable('gymies_chat_leakage_flags')) {
            return response()->json(['data' => []]);
        }
        $rows = Schema::hasTable('gymies_chat_leakage_flags')
            ? DB::table('gymies_chat_leakage_flags')->orderByDesc('id')->limit(100)->get()
            : collect();
        return response()->json(['data' => $rows]);
    }

    public function scanChatKeywords(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_system_settings')) {
            return response()->json(['keywords' => []]);
        }
        $setting = DB::table('gymies_system_settings')->where('setting_key', 'chat_leakage_keywords')->first();
        $keywords = $setting && $setting->setting_value
            ? json_decode((string) $setting->setting_value, true)
            : [];
        return response()->json(['keywords' => is_array($keywords) ? $keywords : []]);
    }

    public function reviewLeakageFlag(Request $request, string $flagId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($flagId)) {
            return response()->json(['message' => 'Ongeldige flag id.'], 422);
        }
        $request->validate(['action' => 'required|in:confirmed,false_positive']);
        if (!Schema::hasTable('gymies_chat_leakage_flags')) {
            return response()->json(['message' => 'Chat leakage flags tabel ontbreekt.'], 503);
        }
        $id = (int) $flagId;
        $flag = DB::table('gymies_chat_leakage_flags')->where('id', $id)->first();
        if (!$flag) {
            return response()->json(['message' => 'Flag niet gevonden.'], 404);
        }
        DB::table('gymies_chat_leakage_flags')->where('id', $id)->update([
            'reviewed_at' => now(),
            'reviewed_by_user_id' => (int) $admin->id,
            'status' => (string) $request->input('action'),
        ]);
        $this->audit((int) $admin->id, 'admin_chat_leakage_reviewed', 'chat_leakage_flag', $id, [
            'status' => (string) $request->input('action'),
        ]);
        return response()->json(['ok' => true]);
    }

    /** Trainer tiers (ranking levels). */

    public function trainerTiers(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_trainer_tiers')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_trainer_tiers')->orderByDesc('id')->get();
        return response()->json(['data' => $rows]);
    }

    public function updateUserTier(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate(['tier_id' => 'required|integer|min:1']);
        if (!Schema::hasTable('gymies_trainer_tiers')) {
            return response()->json(['message' => 'Trainer tiers tabel ontbreekt.'], 503);
        }
        $id = (int) $userId;
        $tierId = (int) $request->input('tier_id');
        if (!DB::table('gymies_trainer_tiers')->where('id', $tierId)->exists()) {
            return response()->json(['message' => 'Tier niet gevonden.'], 404);
        }
        DB::table('gymies_users')->where('id', $id)->update(['trainer_tier_id' => $tierId]);
        $this->audit((int) $admin->id, 'admin_user_tier_updated', 'user', $id, ['tier_id' => $tierId]);
        return response()->json(['ok' => true]);
    }

    /** Bulk marketing: campagnes en mails. */

    public function bulkCampaigns(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_bulk_campaigns')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_bulk_campaigns')->orderByDesc('id')->limit(100)->get();
        return response()->json(['data' => $rows]);
    }

    public function bulkCampaignStore(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'name' => 'required|string|max:255',
            'target_role' => 'required|in:trainer,klant,all',
            'subject' => 'required|string|max:255',
            'body' => 'required|string|max:5000',
        ]);
        if (!Schema::hasTable('gymies_bulk_campaigns')) {
            return response()->json(['message' => 'Bulk campaigns tabel ontbreekt.'], 503);
        }
        $id = DB::table('gymies_bulk_campaigns')->insertGetId([
            'created_by_user_id' => (int) $admin->id,
            'name' => trim((string) $request->input('name')),
            'target_role' => (string) $request->input('target_role'),
            'subject' => trim((string) $request->input('subject')),
            'body' => trim((string) $request->input('body')),
            'sent_at' => null,
            'created_at' => now(),
        ]);
        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    public function bulkCampaignSend(Request $request, string $campaignId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($campaignId)) {
            return response()->json(['message' => 'Ongeldige campaign id.'], 422);
        }
        if (!Schema::hasTable('gymies_bulk_campaigns')) {
            return response()->json(['message' => 'Bulk campaigns tabel ontbreekt.'], 503);
        }
        $id = (int) $campaignId;
        $campaign = DB::table('gymies_bulk_campaigns')->where('id', $id)->first();
        if (!$campaign) {
            return response()->json(['message' => 'Campagne niet gevonden.'], 404);
        }
        DB::table('gymies_bulk_campaigns')->where('id', $id)->update(['sent_at' => now()]);
        $this->audit((int) $admin->id, 'admin_bulk_campaign_sent', 'bulk_campaign', $id, [
            'target_role' => (string) $campaign->target_role,
        ]);
        return response()->json(['ok' => true]);
    }

    /** Analytics heatmap (demand vs supply). */

    public function heatmap(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_bookings') || !Schema::hasTable('gymies_availability_slots')) {
            return response()->json(['data' => []]);
        }
        $period = trim((string) $request->query('period', 'week'));
        $data = $this->heatmapDemandSupply($period);
        return response()->json(['data' => $data]);
    }

    public function heatmapDemandSupply(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.audit.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $period = trim((string) $request->query('period', 'month'));
        $data = $this->heatmapSupplyOnly($period);
        return response()->json(['data' => $data]);
    }

    /**
     * Heatmap voorbereiding (private).
     */
    private function heatmapSupplyOnly(string $period): array
    {
        if (!Schema::hasTable('gymies_availability_slots')) {
            return [];
        }
        $data = [];
        if ($period === 'week') {
            for ($i = 0; $i < 7; $i++) {
                $data[] = ['day' => now()->addDays($i)->format('Y-m-d'), 'slots' => 0];
            }
        } else {
            $start = now()->startOfMonth();
            for ($i = 0; $i < $start->daysInMonth; $i++) {
                $data[] = ['week' => $start->addDays($i)->format('W'), 'slots' => 0];
            }
        }
        return $data;
    }

    /**
     * Log audit entry in gymies_audit_log.
     */
    private function audit(int $actorId, string $action, string $entityType, int $entityId, array $newValues, ?array $oldValues = null): void
    {
        if (!Schema::hasTable('gymies_audit_log')) {
            return;
        }
        DB::table('gymies_audit_log')->insert([
            'user_id' => $actorId,
            'action' => $action,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'old_values' => $oldValues !== null ? json_encode($oldValues, JSON_UNESCAPED_UNICODE) : null,
            'new_values' => json_encode($newValues, JSON_UNESCAPED_UNICODE),
            'ip_address' => request()->ip(),
            'created_at' => now(),
        ]);
    }

    private function isPositiveId(string $id): bool
    {
        return ctype_digit($id) && (int) $id > 0;
    }

    // ========== SaaS SUBSCRIPTION MANAGEMENT ==========

    /**
     * Admin: overzicht trainer-abonnementen.
     */
    public function subscriptions(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['subscriptions' => []]);
        }

        $subs = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->join('gymies_users as u', 'u.id', '=', 's.trainer_user_id')
            ->select('s.*', 'p.name as plan_name', 'p.slug as plan_slug', 'p.price_cents_per_month',
                'u.display_name as trainer_name', 'u.email as trainer_email')
            ->orderByDesc('s.created_at')
            ->get();

        return response()->json(['subscriptions' => $subs]);
    }

    /**
     * Admin: MRR/ARR dashboard.
     */
    public function subscriptionRevenue(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['mrr_cents' => 0, 'arr_cents' => 0, 'active_count' => 0]);
        }

        $activeSubs = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->whereIn('s.status', ['active', 'trialing'])
            ->select('p.price_cents_per_month', DB::raw('COUNT(*) as cnt'))
            ->groupBy('p.price_cents_per_month')
            ->get();

        $mrrCents = 0;
        $activeCount = 0;
        foreach ($activeSubs as $row) {
            $mrrCents += (int) $row->price_cents_per_month * (int) $row->cnt;
            $activeCount += (int) $row->cnt;
        }

        $pastDueCount = (int) DB::table('gymies_subscriptions')->where('status', 'past_due')->count();
        $cancelledThisMonth = (int) DB::table('gymies_subscriptions')
            ->where('status', 'cancelled')
            ->whereMonth('cancelled_at', now()->month)
            ->whereYear('cancelled_at', now()->year)
            ->count();

        $planBreakdown = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->whereIn('s.status', ['active', 'trialing'])
            ->select('p.slug', 'p.name', 'p.price_cents_per_month', DB::raw('COUNT(*) as active_count'))
            ->groupBy('p.slug', 'p.name', 'p.price_cents_per_month')
            ->get();

        return response()->json([
            'mrr_cents' => $mrrCents,
            'arr_cents' => $mrrCents * 12,
            'active_count' => $activeCount,
            'past_due_count' => $pastDueCount,
            'cancelled_this_month' => $cancelledThisMonth,
            'plan_breakdown' => $planBreakdown,
        ]);
    }

    /**
     * Admin: alle SaaS-plannen (voor prijsbeheer in vault-console).
     * Zorgt dat plannen zonder slug die krijgen (backfill), zodat sync en update werken.
     */
    public function plansIndex(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_plans')) {
            return response()->json(['plans' => []]);
        }

        $this->ensurePlansHaveSlugs();

        // Alleen actieve plannen (zelfde filtering als onboarding/website – dynamische prijzen).
        $plans = DB::table('gymies_plans')
            ->when(
                Schema::hasColumn('gymies_plans', 'is_active'),
                fn ($q) => $q->where('is_active', 1)
            )
            ->orderBy('price_cents_per_month')
            ->orderBy('id')
            ->get();

        // Eén plan per slug (duplicates filteren); plannen zonder slug nu ook tonen (id als fallback).
        $seen = [];
        $plans = $plans->filter(function ($p) use (&$seen) {
            $slug = (string) ($p->slug ?? '');
            $key = $slug !== '' ? $slug : ('id_' . ($p->id ?? ''));
            if (isset($seen[$key])) {
                return false;
            }
            $seen[$key] = true;
            return true;
        })->values();

        return response()->json(['plans' => $plans]);
    }

    /**
     * Zorg dat elk actief plan een slug heeft (starter/pro/studio). Backfill uit name indien leeg.
     */
    private function ensurePlansHaveSlugs(): void
    {
        if (!Schema::hasTable('gymies_plans') || !Schema::hasColumn('gymies_plans', 'slug')) {
            return;
        }
        $nameToSlug = [
            'starter' => 'starter',
            'pro' => 'pro',
            'studio' => 'studio',
            'elite' => 'studio',
        ];
        $rows = DB::table('gymies_plans')
            ->when(Schema::hasColumn('gymies_plans', 'is_active'), fn ($q) => $q->where('is_active', 1))
            ->get(['id', 'slug', 'name']);
        foreach ($rows as $row) {
            $slug = trim((string) ($row->slug ?? ''));
            if ($slug !== '') {
                continue;
            }
            $name = strtolower(trim((string) ($row->name ?? '')));
            $newSlug = null;
            foreach ($nameToSlug as $kw => $s) {
                if (str_contains($name, $kw)) {
                    $newSlug = $s;
                    break;
                }
            }
            if ($newSlug === null) {
                $newSlug = 'starter'; // fallback voor onbekende namen
            }
            $update = ['slug' => $newSlug];
            if (Schema::hasColumn('gymies_plans', 'updated_at')) {
                $update['updated_at'] = now();
            }
            DB::table('gymies_plans')->where('id', (int) $row->id)->update($update);
        }
    }

    /**
     * Admin: plan bijwerken (o.a. prijs per maand in centen).
     * Accepteren id (numeriek) of slug (starter, pro, studio) in de URL.
     * Bestaande abonnementen blijven op oude Mollie-bedragen tot periodewissel;
     * nieuwe select-plan gebruikt direct de nieuwe prijs.
     */
    public function plansUpdate(Request $request, string $planId): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_plans')) {
            return response()->json(['message' => 'Plan niet gevonden.'], 404);
        }

        $request->validate([
            'price_cents_per_month' => 'nullable|integer|min:0|max:10000000',
            'price_euros_per_month' => 'nullable|numeric|min:0|max:100000',
            'name' => 'nullable|string|max:255',
            'description' => 'nullable|string|max:500',
            'is_active' => 'nullable|boolean',
        ]);

        $plan = null;
        if ($this->isPositiveId($planId)) {
            $plan = DB::table('gymies_plans')->where('id', (int) $planId)->first();
        }
        if (!$plan && in_array(strtolower(trim($planId)), ['starter', 'pro', 'studio'], true)) {
            $plan = DB::table('gymies_plans')->where('slug', strtolower(trim($planId)))->first();
        }
        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden.'], 404);
        }

        $actualPlanId = (int) $plan->id;

        $update = [];
        if ($request->has('price_cents_per_month')) {
            $update['price_cents_per_month'] = (int) $request->input('price_cents_per_month');
        } elseif ($request->has('price_euros_per_month')) {
            $update['price_cents_per_month'] = (int) round((float) $request->input('price_euros_per_month') * 100);
        }
        if ($request->has('name')) {
            $name = trim((string) $request->input('name'));
            if ($name !== '') {
                $update['name'] = $name;
            }
        }
        if ($request->has('description')) {
            $update['description'] = $request->input('description') === null
                ? null
                : trim((string) $request->input('description'));
        }
        if ($request->has('is_active')) {
            $update['is_active'] = $request->boolean('is_active') ? 1 : 0;
        }

        if (empty($update)) {
            return response()->json(['message' => 'Geen velden om bij te werken.'], 422);
        }

        if (Schema::hasColumn('gymies_plans', 'updated_at')) {
            $update['updated_at'] = now();
        }

        DB::table('gymies_plans')->where('id', $actualPlanId)->update($update);
        $fresh = DB::table('gymies_plans')->where('id', $actualPlanId)->first();

        return response()->json(['plan' => $fresh, 'message' => 'Plan bijgewerkt.']);
    }

    /**
     * Sync prijzen uit gymies_plans naar site_subscriptions_json (alleen prijsveld, rest blijft).
     */
    public function plansSyncToSite(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $count = $this->syncPlansToSiteSubscriptionsJson();
        if ($count === 0) {
            return response()->json([
                'message' => 'Geen plannen gevonden om te synchroniseren. Controleer dat gymies_plans de slugs starter, pro en studio heeft (draai alter_gymies_fix_plans_and_site_subscriptions.sql indien nodig).',
            ], 422);
        }
        return response()->json(['message' => "Prijzen gesynchroniseerd naar landingspagina ($count plan(nen)).", 'synced_count' => $count]);
    }

    /**
     * Sync gymies_plans → site_subscriptions_json zodat landingspagina actuele prijzen toont.
     * Wijzigt ALLEEN de prijs per plan; rest (title, description, features, layout) blijft intact.
     * Retourneert aantal gesynchroniseerde plannen (0 als niets gedaan).
     */
    private function syncPlansToSiteSubscriptionsJson(): int
    {
        if (!Schema::hasTable('gymies_plans') || !Schema::hasTable('gymies_system_settings')) {
            return 0;
        }

        $this->ensurePlansHaveSlugs();

        // Map slug → prijsstring
        $plans = DB::table('gymies_plans')
            ->when(
                Schema::hasColumn('gymies_plans', 'is_active'),
                fn ($q) => $q->where('is_active', 1)
            )
            ->orderBy('price_cents_per_month')
            ->orderBy('id')
            ->get(['slug', 'price_cents_per_month']);

        $slugToPrice = [];
        $orderedPrices = [];
        $orderedSlugs = [];
        foreach ($plans as $p) {
            $slug = (string) ($p->slug ?? '');
            if ($slug === '') {
                continue;
            }
            $cents = (int) ($p->price_cents_per_month ?? 0);
            $euro = $cents / 100;
            $priceStr = $cents === 0
                ? '€0'
                : ($euro == floor($euro) ? '€' . (int) $euro : '€' . number_format($euro, 2, ',', ''));
            $slugToPrice[$slug] = $priceStr;
            $orderedPrices[] = $priceStr;
            $orderedSlugs[] = $slug;
        }

        if ($slugToPrice === []) {
            return 0;
        }

        // Bestaande site_subscriptions_json laden
        $row = DB::table('gymies_system_settings')->where('setting_key', 'site_subscriptions_json')->first();
        $existing = $row ? trim((string) ($row->setting_value ?? '')) : '';

        if ($existing !== '') {
            $decoded = json_decode($existing, true);
            if (is_array($decoded) && count($decoded) > 0) {
                // Alleen prijzen bijwerken; rest onaangeroerd
                $slugMatch = [
                    'starter' => ['starter'],
                    'pro' => ['pro'],
                    'studio' => ['studio', 'elite'],
                ];
                foreach ($decoded as $i => $item) {
                    if (!is_array($item)) {
                        continue;
                    }
                    $title = strtolower(trim((string) ($item['title'] ?? '')));
                    $slugFromItem = $item['slug'] ?? null;
                    if ($slugFromItem !== null && isset($slugToPrice[$slugFromItem])) {
                        $decoded[$i]['price'] = $slugToPrice[$slugFromItem];
                        $decoded[$i]['slug'] = $slugFromItem;
                        continue;
                    }
                    foreach ($slugMatch as $slug => $keywords) {
                        foreach ($keywords as $kw) {
                            if (str_contains($title, $kw)) {
                                $decoded[$i]['price'] = $slugToPrice[$slug] ?? $item['price'] ?? '€0';
                                $decoded[$i]['slug'] = $slug;
                                break 2;
                            }
                        }
                    }
                    // Position-based fallback: eerste kaart = eerste plan, etc.
                    if (isset($orderedPrices[$i], $orderedSlugs[$i])) {
                        $decoded[$i]['price'] = $orderedPrices[$i];
                        $decoded[$i]['slug'] = $orderedSlugs[$i];
                    }
                }
                $json = json_encode($decoded, JSON_UNESCAPED_UNICODE);
                if ($json !== false) {
                    $updateData = ['setting_value' => $json];
                    if (Schema::hasColumn('gymies_system_settings', 'updated_at')) {
                        $updateData['updated_at'] = now();
                    }
                    DB::table('gymies_system_settings')->updateOrInsert(
                        ['setting_key' => 'site_subscriptions_json'],
                        $updateData
                    );
                }
                return count($slugToPrice);
            }
        }

        // Geen bestaande JSON of ongeldig → opnieuw opbouwen
        $defaults = [
            'starter' => ['description' => 'Voor de beginnende trainer', 'features' => ['1 Actief profiel', 'Directe boekingen', 'Support via community'], 'buttonText' => 'Begin gratis', 'isFeatured' => false],
            'pro' => ['description' => 'Meest gekozen door experts', 'features' => ['Story functionaliteit', '0% Commissie op sessies', 'Priority in zoekresultaten', 'Uitgebreide analytics'], 'buttonText' => 'Start met Pro', 'isFeatured' => true],
            'studio' => ['description' => 'Voor studio\'s en gyms', 'features' => ['Onbeperkt trainers', 'Eigen branding opties', 'API koppelingen', 'Dedicated manager'], 'buttonText' => 'Contact sales', 'isFeatured' => false],
        ];
        $plansFull = DB::table('gymies_plans')
            ->when(Schema::hasColumn('gymies_plans', 'is_active'), fn ($q) => $q->where('is_active', 1))
            ->orderBy('price_cents_per_month')
            ->orderBy('id')
            ->get(['slug', 'name', 'description', 'price_cents_per_month']);

        $arr = [];
        foreach ($plansFull as $p) {
            $slug = (string) ($p->slug ?? '');
            if ($slug === '' || !isset($slugToPrice[$slug])) {
                continue;
            }
            $def = $defaults[$slug] ?? ['description' => (string) ($p->description ?? ''), 'features' => [], 'buttonText' => 'Kies plan', 'isFeatured' => false];
            $arr[] = [
                'slug' => $slug,
                'title' => (string) ($p->name ?? ucfirst($slug)),
                'price' => $slugToPrice[$slug],
                'description' => trim((string) ($p->description ?? '')) !== '' ? (string) $p->description : $def['description'],
                'features' => $def['features'],
                'buttonText' => $def['buttonText'],
                'isFeatured' => $def['isFeatured'],
            ];
        }
        if ($arr !== []) {
            $json = json_encode($arr, JSON_UNESCAPED_UNICODE);
            if ($json !== false) {
                $updateData = ['setting_value' => $json];
                if (Schema::hasColumn('gymies_system_settings', 'updated_at')) {
                    $updateData['updated_at'] = now();
                }
                DB::table('gymies_system_settings')->updateOrInsert(
                    ['setting_key' => 'site_subscriptions_json'],
                    $updateData
                );
            }
        }
        return count($arr);
    }

    /**
     * Admin: abonnement toewijzen aan gebruiker/trainer met 1 klik.
     * Werkt voor trainers en klanten (klant wordt automatisch trainer).
     * Geen Mollie-flow — direct actief in de database.
     */
    public function assignSubscription(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate(['plan_slug' => 'required|string|in:starter,pro,studio']);
        $planSlug = $request->input('plan_slug');

        if (!Schema::hasTable('gymies_plans') || !Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['message' => 'SaaS-tabellen ontbreken. Draai migraties.'], 503);
        }

        $plan = DB::table('gymies_plans')->where('slug', $planSlug)->where('is_active', 1)->first();
        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden of niet actief.'], 404);
        }

        $user = DB::table('gymies_users')->where('id', (int) $userId)->first();
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        $trainerId = (int) $userId;
        $now = now();

        if ((string) $user->role !== 'trainer') {
            DB::table('gymies_users')->where('id', $trainerId)->update([
                'role' => 'trainer',
                'updated_at' => $now,
            ]);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Trainerprofielen-tabel ontbreekt.'], 503);
        }

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->first();
        if (!$profile) {
            DB::table('gymies_trainer_profiles')->insert([
                'user_id' => $trainerId,
                'bio' => null,
                'specialty' => null,
                'hourly_rate_cents' => null,
                'region' => null,
                'is_available' => 0,
                'subscription_plan' => $planSlug,
                'mollie_onboarding_status' => 'not_started',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        } else {
            DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->update([
                'subscription_plan' => $planSlug,
                'updated_at' => $now,
            ]);
        }

        $cancelPayload = [
            'status' => 'cancelled',
            'cancelled_at' => $now,
            'updated_at' => $now,
        ];
        if (Schema::hasColumn('gymies_subscriptions', 'cancel_reason')) {
            $cancelPayload['cancel_reason'] = 'Admin: nieuw plan toegewezen';
        }
        DB::table('gymies_subscriptions')
            ->where('trainer_user_id', $trainerId)
            ->whereIn('status', ['active', 'trialing'])
            ->update($cancelPayload);

        $periodStart = $now->toDateString();
        $periodEnd = $now->copy()->addMonth()->toDateString();

        DB::table('gymies_subscriptions')->insert([
            'trainer_user_id' => $trainerId,
            'plan_id' => (int) $plan->id,
            'status' => 'active',
            'current_period_start' => $periodStart,
            'current_period_end' => $periodEnd,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $this->audit((int) $admin->id, 'admin_assign_subscription', 'user', $trainerId, [
            'plan_slug' => $planSlug,
            'plan_id' => (int) $plan->id,
        ]);

        return response()->json([
            'ok' => true,
            'message' => ucfirst($planSlug) . ' toegewezen aan ' . ($user->display_name ?? $user->email),
            'subscription_plan' => $planSlug,
        ]);
    }

    /**
     * Admin: trainer onboarding pipeline (wie zit waar in het onboarding-proces).
     */
    public function onboardingPipeline(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        $trainers = DB::table('gymies_users as u')
            ->leftJoin('gymies_trainer_profiles as tp', 'tp.user_id', '=', 'u.id')
            ->where('u.role', 'trainer')
            ->select(
                'u.id', 'u.display_name', 'u.email', 'u.created_at',
                'tp.mollie_onboarding_status', 'tp.subscription_plan', 'tp.mollie_profile_id'
            )
            ->orderByDesc('u.created_at')
            ->get();

        $result = [];
        foreach ($trainers as $t) {
            $docs = [];
            if (Schema::hasTable('gymies_document_uploads') && Schema::hasColumn('gymies_document_uploads', 'document_category')) {
                $docs = DB::table('gymies_document_uploads')
                    ->where('user_id', (int) $t->id)
                    ->whereIn('document_category', ['kvk_extract', 'id_document', 'certification', 'vog'])
                    ->get(['document_category', 'verified_at', 'rejected_at'])
                    ->keyBy('document_category')
                    ->toArray();
            }
            $hasSub = Schema::hasTable('gymies_subscriptions')
                ? DB::table('gymies_subscriptions')
                    ->where('trainer_user_id', (int) $t->id)
                    ->whereIn('status', ['active', 'trialing'])
                    ->exists()
                : false;

            $result[] = [
                'trainer_id' => (string) $t->id,
                'name' => $t->display_name,
                'email' => $t->email,
                'registered_at' => $t->created_at,
                'documents' => $docs,
                'mollie_status' => $t->mollie_onboarding_status ?? 'not_started',
                'has_mollie_profile' => $t->mollie_profile_id !== null,
                'subscription_plan' => $t->subscription_plan,
                'has_active_subscription' => $hasSub,
            ];
        }

        return response()->json(['trainers' => $result]);
    }

    /**
     * Admin: ghost-rating dashboard (overzicht per trainer).
     */
    public function ghostRatingDashboard(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_ghost_ratings')) {
            return response()->json(['trainers' => []]);
        }

        $trainers = DB::table('gymies_ghost_ratings as gr')
            ->join('gymies_users as u', 'u.id', '=', 'gr.trainer_user_id')
            ->select(
                'gr.trainer_user_id',
                'u.display_name as trainer_name',
                DB::raw('ROUND(AVG(gr.punctuality), 2) as avg_punctuality'),
                DB::raw('ROUND(AVG(gr.energy), 2) as avg_energy'),
                DB::raw('ROUND(AVG(gr.would_rebook), 2) as avg_would_rebook'),
                DB::raw('COUNT(*) as total_ratings'),
            )
            ->groupBy('gr.trainer_user_id', 'u.display_name')
            ->orderByRaw('AVG(gr.energy) ASC')
            ->get();

        return response()->json(['trainers' => $trainers]);
    }
}
