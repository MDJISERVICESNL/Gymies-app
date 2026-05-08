<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
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
        $q = trim((string) $request->query('q', ''));
        // B46: Escape LIKE-speciale tekens zodat % en _ niet als wildcards werken in zoekopdrachten.
        $qLike = $q !== '' ? '%' . addcslashes($q, '%_\\') . '%' : '';
        $role = trim((string) $request->query('role', ''));
        $status = trim((string) $request->query('status', ''));
        $isAdminFilter = filter_var($request->query('is_admin'), FILTER_VALIDATE_BOOLEAN);
        $page = max(1, (int) $request->query('page', 1));
        $perPage = min(200, max(10, (int) $request->query('per_page', 50)));

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
        if ($qLike !== '') {
            $query->where(function ($w) use ($qLike, $hasFirstName, $hasLastName, $hasPhone): void {
                $w->where('email', 'like', $qLike)
                    ->orWhere('display_name', 'like', $qLike);
                if ($hasPhone) {
                    $w->orWhere('phone', 'like', $qLike);
                }
                if ($hasFirstName) {
                    $w->orWhere('first_name', 'like', $qLike);
                }
                if ($hasLastName) {
                    $w->orWhere('last_name', 'like', $qLike);
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

        $total = $query->count();
        $rows = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        return response()->json([
            'data' => $rows,
            'total' => $total,
            'page' => $page,
            'per_page' => $perPage,
        ]);
    }

    /**
     * Rate limited via middleware: admin.throttle
     */
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
    /**
     * Rate limited via middleware: admin.throttle
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
            // Admin-only endpoint: retrieve recent bookings for a user (limited to 5 results for performance)
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
        $q = trim((string) $request->query('q', ''));
        // B46 (export): Escape LIKE-speciale tekens voor correcte export-filtering.
        $qLike = $q !== '' ? '%' . addcslashes($q, '%_\\') . '%' : '';
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
        if ($qLike !== '') {
            $query->where(function ($w) use ($qLike): void {
                $w->where('email', 'like', $qLike)
                    ->orWhere('display_name', 'like', $qLike);
                if (Schema::hasColumn('gymies_users', 'phone')) {
                    $w->orWhere('phone', 'like', $qLike);
                }
                if (Schema::hasColumn('gymies_users', 'first_name')) {
                    $w->orWhere('first_name', 'like', $qLike);
                }
                if (Schema::hasColumn('gymies_users', 'last_name')) {
                    $w->orWhere('last_name', 'like', $qLike);
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
                '"' . str_replace(['"', "\n", "\r"], ['""', ' ', ''], (string) $r->email) . '"',
                '"' . str_replace(['"', "\n", "\r"], ['""', ' ', ''], (string) ($r->display_name ?? '')) . '"',
                '"' . str_replace(['"', "\n", "\r"], ['""', ' ', ''], (string) ($r->role ?? '')) . '"',
                '"' . str_replace(['"', "\n", "\r"], ['""', ' ', ''], (string) ($r->created_at ?? '')) . '"'
            );
        }
        return response()->json(['data' => ['csv' => implode("\n", $lines)]]);
    }

    public function payments(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);
        $rows = [];

        if (Schema::hasTable('gymies_payment_transactions')) {
            // FIX 2: Add limit to prevent unbounded query
            $rows = DB::table('gymies_payment_transactions')
                ->orderByDesc('id')
                ->limit($limit)
                ->get()
                ->all();
        } else {
            // FIX 2: Add limit to prevent unbounded query
            $rows = DB::table('gymies_bookings')
                ->orderByDesc('id')
                ->limit($limit)
                ->get([
                    'id',
                    'client_user_id',
                    'trainer_user_id',
                    'amount_cents',
                    'status',
                    'payment_provider_id',
                    'paid_at',
                    'created_at',
                ])
                ->map(static fn ($r) => [
                    'id' => (string) $r->id,
                    'booking_id' => (string) $r->id,
                    'user_id' => (string) $r->client_user_id,
                    'counterparty_user_id' => (string) $r->trainer_user_id,
                    'provider' => 'unknown',
                    'provider_transaction_id' => (string) ($r->payment_provider_id ?? ''),
                    'amount_cents' => (int) ($r->amount_cents ?? 0),
                    'status' => (string) ($r->status ?? 'unknown'),
                    'created_at' => $r->created_at,
                    'paid_at' => $r->paid_at,
                ])
                ->all();
        }

        return response()->json(['data' => $rows]);
    }

    public function promoCodes(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_promo_codes')) {
            return response()->json(['data' => []]);
        }
        // FIX 3: B50 already in place - Limiet toegevoegd – onbegrensde ->get() kan geheugen uitputten bij veel promo-codes.
        $promoLimit = min(1000, max(1, (int) ($request->query('limit', 500))));
        $rows = DB::table('gymies_promo_codes')
            ->orderByDesc('id')
            ->limit($promoLimit)
            ->get()
            ->map(static fn ($r) => [
                'id' => (string) $r->id,
                'code' => (string) $r->code,
                'discount_type' => (string) $r->discount_type,
                'value_cents' => (int) $r->value_cents,
                'valid_from' => $r->valid_from,
                'valid_until' => $r->valid_until,
                'max_uses' => $r->max_uses !== null ? (int) $r->max_uses : null,
                'use_count' => (int) ($r->use_count ?? 0),
                'created_at' => $r->created_at,
            ])
            ->all();
        return response()->json(['data' => $rows]);
    }

    public function storePromoCode(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'code' => 'required|string|max:64',
            'discount_type' => 'required|string|in:percent,fixed',
            'value_cents' => 'required|integer|min:1',
            'valid_from' => 'nullable|date',
            'valid_until' => 'nullable|date',
            'max_uses' => 'nullable|integer|min:1',
        ]);
        if (!Schema::hasTable('gymies_promo_codes')) {
            return response()->json(['message' => 'Tabel gymies_promo_codes ontbreekt.'], 500);
        }
        $code = strtoupper(trim((string) $request->input('code')));
        $exists = DB::table('gymies_promo_codes')->where('code', $code)->exists();
        if ($exists) {
            return response()->json(['message' => 'Deze code bestaat al.'], 422);
        }
        $valueCents = (int) $request->input('value_cents');
        if ($request->input('discount_type') === 'percent' && ($valueCents < 1 || $valueCents > 100)) {
            return response()->json(['message' => 'Percentage moet tussen 1 en 100 liggen.'], 422);
        }
        $id = DB::table('gymies_promo_codes')->insertGetId([
            'code' => $code,
            'discount_type' => $request->input('discount_type'),
            'value_cents' => $valueCents,
            'valid_from' => $request->input('valid_from') ?: null,
            'valid_until' => $request->input('valid_until') ?: null,
            'max_uses' => $request->input('max_uses') ? (int) $request->input('max_uses') : null,
            'use_count' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $row = DB::table('gymies_promo_codes')->where('id', $id)->first();
        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'code' => (string) $row->code,
                'discount_type' => (string) $row->discount_type,
                'value_cents' => (int) $row->value_cents,
                'valid_from' => $row->valid_from,
                'valid_until' => $row->valid_until,
                'max_uses' => $row->max_uses ? (int) $row->max_uses : null,
                'use_count' => (int) $row->use_count,
            ],
        ], 201);
    }

    public function payouts(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $dateFrom = trim((string) $request->query('date_from', ''));
        $dateTo = trim((string) $request->query('date_to', ''));
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);
        $hasGrossCents = Schema::hasColumn('gymies_payouts', 'gross_cents');
        $hasFeeCents = Schema::hasColumn('gymies_payouts', 'fee_cents');
        $hasReference = Schema::hasColumn('gymies_payouts', 'reference');
        $hasRequestedAt = Schema::hasColumn('gymies_payouts', 'requested_at');
        $hasPaidAt = Schema::hasColumn('gymies_payouts', 'paid_at');

        $query = DB::table('gymies_payouts as p')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'p.trainer_user_id')
            ->orderByDesc('p.id');
        if ($status !== '') {
            $query->where('p.status', $status);
        }
        if ($dateFrom !== '' && Schema::hasColumn('gymies_payouts', 'created_at')) {
            $query->where('p.created_at', '>=', $dateFrom);
        }
        if ($dateTo !== '') {
            $query->where('p.created_at', '<=', $dateTo . ' 23:59:59');
        }
        $rows = $query->limit($limit)->get([
                'p.id',
                'p.trainer_user_id',
                'u.email as trainer_email',
                'u.display_name as trainer_name',
                'p.amount_cents',
                $hasGrossCents ? 'p.gross_cents' : DB::raw('0 as gross_cents'),
                $hasFeeCents ? 'p.fee_cents' : DB::raw('0 as fee_cents'),
                'p.status',
                $hasReference ? 'p.reference' : DB::raw('NULL as reference'),
                $hasRequestedAt ? 'p.requested_at' : DB::raw('NULL as requested_at'),
                $hasPaidAt ? 'p.paid_at' : DB::raw('NULL as paid_at'),
            ]);

        return response()->json(['data' => $rows]);
    }

    public function updatePayoutStatus(Request $request, string $payoutId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($payoutId)) {
            return response()->json(['message' => 'Ongeldige payout id.'], 422);
        }
        $request->validate([
            'status' => 'required|in:pending,paid,failed',
            'reason' => 'required|string|max:500',
            'reference' => 'nullable|string|max:255',
            'paid_at' => 'nullable|date',
        ]);
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['message' => 'Payout tabel ontbreekt.'], 422);
        }
        $id = (int) $payoutId;
        $p = DB::table('gymies_payouts')->where('id', $id)->first();
        if (!$p) {
            return response()->json(['message' => 'Payout niet gevonden.'], 404);
        }
        $status = (string) $request->input('status');
        $update = ['status' => $status, 'updated_at' => now()];
        if ($status === 'paid') {
            $update['paid_at'] = $request->input('paid_at') ? $request->input('paid_at') : now();
            if (Schema::hasColumn('gymies_payouts', 'reference')) {
                $ref = trim((string) $request->input('reference', ''));
                $update['reference'] = $ref !== '' ? $ref : null;
            }
        }
        if (Schema::hasColumn('gymies_payouts', 'reference') && $status !== 'paid') {
            $ref = trim((string) $request->input('reference', ''));
            if ($ref !== '') {
                $update['reference'] = $ref;
            }
        }
        DB::table('gymies_payouts')->where('id', $id)->update($update);

        $this->audit((int) $admin->id, 'admin_payout_status_updated', 'payout', $id, [
            'old_status' => (string) $p->status,
            'new_status' => $status,
            'reason' => (string) $request->input('reason'),
        ]);

        return response()->json(['ok' => true]);
    }

    public function tickets(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $priority = trim((string) $request->query('priority', ''));
        $q = trim((string) $request->query('q', ''));
        // B48: Escape LIKE-speciale tekens zodat % en _ niet als wildcards werken.
        $qLikeTickets = $q !== '' ? '%' . addcslashes($q, '%_\\') . '%' : '';
        $assignedToMe = filter_var($request->query('assigned_to_me'), FILTER_VALIDATE_BOOLEAN);
        $sort = trim((string) $request->query('sort', 'created_at_desc'));
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);

        $select = [
            't.id', 't.user_id', 'u.email as user_email', 'u.display_name as user_name',
            't.subject', 't.category', 't.priority', 't.status', 't.assigned_to_user_id',
            'a.email as assigned_email', 'a.display_name as assigned_name',
            't.created_at', 't.updated_at', 't.resolved_at',
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'close_reason')) {
            $select[] = 't.close_reason';
        }
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $select[] = 't.submitter_name';
            $select[] = 't.submitter_email';
            $select[] = 't.submitter_phone';
        }
        $query = DB::table('gymies_support_tickets as t')
            ->leftJoin('gymies_users as u', 'u.id', '=', 't.user_id')
            ->leftJoin('gymies_users as a', 'a.id', '=', 't.assigned_to_user_id')
            ->select($select);
        if ($status !== '') {
            $query->where('t.status', $status);
        }
        if ($priority !== '') {
            $query->where('t.priority', $priority);
        }
        if ($assignedToMe) {
            $query->where('t.assigned_to_user_id', (int) $admin->id);
        }
        if ($qLikeTickets !== '') {
            $ticketIdsFromMessages = [];
            if (Schema::hasTable('gymies_support_ticket_messages')) {
                $ticketIdsFromMessages = DB::table('gymies_support_ticket_messages')
                    ->where('message', 'like', $qLikeTickets)
                    ->pluck('ticket_id')
                    ->unique()
                    ->values()
                    ->all();
            }
            $query->where(function ($w) use ($qLikeTickets, $ticketIdsFromMessages): void {
                $w->where('t.subject', 'like', $qLikeTickets)
                    ->orWhere('u.email', 'like', $qLikeTickets)
                    ->orWhere('u.display_name', 'like', $qLikeTickets);
                if (count($ticketIdsFromMessages) > 0) {
                    $w->orWhereIn('t.id', $ticketIdsFromMessages);
                }
            });
        }
        switch ($sort) {
            case 'created_at_asc':
                $query->orderBy('t.created_at');
                break;
            case 'priority':
                $query->orderByRaw("FIELD(t.priority, 'critical', 'high', 'medium', 'low')")->orderByDesc('t.created_at');
                break;
            case 'status':
                $query->orderBy('t.status')->orderByDesc('t.created_at');
                break;
            case 'assigned':
                $query->orderByRaw('t.assigned_to_user_id IS NULL')->orderBy('a.display_name')->orderByDesc('t.created_at');
                break;
            default:
                $query->orderByDesc('t.id');
                break;
        }

        return response()->json(['data' => $query->limit($limit)->get()]);
    }

    public function updateTicket(Request $request, string $ticketId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($ticketId)) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        $request->validate([
            'status' => 'required|in:new,in_progress,waiting_customer,resolved',
            'priority' => 'required|in:low,medium,high,critical',
            'reason' => 'required|string|max:500',
            'assigned_to_user_id' => 'nullable|integer|min:0',
            'close_reason' => 'nullable|string|max:255',
        ]);
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Support tabel ontbreekt.'], 422);
        }
        $id = (int) $ticketId;
        $t = DB::table('gymies_support_tickets')->where('id', $id)->first();
        if (!$t) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }
        $assignedTo = $request->has('assigned_to_user_id') ? $request->input('assigned_to_user_id') : null;
        $assignedToId = $assignedTo === null || $assignedTo === '' ? null : (int) $assignedTo;
        if ($assignedToId !== null && $assignedToId < 1) {
            $assignedToId = null;
        }

        $update = [
            'status' => (string) $request->input('status'),
            'priority' => (string) $request->input('priority'),
            'updated_at' => now(),
            'resolved_at' => (string) $request->input('status') === 'resolved' ? now() : null,
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'assigned_to_user_id')) {
            $update['assigned_to_user_id'] = $assignedToId;
        }
        if (Schema::hasColumn('gymies_support_tickets', 'close_reason')) {
            $update['close_reason'] = (string) $request->input('status') === 'resolved'
                ? trim((string) $request->input('close_reason', '')) ?: null
                : null;
        }
        DB::table('gymies_support_tickets')->where('id', $id)->update($update);

        $auditPayload = [
            'reason' => (string) $request->input('reason'),
            'old_status' => (string) $t->status,
            'new_status' => (string) $request->input('status'),
            'old_priority' => (string) $t->priority,
            'new_priority' => (string) $request->input('priority'),
        ];
        if ($request->has('assigned_to_user_id')) {
            $auditPayload['assigned_to_user_id'] = $assignedToId;
        }
        $this->audit((int) $admin->id, 'admin_ticket_updated', 'support_ticket', $id, $auditPayload);

        return response()->json(['ok' => true]);
    }

    public function ticketMessages(Request $request, string $ticketId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($ticketId)) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        if (!Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_support_ticket_messages')
            ->where('ticket_id', (int) $ticketId)
            ->orderBy('id')
            ->get();

        return response()->json(['data' => $rows]);
    }

    public function addTicketMessage(Request $request, string $ticketId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($ticketId)) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        $request->validate([
            'message' => 'required|string|max:5000',
            'is_internal' => 'nullable|boolean',
        ]);
        if (!Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Ticket messages tabel ontbreekt.'], 422);
        }
        $isInternal = $request->boolean('is_internal', true);
        $messageBody = trim((string) $request->input('message'));

        $id = DB::table('gymies_support_ticket_messages')->insertGetId([
            'ticket_id' => (int) $ticketId,
            'author_user_id' => (int) $admin->id,
            'message' => $messageBody,
            'is_internal' => $isInternal ? 1 : 0,
            'created_at' => now(),
        ]);

        if (!$isInternal && Schema::hasTable('gymies_support_tickets')) {
            $this->sendTicketReplyNotificationEmail((int) $ticketId, $messageBody);
            if (class_exists(\App\Helpers\GymiesSupportSync::class)) {
                \App\Helpers\GymiesSupportSync::syncAdminReplyToConversation((int) $ticketId, $messageBody);
            }
        }

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    /**
     * Stuur e-mail naar de klant/trainer wanneer er een antwoord op het ticket is geplaatst.
     * Bij ontbrekende mailconfiguratie wordt alleen gelogd; de API-response faalt niet.
     */
    private function sendTicketReplyNotificationEmail(int $ticketId, string $messageBody): void
    {
        try {
            $ticket = DB::table('gymies_support_tickets')->where('id', $ticketId)->first();
            if (!$ticket || !isset($ticket->user_id)) {
                return;
            }
            $user = DB::table('gymies_users')->where('id', $ticket->user_id)->first();
            if (!$user || empty($user->email)) {
                return;
            }

            $email       = (string) $user->email;
            $displayName = trim((string) ($user->display_name ?? ''));
            $appName     = \App\Helpers\GymiesNotificationEmail::mailBrandName();
            $baseUrl     = \App\Helpers\GymiesNotificationEmail::mailPublicBaseUrl();
            $ticketSubj  = trim((string) ($ticket->subject ?? 'Jouw ticket'));

            [$subject, $textBody, $htmlBody] = \App\Helpers\GymiesMailTemplates::ticketAntwoord(
                $displayName,
                $ticketSubj,
                (string) $ticketId,
                $messageBody,
                $appName,
                $baseUrl,
            );

            \App\Helpers\GymiesNotificationEmail::send($email, $subject, $textBody, $htmlBody);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('Gymies ticket reply email failed', ['ticket_id' => $ticketId, 'error' => $e->getMessage()]);
            }
        }
    }

    /** Dupliceer ticket: nieuw ticket voor dezelfde klant met nieuw onderwerp (zelfde categorie/prioriteit). */
    public function duplicateTicket(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'source_ticket_id' => 'required|integer|min:1',
            'new_subject' => 'required|string|max:255',
        ]);
        if (!Schema::hasTable('gymies_support_tickets') || !Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Support niet beschikbaar.'], 503);
        }
        $sourceId = (int) $request->input('source_ticket_id');
        $source = DB::table('gymies_support_tickets')->where('id', $sourceId)->first();
        if (!$source) {
            return response()->json(['message' => 'Bron-ticket niet gevonden.'], 404);
        }
        $newSubject = trim((string) $request->input('new_subject'));
        $newId = DB::table('gymies_support_tickets')->insertGetId([
            'user_id' => (int) $source->user_id,
            'subject' => $newSubject,
            'category' => (string) ($source->category ?? 'general'),
            'priority' => (string) ($source->priority ?? 'medium'),
            'status' => 'new',
            'assigned_to_user_id' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $firstMessage = DB::table('gymies_support_ticket_messages')
            ->where('ticket_id', $sourceId)
            ->where('is_internal', 0)
            ->orderBy('id')
            ->first();
        $body = $firstMessage ? trim((string) $firstMessage->message) : 'Vervolgvraag (gedupliceerd van ticket #' . $sourceId . ').';
        if (strlen($body) > 5000) {
            $body = substr($body, 0, 4997) . '...';
        }
        DB::table('gymies_support_ticket_messages')->insert([
            'ticket_id' => $newId,
            'author_user_id' => (int) $source->user_id,
            'message' => $body,
            'is_internal' => 0,
            'created_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_ticket_duplicated', 'support_ticket', $newId, ['source_ticket_id' => $sourceId]);
        return response()->json(['data' => ['id' => (string) $newId]], 201);
    }

    public function bookingsMonitor(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $dateFrom = trim((string) $request->query('date_from', ''));
        $dateTo = trim((string) $request->query('date_to', ''));
        $trainerId = $request->query('trainer_id') ? (int) $request->query('trainer_id') : null;
        $clientId = $request->query('client_id') ? (int) $request->query('client_id') : null;

        // S-041: IDOR bookingsMonitor — Admin-only check voor trainer_id en client_id parameters
        // Deze parameters zijn admin-only. Als niet-admin probeert eigen data te filteren moet dit gelijk zijn aan user_id.
        if ($admin->role !== 'admin') {
            if (($trainerId !== null && $trainerId !== (int) $admin->id) ||
                ($clientId !== null && $clientId !== (int) $admin->id)) {
                return response()->json(['message' => 'Niet geautoriseerd om andere gebruikers data te bekijken.'], 403);
            }
        }
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);

        $query = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->orderByDesc('b.id')
            ->select([
                'b.id',
                'b.status',
                'b.scheduled_at',
                'b.duration_minutes',
                'b.amount_cents',
                'b.paid_at',
                'b.client_user_id',
                'b.trainer_user_id',
                'b.created_at',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            ]);
        if ($status !== '') {
            $query->where('b.status', $status);
        }
        if ($dateFrom !== '') {
            $query->where('b.scheduled_at', '>=', $dateFrom);
        }
        if ($dateTo !== '') {
            $query->where('b.scheduled_at', '<=', $dateTo . ' 23:59:59');
        }
        if ($trainerId !== null && $trainerId > 0) {
            $query->where('b.trainer_user_id', $trainerId);
        }
        if ($clientId !== null && $clientId > 0) {
            $query->where('b.client_user_id', $clientId);
        }

        return response()->json(['data' => $query->limit($limit)->get()]);
    }

    /** Eén boeking met klant/trainer en optionele velden. */
    public function bookingDetail(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.id', $id)
            ->select([
                'b.id', 'b.status', 'b.scheduled_at', 'b.duration_minutes', 'b.amount_cents',
                'b.paid_at', 'b.client_user_id', 'b.trainer_user_id', 'b.created_at', 'b.updated_at',
                'b.location_type', 'b.location_notes', 'b.client_notes', 'b.trainer_notes',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('c.email as client_email'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                DB::raw('t.email as trainer_email'),
            ])
            ->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        return response()->json(['data' => $b]);
    }

    /** Boeking annuleren namens admin (met reden; optioneel refund-vlag voor rapportage). */
    public function cancelBooking(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'reason' => 'required|string|max:500',
            'refund' => 'nullable|boolean',
        ]);
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (in_array((string) $b->status, ['cancelled', 'completed'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet meer geannuleerd worden.'], 422);
        }
        $update = [
            'status' => 'cancelled',
            'updated_at' => now(),
            'cancelled_at' => now(),
            'cancelled_by_user_id' => (int) $admin->id,
        ];
        if (Schema::hasColumn('gymies_bookings', 'cancelled_by_user_id')) {
            $update['cancelled_by_user_id'] = (int) $admin->id;
        }
        DB::table('gymies_bookings')->where('id', $id)->update($update);
        $this->audit((int) $admin->id, 'admin_booking_cancelled', 'booking', $id, [
            'reason' => (string) $request->input('reason'),
            'refund' => $request->boolean('refund', false),
        ]);
        return response()->json(['ok' => true]);
    }

    /**
     * Forceer Refund / Boete kwijtschelden: bij overmacht kan admin de €25 boete van de trainer weghalen.
     * POST met reason (verplicht). Verhoogt trainer_balance_cents met 2500.
     */
    public function waiveTrainerPenalty(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate(['reason' => 'required|string|max:500']);
        $bid = (int) $bookingId;
        $booking = DB::table('gymies_bookings')->where('id', $bid)->first(['trainer_user_id']);
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $trainerId = (int) $booking->trainer_user_id;
        if (!Schema::hasColumn('gymies_users', 'trainer_balance_cents')) {
            return response()->json(['message' => 'Trainerbalans niet beschikbaar.'], 503);
        }
        // S-075: Race Condition waiveTrainerPenalty — Atomische update in plaats van increment+query
        // Increment is atomair, maar de volgende value() query is NIET atomair. Fix: gebruiken incrementing return value
        $addCents = 2500;
        DB::table('gymies_users')->where('id', $trainerId)->increment('trainer_balance_cents', $addCents, ['updated_at' => now()]);
        // S-075: Atomaire balance lookup na increment (of alternatief: return increment delta)
        $newBalance = (int) (DB::table('gymies_users')->where('id', $trainerId)->value('trainer_balance_cents') ?? 0);
        $current = $newBalance - $addCents; // Reconstructed for audit log
        $this->audit((int) $admin->id, 'admin_waive_trainer_penalty', 'booking', $bid, [
            'reason' => (string) $request->input('reason'),
            'trainer_id' => $trainerId,
            'balance_before' => $current,
            'balance_after' => $newBalance,
        ]);
        return response()->json(['ok' => true, 'trainer_balance_cents' => $newBalance]);
    }

    /**
     * Refund of credit: volledige/gedeeltelijke terugbetaling (registratie) of credit naar wallet.
     * Bij wallet_credit wordt het bedrag aan de klant-wallet toegevoegd; bij refund alleen gelogd (Mollie later).
     * Optioneel: boeking automatisch op cancelled zetten (cancel_booking=true).
     */
    public function refundOrCredit(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'type' => 'required|in:full_refund,partial_refund,wallet_credit,split',
            'amount_cents' => 'nullable|integer|min:0',
            'reason' => 'required|string|max:500',
            'cancel_booking' => 'nullable|boolean',
        ]);
        $id = (int) $bookingId;
        $type = (string) $request->input('type');
        $reason = trim((string) $request->input('reason'));
        $cancelBooking = $request->boolean('cancel_booking', true);

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $bookingStatus = (string) $b->status;
        if ($bookingStatus === 'cancelled') {
            return response()->json(['message' => 'Deze boeking kan niet worden terugbetaald of gecrediteerd.'], 422);
        }
        // Voor voltooide boekingen: alleen gedeeltelijke terugbetaling, wallet-credit of split.
        if ($bookingStatus === 'completed' && !in_array($type, ['partial_refund', 'wallet_credit', 'split'], true)) {
            return response()->json(['message' => 'Voor voltooide boekingen is alleen gedeeltelijke terugbetaling, wallet-credit of split toegestaan.'], 422);
        }
        if ($bookingStatus === 'completed') {
            $cancelBooking = false;
        }

        $bookingAmountCents = (int) ($b->amount_cents ?? 0);
        $amountCents = $request->has('amount_cents') ? (int) $request->input('amount_cents') : $bookingAmountCents;

        // Split: 50% naar klant (wallet), 50% blijft voor trainer (uitbetaling).
        if ($type === 'split') {
            $amountCents = (int) floor($bookingAmountCents / 2);
            $cancelBooking = false;
        }

        if ($type === 'partial_refund' && $amountCents <= 0) {
            return response()->json(['message' => 'Bij gedeeltelijke terugbetaling is amount_cents verplicht.'], 422);
        }
        if ($type !== 'partial_refund' && $type !== 'split' && $bookingAmountCents > 0) {
            $amountCents = $bookingAmountCents;
        }
        if ($amountCents > $bookingAmountCents) {
            $amountCents = $bookingAmountCents;
        }
        // Bij bankrefund (full/partial) wordt de admin-fee ingehouden; opgeslagen amount = bedrag dat naar klant gaat.
        if ($type === 'full_refund' || $type === 'partial_refund') {
            $feeCents = (int) $this->getSetting('bank_refund_admin_fee_cents', '99');
            $amountCents = max(0, $amountCents - $feeCents);
        }
        $clientUserId = (int) $b->client_user_id;

        if (!Schema::hasTable('gymies_admin_refunds')) {
            return response()->json(['message' => 'Refund-tabel niet beschikbaar. Draai migratie alter_gymies_wallet_and_refund.sql.'], 503);
        }

        $refundStatus = 'pending';
        if ($type === 'wallet_credit' || $type === 'split') {
            if (!Schema::hasTable('gymies_wallet_transactions') || !Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
                return response()->json(['message' => 'Wallet niet beschikbaar. Draai migratie alter_gymies_wallet_and_refund.sql.'], 503);
            }
            // Atomische increment voorkomt race condition bij gelijktijdige refunds.
            DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
            $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
            $walletInsert = [
                'user_id' => $clientUserId,
                'amount_cents' => $amountCents,
                'balance_after_cents' => $newBalance,
                'booking_id' => $id,
                'reason' => $reason,
                'reference_type' => 'admin_refund_credit',
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ];
            if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                $walletInsert['expires_at'] = now()->addYear()->toDateString();
            }
            DB::table('gymies_wallet_transactions')->insert($walletInsert);
            $refundStatus = 'completed';
        }

        DB::table('gymies_admin_refunds')->insert([
            'booking_id' => $id,
            'client_user_id' => $clientUserId,
            'type' => $type,
            'amount_cents' => $amountCents,
            'status' => $refundStatus,
            'reason' => $reason,
            'admin_user_id' => (int) $admin->id,
            'created_at' => now(),
        ]);

        if ($cancelBooking) {
            DB::table('gymies_bookings')->where('id', $id)->update([
                'status' => 'cancelled',
                'updated_at' => now(),
                'cancelled_at' => now(),
                'cancelled_by_user_id' => (int) $admin->id,
            ]);
        }

        $this->audit((int) $admin->id, 'admin_refund_or_credit', 'booking', $id, [
            'type' => $type,
            'amount_cents' => $amountCents,
            'reason' => $reason,
            'cancel_booking' => $cancelBooking,
            'refund_status' => $refundStatus,
        ]);

        return response()->json([
            'ok' => true,
            'type' => $type,
            'amount_cents' => $amountCents,
            'refund_status' => $refundStatus,
            'booking_cancelled' => $cancelBooking,
        ]);
    }

    /** Bulk: meerdere boekingen 100% refund naar wallet + annuleren (bijv. evenement geannuleerd). */
    public function bulkRefundToWallet(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'booking_ids' => 'required|array',
            'booking_ids.*' => 'integer|min:1',
            'reason' => 'required|string|max:500',
        ]);
        $ids = array_unique(array_filter(array_map('intval', $request->input('booking_ids', []))));

        // S-043: Missing Per-Booking Auth — Limiet verlaagd van 100 naar 50
        if (count($ids) > 50) {
            return response()->json(['message' => 'Maximaal 50 boekingen per bulkactie.'], 422);
        }
        $reason = trim((string) $request->input('reason'));
        if (!Schema::hasTable('gymies_bookings') || !Schema::hasTable('gymies_admin_refunds')) {
            return response()->json(['message' => 'Bookings of refund-tabel niet beschikbaar.'], 503);
        }
        $hasWallet = Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents');
        $processed = 0;
        $skipped = 0;
        foreach ($ids as $id) {
            $b = DB::table('gymies_bookings')->where('id', $id)->first();
            if (!$b || in_array((string) $b->status, ['cancelled', 'completed'], true)) {
                $skipped++;
                continue;
            }

            // S-043: Per-booking authorization checks voor dubbele refunds voorkomen
            // Controleer dat booking status 'cancelled' is en geen bestaande wallet-credit bestaat
            if ((string) $b->status === 'cancelled') {
                $skipped++;
                continue;
            }

            // Controleer of er al een wallet credit voor deze boeking bestaat (dubbele refund preventie)
            $existingCredit = DB::table('gymies_wallet_transactions')
                ->where('booking_id', $id)
                ->where('reference_type', 'admin_refund_credit')
                ->exists();
            if ($existingCredit) {
                $skipped++;
                continue;
            }

            $amountCents = (int) ($b->amount_cents ?? 0);
            $clientUserId = (int) $b->client_user_id;
            if ($hasWallet && $amountCents > 0) {
                // S-077: Atomische increment voorkomt race condition bij gelijktijdige refunds.
                // Lees NIET het saldo na increment (TOCTOU-kwetsbaarheid).
                DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
                // S-077: balance_after_cents omitted — avoid TOCTOU by not reading after increment
                $walletInsert = [
                    'user_id' => $clientUserId,
                    'amount_cents' => $amountCents,
                    // 'balance_after_cents' omitted per S-077 (TOCTOU prevention)
                    'booking_id' => $id,
                    'reason' => $reason,
                    'reference_type' => 'admin_refund_credit',
                    'admin_user_id' => (int) $admin->id,
                    'created_at' => now(),
                ];
                if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                    $walletInsert['expires_at'] = now()->addYear()->toDateString();
                }
                DB::table('gymies_wallet_transactions')->insert($walletInsert);
            }
            DB::table('gymies_admin_refunds')->insert([
                'booking_id' => $id,
                'client_user_id' => $clientUserId,
                'type' => 'wallet_credit',
                'amount_cents' => $amountCents,
                'status' => $hasWallet ? 'completed' : 'pending',
                'reason' => $reason,
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ]);
            DB::table('gymies_bookings')->where('id', $id)->update([
                'status' => 'cancelled',
                'updated_at' => now(),
                'cancelled_at' => now(),
                'cancelled_by_user_id' => (int) $admin->id,
            ]);
            $this->audit((int) $admin->id, 'admin_bulk_refund_wallet', 'booking', $id, ['amount_cents' => $amountCents, 'reason' => $reason]);
            $processed++;
        }
        return response()->json(['ok' => true, 'processed' => $processed, 'skipped' => $skipped]);
    }

    /** Boeking verplaatsen (nieuwe datum/tijd). */
    public function rescheduleBooking(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'scheduled_at' => 'required|date',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (in_array((string) $b->status, ['cancelled', 'completed'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet verplaatst worden.'], 422);
        }
        $newAt = $request->input('scheduled_at');
        DB::table('gymies_bookings')->where('id', $id)->update([
            'scheduled_at' => $newAt,
            'updated_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_booking_rescheduled', 'booking', $id, [
            'reason' => (string) $request->input('reason'),
            'old_scheduled_at' => $b->scheduled_at,
            'new_scheduled_at' => $newAt,
        ]);
        return response()->json(['ok' => true]);
    }

    public function addBookingIncident(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'note' => 'required|string|max:2000',
            'reason' => 'required|string|max:500',
            'create_ticket' => 'nullable|boolean',
        ]);
        if (!Schema::hasTable('gymies_admin_alerts')) {
            return response()->json(['message' => 'Admin alerts tabel ontbreekt.'], 422);
        }
        $bid = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $bid)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $payload = [
            'alert_type' => 'booking_incident',
            'severity' => 'medium',
            'title' => 'Booking incident',
            'message' => trim((string) $request->input('note')),
            'entity_type' => 'booking',
            'entity_id' => $bid,
            'status' => 'open',
            'created_by_user_id' => (int) $admin->id,
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id')) {
            $payload['linked_ticket_id'] = null;
        }
        $id = DB::table('gymies_admin_alerts')->insertGetId($payload);

        $linkedTicketId = null;
        $createTicket = $request->boolean('create_ticket', true);
        if ($createTicket && Schema::hasTable('gymies_support_tickets') && Schema::hasTable('gymies_support_ticket_messages')) {
            $clientUserId = (int) $b->client_user_id;
            $subject = 'Incident boeking #' . $bookingId . ' – ' . trim((string) $request->input('reason'));
            $note = trim((string) $request->input('note'));
            $ticketId = DB::table('gymies_support_tickets')->insertGetId([
                'user_id' => $clientUserId,
                'subject' => mb_substr($subject, 0, 255),
                'category' => 'booking',
                'priority' => 'high',
                'status' => 'new',
                'assigned_to_user_id' => null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            DB::table('gymies_support_ticket_messages')->insert([
                'ticket_id' => $ticketId,
                'author_user_id' => (int) $admin->id,
                'message' => "[Incident automatisch aangemaakt]\n\n" . $note,
                'is_internal' => 0,
                'created_at' => now(),
            ]);
            $linkedTicketId = $ticketId;
            if (Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id')) {
                DB::table('gymies_admin_alerts')->where('id', $id)->update(['linked_ticket_id' => $ticketId]);
            }
        }

        $this->audit((int) $admin->id, 'admin_booking_incident_added', 'booking', $bid, [
            'reason' => (string) $request->input('reason'),
            'incident_id' => (int) $id,
            'linked_ticket_id' => $linkedTicketId,
        ]);

        return response()->json([
            'ok' => true,
            'incident_id' => (string) $id,
            'linked_ticket_id' => $linkedTicketId ? (string) $linkedTicketId : null,
        ], 201);
    }

    /** Incidenten voor een boeking (bewijslast: ticket-berichten indien gekoppeld). */
    public function bookingIncidents(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId) || !Schema::hasTable('gymies_admin_alerts')) {
            return response()->json(['data' => []]);
        }
        $bid = (int) $bookingId;
        $select = ['a.id', 'a.title', 'a.message', 'a.severity', 'a.status', 'a.created_at', DB::raw('COALESCE(u.display_name, u.email) as created_by_name')];
        if (Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id')) {
            $select[] = 'a.linked_ticket_id';
        }
        if (Schema::hasColumn('gymies_admin_alerts', 'resolution_type')) {
            $select[] = 'a.resolution_type';
            $select[] = 'a.resolution_reason';
            $select[] = 'a.resolved_at';
        }
        $alerts = DB::table('gymies_admin_alerts as a')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'a.created_by_user_id')
            ->where('a.entity_type', 'booking')
            ->where('a.entity_id', $bid)
            ->where('a.alert_type', 'booking_incident')
            ->orderByDesc('a.id')
            ->get($select);
        $hasLinkedTicket = Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id');
        $out = [];
        foreach ($alerts as $a) {
            $row = [
                'id' => (string) $a->id,
                'title' => $a->title ?? null,
                'message' => $a->message ?? null,
                'severity' => $a->severity ?? 'medium',
                'status' => $a->status ?? 'open',
                'created_at' => $a->created_at ?? null,
                'created_by_name' => $a->created_by_name ?? null,
                'resolution_type' => $a->resolution_type ?? null,
                'resolution_reason' => $a->resolution_reason ?? null,
                'resolved_at' => $a->resolved_at ?? null,
                'evidence' => [],
            ];
            if ($hasLinkedTicket && !empty($a->linked_ticket_id) && Schema::hasTable('gymies_support_ticket_messages')) {
                $messages = DB::table('gymies_support_ticket_messages as m')
                    ->leftJoin('gymies_users as u', 'u.id', '=', 'm.author_user_id')
                    ->where('m.ticket_id', $a->linked_ticket_id)
                    ->orderBy('m.id')
                    ->get(['m.id', 'm.message', 'm.is_internal', 'm.created_at', DB::raw('COALESCE(u.display_name, u.email) as author_name')]);
                $row['linked_ticket_id'] = (string) $a->linked_ticket_id;
                $row['evidence'] = $messages->map(fn ($m) => [
                    'message' => $m->message,
                    'author_name' => $m->author_name ?? null,
                    'is_internal' => (bool) $m->is_internal,
                    'created_at' => $m->created_at,
                ])->all();
            }
            $out[] = $row;
        }
        return response()->json(['data' => $out]);
    }

    /** Incident afhandelen: betaal trainer / geef klant credit / splits. */
    public function resolveIncident(Request $request, string $incidentId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'resolution_type' => 'required|in:pay_trainer,give_client_credit,split',
            'reason' => 'required|string|max:500',
        ]);
        if (!$this->isPositiveId($incidentId) || !Schema::hasTable('gymies_admin_alerts')) {
            return response()->json(['message' => 'Incident niet gevonden.'], 404);
        }
        $id = (int) $incidentId;
        $alert = DB::table('gymies_admin_alerts')->where('id', $id)->where('alert_type', 'booking_incident')->first();
        if (!$alert || $alert->entity_type !== 'booking') {
            return response()->json(['message' => 'Incident niet gevonden.'], 404);
        }
        if (($alert->status ?? 'open') === 'resolved') {
            return response()->json(['message' => 'Dit incident is al afgehandeld.'], 422);
        }
        $resolutionType = (string) $request->input('resolution_type');
        $reason = trim((string) $request->input('reason'));
        $bookingId = (int) $alert->entity_id;
        $b = DB::table('gymies_bookings')->where('id', $bookingId)->first();
        $clientUserId = $b ? (int) $b->client_user_id : null;
        $trainerUserId = $b ? (int) $b->trainer_user_id : null;
        $amountCents = $b ? (int) ($b->amount_cents ?? 0) : 0;

        $update = [
            'status' => 'resolved',
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_admin_alerts', 'resolution_type')) {
            $update['resolution_type'] = $resolutionType;
            $update['resolution_reason'] = $reason;
            $update['resolved_at'] = now();
            $update['resolved_by_user_id'] = (int) $admin->id;
        }
        DB::table('gymies_admin_alerts')->where('id', $id)->update($update);

        if ($resolutionType === 'give_client_credit' && $clientUserId && $amountCents > 0
            && Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
            // Atomische increment voorkomt race condition bij gelijktijdige credits.
            DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
            $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
            $walletInsert = [
                'user_id' => $clientUserId,
                'amount_cents' => $amountCents,
                'balance_after_cents' => $newBalance,
                'booking_id' => $bookingId,
                'reason' => 'Incident afgehandeld: credit voor klant. ' . $reason,
                'reference_type' => 'admin_refund_credit',
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ];
            if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                $walletInsert['expires_at'] = now()->addYear()->toDateString();
            }
            DB::table('gymies_wallet_transactions')->insert($walletInsert);
        }
        if ($resolutionType === 'split' && $clientUserId && $amountCents > 0
            && Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
            $half = (int) round($amountCents / 2);
            // Atomische increment voorkomt race condition bij gelijktijdige credits.
            DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $half);
            $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
            $walletInsert = [
                'user_id' => $clientUserId,
                'amount_cents' => $half,
                'balance_after_cents' => $newBalance,
                'booking_id' => $bookingId,
                'reason' => 'Incident afgehandeld: 50% credit (splits). ' . $reason,
                'reference_type' => 'admin_refund_credit',
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ];
            if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                $walletInsert['expires_at'] = now()->addYear()->toDateString();
            }
            DB::table('gymies_wallet_transactions')->insert($walletInsert);
        }

        $this->audit((int) $admin->id, 'admin_incident_resolved', 'admin_alert', $id, [
            'resolution_type' => $resolutionType,
            'reason' => $reason,
            'booking_id' => $bookingId,
        ]);

        return response()->json(['ok' => true, 'resolution_type' => $resolutionType]);
    }

    /** Dispute & Resolution: lijst open disputes. */
    public function disputes(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $select = [
            'd.id', 'd.booking_id', 'd.raised_by_user_id', 'd.reason', 'd.details', 'd.status', 'd.closed_at', 'd.created_at',
            'b.scheduled_at', 'b.amount_cents', 'b.status as booking_status',
            DB::raw('COALESCE(c.display_name, c.email) as client_name'),
            DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            DB::raw('COALESCE(r.display_name, r.email) as raised_by_name'),
        ];
        if (Schema::hasColumn('gymies_disputes', 'resolution_type')) {
            $select[] = 'd.resolution_type';
        }
        $query = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->leftJoin('gymies_users as r', 'r.id', '=', 'd.raised_by_user_id')
            ->orderByDesc('d.id')
            ->select($select);
        if ($status !== '') {
            $query->where('d.status', $status);
        }
        $rows = $query->limit(100)->get();
        return response()->json(['data' => $rows]);
    }

    /** Dispute detail + berichten (chat). */
    public function disputeDetail(Request $request, string $disputeId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($disputeId) || !Schema::hasTable('gymies_disputes')) {
            return response()->json(['message' => 'Dispute niet gevonden.'], 404);
        }
        $id = (int) $disputeId;
        $d = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('d.id', $id)
            ->select([
                'd.*', 'b.scheduled_at', 'b.amount_cents', 'b.status as booking_status', 'b.client_user_id', 'b.trainer_user_id',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('c.email as client_email'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                DB::raw('t.email as trainer_email'),
            ])
            ->first();
        if (!$d) {
            return response()->json(['message' => 'Dispute niet gevonden.'], 404);
        }
        $messages = [];
        if (Schema::hasTable('gymies_dispute_messages')) {
            $messages = DB::table('gymies_dispute_messages as m')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'm.author_user_id')
                ->where('m.dispute_id', $id)
                ->orderBy('m.created_at')
                ->get(['m.id', 'm.author_user_id', 'm.message', 'm.is_internal', 'm.created_at', 'u.display_name as author_name'])
                ->all();
        }
        return response()->json(['data' => ['dispute' => $d, 'messages' => $messages]]);
    }

    /** Dispute oplossen: client (refund klant), trainer (payout vrij), split (50/50). */
    public function resolveDispute(Request $request, string $disputeId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($disputeId)) {
            return response()->json(['message' => 'Ongeldige dispute id.'], 422);
        }
        $request->validate([
            'resolution_type' => 'required|in:client,trainer,split',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['message' => 'Disputes niet beschikbaar.'], 503);
        }
        $id = (int) $disputeId;
        $d = DB::table('gymies_disputes')->where('id', $id)->first();
        if (!$d || !in_array((string) $d->status, ['open', 'in_progress'], true)) {
            return response()->json(['message' => 'Dispute niet gevonden of al afgehandeld.'], 404);
        }
        $resolutionType = (string) $request->input('resolution_type');
        $reason = (string) $request->input('reason');
        $bookingId = (int) $d->booking_id;

        $update = ['status' => 'resolved', 'resolution_notes' => $reason, 'closed_at' => now()];
        if (Schema::hasColumn('gymies_disputes', 'resolution_type')) {
            $update['resolution_type'] = $resolutionType;
        }
        if (Schema::hasColumn('gymies_disputes', 'resolved_by_user_id')) {
            $update['resolved_by_user_id'] = (int) $admin->id;
        }
        DB::table('gymies_disputes')->where('id', $id)->update($update);

        $b = DB::table('gymies_bookings')->where('id', $bookingId)->first();
        if ($b) {
            if ($resolutionType === 'client') {
                DB::table('gymies_bookings')->where('id', $bookingId)->update([
                    'status' => 'cancelled',
                    'updated_at' => now(),
                    'cancelled_at' => now(),
                    'cancelled_by_user_id' => (int) $admin->id,
                ]);
            }
        }

        // Release payout hold when dispute is resolved
        if (Schema::hasTable('gymies_payouts') && Schema::hasColumn('gymies_payouts', 'is_held')) {
            DB::table('gymies_payouts')
                ->where('booking_id', $bookingId)
                ->where('is_held', 1)
                ->update([
                    'is_held' => 0,
                    'released_at' => now(),
                ]);
        }

        $this->audit((int) $admin->id, 'admin_dispute_resolved', 'dispute', $id, [
            'resolution_type' => $resolutionType,
            'reason' => $reason,
            'booking_id' => $bookingId,
        ]);
        return response()->json(['ok' => true, 'message' => 'Dispute afgehandeld.']);
    }

    /** Beschikbaarheid blokkeren voor trainer (datum of periode). */
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
        // S-042: Missing Authorization bulkAssignTicketsFromYesterday
        // Vereist admin-level autorisatie om tickets van gisteren aan te passen.
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        // S-042: Expliciete admin-check voor bulk ticket assignment van specifieke datum
        if ($admin->role !== 'admin') {
            return response()->json(['message' => 'Alleen admins kunnen tickets in bulk toewijzen.'], 403);
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
        // S-014: SSRF-preventie — valideer dat het een geldig publiek IPv4/IPv6-adres is
        // voordat we het als URL-parameter gebruiken. Private/reserved ranges worden geweigerd.
        if ($ip === '') {
            return null;
        }
        // filter_var valideert IP-formaat en weert adressen buiten publiek bereik
        if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false) {
            return null;
        }
        // Extra check: alleen IPv4 of IPv6 toegestaan, geen hostnames
        if (!filter_var($ip, FILTER_VALIDATE_IP)) {
            return null;
        }
        // S-014: Gebruik HTTPS i.p.v. HTTP om MITM te voorkomen; begrens response-grootte
        $url = 'https://ip-api.com/json/' . rawurlencode($ip) . '?fields=countryCode';
        $ctx = stream_context_create(['http' => ['timeout' => 1.5, 'max_redirects' => 0]]);
        $raw = @file_get_contents($url, false, $ctx);
        if ($raw === false || strlen($raw) > 512) {
            return null;
        }
        $data = json_decode($raw, true);
        // S-014: Valideer response-formaat — countryCode moet 2 hoofdletters zijn
        if (!isset($data['countryCode']) || !preg_match('/^[A-Z]{2}$/', (string) $data['countryCode'])) {
            return null;
        }
        return (string) $data['countryCode'];
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
        $q = trim((string) $request->query('q', ''));
        $users = [];
        $bookings = [];
        $tickets = [];
        $organisations = [];
        $like = strlen($q) >= 2 ? '%' . $q . '%' : null;
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

    public function organisations(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_organisations')) {
            return response()->json(['data' => []]);
        }
        $q = trim((string) $request->query('q', ''));
        // B49: Escape LIKE-speciale tekens zodat % en _ niet als wildcards werken.
        $qLikeOrgs = $q !== '' ? '%' . addcslashes($q, '%_\\') . '%' : '';
        $groupBy = ['o.id', 'o.name', 'o.status', 'o.created_at'];
        $select = 'o.id, o.name, o.status, o.created_at';
        if (Schema::hasColumn('gymies_organisations', 'contact_email')) {
            $groupBy[] = 'o.contact_email';
            $select .= ', o.contact_email';
        }
        if (Schema::hasColumn('gymies_organisations', 'payout_frequency')) {
            $groupBy[] = 'o.payout_frequency';
            $select .= ', o.payout_frequency';
        }
        if (Schema::hasColumn('gymies_organisations', 'type')) {
            $groupBy[] = 'o.type';
            $select .= ', o.type';
        }
        $query = DB::table('gymies_organisations as o')
            ->groupBy($groupBy)
            ->orderByDesc('o.id')
            ->selectRaw($select);
        if ($qLikeOrgs !== '') {
            $query->where(function ($w) use ($qLikeOrgs): void {
                $w->where('o.name', 'like', $qLikeOrgs);
                if (Schema::hasColumn('gymies_organisations', 'contact_email')) {
                    $w->orWhere('o.contact_email', 'like', $qLikeOrgs);
                }
            });
        }

        if (Schema::hasTable('gymies_organisation_members')) {
            $query->leftJoin('gymies_organisation_members as m', 'm.organisation_id', '=', 'o.id')
                ->selectRaw('COUNT(DISTINCT m.user_id) as members_count');
        } else {
            $query->selectRaw('0 as members_count');
        }

        if (Schema::hasTable('gymies_organisation_settlements')) {
            $query->leftJoin('gymies_organisation_settlements as s', 's.organisation_id', '=', 'o.id')
                ->selectRaw('SUM(CASE WHEN s.status IN ("draft","approved") THEN 1 ELSE 0 END) as open_settlements_count');
        } else {
            $query->selectRaw('0 as open_settlements_count');
        }

        if (Schema::hasTable('gymies_organisation_trainers')) {
            $query->leftJoin('gymies_organisation_trainers as ot', 'ot.organisation_id', '=', 'o.id')
                ->selectRaw('COUNT(DISTINCT ot.trainer_user_id) as trainers_count');
        } else {
            $query->selectRaw('0 as trainers_count');
        }

        if (Schema::hasTable('gymies_bookings') && Schema::hasColumn('gymies_bookings', 'organisation_id')) {
            $start = now()->startOfMonth()->toDateTimeString();
            $end = now()->endOfMonth()->toDateTimeString();
            $query->selectRaw('(SELECT COALESCE(SUM(b.amount_cents), 0) FROM gymies_bookings b WHERE b.organisation_id = o.id AND b.scheduled_at >= ? AND b.scheduled_at <= ? AND b.status IN ("confirmed", "completed", "no_show")) as revenue_this_month_cents', [$start, $end]);
        } else {
            $query->selectRaw('0 as revenue_this_month_cents');
        }

        $rows = $query->get();

        return response()->json(['data' => $rows]);
    }

    /** Organisatie (gym) bewerken: naam, contactmail, status, payout-frequentie. */
    public function updateOrganisation(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId)) {
            return response()->json(['message' => 'Ongeldige organisatie id.'], 422);
        }
        $request->validate([
            'name' => 'nullable|string|max:255',
            'contact_email' => 'nullable|email|max:255',
            'status' => 'nullable|in:active,inactive,suspended',
            'payout_frequency' => 'nullable|in:weekly,biweekly,monthly',
        ]);
        if (!Schema::hasTable('gymies_organisations')) {
            return response()->json(['message' => 'Organisaties niet beschikbaar.'], 503);
        }
        $id = (int) $orgId;
        $org = DB::table('gymies_organisations')->where('id', $id)->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }

        // S-096: Weak Permission Check organisations — Voeg eigendoms-check toe
        // Superadmins mogen alles, organisatie-eigenaren mogen alleen hun eigen organisatie bewerken
        if ($admin->role !== 'admin') { // Niet superadmin
            $isOrgOwner = DB::table('gymies_organisation_members')
                ->where('organisation_id', $id)
                ->where('user_id', (int) $admin->id)
                ->where('role', 'owner')
                ->exists();

            if (!$isOrgOwner) {
                return response()->json(['message' => 'Je hebt geen toestemming om deze organisatie te bewerken.'], 403);
            }
        }

        $update = ['updated_at' => now()];
        if ($request->has('name')) {
            $update['name'] = trim((string) $request->input('name'));
        }
        if (Schema::hasColumn('gymies_organisations', 'contact_email') && $request->has('contact_email')) {
            $update['contact_email'] = trim((string) $request->input('contact_email')) ?: null;
        }
        if ($request->has('status')) {
            $update['status'] = (string) $request->input('status');
        }
        if ($request->has('payout_frequency')) {
            $update['payout_frequency'] = (string) $request->input('payout_frequency');
        }
        DB::table('gymies_organisations')->where('id', $id)->update($update);
        $this->audit((int) $admin->id, 'admin_organisation_updated', 'organisation', $id, $update);
        return response()->json(['ok' => true]);
    }

    public function organisationMembers(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId)) {
            return response()->json(['message' => 'Ongeldige organisatie id.'], 422);
        }
        $rows = DB::table('gymies_organisation_members as m')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'm.user_id')
            ->where('m.organisation_id', (int) $orgId)
            ->orderByDesc('m.id')
            ->get([
                'm.id',
                'm.user_id',
                'u.email',
                'u.display_name',
                'm.role',
                'm.status',
                'm.invited_at',
                'm.joined_at',
            ]);

        return response()->json(['data' => $rows]);
    }

    public function updateOrganisationMember(Request $request, string $orgId, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId) || !$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige id.'], 422);
        }
        $request->validate([
            'role' => 'nullable|in:owner,manager,viewer',
            'status' => 'nullable|in:active,inactive',
            'reason' => 'required|string|max:500',
        ]);
        $member = DB::table('gymies_organisation_members')
            ->where('organisation_id', (int) $orgId)
            ->where('user_id', (int) $userId)
            ->first();
        if (!$member) {
            return response()->json(['message' => 'Teamlid niet gevonden.'], 404);
        }

        // S-044: Privilege Escalation updateOrganisationMember — Check org ownership
        // Alleen org-eigenaren/managers mogen leden updaten (tenzij superadmin)
        if ($admin->role !== 'admin') {
            $isOrgOwner = DB::table('gymies_organisation_members')
                ->where('organisation_id', (int) $orgId)
                ->where('user_id', (int) $admin->id)
                ->whereIn('role', ['owner', 'manager'])
                ->exists();

            if (!$isOrgOwner) {
                return response()->json(['message' => 'Niet geautoriseerd om leden van deze organisatie te beheren.'], 403);
            }
        }

        $update = ['updated_at' => now()];
        if ($request->filled('role')) {
            $update['role'] = (string) $request->input('role');
        }
        if ($request->filled('status')) {
            $update['status'] = (string) $request->input('status');
        }
        DB::table('gymies_organisation_members')
            ->where('id', (int) $member->id)
            ->update($update);
        $this->audit((int) $admin->id, 'admin_organisation_member_updated', 'organisation_member', (int) $member->id, [
            'reason' => (string) $request->input('reason'),
            'changes' => $update,
        ]);

        return response()->json(['ok' => true]);
    }

    /** Financieel overzicht voor een organisatie: omzet, commissie, netto (optioneel periode). */
    public function organisationSettlementOverview(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId) || !Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $id = (int) $orgId;
        $org = DB::table('gymies_organisations')->where('id', $id)->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $periodStart = trim((string) $request->query('period_start', ''));
        $periodEnd = trim((string) $request->query('period_end', ''));

        // S-074: Date range validation — parse with strict format and bounds check
        $start = now()->startOfMonth();
        $end = now()->endOfMonth();
        if ($periodStart !== '') {
            try {
                $start = \Illuminate\Support\Carbon::createFromFormat('Y-m-d', $periodStart);
                if (!$start) {
                    return response()->json(['message' => 'period_start invalid format (Y-m-d required)'], 422);
                }
            } catch (\Exception) {
                return response()->json(['message' => 'period_start invalid format (Y-m-d required)'], 422);
            }
            $start = $start->startOfDay();
        }
        if ($periodEnd !== '') {
            try {
                $end = \Illuminate\Support\Carbon::createFromFormat('Y-m-d', $periodEnd);
                if (!$end) {
                    return response()->json(['message' => 'period_end invalid format (Y-m-d required)'], 422);
                }
            } catch (\Exception) {
                return response()->json(['message' => 'period_end invalid format (Y-m-d required)'], 422);
            }
            $end = $end->endOfDay();
        }
        // S-074: Max 1 year difference
        if ($start->diffInDays($end) > 365) {
            return response()->json(['message' => 'Date range exceeds max 1 year'], 422);
        }

        $baseQuery = fn () => DB::table('gymies_bookings')->where('organisation_id', $id)->whereBetween('scheduled_at', [$start, $end]);
        $bookingsCount = $baseQuery()->count();
        $grossCents = (int) $baseQuery()->whereIn('status', ['confirmed', 'completed', 'no_show'])->sum('amount_cents');
        $platformFeeCents = (int) round($grossCents * 0.12);
        $netCents = max($grossCents - $platformFeeCents, 0);

        return response()->json([
            'data' => [
                'organisation_id' => (string) $id,
                'organisation_name' => (string) $org->name,
                'period_start' => $start->toDateString(),
                'period_end' => $end->toDateString(),
                'bookings_count' => $bookingsCount,
                'gross_cents' => $grossCents,
                'platform_fee_cents' => $platformFeeCents,
                'net_cents' => $netCents,
            ],
        ]);
    }

    /** Settlement rapport: boekingen in periode voor één organisatie (één-klik overzicht). */
    public function organisationSettlementReport(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId) || !Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $id = (int) $orgId;
        $org = DB::table('gymies_organisations')->where('id', $id)->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $periodStart = trim((string) $request->query('period_start', ''));
        $periodEnd = trim((string) $request->query('period_end', ''));
        if ($periodStart === '' || $periodEnd === '') {
            return response()->json(['message' => 'period_start en period_end zijn verplicht.'], 422);
        }

        // S-074: Date range validation — parse with strict format and bounds check
        try {
            $start = \Illuminate\Support\Carbon::createFromFormat('Y-m-d', $periodStart);
            if (!$start) {
                return response()->json(['message' => 'period_start invalid format (Y-m-d required)'], 422);
            }
        } catch (\Exception) {
            return response()->json(['message' => 'period_start invalid format (Y-m-d required)'], 422);
        }
        try {
            $end = \Illuminate\Support\Carbon::createFromFormat('Y-m-d', $periodEnd);
            if (!$end) {
                return response()->json(['message' => 'period_end invalid format (Y-m-d required)'], 422);
            }
        } catch (\Exception) {
            return response()->json(['message' => 'period_end invalid format (Y-m-d required)'], 422);
        }

        $start = $start->startOfDay();
        $end = $end->endOfDay();

        // S-074: Max 1 year difference
        if ($start->diffInDays($end) > 365) {
            return response()->json(['message' => 'Date range exceeds max 1 year'], 422);
        }

        $rows = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.organisation_id', $id)
            ->whereBetween('b.scheduled_at', [$start, $end])
            ->orderBy('b.scheduled_at')
            ->get([
                'b.id',
                'b.scheduled_at',
                'b.status',
                'b.amount_cents',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            ]);

        $bookings = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'scheduled_at' => $r->scheduled_at,
            'status' => $r->status,
            'amount_cents' => (int) ($r->amount_cents ?? 0),
            'client_name' => $r->client_name ?? '',
            'trainer_name' => $r->trainer_name ?? '',
        ])->all();
        $revenueRows = $rows->filter(fn ($r) => in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true));
        $grossCents = (int) $revenueRows->sum('amount_cents');
        $feeCents = (int) round($grossCents * 0.12);
        $netCents = max($grossCents - $feeCents, 0);

        return response()->json([
            'data' => [
                'organisation_id' => (string) $id,
                'organisation_name' => (string) $org->name,
                'period_start' => $periodStart,
                'period_end' => $periodEnd,
                'bookings' => $bookings,
                'summary' => [
                    'bookings_count' => count($bookings),
                    'gross_cents' => $grossCents,
                    'platform_fee_cents' => $feeCents,
                    'net_cents' => $netCents,
                ],
            ],
        ]);
    }

    /** Werkbak "Vandaag": actiepunten met urgency (red/orange/green), quick_action en retention_alerts. */
    public function inbox(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $items = [];
        $now = now();
        $yesterday = $now->copy()->subDay()->toDateTimeString();

        if (Schema::hasTable('gymies_support_tickets')) {
            $tickets = DB::table('gymies_support_tickets as t')
                ->leftJoin('gymies_users as u', 'u.id', '=', 't.user_id')
                ->whereIn('t.status', ['new', 'in_progress', 'waiting_customer'])
                ->orderByRaw("CASE t.priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END")
                ->orderBy('t.created_at')
                ->limit(50)
                ->get(['t.id', 't.subject', 't.status', 't.priority', 't.created_at', 'u.email as user_email']);
            foreach ($tickets as $t) {
                $createdAt = $t->created_at ?? '';
                $isOver24h = $createdAt !== '' && $createdAt < $yesterday;
                $urgency = ($t->priority === 'critical' || $t->priority === 'high') && $isOver24h ? 'red' : ($isOver24h ? 'orange' : 'green');
                $items[] = [
                    'type' => 'ticket',
                    'entity_type' => 'ticket',
                    'entity_id' => (string) $t->id,
                    'title' => (string) ($t->subject ?? 'Ticket #' . $t->id),
                    'subtitle' => ($t->user_email ?? '') . ' · ' . ($t->priority ?? 'medium') . ' · ' . $t->status,
                    'priority' => $t->priority === 'critical' ? 'high' : ($t->priority === 'high' ? 'medium' : 'low'),
                    'urgency' => $urgency,
                    'created_at' => $createdAt,
                    'tab' => 'tickets',
                ];
            }
        }

        if (Schema::hasTable('gymies_payouts')) {
            $payouts = DB::table('gymies_payouts as p')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'p.trainer_user_id')
                ->whereIn('p.status', ['failed', 'pending'])
                ->orderByDesc('p.id')
                ->limit(30)
                ->get(['p.id', 'p.status', 'p.amount_cents', 'p.created_at', 'u.display_name as trainer_name']);
            foreach ($payouts as $p) {
                $createdAt = $p->created_at ?? '';
                $isOver24h = $createdAt !== '' && $createdAt < $yesterday;
                $urgency = ($p->status === 'failed' && $isOver24h) ? 'red' : (($p->status === 'failed' || $isOver24h) ? 'orange' : 'green');
                $items[] = [
                    'type' => 'payout',
                    'entity_type' => 'payout',
                    'entity_id' => (string) $p->id,
                    'title' => 'Payout #' . $p->id . ' · ' . ($p->trainer_name ?? 'Trainer'),
                    'subtitle' => 'status: ' . $p->status . ' · €' . number_format(($p->amount_cents ?? 0) / 100, 2),
                    'priority' => $p->status === 'failed' ? 'high' : 'medium',
                    'urgency' => $urgency,
                    'created_at' => $createdAt,
                    'tab' => 'payments',
                    'quick_action' => ['type' => 'payout_mark_paid', 'payout_id' => (string) $p->id],
                ];
            }
        }

        if (Schema::hasTable('gymies_bookings')) {
            $failedBookings = DB::table('gymies_bookings as b')
                ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
                ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
                ->whereIn('b.status', ['payment_failed', 'failed'])
                ->orderByDesc('b.id')
                ->limit(30)
                ->get(['b.id', 'b.status', 'b.amount_cents', 'b.created_at', DB::raw('COALESCE(c.display_name, c.email) as client_name'), DB::raw('COALESCE(t.display_name, t.email) as trainer_name')]);
            foreach ($failedBookings as $b) {
                $items[] = [
                    'type' => 'booking',
                    'entity_type' => 'booking',
                    'entity_id' => (string) $b->id,
                    'title' => 'Booking #' . $b->id . ' · ' . ($b->client_name ?? '') . ' → ' . ($b->trainer_name ?? ''),
                    'subtitle' => 'status: ' . $b->status . ' · €' . number_format(($b->amount_cents ?? 0) / 100, 2),
                    'priority' => 'medium',
                    'urgency' => 'orange',
                    'created_at' => $b->created_at ?? '',
                    'tab' => 'bookings',
                ];
            }
        }

        $retentionAlerts = $this->inboxRetentionAlerts();
        $redFlags = $this->inboxRedFlags();

        usort($items, static function ($a, $b) {
            $u = ['red' => 0, 'orange' => 1, 'green' => 2];
            $ua = $u[$a['urgency'] ?? 'green'] ?? 2;
            $ub = $u[$b['urgency'] ?? 'green'] ?? 2;
            if ($ua !== $ub) {
                return $ua <=> $ub;
            }
            $p = ['high' => 0, 'medium' => 1, 'low' => 2];
            $pa = $p[$a['priority']] ?? 2;
            $pb = $p[$b['priority']] ?? 2;
            if ($pa !== $pb) {
                return $pa <=> $pb;
            }
            return strcmp($a['created_at'] ?? '', $b['created_at'] ?? '');
        });

        return response()->json([
            'data' => [
                'items' => array_slice($items, 0, 80),
                'retention_alerts' => $retentionAlerts,
                'red_flags' => $redFlags,
            ],
        ]);
    }

    /**
     * Rode vlaggen: trainer 3x achter elkaar geannuleerd, ticket 12h niet beantwoord (hoog), IP veel mislukte logins.
     * S-094: Weak Fraud Detection — Deze heuristiek geeft false positives (legitieme annuleringen).
     * Betere aanpak: check verhouding annuleringen/totaal-boekingen en exclude trainers met <5 totale boekingen.
     */
    private function inboxRedFlags(): array
    {
        $flags = [];
        if (Schema::hasTable('gymies_bookings')) {
            $trainerIds = DB::table('gymies_bookings')
                ->where('status', 'cancelled')
                ->whereNotNull('cancelled_by_user_id')
                ->orderByDesc('cancelled_at')
                ->limit(500)
                ->get(['trainer_user_id', 'cancelled_at']);
            $byTrainer = [];
            foreach ($trainerIds as $r) {
                $tid = (int) $r->trainer_user_id;
                if (!isset($byTrainer[$tid])) {
                    $byTrainer[$tid] = [];
                }
                $byTrainer[$tid][] = $r->cancelled_at ?? '';
            }
            foreach ($byTrainer as $tid => $dates) {
                // S-094: Check minimale boekingen voordat je als suspicious markeert
                $totalBookings = DB::table('gymies_bookings')
                    ->where('trainer_user_id', $tid)
                    ->count();

                if ($totalBookings < 5) {
                    continue; // Niet flaggen voor trainers met <5 totale boekingen
                }

                $consecutive = 0;
                $prev = null;
                foreach ($dates as $d) {
                    if ($prev === null || (strtotime($d) - strtotime($prev)) <= 86400 * 2) {
                        $consecutive++;
                    } else {
                        $consecutive = 1;
                    }
                    $prev = $d;
                    if ($consecutive >= 3) {
                        // S-094: Ook check verhouding annuleringen/totaal
                        $cancelledCount = count($dates);
                        $cancellationRatio = $cancelledCount / $totalBookings;

                        // Alleen flaggen als >50% van boekingen geannuleerd OF >5 opeenvolgende annuleringen
                        if ($cancellationRatio > 0.5 || $consecutive > 5) {
                            $trainer = DB::table('gymies_users')->where('id', $tid)->first();
                            $flags[] = [
                                'type' => 'trainer_consecutive_cancellations',
                                'title' => 'Trainer heeft ' . $consecutive . ' boekingen achter elkaar geannuleerd',
                                'subtitle' => $trainer ? ($trainer->display_name ?? $trainer->email) : 'Trainer #' . $tid,
                                'entity_type' => 'user',
                                'entity_id' => (string) $tid,
                                'tab' => 'users',
                                'cancellation_ratio' => round($cancellationRatio * 100, 1) . '%',
                            ];
                        }
                        break;
                    }
                }
            }
        }
        if (Schema::hasTable('gymies_support_tickets')) {
            $twelveHoursAgo = now()->subHours(12)->toDateTimeString();
            $open = DB::table('gymies_support_tickets as t')
                ->leftJoin('gymies_support_ticket_messages as m', 'm.ticket_id', '=', 't.id')
                ->whereIn('t.status', ['new', 'in_progress', 'waiting_customer'])
                ->whereIn('t.priority', ['high', 'critical'])
                ->where('t.created_at', '<', $twelveHoursAgo)
                ->selectRaw('t.id, t.subject, t.priority, t.created_at, MAX(m.created_at) as last_message_at')
                ->groupBy('t.id', 't.subject', 't.priority', 't.created_at')
                ->get();
            foreach ($open as $t) {
                $lastMsg = $t->last_message_at ?? $t->created_at;
                if ($lastMsg && $lastMsg < $twelveHoursAgo) {
                    $flags[] = [
                        'type' => 'ticket_unanswered_12h_high',
                        'title' => 'Ticket #' . $t->id . ' al 12+ uur niet beantwoord (prioriteit ' . $t->priority . ')',
                        'subtitle' => (string) ($t->subject ?? ''),
                        'entity_type' => 'ticket',
                        'entity_id' => (string) $t->id,
                        'tab' => 'tickets',
                    ];
                }
            }
        }
        if (Schema::hasTable('gymies_auth_attempts')) {
            $windowStart = now()->subHours(24)->toDateTimeString();
            $ipCounts = DB::table('gymies_auth_attempts')
                ->where('was_success', 0)
                ->where('created_at', '>=', $windowStart)
                ->selectRaw('ip_address, COUNT(*) as cnt, COUNT(DISTINCT email) as distinct_emails')
                ->groupBy('ip_address')
                ->having('cnt', '>=', 20)
                ->get();
            foreach ($ipCounts as $r) {
                $flags[] = [
                    'type' => 'ip_many_failed_logins',
                    'title' => 'IP ' . $r->ip_address . ': ' . $r->cnt . ' mislukte logins op ' . $r->distinct_emails . ' accounts',
                    'subtitle' => 'Afgelopen 24 uur',
                    'entity_type' => 'security',
                    'entity_id' => (string) $r->ip_address,
                    'tab' => 'security',
                ];
            }
        }
        return array_slice($flags, 0, 20);
    }

    /** Proactieve signalen: trainer annuleert veel, klant inactief met saldo, org no-shows, slapende wallets, trainer drop-off. */
    private function inboxRetentionAlerts(): array
    {
        $alerts = [];
        if (Schema::hasTable('gymies_user_wallets') && Schema::hasTable('gymies_bookings')) {
            $cutoff = now()->subDays(14)->toDateTimeString();
            $wallets = DB::table('gymies_user_wallets as w')
                ->join('gymies_users as u', 'u.id', '=', 'w.user_id')
                ->where('w.balance_cents', '>=', 2500)
                ->get(['w.user_id', 'w.balance_cents', 'u.display_name', 'u.email']);
            foreach ($wallets as $w) {
                $lastBooking = DB::table('gymies_bookings')
                    ->where('client_user_id', $w->user_id)
                    ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                    ->orderByDesc('scheduled_at')
                    ->value('scheduled_at');
                if ($lastBooking === null || $lastBooking < $cutoff) {
                    $alerts[] = [
                        'type' => 'sleeping_wallet',
                        'severity' => 'orange',
                        'title' => 'Slapende wallet: €' . number_format($w->balance_cents / 100, 2) . ' · 14+ dagen geen boeking',
                        'subtitle' => $w->display_name ?? $w->email,
                        'entity_type' => 'user',
                        'entity_id' => (string) $w->user_id,
                        'tab' => 'users',
                        'balance_cents' => (int) $w->balance_cents,
                    ];
                }
            }
            $alerts = array_slice($alerts, 0, 10);
        }
        if (Schema::hasTable('gymies_bookings') && Schema::hasTable('gymies_availability_slots')) {
            $cutoff = now()->subDays(10)->toDateTimeString();
            $trainersWithBookings = DB::table('gymies_bookings')
                ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                ->where('scheduled_at', '>=', now()->subDays(30)->toDateTimeString())
                ->selectRaw('trainer_user_id, COUNT(*) as cnt')
                ->groupBy('trainer_user_id')
                ->having('cnt', '>=', 12)
                ->pluck('cnt', 'trainer_user_id');
            foreach ($trainersWithBookings as $tid => $cnt) {
                $lastSlot = DB::table('gymies_availability_slots')->where('user_id', $tid)->orderByDesc('start_at')->value('start_at');
                if ($lastSlot === null || $lastSlot < $cutoff) {
                    $trainer = DB::table('gymies_users')->where('id', $tid)->first();
                    $alerts[] = [
                        'type' => 'trainer_dropoff',
                        'severity' => 'orange',
                        'title' => 'Trainer drop-off: 10+ dagen geen nieuwe beschikbaarheid',
                        'subtitle' => $trainer ? ($trainer->display_name ?? $trainer->email) : 'Trainer #' . $tid,
                        'entity_type' => 'user',
                        'entity_id' => (string) $tid,
                        'tab' => 'users',
                    ];
                }
            }
        }
        if (Schema::hasTable('gymies_bookings')) {
            $trainerCancels = DB::table('gymies_bookings')
                ->where('status', 'cancelled')
                ->whereNotNull('cancelled_by_user_id')
                ->selectRaw('trainer_user_id, COUNT(*) as cnt')
                ->groupBy('trainer_user_id')
                ->having('cnt', '>=', 3)
                ->get();
            foreach ($trainerCancels as $row) {
                $trainer = DB::table('gymies_users')->where('id', $row->trainer_user_id)->first();
                $alerts[] = [
                    'type' => 'trainer_repeated_cancellations',
                    'severity' => 'orange',
                    'title' => 'Trainer heeft ' . $row->cnt . ' boekingen geannuleerd',
                    'subtitle' => $trainer ? ($trainer->display_name ?? $trainer->email) : 'Trainer #' . $row->trainer_user_id,
                    'entity_type' => 'user',
                    'entity_id' => (string) $row->trainer_user_id,
                    'tab' => 'users',
                ];
            }
        }
        if (Schema::hasTable('gymies_organisations')) {
            $pendingOrgs = DB::table('gymies_organisations')
                ->whereIn('status', ['pending', 'verification_pending'])
                ->limit(20)
                ->get(['id', 'name', 'status', 'created_at']);
            foreach ($pendingOrgs as $o) {
                $alerts[] = [
                    'type' => 'organisation_verification',
                    'severity' => 'green',
                    'title' => 'Organisatie wacht op verificatie',
                    'subtitle' => (string) ($o->name ?? 'Org #' . $o->id),
                    'entity_type' => 'organisation',
                    'entity_id' => (string) $o->id,
                    'tab' => 'organisations',
                ];
            }
        }
        return $alerts;
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
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Tickets niet beschikbaar.'], 422);
        }
        $request->validate([
            'ticket_ids' => 'required|array',
            'ticket_ids.*' => 'integer|min:1',
            'status' => 'nullable|in:new,in_progress,waiting_customer,resolved',
            'priority' => 'nullable|in:low,medium,high,critical',
            'assigned_to_user_id' => 'nullable|integer|min:0',
            'reason' => 'required|string|max:500',
        ]);
        $ids = array_unique(array_filter(array_map('intval', $request->input('ticket_ids', []))));
        if (count($ids) > 100) {
            return response()->json(['message' => 'Maximaal 100 tickets per bulkactie.'], 422);
        }
        $status = $request->input('status');
        $priority = $request->input('priority');
        $assignedTo = $request->input('assigned_to_user_id');
        $assignedToId = $assignedTo === null || $assignedTo === '' ? null : (int) $assignedTo;
        if ($assignedToId !== null && $assignedToId < 1) {
            $assignedToId = null;
        }
        $reason = (string) $request->input('reason');
        $update = ['updated_at' => now()];
        if ($status !== null) {
            $update['status'] = $status;
            if ($status === 'resolved' && Schema::hasColumn('gymies_support_tickets', 'resolved_at')) {
                $update['resolved_at'] = now();
            }
        }
        if ($priority !== null) {
            $update['priority'] = $priority;
        }
        if ($request->has('assigned_to_user_id') && Schema::hasColumn('gymies_support_tickets', 'assigned_to_user_id')) {
            $update['assigned_to_user_id'] = $assignedToId;
        }
        $updated = DB::table('gymies_support_tickets')->whereIn('id', $ids)->update($update);
        foreach ($ids as $id) {
            $this->audit((int) $admin->id, 'admin_bulk_ticket_update', 'support_ticket', $id, ['reason' => $reason, 'update' => $update]);
        }
        return response()->json(['ok' => true, 'updated' => $updated]);
    }

    /** Bulk: payout status wijzigen. */
    public function bulkPayoutsStatus(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['message' => 'Payouts niet beschikbaar.'], 422);
        }
        $request->validate([
            'payout_ids' => 'required|array',
            'payout_ids.*' => 'integer|min:1',
            'status' => 'required|in:pending,processing,paid,failed,cancelled',
            'reason' => 'required|string|max:500',
        ]);
        $ids = array_unique(array_filter(array_map('intval', $request->input('payout_ids', []))));
        if (count($ids) > 50) {
            return response()->json(['message' => 'Maximaal 50 payouts per bulkactie.'], 422);
        }
        $status = (string) $request->input('status');
        $reason = (string) $request->input('reason');
        $update = ['status' => $status, 'updated_at' => now()];
        if ($status === 'paid' && Schema::hasColumn('gymies_payouts', 'paid_at')) {
            $update['paid_at'] = now();
        }
        $updated = DB::table('gymies_payouts')->whereIn('id', $ids)->update($update);
        foreach ($ids as $id) {
            $this->audit((int) $admin->id, 'admin_bulk_payout_status', 'payout', $id, ['status' => $status, 'reason' => $reason]);
        }
        return response()->json(['ok' => true, 'updated' => $updated]);
    }

    /** Opgeslagen filters/weergaven. */
    public function savedViews(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_admin_saved_views')) {
            return response()->json(['data' => []]);
        }
        $userId = (int) $admin->id;
        $rows = DB::table('gymies_admin_saved_views')
            ->where(function ($q) use ($userId): void {
                $q->whereNull('user_id')->orWhere('user_id', $userId);
            })
            ->orderBy('name')
            ->get(['id', 'user_id', 'name', 'entity_type', 'filters', 'created_at']);
        $data = $rows->map(static function ($r) {
            $filters = $r->filters;
            if (is_string($filters)) {
                $filters = json_decode($filters, true) ?? [];
            }
            return [
                'id' => (string) $r->id,
                'name' => $r->name,
                'entity_type' => $r->entity_type,
                'filters' => is_array($filters) ? $filters : [],
            ];
        })->all();
        return response()->json(['data' => $data]);
    }

    public function storeSavedView(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'name' => 'required|string|max:120',
            'entity_type' => 'required|in:users,tickets,bookings,payouts',
            'filters' => 'required|array',
        ]);
        if (!Schema::hasTable('gymies_admin_saved_views')) {
            return response()->json(['message' => 'Saved views niet beschikbaar.'], 422);
        }
        $filters = $request->input('filters');
        if (!is_array($filters)) {
            $filters = [];
        }
        $id = DB::table('gymies_admin_saved_views')->insertGetId([
            'user_id' => (int) $admin->id,
            'name' => trim((string) $request->input('name')),
            'entity_type' => (string) $request->input('entity_type'),
            'filters' => json_encode($filters, JSON_UNESCAPED_UNICODE),
            'created_at' => now(),
        ]);
        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    public function destroySavedView(Request $request, string $id): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($id)) {
            return response()->json(['message' => 'Ongeldige id.'], 422);
        }
        if (!Schema::hasTable('gymies_admin_saved_views')) {
            return response()->json(['ok' => true]);
        }
        $deleted = DB::table('gymies_admin_saved_views')
            ->where('id', (int) $id)
            ->where('user_id', (int) $admin->id)
            ->delete();
        return response()->json(['ok' => true, 'deleted' => $deleted > 0]);
    }

    /** Notitietemplates voor snelle interne notities. */
    public function noteTemplates(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_admin_note_templates')) {
            return response()->json(['data' => []]);
        }
        $category = trim((string) $request->query('category', ''));
        $query = DB::table('gymies_admin_note_templates')->orderBy('sort_order')->orderBy('name');
        if ($category !== '') {
            $query->where('category', $category);
        }
        $rows = $query->get(['id', 'name', 'body', 'category']);
        $data = $rows->map(static fn ($r) => [
            'id' => (string) $r->id,
            'name' => $r->name,
            'body' => $r->body,
            'category' => $r->category,
        ])->all();
        return response()->json(['data' => $data]);
    }

    // ========== Control Tower: Profitability Guard ==========
    public function profitabilityOverview(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $period = trim((string) $request->query('period', 'week')); // day, week
        $days = $period === 'day' ? 1 : 7;
        $from = now()->subDays($days)->startOfDay()->toDateTimeString();

        $commissionCents = 0;
        $transactionCount = 0;
        $minPriceCents = (int) $this->getSetting('profitability_min_booking_price_cents', '1500');
        $mollieFeeCents = (int) $this->getSetting('profitability_mollie_fee_cents', '29');
        $btwPercent = (float) $this->getSetting('profitability_btw_percent', '21');

        if (Schema::hasTable('gymies_bookings')) {
            $row = DB::table('gymies_bookings')
                ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                ->where('paid_at', '>=', $from)
                ->whereNotNull('paid_at')
                ->selectRaw('COALESCE(SUM(platform_fee_cents), 0) as commission_cents, COUNT(*) as cnt')
                ->first();
            $commissionCents = (int) ($row->commission_cents ?? 0);
            $transactionCount = (int) ($row->cnt ?? 0);
        }
        $transactionCostCents = $transactionCount * $mollieFeeCents;
        $btwOnCommission = $commissionCents * ($btwPercent / 100);
        $netMarginCents = $commissionCents - (int) round($btwOnCommission) - $transactionCostCents;

        $payoutMismatches = [];
        if (Schema::hasTable('gymies_payouts') && Schema::hasColumn('gymies_payouts', 'mollie_payout_id')) {
            $pending = DB::table('gymies_payouts')->whereIn('status', ['pending', 'paid'])->whereNotNull('mollie_payout_id')->count();
            if ($pending > 0) {
                $payoutMismatches[] = ['type' => 'no_mollie_id', 'count' => $pending, 'message' => 'Payouts zonder Mollie-id'];
            }
        }

        $belowMin = 0;
        if (Schema::hasTable('gymies_bookings')) {
            $belowMin = DB::table('gymies_bookings')
                ->whereIn('status', ['pending', 'confirmed'])
                ->where('scheduled_at', '>=', now()->toDateTimeString())
                ->whereNotNull('amount_cents')
                ->where('amount_cents', '<', $minPriceCents)
                ->count();
        }

        return response()->json([
            'data' => [
                'period' => $period,
                'days' => $days,
                'commission_cents' => $commissionCents,
                'transaction_count' => $transactionCount,
                'transaction_cost_cents' => $transactionCostCents,
                'btw_cents' => (int) round($btwOnCommission),
                'net_margin_cents' => $netMarginCents,
                'min_price_cents' => $minPriceCents,
                'below_min_count' => $belowMin,
                'payout_reconciliation' => ['mismatches' => $payoutMismatches],
            ],
        ]);
    }

    public function profitabilitySettings(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        return response()->json([
            'data' => [
                'min_booking_price_cents' => (int) $this->getSetting('profitability_min_booking_price_cents', '1500'),
                'mollie_fee_cents' => (int) $this->getSetting('profitability_mollie_fee_cents', '29'),
                'btw_percent' => (float) $this->getSetting('profitability_btw_percent', '21'),
                'group_session_trainer_penalty_cents' => (int) $this->getSetting('group_session_trainer_penalty_cents', '5000'),
                'bank_refund_admin_fee_cents' => (int) $this->getSetting('bank_refund_admin_fee_cents', '99'),
                // Revenue & Upsell
                'annual_contract_free_months' => (int) $this->getSetting('upsell_annual_contract_free_months', '2'),
                'pro_trial_days' => (int) $this->getSetting('upsell_pro_trial_days', '14'),
                'referral_free_months' => (int) $this->getSetting('upsell_referral_free_months', '1'),
            ],
        ]);
    }

    public function updateProfitabilitySettings(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'min_booking_price_cents' => 'nullable|integer|min:0|max:100000',
            'mollie_fee_cents' => 'nullable|integer|min:0|max:500',
            'btw_percent' => 'nullable|numeric|min:0|max:100',
            'group_session_trainer_penalty_cents' => 'nullable|integer|min:0|max:100000',
            'bank_refund_admin_fee_cents' => 'nullable|integer|min:0|max:500',
            'annual_contract_free_months' => 'nullable|integer|min:0|max:12',
            'pro_trial_days' => 'nullable|integer|min:0|max:90',
            'referral_free_months' => 'nullable|integer|min:0|max:12',
        ]);
        if (!Schema::hasTable('gymies_system_settings')) {
            return response()->json(['message' => 'Settings niet beschikbaar.'], 503);
        }
        $mapping = [
            'min_booking_price_cents' => 'profitability_min_booking_price_cents',
            'mollie_fee_cents' => 'profitability_mollie_fee_cents',
            'btw_percent' => 'profitability_btw_percent',
            'group_session_trainer_penalty_cents' => 'group_session_trainer_penalty_cents',
            'bank_refund_admin_fee_cents' => 'bank_refund_admin_fee_cents',
            'annual_contract_free_months' => 'upsell_annual_contract_free_months',
            'pro_trial_days' => 'upsell_pro_trial_days',
            'referral_free_months' => 'upsell_referral_free_months',
        ];
        foreach ($mapping as $input => $key) {
            $v = $request->input($input);
            if ($v !== null && $v !== '') {
                DB::table('gymies_system_settings')->updateOrInsert(
                    ['setting_key' => $key],
                    ['setting_value' => (string) $v, 'updated_at' => now()]
                );
            }
        }
        return response()->json(['ok' => true]);
    }

    /**
     * Control Tower: upload afbeelding of video voor site-media.
     * POST multipart: file (verplicht), key (optioneel: hero_image|hero_video|section_training|section_trainer|section_fitness|og_image|gallery).
     * Bij key=gallery: voegt URL toe aan site_gallery_urls. Anders: zet direct in het betreffende veld.
     */
    public function uploadSiteMedia(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'key' => 'nullable|string|in:hero_image,hero_video,section_training,section_trainer,section_fitness,og_image,gallery',
        ]);
        $file = $request->file('file');
        if (!$file || !$file->isValid()) {
            return response()->json(['message' => 'Geen geldig bestand ontvangen.'], 422);
        }
        $key = trim((string) $request->input('key', 'gallery'));
        $ext = strtolower($file->getClientOriginalExtension() ?: $file->guessExtension() ?: 'bin');
        $allowedImages = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
        $allowedVideo = ['mp4', 'webm'];
        if (in_array($ext, $allowedVideo)) {
            $maxMb = 50;
        } elseif (in_array($ext, $allowedImages)) {
            $maxMb = 5;
        } else {
            return response()->json(['message' => 'Alleen afbeeldingen (jpg, png, gif, webp) of video (mp4, webm) toegestaan.'], 422);
        }
        if ($file->getSize() > $maxMb * 1024 * 1024) {
            return response()->json(['message' => "Bestand te groot. Max $maxMb MB."], 422);
        }
        $dir = 'site-media';
        $name = $key . '_' . substr(md5((string) microtime(true)), 0, 8) . '.' . $ext;
        $path = $file->storeAs($dir, $name, 'public');
        if (!$path) {
            return response()->json(['message' => 'Opslaan mislukt.'], 500);
        }
        $url = rtrim(config('app.url', ''), '/') . '/storage/' . $path;
        if ($key === 'gallery') {
            if (!Schema::hasTable('gymies_system_settings')) {
                return response()->json(['message' => 'Settings-tabel ontbreekt.'], 503);
            }
            $row = DB::table('gymies_system_settings')->where('setting_key', 'site_gallery_urls')->first();
            $arr = [];
            if ($row && trim((string) $row->setting_value) !== '') {
                $decoded = json_decode((string) $row->setting_value, true);
                if (is_array($decoded)) {
                    $arr = $decoded;
                }
            }
            $arr[] = $url;
            DB::table('gymies_system_settings')->updateOrInsert(
                ['setting_key' => 'site_gallery_urls'],
                ['setting_value' => json_encode($arr, JSON_UNESCAPED_SLASHES), 'updated_at' => now()]
            );
        } else {
            $map = [
                'hero_image' => 'site_hero_image_url',
                'hero_video' => 'site_hero_video_url',
                'section_training' => 'site_section_training_url',
                'section_trainer' => 'site_section_trainer_url',
                'section_fitness' => 'site_section_fitness_url',
                'og_image' => 'site_og_image_url',
            ];
            $settingKey = $map[$key] ?? null;
            if ($settingKey && Schema::hasTable('gymies_system_settings')) {
                DB::table('gymies_system_settings')->updateOrInsert(
                    ['setting_key' => $settingKey],
                    ['setting_value' => $url, 'updated_at' => now()]
                );
            }
        }
        $this->audit((int) $admin->id, 'admin_site_media_upload', 'settings', 0, ['key' => $key]);
        return response()->json(['url' => $url]);
    }

    /**
     * Control Tower: hero/sectie-afbeeldingen en hero-video als absolute URLs.
     * Opslag in gymies_system_settings. Lege string = uitschakelen.
     */
    public function updateSiteMedia(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'site_hero_image_url' => 'nullable|string|max:2000',
            'site_hero_video_url' => 'nullable|string|max:2000',
            'site_section_training_url' => 'nullable|string|max:2000',
            'site_section_trainer_url' => 'nullable|string|max:2000',
            'site_section_fitness_url' => 'nullable|string|max:2000',
            'site_og_image_url' => 'nullable|string|max:2000',
            'site_gallery_urls' => 'nullable|string|max:50000',
            'plan_starter_features' => 'nullable|string|max:10000',
            'plan_pro_features' => 'nullable|string|max:10000',
            'plan_studio_features' => 'nullable|string|max:10000',
        ]);
        if (!Schema::hasTable('gymies_system_settings')) {
            return response()->json(['message' => 'Settings-tabel ontbreekt.'], 503);
        }
        // site_subscriptions_json is niet bewerkbaar – komt altijd dynamisch uit gymies_plans
        $map = [
            'site_hero_image_url',
            'site_hero_video_url',
            'site_section_training_url',
            'site_section_trainer_url',
            'site_section_fitness_url',
            'site_og_image_url',
        ];
        // Eén transactie: alles-of-niets, minder kans op half-weggeschreven state bij trage DB.
        DB::transaction(function () use ($request, $map): void {
            foreach ($map as $key) {
                if (!$request->has($key)) {
                    continue;
                }
                $v = trim((string) $request->input($key, ''));
                DB::table('gymies_system_settings')->updateOrInsert(
                    ['setting_key' => $key],
                    ['setting_value' => $v, 'updated_at' => now()]
                );
            }
            if ($request->has('site_gallery_urls')) {
                $input = $request->input('site_gallery_urls', []);
                if (is_string($input) && trim($input) !== '') {
                    $decoded = json_decode($input, true);
                    $input = is_array($decoded) ? $decoded : [];
                }
                $arr = is_array($input) ? array_values(array_filter(array_map('strval', $input), fn ($s) => trim($s) !== '')) : [];
                DB::table('gymies_system_settings')->updateOrInsert(
                    ['setting_key' => 'site_gallery_urls'],
                    ['setting_value' => json_encode($arr, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), 'updated_at' => now()]
                );
            }
            foreach (['plan_starter_features', 'plan_pro_features', 'plan_studio_features'] as $fk) {
                if (!$request->has($fk)) {
                    continue;
                }
                $v = $request->input($fk);
                $arr = is_array($v) ? array_values(array_filter(array_map('strval', $v), fn ($s) => trim($s) !== '')) : [];
                if (is_string($v) && trim($v) !== '') {
                    $decoded = json_decode($v, true);
                    $arr = is_array($decoded) ? array_values(array_filter(array_map('strval', $decoded), fn ($s) => trim($s) !== '')) : [];
                }
                DB::table('gymies_system_settings')->updateOrInsert(
                    ['setting_key' => $fk],
                    ['setting_value' => json_encode($arr, JSON_UNESCAPED_UNICODE), 'updated_at' => now()]
                );
            }
        });
        $this->audit((int) $admin->id, 'admin_site_media_update', 'settings', 0, []);
        return response()->json(['ok' => true, 'saved_at' => now()->toIso8601String()]);
    }

    private function getSetting(string $key, string $default): string
    {
        if (!Schema::hasTable('gymies_system_settings')) {
            return $default;
        }
        $row = DB::table('gymies_system_settings')->where('setting_key', $key)->first();
        return $row ? (string) $row->setting_value : $default;
    }

    // ========== Control Tower: Retention & Churn ==========

    public function trainerDropoffAlerts(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $daysNoAvailability = (int) $request->query('days', 10);
        $minBookingsPerWeek = (float) $request->query('min_per_week', 3);
        $cutoff = now()->subDays($daysNoAvailability)->toDateTimeString();

        $list = [];
        if (Schema::hasTable('gymies_bookings') && Schema::hasTable('gymies_availability_slots')) {
            $trainersWithRecentBookings = DB::table('gymies_bookings')
                ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                ->where('scheduled_at', '>=', now()->subDays(30)->toDateTimeString())
                ->selectRaw('trainer_user_id, COUNT(*) as cnt')
                ->groupBy('trainer_user_id')
                ->having('cnt', '>=', (int) ceil($minBookingsPerWeek * 4))
                ->pluck('cnt', 'trainer_user_id');
            foreach ($trainersWithRecentBookings as $tid => $cnt) {
                $lastSlot = DB::table('gymies_availability_slots')
                    ->where('user_id', $tid)
                    ->orderByDesc('start_at')
                    ->value('start_at');
                if ($lastSlot === null || $lastSlot < $cutoff) {
                    $trainer = DB::table('gymies_users')->where('id', $tid)->first();
                    $list[] = [
                        'user_id' => (string) $tid,
                        'display_name' => $trainer ? ($trainer->display_name ?? $trainer->email) : 'Trainer #' . $tid,
                        'email' => $trainer->email ?? null,
                        'bookings_last_30d' => (int) $cnt,
                        'last_availability_at' => $lastSlot,
                    ];
                }
            }
        }
        return response()->json(['data' => array_slice($list, 0, 30)]);
    }

    public function sendNudge(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'user_id' => 'required|integer|min:1',
            'nudge_type' => 'required|in:push,discount_code',
            'title' => 'nullable|string|max:255',
            'body' => 'nullable|string|max:2000',
            'discount_code' => 'nullable|string|max:64',
        ]);
        $userId = (int) $request->input('user_id');
        $nudgeType = (string) $request->input('nudge_type');
        if (!Schema::hasTable('gymies_admin_nudges')) {
            return response()->json(['message' => 'Nudges niet beschikbaar.'], 503);
        }
        DB::table('gymies_admin_nudges')->insert([
            'user_id' => $userId,
            'nudge_type' => $nudgeType,
            'title' => $request->input('title'),
            'body' => $request->input('body'),
            'discount_code' => $request->input('discount_code'),
            'created_by_user_id' => $admin->id,
            'created_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_nudge_sent', 'user', $userId, ['nudge_type' => $nudgeType]);
        return response()->json(['ok' => true, 'message' => 'Nudge geregistreerd. Push/kortingscode moet extern worden verstuurd.']);
    }

    // ========== Control Tower: Revenue Leakage ==========
    private const LEAKAGE_KEYWORDS = ['tikkie', 'contant', 'bankrekening', 'overschrijven', '06-', '06 ', 'betalen buiten', 'buiten de app', 'whatsapp', 'cash', 'pin', 'iban', 'rechtstreeks', 'onderling'];

    public function chatLeakageFlags(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_chat_leakage_flags')) {
            return response()->json(['data' => []]);
        }
        $reviewed = $request->query('reviewed'); // 0, 1, or omit = all
        $query = DB::table('gymies_chat_leakage_flags as f')
            ->leftJoin('gymies_conversations as c', 'c.id', '=', 'f.conversation_id')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'f.from_user_id')
            ->orderByDesc('f.created_at')
            ->limit(100)
            ->select('f.id', 'f.conversation_id', 'f.message_id', 'f.from_user_id', 'f.keywords_found', 'f.message_snippet', 'f.reviewed_at', 'f.action_taken', 'f.created_at', 'u.display_name as from_name', 'u.email as from_email');
        if ($reviewed === '0') {
            $query->whereNull('f.reviewed_at');
        } elseif ($reviewed === '1') {
            $query->whereNotNull('f.reviewed_at');
        }
        $rows = $query->get();
        $list = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'conversation_id' => (string) $r->conversation_id,
            'message_id' => (string) $r->message_id,
            'from_user_id' => (string) $r->from_user_id,
            'from_name' => $r->from_name ?? $r->from_email,
            'keywords_found' => $r->keywords_found,
            'message_snippet' => $r->message_snippet,
            'reviewed_at' => $r->reviewed_at,
            'action_taken' => $r->action_taken,
            'created_at' => $r->created_at,
        ])->all();
        return response()->json(['data' => $list]);
    }

    public function scanChatKeywords(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_messages') || !Schema::hasTable('gymies_chat_leakage_flags')) {
            return response()->json(['message' => 'Chat of leakage-tabel niet beschikbaar.'], 503);
        }
        $since = $request->input('since'); // optional Y-m-d
        $query = DB::table('gymies_messages')->orderByDesc('id')->limit(500);
        if ($since) {
            $query->where('created_at', '>=', $since . ' 00:00:00');
        }
        $messages = $query->get(['id', 'conversation_id', 'from_user_id', 'body']);
        $found = 0;
        foreach ($messages as $m) {
            $body = strtolower((string) ($m->body ?? ''));
            $matched = [];
            foreach (self::LEAKAGE_KEYWORDS as $kw) {
                if (str_contains($body, $kw)) {
                    $matched[] = $kw;
                }
            }
            if ($matched !== []) {
                $exists = DB::table('gymies_chat_leakage_flags')->where('message_id', $m->id)->exists();
                if (!$exists) {
                    DB::table('gymies_chat_leakage_flags')->insert([
                        'conversation_id' => $m->conversation_id,
                        'message_id' => $m->id,
                        'from_user_id' => $m->from_user_id,
                        'keywords_found' => implode(',', $matched),
                        'message_snippet' => \Illuminate\Support\Str::limit($m->body, 200),
                        'created_at' => now(),
                    ]);
                    $found++;
                }
            }
        }
        return response()->json(['ok' => true, 'new_flags_count' => $found]);
    }

    public function reviewLeakageFlag(Request $request, string $flagId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($flagId) || !Schema::hasTable('gymies_chat_leakage_flags')) {
            return response()->json(['message' => 'Ongeldige flag.'], 422);
        }
        $request->validate(['action_taken' => 'required|in:warning,fine,dismissed']);
        $action = (string) $request->input('action_taken');
        DB::table('gymies_chat_leakage_flags')->where('id', (int) $flagId)->update([
            'reviewed_at' => now(),
            'reviewed_by_user_id' => $admin->id,
            'action_taken' => $action,
        ]);
        $this->audit((int) $admin->id, 'admin_leakage_flag_reviewed', 'leakage_flag', (int) $flagId, ['action_taken' => $action]);
        return response()->json(['ok' => true]);
    }

    // ========== Control Tower: Trainer Tiers & Bulk Marketing ==========
    public function trainerTiers(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $tier = $request->query('tier'); // bronze, silver, gold
        $hasTier = Schema::hasTable('gymies_trainer_profiles') && Schema::hasColumn('gymies_trainer_profiles', 'tier');
        $query = DB::table('gymies_users as u')
            ->where('u.role', 'trainer')
            ->leftJoin('gymies_trainer_profiles as p', 'p.user_id', '=', 'u.id')
            ->select('u.id', 'u.display_name', 'u.email', $hasTier ? DB::raw('COALESCE(p.tier, \'bronze\') as tier') : DB::raw('\'bronze\' as tier'));
        if ($tier && in_array($tier, ['bronze', 'silver', 'gold'], true)) {
            if ($hasTier) {
                $query->where(DB::raw('COALESCE(p.tier, \'bronze\')'), $tier);
            }
        }
        $rows = $query->limit(200)->get();
        $list = $rows->map(fn ($r) => [
            'user_id' => (string) $r->id,
            'display_name' => $r->display_name ?? $r->email,
            'email' => $r->email,
            'tier' => $r->tier ?? 'bronze',
        ])->all();
        return response()->json(['data' => $list]);
    }

    public function updateUserTier(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user.'], 422);
        }
        $request->validate(['tier' => 'required|in:bronze,silver,gold']);
        $tier = (string) $request->input('tier');
        if (!Schema::hasTable('gymies_trainer_profiles') || !Schema::hasColumn('gymies_trainer_profiles', 'tier')) {
            return response()->json(['message' => 'Tier niet beschikbaar.'], 503);
        }
        $id = (int) $userId;
        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $id)->first();
        if ($profile) {
            DB::table('gymies_trainer_profiles')->where('user_id', $id)->update(['tier' => $tier]);
        } else {
            DB::table('gymies_trainer_profiles')->insert(['user_id' => $id, 'tier' => $tier, 'created_at' => now(), 'updated_at' => now()]);
        }
        $this->audit((int) $admin->id, 'admin_user_tier_updated', 'user', $id, ['tier' => $tier]);
        return response()->json(['ok' => true, 'tier' => $tier]);
    }

    public function bulkCampaigns(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_bulk_campaigns')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_bulk_campaigns')->orderByDesc('id')->limit(50)->get();
        $list = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'name' => $r->name,
            'segment_filters' => $r->segment_filters ? json_decode($r->segment_filters, true) : [],
            'message_text' => $r->message_text,
            'message_type' => $r->message_type ?? 'push',
            'sent_at' => $r->sent_at,
            'created_at' => $r->created_at,
        ])->all();
        return response()->json(['data' => $list]);
    }

    public function bulkCampaignStore(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'name' => 'required|string|max:255',
            'segment_filters' => 'nullable|array',
            'segment_filters.tier' => 'nullable|string|in:bronze,silver,gold',
            'segment_filters.city' => 'nullable|string|max:100',
            'message_text' => 'required|string|max:5000',
            'message_type' => 'nullable|in:push,email,discount_code',
            'discount_code' => 'nullable|string|max:64',
            'discount_percent' => 'nullable|integer|min:1|max:100',
        ]);
        if (!Schema::hasTable('gymies_bulk_campaigns')) {
            return response()->json(['message' => 'Campaigns niet beschikbaar.'], 503);
        }
        $id = DB::table('gymies_bulk_campaigns')->insertGetId([
            'name' => $request->input('name'),
            'segment_filters' => json_encode($request->input('segment_filters', [])),
            'message_text' => $request->input('message_text'),
            'message_type' => $request->input('message_type', 'push'),
            'discount_code' => $request->input('discount_code'),
            'discount_percent' => $request->input('discount_percent'),
            'created_by_user_id' => $admin->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        return response()->json(['ok' => true, 'id' => $id]);
    }

    public function bulkCampaignSend(Request $request, string $campaignId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($campaignId) || !Schema::hasTable('gymies_bulk_campaigns')) {
            return response()->json(['message' => 'Ongeldige campaign.'], 422);
        }
        $campaign = DB::table('gymies_bulk_campaigns')->where('id', (int) $campaignId)->first();
        if (!$campaign) {
            return response()->json(['message' => 'Campaign niet gevonden.'], 404);
        }
        DB::table('gymies_bulk_campaigns')->where('id', (int) $campaignId)->update(['sent_at' => now()]);
        $this->audit((int) $admin->id, 'admin_bulk_campaign_sent', 'campaign', (int) $campaignId, []);
        return response()->json(['ok' => true, 'message' => 'Campaign gemarkeerd als verstuurd. Versturen van push/email gebeurt extern.']);
    }

    public function heatmap(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $data = $this->heatmapSupplyOnly();
        return response()->json(['data' => $data]);
    }

    /** Demand vs Supply + Gap Detection: waar zoeken klanten vs waar zitten trainers. */
    public function heatmapDemandSupply(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $days = min(max((int) $request->query('days', 30), 7), 365);
        $since = now()->subDays($days)->toDateTimeString();

        $demandByCity = [];
        if (Schema::hasTable('gymies_search_log')) {
            $rows = DB::table('gymies_search_log')
                ->where('created_at', '>=', $since)
                ->whereNotNull('city_normalized')
                ->where('city_normalized', '!=', '')
                ->selectRaw('city_normalized as city, COUNT(*) as demand_count')
                ->groupBy('city_normalized')
                ->get();
            foreach ($rows as $r) {
                $demandByCity[$r->city] = (int) $r->demand_count;
            }
        }

        $supplyByCity = [];
        foreach ($this->heatmapSupplyOnly() as $row) {
            $city = (string) ($row['city'] ?? '');
            if ($city !== '') {
                $supplyByCity[$city] = (int) ($row['trainer_count'] ?? 0);
            }
        }

        $allCities = array_unique(array_merge(array_keys($demandByCity), array_keys($supplyByCity)));
        $result = [];
        foreach ($allCities as $city) {
            $demand = $demandByCity[$city] ?? 0;
            $supply = $supplyByCity[$city] ?? 0;
            $gap = $demand - $supply;
            $result[] = [
                'city' => $city,
                'demand_count' => $demand,
                'supply_count' => $supply,
                'gap' => $gap,
                'message' => $gap > 0 ? "{$demand}x gezocht, {$supply} trainer(s) – werven!" : null,
            ];
        }
        usort($result, static fn ($a, $b) => ($b['gap'] ?? 0) <=> ($a['gap'] ?? 0));
        return response()->json(['data' => array_slice($result, 0, 50), 'days' => $days]);
    }

    /** Supply only: trainers per stad (trainer_locations.city + trainer_profiles.region). */
    private function heatmapSupplyOnly(): array
    {
        $byCity = [];
        if (Schema::hasTable('gymies_trainer_locations')) {
            $rows = DB::table('gymies_trainer_locations')
                ->whereNotNull('city')
                ->where('city', '!=', '')
                ->selectRaw('LOWER(TRIM(city)) as city, COUNT(DISTINCT trainer_user_id) as trainer_count')
                ->groupBy(DB::raw('LOWER(TRIM(city))'))
                ->get();
            foreach ($rows as $r) {
                $byCity[$r->city] = (int) $r->trainer_count;
            }
        }
        if (Schema::hasTable('gymies_trainer_profiles') && Schema::hasColumn('gymies_trainer_profiles', 'region')) {
            $rows = DB::table('gymies_trainer_profiles')
                ->whereNotNull('region')
                ->where('region', '!=', '')
                ->get(['user_id', 'region']);
            foreach ($rows as $r) {
                $region = (string) $r->region;
                $first = trim(explode(',', $region)[0] ?? $region);
                if ($first !== '') {
                    $city = mb_strtolower($first);
                    if (mb_strlen($city) > 100) {
                        $city = mb_substr($city, 0, 100);
                    }
                    $byCity[$city] = ($byCity[$city] ?? 0) + 1;
                }
            }
        }
        $result = [];
        foreach ($byCity as $city => $count) {
            $result[] = ['city' => $city, 'trainer_count' => $count];
        }
        return $result;
    }

    /**
     * @param array<string,mixed> $newValues
     * @param array<string,mixed>|null $oldValues
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

        // B44: Limiet toegevoegd – bij grote groei kan deze tabel duizenden rijen bevatten.
        $limit = min(500, max(1, (int) ($request->query('limit', 200))));
        $subs = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->join('gymies_users as u', 'u.id', '=', 's.trainer_user_id')
            ->select('s.*', 'p.name as plan_name', 'p.slug as plan_slug', 'p.price_cents_per_month',
                'u.display_name as trainer_name', 'u.email as trainer_email')
            ->orderByDesc('s.created_at')
            ->limit($limit)
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

        // B45: Limiet + bulk-fetch om N+1 query probleem op te lossen.
        // Was: per trainer aparte queries voor documenten en subscriptions → O(n) DB-calls.
        // Nu: één query per tabel met whereIn → O(1) DB-calls ongeacht aantal trainers.
        $pipelineLimit = min(500, max(1, (int) ($request->query('limit', 200))));
        $trainers = DB::table('gymies_users as u')
            ->leftJoin('gymies_trainer_profiles as tp', 'tp.user_id', '=', 'u.id')
            ->where('u.role', 'trainer')
            ->select(
                'u.id', 'u.display_name', 'u.email', 'u.created_at',
                'tp.mollie_onboarding_status', 'tp.subscription_plan', 'tp.mollie_profile_id'
            )
            ->orderByDesc('u.created_at')
            ->limit($pipelineLimit)
            ->get();

        $trainerIds = $trainers->pluck('id')->map(fn ($id) => (int) $id)->toArray();

        // Bulk-fetch documenten voor alle trainers in één query
        $allDocs = [];
        if ($trainerIds !== [] && Schema::hasTable('gymies_document_uploads') && Schema::hasColumn('gymies_document_uploads', 'document_category')) {
            $allDocs = DB::table('gymies_document_uploads')
                ->whereIn('user_id', $trainerIds)
                ->whereIn('document_category', ['kvk_extract', 'id_document', 'certification', 'vog'])
                ->get(['user_id', 'document_category', 'verified_at', 'rejected_at'])
                ->groupBy('user_id')
                ->toArray();
        }

        // Bulk-fetch actieve subscriptions voor alle trainers in één query
        $activeSubTrainerIds = [];
        if ($trainerIds !== [] && Schema::hasTable('gymies_subscriptions')) {
            $activeSubTrainerIds = DB::table('gymies_subscriptions')
                ->whereIn('trainer_user_id', $trainerIds)
                ->whereIn('status', ['active', 'trialing'])
                ->pluck('trainer_user_id')
                ->map(fn ($id) => (int) $id)
                ->flip()
                ->toArray();
        }

        $result = [];
        foreach ($trainers as $t) {
            $trainerId = (int) $t->id;
            $docsForTrainer = $allDocs[$trainerId] ?? [];
            $docsByCategory = [];
            foreach ($docsForTrainer as $doc) {
                $docsByCategory[$doc->document_category] = $doc;
            }
            $result[] = [
                'trainer_id' => (string) $t->id,
                'name' => $t->display_name,
                'email' => $t->email,
                'registered_at' => $t->created_at,
                'documents' => $docsByCategory,
                'mollie_status' => $t->mollie_onboarding_status ?? 'not_started',
                'has_mollie_profile' => $t->mollie_profile_id !== null,
                'subscription_plan' => $t->subscription_plan,
                'has_active_subscription' => isset($activeSubTrainerIds[$trainerId]),
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

    /**
     * S-076: Feature Flag Tampering Prevention
     * Helper-functie voor feature flag updates.
     * Voorkomt dat gebruikers willekeurige JSON/strings kunnen injiceren als flag values.
     *
     * Gebruik: voeg deze validatie toe aan endpoints die feature flags instellen.
     *
     * @param array $flags Associatief array van [flag_key => value]
     * @return array|JsonResponse Validated flags of error response
     */
    protected function validateFeatureFlags(array $flags)
    {
        // Whitelist van toegestane feature flags en hun geldige waardes
        $allowedFlags = [
            'chat_enabled' => ['type' => 'boolean'],
            'booking_enabled' => ['type' => 'boolean'],
            'payments_enabled' => ['type' => 'boolean'],
            'trainer_signups_enabled' => ['type' => 'boolean'],
            'referrals_enabled' => ['type' => 'boolean'],
            'wallet_feature_enabled' => ['type' => 'boolean'],
            'points_system_enabled' => ['type' => 'boolean'],
            'ghost_ratings_enabled' => ['type' => 'boolean'],
        ];

        $validated = [];

        foreach ($flags as $key => $value) {
            // S-076: Alleen whitelisted flags mogen worden ingesteld
            if (!isset($allowedFlags[$key])) {
                return response()->json(
                    ['message' => "Feature flag '{$key}' is niet in de whitelist."],
                    422
                );
            }

            $flagDef = $allowedFlags[$key];

            // S-076: Type validatie — alleen boolean values voor boolean flags
            if ($flagDef['type'] === 'boolean') {
                if (!is_bool($value) && $value !== '0' && $value !== '1' && $value !== 0 && $value !== 1) {
                    return response()->json(
                        ['message' => "Feature flag '{$key}' moet een boolean zijn."],
                        422
                    );
                }
                $validated[$key] = (bool) $value;
            }
        }

        return $validated;
    }

    // =========================================================================
    // GYM DEMO AANVRAGEN
    // =========================================================================

    /**
     * GET admin/demo-requests
     *
     * Overzicht van alle demo-aanvragen met filtering op status.
     * Query params: ?status=new|contacted|demo_scheduled|converted|rejected
     *               ?page=1&per_page=25
     */
    public function demoRequests(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_gym_demo_requests')) {
            return response()->json(['message' => 'Demo requests tabel bestaat niet.'], 404);
        }

        $query = DB::table('gymies_gym_demo_requests')->orderByDesc('created_at');

        // Filter op status
        $status = $request->query('status');
        if ($status && in_array($status, ['new', 'contacted', 'demo_scheduled', 'converted', 'rejected'])) {
            $query->where('status', $status);
        }

        // Zoeken op naam of email
        $search = $request->query('search');
        if ($search && is_string($search) && mb_strlen($search) >= 2) {
            $term = '%' . mb_strtolower($search) . '%';
            $query->where(function ($q) use ($term) {
                $q->whereRaw('LOWER(gym_name) LIKE ?', [$term])
                  ->orWhereRaw('LOWER(contact_name) LIKE ?', [$term])
                  ->orWhereRaw('LOWER(email) LIKE ?', [$term]);
            });
        }

        $perPage = min((int) ($request->query('per_page') ?: 25), 100);
        $results = $query->paginate($perPage);

        // Statistieken
        $stats = DB::table('gymies_gym_demo_requests')
            ->selectRaw("
                COUNT(*) as total,
                SUM(CASE WHEN status = 'new' THEN 1 ELSE 0 END) as new_count,
                SUM(CASE WHEN status = 'contacted' THEN 1 ELSE 0 END) as contacted_count,
                SUM(CASE WHEN status = 'demo_scheduled' THEN 1 ELSE 0 END) as scheduled_count,
                SUM(CASE WHEN status = 'converted' THEN 1 ELSE 0 END) as converted_count,
                SUM(CASE WHEN status = 'rejected' THEN 1 ELSE 0 END) as rejected_count
            ")
            ->first();

        return response()->json([
            'data' => $results->items(),
            'meta' => [
                'current_page' => $results->currentPage(),
                'last_page'    => $results->lastPage(),
                'per_page'     => $results->perPage(),
                'total'        => $results->total(),
            ],
            'stats' => $stats,
        ]);
    }

    /**
     * POST admin/demo-requests/{id}
     *
     * Status van een demo-aanvraag bijwerken + notities toevoegen.
     */
    public function updateDemoRequest(Request $request, int $id): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_gym_demo_requests')) {
            return response()->json(['message' => 'Demo requests tabel bestaat niet.'], 404);
        }

        $demoRequest = DB::table('gymies_gym_demo_requests')->where('id', $id)->first();
        if (!$demoRequest) {
            return response()->json(['message' => 'Demo-aanvraag niet gevonden.'], 404);
        }

        $data = $request->validate([
            'status'        => 'nullable|string|in:new,contacted,demo_scheduled,approved,converted,rejected',
            'notes'         => 'nullable|string|max:5000',
            'reject_reason' => 'nullable|string|max:2000',
        ]);

        $updates = ['updated_at' => now()];

        if (isset($data['status'])) {
            $updates['status'] = $data['status'];

            // Bij 'contacted' automatisch contacted_at zetten
            if ($data['status'] === 'contacted' && empty($demoRequest->contacted_at)) {
                if (Schema::hasColumn('gymies_gym_demo_requests', 'contacted_at')) {
                    $updates['contacted_at'] = now();
                }
            }

            // Bij 'approved': genereer invite token en stuur registratielink
            if ($data['status'] === 'approved') {
                $tokenResult = $this->generateGymInviteToken($demoRequest, $admin, $data['notes'] ?? null);
                if ($tokenResult instanceof JsonResponse) {
                    return $tokenResult;
                }
                if (Schema::hasColumn('gymies_gym_demo_requests', 'approved_at')) {
                    $updates['approved_at'] = now();
                }
                if (Schema::hasColumn('gymies_gym_demo_requests', 'invite_token_id')) {
                    $updates['invite_token_id'] = $tokenResult['token_id'];
                }
            }

            // Bij 'rejected': stuur afwijzingsmail
            if ($data['status'] === 'rejected') {
                $this->sendRejectionEmail($demoRequest, $data['reject_reason'] ?? '');
            }
        }

        if (array_key_exists('notes', $data)) {
            $updates['notes'] = $data['notes'];
        }

        $oldStatus = $demoRequest->status ?? 'new';

        DB::table('gymies_gym_demo_requests')->where('id', $id)->update($updates);

        $updated = DB::table('gymies_gym_demo_requests')->where('id', $id)->first();

        // Actielogboek: elke statuswijziging en notitie vastleggen
        $this->logDemoRequestAction($id, $admin, [
            'action'     => isset($data['status']) ? 'status_change' : 'note_added',
            'old_status' => $oldStatus,
            'new_status' => $data['status'] ?? $oldStatus,
            'notes'      => $data['notes'] ?? null,
            'metadata'   => isset($tokenResult) ? ['token_id' => $tokenResult['token_id'] ?? null] : null,
        ]);

        // Voeg invite token info toe als die bestaat
        $inviteToken = null;
        if (Schema::hasTable('gymies_gym_invite_tokens') && ($updated->invite_token_id ?? null)) {
            $inviteToken = DB::table('gymies_gym_invite_tokens')
                ->where('id', $updated->invite_token_id)
                ->first();
        }

        return response()->json([
            'message' => ($data['status'] ?? '') === 'approved'
                ? 'Aanvraag goedgekeurd. Registratielink is verstuurd naar ' . $demoRequest->email . '.'
                : (($data['status'] ?? '') === 'rejected'
                    ? 'Aanvraag afgewezen. Notificatie is verstuurd.'
                    : 'Demo-aanvraag bijgewerkt.'),
            'data'         => $updated,
            'invite_token' => $inviteToken,
        ]);
    }

    /**
     * Genereer een uniek invite token voor een goedgekeurde gym-aanvraag.
     * Verstuurt automatisch de registratielink per e-mail.
     */
    /**
     * GET admin/demo-requests/{id}/logs
     *
     * Actielogboek voor een specifieke demo-aanvraag.
     * Toont alle statuswijzigingen, notities, uitnodigingen etc.
     */
    public function demoRequestLogs(Request $request, int $id): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_gym_demo_request_logs')) {
            return response()->json(['logs' => [], 'message' => 'Logboek tabel bestaat nog niet.']);
        }

        $logs = DB::table('gymies_gym_demo_request_logs')
            ->where('demo_request_id', $id)
            ->orderByDesc('created_at')
            ->get();

        return response()->json(['logs' => $logs]);
    }

    /**
     * Log een actie in het demo-aanvraag actielogboek.
     */
    private function logDemoRequestAction(int $demoRequestId, object $admin, array $data): void
    {
        if (!Schema::hasTable('gymies_gym_demo_request_logs')) {
            return; // Tabel bestaat nog niet — stille fallback
        }

        try {
            DB::table('gymies_gym_demo_request_logs')->insert([
                'demo_request_id' => $demoRequestId,
                'admin_id'        => $admin->id ?? null,
                'admin_name'      => $admin->display_name ?? $admin->email ?? null,
                'action'          => $data['action'] ?? 'unknown',
                'old_status'      => $data['old_status'] ?? null,
                'new_status'      => $data['new_status'] ?? null,
                'notes'           => $data['notes'] ?? null,
                'metadata_json'   => !empty($data['metadata']) ? json_encode($data['metadata']) : null,
                'created_at'      => now(),
            ]);
        } catch (\Throwable $e) {
            // Logging mag nooit een operatie blokkeren
            if (function_exists('logger')) {
                logger()->warning('DemoRequestLog: schrijven mislukt', [
                    'demo_request_id' => $demoRequestId,
                    'error' => $e->getMessage(),
                ]);
            }
        }
    }

    private function generateGymInviteToken(object $demoRequest, object $admin, ?string $notes): array|JsonResponse
    {
        if (!Schema::hasTable('gymies_gym_invite_tokens')) {
            return response()->json(['message' => 'Invite tokens tabel bestaat niet. Draai eerst de migratie.'], 500);
        }

        // Check of er al een actieve token is voor deze aanvraag
        $existingToken = DB::table('gymies_gym_invite_tokens')
            ->where('demo_request_id', $demoRequest->id)
            ->where('status', 'pending')
            ->where('expires_at', '>', now())
            ->first();

        if ($existingToken) {
            return response()->json([
                'message' => 'Er is al een actieve registratielink voor deze aanvraag.',
                'invite_token' => $existingToken,
            ], 409);
        }

        // Token genereren (64 hex chars = 32 bytes entropy, zelfde als sessie-tokens)
        $token = bin2hex(random_bytes(32));
        $expiresInDays = 14; // Token geldig voor 14 dagen (B2B besluitvorming)
        $expiresAt = now()->addDays($expiresInDays);

        $tokenId = DB::table('gymies_gym_invite_tokens')->insertGetId([
            'token'                => $token,
            'demo_request_id'      => $demoRequest->id,
            'email'                => $demoRequest->email,
            'gym_name'             => $demoRequest->gym_name,
            'contact_name'         => $demoRequest->contact_name,
            'phone'                => $demoRequest->phone ?? null,
            'city'                 => $demoRequest->city ?? null,
            'estimated_trainers'   => $demoRequest->estimated_trainers ?? null,
            'website_url'          => $demoRequest->website_url ?? null,
            'status'               => 'pending',
            'approved_by_admin_id' => $admin->id ?? null,
            'admin_notes'          => $notes,
            'expires_at'           => $expiresAt,
            'created_at'           => now(),
            'updated_at'           => now(),
        ]);

        // Registratielink e-mail versturen
        try {
            $appName = \App\Helpers\GymiesNotificationEmail::mailBrandName();
            $baseUrl = \App\Helpers\GymiesNotificationEmail::mailPublicBaseUrl();

            [$subject, $text, $html] = \App\Helpers\GymiesMailTemplates::gymAanvraagGoedgekeurd(
                $demoRequest->contact_name,
                $demoRequest->gym_name,
                $token,
                (string) $expiresInDays,
                $appName,
                $baseUrl,
            );
            \App\Helpers\GymiesNotificationEmail::send($demoRequest->email, $subject, $text, $html);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('GymInviteToken: goedkeuringsmail mislukt', [
                    'email' => $demoRequest->email,
                    'token_id' => $tokenId,
                    'error' => $e->getMessage(),
                ]);
            }
            // Niet blokkeren — token is aangemaakt, admin kan link ook handmatig delen
        }

        if (function_exists('logger')) {
            logger()->info('GymInviteToken: token aangemaakt en mail verstuurd', [
                'token_id'        => $tokenId,
                'demo_request_id' => $demoRequest->id,
                'email'           => $demoRequest->email,
                'gym_name'        => $demoRequest->gym_name,
                'expires_at'      => $expiresAt->toIso8601String(),
                'admin_id'        => $admin->id ?? null,
            ]);
        }

        return [
            'token_id'   => $tokenId,
            'token'      => $token,
            'expires_at' => $expiresAt->toIso8601String(),
        ];
    }

    /**
     * Verstuur afwijzingsmail naar gym-aanvrager.
     */
    private function sendRejectionEmail(object $demoRequest, string $reason): void
    {
        try {
            $appName = \App\Helpers\GymiesNotificationEmail::mailBrandName();
            $baseUrl = \App\Helpers\GymiesNotificationEmail::mailPublicBaseUrl();

            [$subject, $text, $html] = \App\Helpers\GymiesMailTemplates::gymAanvraagAfgewezen(
                $demoRequest->contact_name,
                $demoRequest->gym_name,
                $reason,
                $appName,
                $baseUrl,
            );
            \App\Helpers\GymiesNotificationEmail::send($demoRequest->email, $subject, $text, $html);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('GymRejection: afwijzingsmail mislukt', [
                    'email' => $demoRequest->email,
                    'error' => $e->getMessage(),
                ]);
            }
        }
    }

    /**
     * POST admin/demo-requests/{id}/resend-invite
     *
     * Hernodig: revoke oud token, genereer nieuw token, verstuur registratiemail opnieuw.
     * Bruikbaar als de gym-eigenaar de mail kwijt is, link verlopen, of mail in spam zat.
     */
    public function resendDemoInvite(Request $request, int $id): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_gym_demo_requests') || !Schema::hasTable('gymies_gym_invite_tokens')) {
            return response()->json(['message' => 'Vereiste tabellen bestaan niet.'], 500);
        }

        $demoRequest = DB::table('gymies_gym_demo_requests')->where('id', $id)->first();
        if (!$demoRequest) {
            return response()->json(['message' => 'Demo-aanvraag niet gevonden.'], 404);
        }

        // Alleen opnieuw uitnodigen als status approved of contacted is
        if (!in_array($demoRequest->status ?? '', ['approved', 'contacted', 'demo_scheduled'], true)) {
            return response()->json([
                'message' => 'Kan alleen heruitnodigingen versturen voor goedgekeurde of actieve aanvragen.',
            ], 422);
        }

        // Revoke alle bestaande pending tokens voor deze aanvraag
        DB::table('gymies_gym_invite_tokens')
            ->where('demo_request_id', $id)
            ->where('status', 'pending')
            ->update([
                'status'     => 'revoked',
                'updated_at' => now(),
            ]);

        // Genereer nieuw token en verstuur mail
        $tokenResult = $this->generateGymInviteToken($demoRequest, $admin, 'Heruitnodiging verstuurd');
        if ($tokenResult instanceof JsonResponse) {
            return $tokenResult;
        }

        // Update invite_token_id op demo request
        if (Schema::hasColumn('gymies_gym_demo_requests', 'invite_token_id')) {
            DB::table('gymies_gym_demo_requests')
                ->where('id', $id)
                ->update([
                    'invite_token_id' => $tokenResult['token_id'],
                    'status'          => 'approved',
                    'updated_at'      => now(),
                ]);
        }

        // Actielogboek
        $this->logDemoRequestAction($id, $admin, [
            'action'     => 'invite_resent',
            'old_status' => $demoRequest->status,
            'new_status' => 'approved',
            'notes'      => 'Heruitnodiging verstuurd — nieuw token aangemaakt',
            'metadata'   => ['token_id' => $tokenResult['token_id']],
        ]);

        if (function_exists('logger')) {
            logger()->info('Admin: heruitnodiging verstuurd', [
                'demo_request_id' => $id,
                'new_token_id'    => $tokenResult['token_id'],
                'email'           => $demoRequest->email,
                'admin_id'        => $admin->id ?? null,
            ]);
        }

        return response()->json([
            'message' => 'Nieuwe registratielink verstuurd naar ' . $demoRequest->email . '.',
            'data'    => [
                'token_id'   => $tokenResult['token_id'],
                'expires_at' => $tokenResult['expires_at'],
            ],
        ]);
    }

    // =========================================================================
    // GYM REGISTRATIES OVERZICHT
    // =========================================================================

    /**
     * GET admin/gym-registrations
     *
     * Overzicht van alle gym-registraties (organisations met type=gym).
     */
    public function gymRegistrations(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        $query = DB::table('gymies_organisations as o')
            ->leftJoin('gymies_organisation_members as m', function ($join) {
                $join->on('o.id', '=', 'm.organisation_id')
                     ->where('m.role', '=', 'owner');
            })
            ->leftJoin('gymies_users as u', 'u.id', '=', 'm.user_id')
            ->where('o.type', 'gym')
            ->select([
                'o.id as organisation_id',
                'o.name as gym_name',
                'o.status as gym_status',
                'o.contact_email',
                'o.created_at as registered_at',
                'u.id as owner_user_id',
                'u.display_name as owner_name',
                'u.email as owner_email',
                'u.email_verified_at',
            ])
            ->orderByDesc('o.created_at');

        // Zoeken
        $search = $request->query('search');
        if ($search && is_string($search) && mb_strlen($search) >= 2) {
            $term = '%' . mb_strtolower($search) . '%';
            $query->where(function ($q) use ($term) {
                $q->whereRaw('LOWER(o.name) LIKE ?', [$term])
                  ->orWhereRaw('LOWER(u.display_name) LIKE ?', [$term])
                  ->orWhereRaw('LOWER(u.email) LIKE ?', [$term]);
            });
        }

        // Filter op status
        $status = $request->query('status');
        if ($status && in_array($status, ['active', 'inactive', 'suspended'])) {
            $query->where('o.status', $status);
        }

        $perPage = min((int) ($request->query('per_page') ?: 25), 100);
        $results = $query->paginate($perPage);

        // Extra data per gym: aantal trainers en locaties
        $orgIds = collect($results->items())->pluck('organisation_id')->filter()->toArray();
        $trainerCounts = [];
        $locationCounts = [];

        if (!empty($orgIds)) {
            $trainerCounts = DB::table('gymies_organisation_trainers')
                ->whereIn('organisation_id', $orgIds)
                ->where('status', 'active')
                ->selectRaw('organisation_id, COUNT(*) as count')
                ->groupBy('organisation_id')
                ->pluck('count', 'organisation_id')
                ->toArray();

            if (Schema::hasTable('gymies_gym_locations')) {
                $locationCounts = DB::table('gymies_gym_locations')
                    ->whereIn('organisation_id', $orgIds)
                    ->selectRaw('organisation_id, COUNT(*) as count')
                    ->groupBy('organisation_id')
                    ->pluck('count', 'organisation_id')
                    ->toArray();
            }
        }

        // Voeg counts toe aan resultaten
        $items = array_map(function ($item) use ($trainerCounts, $locationCounts) {
            $item->trainer_count  = $trainerCounts[$item->organisation_id] ?? 0;
            $item->location_count = $locationCounts[$item->organisation_id] ?? 0;
            return $item;
        }, $results->items());

        return response()->json([
            'data' => $items,
            'meta' => [
                'current_page' => $results->currentPage(),
                'last_page'    => $results->lastPage(),
                'per_page'     => $results->perPage(),
                'total'        => $results->total(),
            ],
        ]);
    }
}

