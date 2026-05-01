<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trainer Client Management: methods for handling client progress, dossiers, messaging,
 * session notes, and client relationships.
 */
trait TrainerClientsTrait
{
    /**
     * Transformation Log: lijst progressie voor één klant (alleen als er boeking met trainer is).
     */
    public function clientProgressIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant.'], 422);
        }
        $hasRelation = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->exists();
        if (!$hasRelation) {
            return response()->json(['message' => 'Geen relatie met deze klant.'], 403);
        }
        if (!Schema::hasTable('gymies_client_progress')) {
            return response()->json([
                'data' => [],
                'charts_available' => false,
                'upgrade_hint' => 'Upgrade naar Elite om grafieken uit progressiedata te genereren.',
            ]);
        }
        $rows = DB::table('gymies_client_progress')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->orderByDesc('created_at')
            ->limit(200)
            ->get();
        $plan = \App\Helpers\GymiesPlanManager::trainerPlanSlug($trainerId);
        $chartsAvailable = $plan === 'studio'; // elite valt onder studio in slug

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'type' => (string) $r->type,
            'value' => (string) $r->value,
            'note' => $r->note !== null ? (string) $r->note : null,
            'is_private' => (int) ($r->is_private ?? 0) === 1,
            'created_at' => $r->created_at,
        ])->all();

        return response()->json([
            'data' => $data,
            'charts_available' => $chartsAvailable,
            'upgrade_hint' => $chartsAvailable
                ? null
                : 'Wil je grafieken genereren van deze data voor je klant? Upgrade naar Elite.',
        ]);
    }

    /**
     * Transformation Log: nieuwe meting toevoegen.
     */
    public function clientProgressStore(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant.'], 422);
        }
        $hasRelation = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->exists();
        if (!$hasRelation) {
            return response()->json(['message' => 'Geen relatie met deze klant.'], 403);
        }
        if (!Schema::hasTable('gymies_client_progress')) {
            \App\Helpers\GymiesSchemaEnsure::clientProgressTable();
        }
        if (!Schema::hasTable('gymies_client_progress')) {
            return response()->json(['message' => 'Progressie-tabel ontbreekt. Voer alter_gymies_client_progress.sql uit.'], 503);
        }
        $request->validate([
            'type' => 'required|string|in:' . implode(',', self::PROGRESS_TYPES),
            'value' => 'required|string|max:2000',
            'note' => 'nullable|string|max:500',
            'is_private' => 'nullable|boolean',
        ]);
        $type = (string) $request->input('type');
        $value = trim((string) $request->input('value'));
        $note = trim((string) ($request->input('note') ?? ''));
        $isPrivate = $request->boolean('is_private', false);
        // is_private als Elite-feature: alleen studio/elite mag opslaan met private
        $plan = \App\Helpers\GymiesPlanManager::trainerPlanSlug($trainerId);
        if ($isPrivate && $plan !== 'studio') {
            $isPrivate = false;
        }

        $id = DB::table('gymies_client_progress')->insertGetId([
            'client_user_id' => $clientId,
            'trainer_user_id' => $trainerId,
            'type' => $type,
            'value' => $value,
            'note' => $note !== '' ? $note : null,
            'is_private' => $isPrivate ? 1 : 0,
            'created_at' => now(),
        ]);

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'type' => $type,
                'value' => $value,
                'note' => $note !== '' ? $note : null,
                'is_private' => $isPrivate,
            ],
        ], 201);
    }

    /**
     * Klantenbestand: alle klanten met minstens één boeking bij deze trainer.
     * Zoek op naam/e-mail; filter op datum: session_date (YYYY-MM-DD) = klanten die op die datum hebben getraind.
     */
    public function clientsIndex(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $query = trim((string) $request->query('query', ''));
        $sessionDate = trim((string) $request->query('session_date', ''));

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }

        $clients = DB::table('gymies_bookings as b')
            ->join('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->where('b.trainer_user_id', $trainerId)
            ->when($query !== '', function ($q) use ($query): void {
                $q->where(function ($nested) use ($query): void {
                    $nested->where('c.display_name', 'like', '%' . $query . '%')
                        ->orWhere('c.email', 'like', '%' . $query . '%');
                });
            })
            ->when($sessionDate !== '', function ($q) use ($sessionDate, $trainerId): void {
                $q->whereIn('b.client_user_id', function ($sub) use ($sessionDate, $trainerId): void {
                    $sub->select('client_user_id')
                        ->from('gymies_bookings')
                        ->where('trainer_user_id', $trainerId)
                        ->whereNotNull('scheduled_at')
                        ->whereRaw('DATE(scheduled_at) = ?', [$sessionDate]);
                });
            })
            ->groupBy('b.client_user_id', 'c.display_name', 'c.email')
            ->selectRaw('b.client_user_id')
            ->selectRaw('COALESCE(NULLIF(TRIM(c.display_name), ""), c.email, "Klant") as client_name')
            ->selectRaw('c.email as client_email')
            ->selectRaw('COUNT(*) as bookings_count')
            ->selectRaw('COALESCE(SUM(CASE WHEN b.status IN ("confirmed","completed","no_show") THEN COALESCE(b.amount_cents, 0) ELSE 0 END), 0) as gross_cents')
            ->selectRaw('MAX(b.scheduled_at) as last_booking_at')
            ->orderByDesc('last_booking_at')
            ->limit(500)
            ->get();

        return response()->json([
            'data' => $clients->map(fn ($c) => [
                'client_user_id' => (string) $c->client_user_id,
                'client_name' => (string) $c->client_name,
                'client_email' => (string) ($c->client_email ?? ''),
                'bookings_count' => (int) $c->bookings_count,
                'gross_cents' => (int) $c->gross_cents,
                'last_booking_at' => $c->last_booking_at,
            ])->all(),
        ]);
    }

    /**
     * CRM: klanten met resterende strippenkaart-sessies bij deze trainer maar X dagen niet geboekt.
     * Bron: gymies_packages + boekingen met package_id (geen wallet).
     */
    public function sleepingClients(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $daysInactive = min(max((int) $request->query('days_inactive', 14), 1), 365);
        // Minimaal aantal resterende sessies (strippenkaart) om mee te nemen
        $minRemaining = min(max((int) $request->query('min_remaining_sessions', 1), 1), 1000);
        $cutoff = now()->subDays($daysInactive)->toDateTimeString();

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }
        if (!Schema::hasTable('gymies_packages') || !Schema::hasColumn('gymies_bookings', 'package_id')) {
            return response()->json(['data' => []]);
        }

        $clientIds = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->distinct()
            ->pluck('client_user_id')
            ->filter()
            ->unique()
            ->values()
            ->all();
        if ($clientIds === []) {
            return response()->json(['data' => []]);
        }

        $packages = DB::table('gymies_packages')
            ->where('trainer_user_id', $trainerId)
            ->get(['id', 'sessions_count', 'name']);
        if ($packages->isEmpty()) {
            return response()->json(['data' => []]);
        }

        $out = [];
        foreach ($clientIds as $clientUserId) {
            $remainingTotal = 0;
            foreach ($packages as $pkg) {
                $sessionsCount = (int) ($pkg->sessions_count ?? 0);
                if ($sessionsCount <= 0) {
                    continue;
                }
                $used = (int) DB::table('gymies_bookings')
                    ->where('client_user_id', $clientUserId)
                    ->where('package_id', (int) $pkg->id)
                    ->whereNotIn('status', ['cancelled'])
                    ->count();
                $remainingTotal += max(0, $sessionsCount - $used);
            }
            if ($remainingTotal < $minRemaining) {
                continue;
            }
            $lastBooking = DB::table('gymies_bookings')
                ->where('client_user_id', $clientUserId)
                ->where('trainer_user_id', $trainerId)
                ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                ->orderByDesc('scheduled_at')
                ->value('scheduled_at');
            if ($lastBooking !== null && (string) $lastBooking >= $cutoff) {
                continue;
            }
            $u = DB::table('gymies_users')->where('id', $clientUserId)->first();
            $out[] = [
                'client_user_id' => (string) $clientUserId,
                'display_name' => $u ? (string) ($u->display_name ?? '') : '',
                'email' => $u ? (string) ($u->email ?? '') : '',
                'sessions_remaining_total' => $remainingTotal,
                // Legacy: CRM gebruikte balance_cents — niet meer wallet; 0 = toon sessies
                'balance_cents' => 0,
                'last_booking_at' => $lastBooking,
            ];
        }
        usort($out, static fn ($a, $b) => ($b['sessions_remaining_total'] <=> $a['sessions_remaining_total']));

        return response()->json(['data' => array_slice($out, 0, 100)]);
    }

    /**
     * CRM dossier: GET — lees notities en metadata.
     */
    public function clientDossierGet(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant'], 422);
        }
        if (!$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            \App\Helpers\GymiesSchemaEnsure::clientDossierTableAndShareColumns();
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            return response()->json([
                'data' => [
                    'internal_notes' => null,
                    'medical_background' => null,
                    'goals_long_term' => null,
                    'client_facing_summary' => null,
                    'shared_with_client' => false,
                    'shared_with_client_at' => null,
                    'updated_at' => null,
                ],
            ]);
        }
        $row = DB::table('gymies_client_dossier')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->first();
        if ($row === null) {
            return response()->json([
                'data' => [
                    'internal_notes' => null,
                    'medical_background' => null,
                    'goals_long_term' => null,
                    'client_facing_summary' => null,
                    'shared_with_client' => false,
                    'shared_with_client_at' => null,
                    'updated_at' => null,
                ],
            ]);
        }

        $sharedAt = property_exists($row, 'shared_with_client_at') ? $row->shared_with_client_at : null;

        return response()->json([
            'data' => [
                'internal_notes' => $row->internal_notes ?? null,
                'medical_background' => $row->medical_background ?? null,
                'goals_long_term' => $row->goals_long_term ?? null,
                'client_facing_summary' => property_exists($row, 'client_facing_summary') ? ($row->client_facing_summary ?? null) : null,
                'shared_with_client' => $sharedAt !== null && trim((string) $sharedAt) !== '' && !str_starts_with((string) $sharedAt, '0000-00-00'),
                'shared_with_client_at' => $sharedAt,
                'updated_at' => $row->updated_at ?? null,
            ],
        ]);
    }

    /**
     * CRM dossier: PUT — upsert notities (max lengte beperkt tegen abuse).
     */
    public function clientDossierPut(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant'], 422);
        }
        if (!$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            \App\Helpers\GymiesSchemaEnsure::clientDossierTableAndShareColumns();
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            return response()->json(['message' => 'Dossier nog niet beschikbaar — migratie uitvoeren alter_gymies_client_dossier.sql'], 503);
        }

        $request->validate([
            'internal_notes' => 'nullable|string|max:65535',
            'medical_background' => 'nullable|string|max:65535',
            'goals_long_term' => 'nullable|string|max:65535',
            'client_facing_summary' => 'nullable|string|max:65535',
            'shared_with_client' => 'nullable|boolean',
        ]);

        $now = now();
        $existing = DB::table('gymies_client_dossier')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->first();
        $payload = [
            'trainer_user_id' => $trainerId,
            'client_user_id' => $clientId,
            'internal_notes' => $request->has('internal_notes') ? $request->input('internal_notes') : ($existing?->internal_notes ?? null),
            'medical_background' => $request->has('medical_background') ? $request->input('medical_background') : ($existing?->medical_background ?? null),
            'goals_long_term' => $request->has('goals_long_term') ? $request->input('goals_long_term') : ($existing?->goals_long_term ?? null),
            'updated_at' => $now,
        ];
        if (Schema::hasColumn('gymies_client_dossier', 'client_facing_summary') && $request->has('client_facing_summary')) {
            $payload['client_facing_summary'] = $request->input('client_facing_summary');
        }
        if (Schema::hasColumn('gymies_client_dossier', 'shared_with_client_at')) {
            if ($request->has('shared_with_client')) {
                $payload['shared_with_client_at'] = $request->boolean('shared_with_client') ? $now : null;
            }
        }
        DB::table('gymies_client_dossier')->updateOrInsert(
            ['trainer_user_id' => $trainerId, 'client_user_id' => $clientId],
            $payload
        );

        return response()->json(['data' => ['ok' => true]]);
    }

    /**
     * Client Dossier Summary: engagement metrics and risk flags.
     */
    public function clientDossierSummary(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }

        $attendanceRate = 0.0;
        $streakDays = 0;
        $riskFlags = [];
        $nextBestAction = 'log_next_session_entry';

        if (Schema::hasTable('gymies_client_session_entries')) {
            $entries = DB::table('gymies_client_session_entries')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereNull('deleted_at')
                ->orderByDesc('session_at')
                ->get(['session_at', 'attendance_status']);

            $totalAttendanceTracked = $entries
                ->whereIn('attendance_status', ['attended', 'no_show', 'cancelled', 'unknown'])
                ->count();
            $attended = $entries->where('attendance_status', 'attended')->count();
            $attendanceRate = $totalAttendanceTracked > 0 ? round(($attended / $totalAttendanceTracked) * 100, 1) : 0.0;

            $attendedDates = $entries
                ->where('attendance_status', 'attended')
                ->map(fn ($e) => substr((string) $e->session_at, 0, 10))
                ->filter()
                ->unique()
                ->values()
                ->all();
            if (!empty($attendedDates)) {
                $streakDays = $this->calculateDateStreakDays($attendedDates);
            }

            $latestAt = $entries->first()->session_at ?? null;
            if ($latestAt !== null && \Carbon\Carbon::parse((string) $latestAt)->diffInDays(now()) > 14) {
                $riskFlags[] = 'no_recent_session_entry';
            }
            if ($totalAttendanceTracked >= 3 && $attendanceRate < 60.0) {
                $riskFlags[] = 'low_attendance_rate';
            }
        }

        $goalsTotal = 0;
        $goalsDone = 0;
        if (Schema::hasTable('gymies_client_goals')) {
            $goals = DB::table('gymies_client_goals')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereNull('deleted_at')
                ->get(['status']);
            $goalsTotal = $goals->count();
            $goalsDone = $goals->where('status', 'done')->count();
            if ($goalsTotal === 0) {
                $riskFlags[] = 'no_active_goals';
            }
        }

        if (in_array('low_attendance_rate', $riskFlags, true)) {
            $nextBestAction = 'schedule_reengagement_message';
        } elseif (in_array('no_active_goals', $riskFlags, true)) {
            $nextBestAction = 'create_first_goal';
        } elseif ($streakDays >= 7) {
            $nextBestAction = 'raise_goal_difficulty';
        }

        return response()->json([
            'data' => [
                'attendance_rate' => $attendanceRate,
                'streak_days' => $streakDays,
                'goals_done' => $goalsDone,
                'goals_total' => $goalsTotal,
                'risk_flags' => array_values(array_unique($riskFlags)),
                'next_best_action' => $nextBestAction,
            ],
        ]);
    }

    /**
     * Bulk in-app bericht naar geselecteerde klanten (queue). Alleen klanten met boeking bij deze trainer.
     * Max 25 per request. Payload message wordt in notificatie getoond (trainer_personal_nudge).
     */
    public function bulkMessageClients(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!\App\Helpers\GymiesSchemaEnsure::notificationQueueTable()) {
            return response()->json(['message' => 'Notificatie-queue niet beschikbaar'], 503);
        }

        $request->validate([
            'client_user_ids' => 'required|array|max:25',
            'client_user_ids.*' => 'required|string',
            'message' => 'required|string|min:1|max:2000',
        ]);
        $message = trim((string) $request->input('message'));
        if ($message === '') {
            return response()->json(['message' => 'Bericht mag niet leeg zijn'], 422);
        }

        $trainerName = (string) (DB::table('gymies_users')->where('id', $trainerId)->value('display_name') ?? 'Je trainer');
        $now = now();
        $queued = 0;
        foreach ($request->input('client_user_ids') as $cid) {
            $clientId = (int) $cid;
            if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
                continue;
            }
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $clientId,
                'channel' => 'in_app',
                'event_type' => 'trainer_personal_nudge',
                'payload_json' => json_encode([
                    'trainer_user_id' => (string) $trainerId,
                    'trainer_name' => $trainerName,
                    'message' => $message,
                    'action_url' => '/berichten',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => $now,
                'created_at' => $now,
            ]);
            $queued++;
        }

        return response()->json(['data' => ['queued' => $queued]]);
    }

    /**
     * Stuur aanbieding/promo naar alle klanten die jou als favoriet hebben.
     * POST /trainer/promo-to-favorites { message, discount_code? }
     */
    public function promoToFavorites(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!\App\Helpers\GymiesSchemaEnsure::notificationQueueTable()) {
            return response()->json(['message' => 'Notificatie-queue niet beschikbaar'], 503);
        }
        if (!Schema::hasTable('gymies_favorites')) {
            return response()->json(['message' => 'Favorieten nog niet beschikbaar.'], 503);
        }

        $request->validate([
            'message' => 'required|string|min:1|max:2000',
            'discount_code' => 'nullable|string|max:64',
        ]);
        $message = trim((string) $request->input('message'));
        $discountCode = trim((string) ($request->input('discount_code') ?? ''));
        if ($message === '') {
            return response()->json(['message' => 'Bericht mag niet leeg zijn'], 422);
        }

        $trainerName = (string) (DB::table('gymies_users')->where('id', $trainerId)->value('display_name') ?? 'Je trainer');
        $clientIds = DB::table('gymies_favorites')
            ->where('trainer_user_id', $trainerId)
            ->pluck('client_user_id')
            ->map(fn ($id) => (int) $id)
            ->all();

        $now = now();
        $queued = 0;
        foreach ($clientIds as $clientId) {
            $payload = [
                'trainer_user_id' => (string) $trainerId,
                'trainer_name' => $trainerName,
                'message' => $message,
                'action_url' => "/boeken?trainerId={$trainerId}",
            ];
            if ($discountCode !== '') {
                $payload['discount_code'] = $discountCode;
            }
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $clientId,
                'channel' => 'in_app',
                'event_type' => 'trainer_promo_to_favorites',
                'payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE),
                'scheduled_for' => $now,
                'created_at' => $now,
            ]);
            $queued++;
        }

        return response()->json(['data' => ['queued' => $queued, 'message' => "Aanbieding verstuurd naar {$queued} favorieten."]]);
    }

    /**
     * Sessienotitie na afloop: upsert op booking_id (één note per boeking).
     */
    public function sessionNotePut(Request $request, string $bookingId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $bid = (int) $bookingId;
        if ($bid <= 0 || !Schema::hasTable('gymies_client_session_notes')) {
            return response()->json(['message' => 'Niet beschikbaar'], 503);
        }
        $booking = DB::table('gymies_bookings')->where('id', $bid)->first();
        if ($booking === null || (int) $booking->trainer_user_id !== $trainerId) {
            return response()->json(['message' => 'Boeking niet gevonden'], 404);
        }
        $request->validate([
            'note' => 'required|string|min:1|max:16000',
        ]);
        $note = trim((string) $request->input('note'));
        $now = now();
        DB::table('gymies_client_session_notes')->updateOrInsert(
            ['booking_id' => $bid],
            [
                'booking_id' => $bid,
                'trainer_user_id' => $trainerId,
                'note' => $note,
                'created_at' => $now,
            ]
        );

        return response()->json(['data' => ['ok' => true]]);
    }

    /**
     * Lijst sessienotities voor klant (laatste eerst), alleen boekingen van deze trainer.
     */
    public function clientSessionNotesIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen toegang'], 403);
        }
        if (!Schema::hasTable('gymies_client_session_notes')) {
            return response()->json(['data' => []]);
        }
        $bookingIds = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->pluck('id')
            ->all();
        if ($bookingIds === []) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_client_session_notes as n')
            ->join('gymies_bookings as b', 'b.id', '=', 'n.booking_id')
            ->whereIn('n.booking_id', $bookingIds)
            ->orderByDesc('b.scheduled_at')
            ->limit(100)
            ->get(['n.booking_id', 'n.note', 'n.created_at', 'b.scheduled_at']);

        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'booking_id' => (string) $r->booking_id,
                'scheduled_at' => $r->scheduled_at ?? null,
                'note' => $r->note ?? '',
                'created_at' => $r->created_at ?? null,
            ];
        }

        return response()->json(['data' => $out]);
    }

    /**
     * Private helper: check if trainer has a client relation (booking exists).
     */
    private function trainerHasClientRelation(int $trainerId, int $clientId): bool
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return false;
        }

        return DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->exists();
    }

    /**
     * Private helper: get display name for a client by user ID.
     */
    private function displayNameForClient(int $clientUserId): string
    {
        $u = DB::table('gymies_users')->where('id', $clientUserId)->first(['display_name', 'name', 'email']);
        if (!$u) {
            return 'Klant';
        }
        $name = trim((string) ($u->display_name ?? $u->name ?? ''));
        if ($name !== '') {
            return $name;
        }
        $email = trim((string) ($u->email ?? ''));
        return $email !== '' ? $email : 'Klant';
    }

    /**
     * Private helper: get display name from a user row object.
     */
    private function displayNameFromUserRow(object $u): string
    {
        $name = trim((string) ($u->display_name ?? ''));
        if ($name !== '') {
            return $name;
        }
        $email = trim((string) ($u->email ?? ''));
        return $email !== '' ? $email : 'Klant';
    }
}
