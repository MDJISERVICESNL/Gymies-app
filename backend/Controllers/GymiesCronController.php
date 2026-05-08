<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;

/**
 * Cron-endpoints voor Ghosting-preventie e.d.
 * Beveiligd met ?key= of header X-Cron-Key (config: gymies.cron_key of GYMIES_CRON_KEY).
 */
final class GymiesCronController extends Controller
{
    /**
     * Annuleer pending boekingen waar de trainer niet binnen X uur heeft gereageerd.
     * Stuur de klant een melding (booking_expired_trainer_no_response_for_client).
     * Query: hours=48 (default). Key verplicht.
     */
    public function expirePendingBookings(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $hours = (int) ($request->input('hours') ?? 48);
        if ($hours < 1 || $hours > 168) {
            $hours = 48;
        }

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['expired' => 0, 'message' => 'Geen boekingen-tabel']);
        }

        $cutoff = now()->subHours($hours);

        $rows = DB::table('gymies_bookings')
            ->where('status', 'pending')
            ->where('created_at', '<', $cutoff)
            ->limit(500)
            ->get(['id', 'client_user_id', 'trainer_user_id', 'created_at']);

        if ($rows->isEmpty()) {
            return response()->json(['expired' => 0, 'cutoff' => $cutoff->toIso8601String()]);
        }

        $now = now();
        if (!Schema::hasTable('gymies_notification_queue')) {
            foreach ($rows as $b) {
                DB::table('gymies_bookings')->where('id', $b->id)->update([
                    'status' => 'cancelled',
                    'cancelled_at' => $now,
                    'cancelled_by_user_id' => null,
                    'updated_at' => $now,
                ]);
            }
            return response()->json(['expired' => $rows->count(), 'cutoff' => $cutoff->toIso8601String()]);
        }

        foreach ($rows as $b) {
            DB::table('gymies_bookings')->where('id', $b->id)->update([
                'status' => 'cancelled',
                'cancelled_at' => $now,
                'cancelled_by_user_id' => null,
                'updated_at' => $now,
            ]);
            DB::table('gymies_notification_queue')->insert([
                'user_id' => (int) $b->client_user_id,
                'channel' => 'in_app',
                'event_type' => 'booking_expired_trainer_no_response_for_client',
                'payload_json' => json_encode([
                    'booking_id' => (string) $b->id,
                    'event_type' => 'booking_expired_trainer_no_response',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => $now,
                'created_at' => $now,
            ]);
        }

        $result = ['expired' => $rows->count(), 'cutoff' => $cutoff->toIso8601String()];
        $this->logCronResult('expirePendingBookings', $result);
        return response()->json($result);
    }

    /**
     * Direct Boeken: vervalt reserved boekingen waar reserved_until is verstreken (geen betaling).
     * Aanroep: GET/POST ?key=... (zelfde key). Draai bijv. elke minuut.
     */
    public function expireReservedBookings(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_bookings') || !Schema::hasColumn('gymies_bookings', 'reserved_until')) {
            return response()->json(['expired' => 0, 'message' => 'Reserved-ondersteuning niet beschikbaar']);
        }

        $now = now();
        $rows = DB::table('gymies_bookings')
            ->where('status', 'reserved')
            ->whereNotNull('reserved_until')
            ->where('reserved_until', '<', $now)
            ->get(['id']);

        foreach ($rows as $b) {
            DB::table('gymies_bookings')->where('id', $b->id)->update([
                'status' => 'cancelled',
                'cancelled_at' => $now,
                'cancelled_by_user_id' => null,
                'reserved_until' => null,
                'updated_at' => $now,
            ]);
        }

        $result = ['expired' => $rows->count()];
        $this->logCronResult('expireReservedBookings', $result);
        return response()->json($result);
    }

    /**
     * Boeking-herinnering: in-app melding 24 uur vóór bevestigde sessie.
     * Max 1x per boeking (deduplicatie via gymies_booking_reminders_sent of payload check).
     * Aanroep: GET/POST ?key=... Draai dagelijks (bijv. 08:00).
     */
    public function bookingReminders(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_bookings') || !Schema::hasTable('gymies_notification_queue')) {
            return response()->json(['sent' => 0, 'message' => 'Tabellen ontbreken']);
        }
        $now = now();
        $from = $now->copy()->addHours(23);
        $to = $now->copy()->addHours(25);
        $rows = DB::table('gymies_bookings')
            ->where('status', 'confirmed')
            ->whereBetween('scheduled_at', [$from, $to])
            ->limit(500)
            ->get(['id', 'client_user_id', 'trainer_user_id', 'scheduled_at', 'duration_minutes']);

        // Batch: fetch all trainer names at once
        $trainerIds = $rows->pluck('trainer_user_id')->unique()->map(fn ($id) => (int) $id)->all();
        $trainerNames = DB::table('gymies_users')
            ->whereIn('id', $trainerIds)
            ->pluck('display_name', 'id');

        $sent = 0;
        foreach ($rows as $b) {
            $trainerId = (int) $b->trainer_user_id;
            $trainerName = $trainerNames->get($trainerId);
            $scheduledAt = $b->scheduled_at instanceof \DateTimeInterface
                ? $b->scheduled_at->format('Y-m-d H:i:s')
                : (string) $b->scheduled_at;
            $alreadySent = DB::table('gymies_notification_queue')
                ->where('user_id', (int) $b->client_user_id)
                ->where('event_type', 'booking_reminder_for_client')
                ->where('payload_json', 'like', '%"booking_id":"' . $b->id . '"%')
                ->exists();
            if ($alreadySent) {
                continue;
            }
            DB::table('gymies_notification_queue')->insert([
                'user_id' => (int) $b->client_user_id,
                'channel' => 'in_app',
                'event_type' => 'booking_reminder_for_client',
                'payload_json' => json_encode([
                    'booking_id' => (string) $b->id,
                    'trainer_user_id' => (string) $b->trainer_user_id,
                    'trainer_name' => $trainerName,
                    'scheduled_at' => $scheduledAt,
                    'message' => ($trainerName ?: 'Je trainer') . ' – sessie morgen. Check je QR 15 min voor aanvang.',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => $now,
                'created_at' => $now,
            ]);
            $sent++;
        }
        return response()->json(['sent' => $sent]);
    }

    /**
     * Spoed Inval: zet pending verzoeken op unassigned als expires_at verstreken en niemand accepteerde.
     * Voor backoffice-monitoring. Aanroep: GET/POST ?key=...
     */
    public function expireSpoedInval(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_spoed_inval_requests')) {
            return response()->json(['expired' => 0, 'message' => 'Spoed inval niet beschikbaar']);
        }

        $now = now();
        $updated = DB::table('gymies_spoed_inval_requests')
            ->where('status', 'pending')
            ->whereNotNull('expires_at')
            ->where('expires_at', '<', $now)
            ->update(['status' => 'unassigned', 'updated_at' => $now]);

        return response()->json(['expired' => $updated]);
    }

    /**
     * Spoed Inval batch 1: na 5 min rest van kandidaten notificeren als favorieten niet reageren.
     */
    public function spoedInvalBatch1(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $result = GymiesSpoedInvalController::processBatch1();
        return response()->json($result);
    }

    /**
     * Sessies automatisch op "Voltooid" zetten: 24 uur na het geplande einde van de sessie,
     * tenzij de klant een incident heeft gemeld (open booking_incident voor deze boeking).
     * Aanroep: GET/POST ?key=... (zelfde key als expire-pending-bookings).
     */
    public function autoCompletePastSessions(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['completed' => 0, 'message' => 'Geen boekingen-tabel']);
        }

        $now = now();
        $cutoff = $now->copy()->subHours(24);

        $query = DB::table('gymies_bookings')
            ->where('status', 'confirmed')
            ->whereRaw('DATE_ADD(scheduled_at, INTERVAL COALESCE(duration_minutes, 60) MINUTE) < ?', [$cutoff]);

        if (Schema::hasTable('gymies_admin_alerts')) {
            $bookingIdsWithOpenIncident = DB::table('gymies_admin_alerts')
                ->where('alert_type', 'booking_incident')
                ->where('entity_type', 'booking')
                ->where(function ($q) {
                    $q->whereNull('status')->orWhere('status', '!=', 'resolved');
                })
                ->pluck('entity_id')
                ->map(fn ($id) => (int) $id)
                ->unique()
                ->values()
                ->all();
            if (!empty($bookingIdsWithOpenIncident)) {
                $query->whereNotIn('id', $bookingIdsWithOpenIncident);
            }
        }

        $rows = $query->limit(500)->get(['id', 'client_user_id', 'trainer_user_id']);
        $hasMilestones = Schema::hasColumn('gymies_users', 'completed_sessions_count');
        $hasCheckinAt = Schema::hasColumn('gymies_bookings', 'check_in_at');
        $hasProBadge = Schema::hasColumn('gymies_trainer_profiles', 'is_gymies_pro');
        $milestonesAwarded = 0;
        $proBadgesAwarded = 0;

        foreach ($rows as $b) {
            DB::table('gymies_bookings')->where('id', $b->id)->update([
                'status' => 'completed',
                'updated_at' => $now,
            ]);

            // Milestone: tel voltooide sessies per klant, award credit elke 10e
            if ($hasMilestones && $hasCheckinAt) {
                $wasCheckedIn = DB::table('gymies_bookings')->where('id', $b->id)->whereNotNull('check_in_at')->exists();
                if ($wasCheckedIn) {
                    DB::table('gymies_users')->where('id', (int) $b->client_user_id)
                        ->increment('completed_sessions_count');
                    $count = (int) DB::table('gymies_users')->where('id', (int) $b->client_user_id)
                        ->value('completed_sessions_count');

                    if ($count > 0 && $count % 10 === 0) {
                        // SaaS 2.0: genereer kortingscode i.p.v. wallet credit
                        $discountCents = 500;
                        if (Schema::hasTable('gymies_promo_codes')) {
                            $code = 'MILE' . $count . '-' . strtoupper(bin2hex(random_bytes(3)));
                            $insert = [
                                'code' => $code,
                                'discount_type' => 'fixed',
                                'value_cents' => $discountCents,
                                'valid_from' => $now->toDateString(),
                                'valid_until' => $now->copy()->addMonths(3)->toDateString(),
                                'max_uses' => 1,
                                'use_count' => 0,
                                'created_at' => $now,
                            ];
                            if (Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
                                $insert['trainer_user_id'] = (int) $b->trainer_user_id;
                            }
                            DB::table('gymies_promo_codes')->insert($insert);
                        } else {
                            $code = null;
                        }
                        if (Schema::hasTable('gymies_notification_queue')) {
                            DB::table('gymies_notification_queue')->insert([
                                'user_id' => (int) $b->client_user_id,
                                'channel' => 'in_app',
                                'event_type' => 'milestone_reward',
                                'payload_json' => json_encode([
                                    'sessions_count' => $count,
                                    'reward_cents' => $discountCents,
                                    'promo_code' => $code,
                                    'message' => "Gefeliciteerd! Je {$count}e sessie. Gebruik code {$code} voor €5,- korting!",
                                ], JSON_UNESCAPED_UNICODE),
                                'scheduled_for' => $now,
                                'created_at' => $now,
                            ]);
                        }
                        $milestonesAwarded++;
                    }

                    // Update milestone tier
                    $tier = match (true) {
                        $count >= 100 => 'diamond_100',
                        $count >= 50 => 'gold_50',
                        $count >= 25 => 'silver_25',
                        $count >= 10 => 'bronze_10',
                        default => null,
                    };
                    if ($tier !== null && Schema::hasColumn('gymies_users', 'milestone_tier')) {
                        DB::table('gymies_users')->where('id', (int) $b->client_user_id)->update(['milestone_tier' => $tier]);
                    }
                }
            }

            // Trainer Pro badge: increment consecutive completed, award at 50
            if ($hasProBadge) {
                $trainerId = (int) $b->trainer_user_id;
                DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)
                    ->increment('consecutive_completed');
                $consecutive = (int) DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)
                    ->value('consecutive_completed');
                if ($consecutive >= 50) {
                    $alreadyPro = (int) DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->value('is_gymies_pro');
                    if (!$alreadyPro) {
                        DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->update([
                            'is_gymies_pro' => 1,
                            'gymies_pro_since' => $now,
                        ]);
                        if (Schema::hasTable('gymies_notification_queue')) {
                            DB::table('gymies_notification_queue')->insert([
                                'user_id' => $trainerId,
                                'channel' => 'in_app',
                                'event_type' => 'gymies_pro_badge_earned',
                                'payload_json' => json_encode([
                                    'consecutive_completed' => $consecutive,
                                    'message' => 'Je bent nu Gymies Pro! 50 sessies zonder annulering.',
                                ], JSON_UNESCAPED_UNICODE),
                                'scheduled_for' => $now,
                                'created_at' => $now,
                            ]);
                        }
                        $proBadgesAwarded++;
                    }
                }
            }
        }

        return response()->json([
            'completed' => $rows->count(),
            'milestones_awarded' => $milestonesAwarded,
            'pro_badges_awarded' => $proBadgesAwarded,
            'cutoff' => $cutoff->toIso8601String(),
        ]);
    }

    /**
     * Trainer-hygiëne (ghosting prevention): stuur e-mail naar trainers die langer dan 30 dagen
     * hun beschikbaarheid niet hebben bijgewerkt. Optioneel: zet search_rank_penalty voor lagere ranking.
     * Aanroep: GET/POST /api/gymies/cron/availability-check?key=...&days=30
     * Plan bijv. wekelijks maandag 09:00.
     */
    public function availabilityCheck(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $days = (int) ($request->input('days') ?? 30);
        if ($days < 7 || $days > 365) {
            $days = 30;
        }
        $cutoff = now()->subDays($days);

        if (!Schema::hasTable('gymies_users') || !Schema::hasTable('gymies_availability_slots')) {
            return response()->json(['mailed' => 0, 'message' => 'Tabellen ontbreken']);
        }

        $trainerIds = DB::table('gymies_users')
            ->where('role', 'trainer')
            ->pluck('id')
            ->map(fn ($id) => (int) $id)
            ->all();
        if (empty($trainerIds)) {
            return response()->json(['mailed' => 0, 'cutoff' => $cutoff->toIso8601String()]);
        }

        $lastSlotByTrainer = DB::table('gymies_availability_slots')
            ->whereIn('trainer_user_id', $trainerIds)
            ->selectRaw('trainer_user_id, MAX(updated_at) as last_at')
            ->groupBy('trainer_user_id')
            ->pluck('last_at', 'trainer_user_id');

        $inactiveTrainers = [];
        foreach ($trainerIds as $tid) {
            $lastAt = $lastSlotByTrainer[$tid] ?? null;
            if ($lastAt === null || strtotime($lastAt) < $cutoff->timestamp) {
                $inactiveTrainers[] = $tid;
            }
        }

        $users = empty($inactiveTrainers)
            ? []
            : DB::table('gymies_users')
                ->whereIn('id', $inactiveTrainers)
                ->get(['id', 'email', 'display_name']);

        $appName = \App\Helpers\GymiesNotificationEmail::mailBrandName();
        $mailed = 0;
        foreach ($users as $u) {
            $email = trim((string) ($u->email ?? ''));
            if ($email === '') {
                continue;
            }
            $name = trim((string) ($u->display_name ?? ''));
            $greeting = $name !== '' ? "Hoi {$name}," : 'Hoi,';
            $body = "{$greeting}\n\n"
                . "Het is al een tijd geleden dat je je beschikbaarheid in de app hebt bijgewerkt.\n\n"
                . "Staat je agenda nog goed? Klanten kunnen je alleen boeken als je beschikbare tijden up-to-date zijn.\n\n"
                . "Log in op de app en ga naar Beschikbaarheid om je tijden te bevestigen of aan te passen.\n\n"
                . "Met vriendelijke groet,\n{$appName}";
            try {
                Mail::raw($body, function ($message) use ($email, $appName): void {
                    $message->to($email)->subject("{$appName} – Staat je agenda nog goed?");
                });
                $mailed++;
            } catch (\Throwable $e) {
                logger()->warning('Gymies availability-check email failed', ['email' => $email, 'error' => $e->getMessage()]);
            }
            if (Schema::hasColumn('gymies_users', 'search_rank_penalty')) {
                DB::table('gymies_users')->where('id', $u->id)->update(['search_rank_penalty' => 1, 'updated_at' => now()]);
            }
        }

        return response()->json([
            'mailed' => $mailed,
            'inactive_count' => count($inactiveTrainers),
            'cutoff' => $cutoff->toIso8601String(),
        ]);
    }

    private function validateCronKey(Request $request): bool
    {
        $key = config('gymies.cron_key') ?: (getenv('GYMIES_CRON_KEY') ?: '');
        if ($key === '' || strlen($key) < 16) {
            \Log::error('GYMIES_CRON_KEY ontbreekt of is te kort (min 16 tekens). Alle cron jobs geblokkeerd.', [
                'configured_length' => strlen($key),
                'minimum_required' => 16,
            ]);
            return false;
        }
        $provided = $request->input('key') ?: $request->header('X-Cron-Key');
        if ($provided === null || $provided === '') {
            \Log::warning('Cron request zonder key', [
                'ip' => $request->ip(),
                'uri' => $request->getRequestUri(),
                'method' => $request->method(),
            ]);
            return false;
        }
        $valid = hash_equals($key, (string) $provided);
        if (!$valid) {
            \Log::warning('Cron request met ongeldige key', [
                'ip' => $request->ip(),
                'uri' => $request->getRequestUri(),
                'method' => $request->method(),
                'key_length' => strlen((string) $provided),
            ]);
        }
        return $valid;
    }

    /**
     * Log cron job result voor monitoring (storage/logs/laravel.log).
     */
    private function logCronResult(string $job, array $result): void
    {
        Log::info("Gymies cron: {$job}", $result);
    }

    /**
     * Pro-flow: refresh client health snapshots voor Pro/Studio trainers.
     * Aanroep: GET/POST ?key=... (of X-Cron-Key).
     */
    public function refreshProClientHealth(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_trainer_profiles')
            || !Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')
            || !Schema::hasTable('gymies_bookings')
            || !Schema::hasTable('gymies_trainer_client_health_snapshots')) {
            return response()->json(['refreshed' => 0, 'message' => 'Pro health snapshot tabellen ontbreken.']);
        }

        $trainerIds = DB::table('gymies_trainer_profiles')
            ->get(['user_id', 'subscription_plan'])
            ->filter(function ($r) {
                $p = strtolower(trim((string) ($r->subscription_plan ?? '')));
                return in_array($p, ['pro', 'studio', 'elite'], true);
            })
            ->pluck('user_id')
            ->map(fn ($id) => (int) $id)
            ->filter(fn ($id) => $id > 0)
            ->values()
            ->all();
        if (empty($trainerIds)) {
            return response()->json(['refreshed' => 0, 'trainers' => 0]);
        }

        $now = now();
        $rows = 0;

        // Batch: get all bookings for all pro trainers in one query
        $allBookings = DB::table('gymies_bookings')
            ->whereIn('trainer_user_id', $trainerIds)
            ->whereIn('status', ['completed', 'confirmed', 'no_show', 'cancelled'])
            ->orderByDesc('scheduled_at')
            ->get(['trainer_user_id', 'client_user_id', 'status', 'scheduled_at']);

        // Group bookings by (trainer_user_id, client_user_id) for processing
        $bookingsByKey = [];
        foreach ($allBookings as $booking) {
            $trainerId = (int) $booking->trainer_user_id;
            $clientId = (int) $booking->client_user_id;
            if ($clientId <= 0) continue;

            $key = $trainerId . '_' . $clientId;
            if (!isset($bookingsByKey[$key])) {
                $bookingsByKey[$key] = [
                    'trainer_user_id' => $trainerId,
                    'client_user_id' => $clientId,
                    'bookings' => [],
                ];
            }
            // Keep only last 20 per key
            if (count($bookingsByKey[$key]['bookings']) < 20) {
                $bookingsByKey[$key]['bookings'][] = $booking;
            }
        }

        // Process each trainer-client pair
        foreach ($bookingsByKey as $pair) {
            $trainerId = $pair['trainer_user_id'];
            $clientId = $pair['client_user_id'];
            $recent = collect($pair['bookings']);

            if ($recent->isEmpty()) {
                continue;
            }

            $tracked = $recent->whereIn('status', ['completed', 'confirmed', 'no_show', 'cancelled'])->count();
            $attended = $recent->whereIn('status', ['completed', 'confirmed'])->count();
            $noShows = $recent->where('status', 'no_show')->count();
            $cancelled = $recent->where('status', 'cancelled')->count();
            $attendanceRate = $tracked > 0 ? ($attended / $tracked) : 0.0;
            $noShowRate = $tracked > 0 ? ($noShows / $tracked) : 0.0;
            $cancelRate = $tracked > 0 ? ($cancelled / $tracked) : 0.0;
            $lastAt = $recent
                ->whereIn('status', ['completed', 'confirmed', 'no_show'])
                ->first()?->scheduled_at ?? null;
            $recencyDays = $lastAt ? \Carbon\Carbon::parse((string) $lastAt)->diffInDays($now) : 99;

            $signals = [];
            $score = 100;
            $score -= (int) round($noShowRate * 40);
            $score -= (int) round($cancelRate * 25);
            if ($recencyDays > 14) {
                $score -= min(30, ($recencyDays - 14) * 2);
                $signals[] = 'inactive_14_plus_days';
            }
            if ($attendanceRate < 0.60 && $tracked >= 4) {
                $signals[] = 'attendance_drop';
            }
            if ($noShows > 0) {
                $signals[] = 'recent_no_show';
            }
            $score = max(0, min(100, $score));
            $retentionRisk = $score < 45 || $recencyDays > 21
                ? 'high'
                : ($score < 70 || $recencyDays > 14 ? 'medium' : 'low');
            $noShowRisk = $noShowRate >= 0.25
                ? 'high'
                : ($noShowRate >= 0.10 ? 'medium' : 'low');
            $churnAlert = $retentionRisk === 'high' || in_array('attendance_drop', $signals, true);

            DB::table('gymies_trainer_client_health_snapshots')->updateOrInsert(
                ['trainer_user_id' => $trainerId, 'client_user_id' => $clientId],
                [
                    'health_score' => $score,
                    'retention_risk' => $retentionRisk,
                    'no_show_risk' => $noShowRisk,
                    'churn_alert' => $churnAlert ? 1 : 0,
                    'signals_json' => json_encode(array_values(array_unique($signals)), JSON_UNESCAPED_UNICODE),
                    'updated_at' => $now,
                ]
            );
            $rows++;
        }

        return response()->json([
            'trainers' => count($trainerIds),
            'refreshed' => $rows,
            'updated_at' => $now->toDateTimeString(),
        ]);
    }

    /**
     * Groepslessen: annuleer lessen in status collecting waar 12u voor start Min_Pax niet is bereikt.
     * Notificeer deelnemers en trainer.
     */
    public function expireGroupSessionsMinNotReached(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_group_sessions') || !Schema::hasColumn('gymies_group_sessions', 'status')) {
            return response()->json(['cancelled' => 0]);
        }

        $deadline = now()->addHours(12);
        $sessions = DB::table('gymies_group_sessions')
            ->where('status', 'collecting')
            ->where('scheduled_at', '<=', $deadline)
            ->where('scheduled_at', '>', now())
            ->get(['id', 'trainer_user_id', 'title', 'scheduled_at', 'min_participants']);

        $cancelled = 0;
        foreach ($sessions as $session) {
            $count = (int) DB::table('gymies_group_session_participants')
                ->where('group_session_id', $session->id)
                ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
                ->count();
            $min = (int) ($session->min_participants ?? 1);
            if ($count < $min) {
                DB::table('gymies_group_sessions')->where('id', $session->id)->update([
                    'status' => 'cancelled',
                    'cancelled_at' => now(),
                    'cancelled_by_user_id' => null,
                    'updated_at' => now(),
                ]);
                $participants = DB::table('gymies_group_session_participants')
                    ->where('group_session_id', $session->id)
                    ->whereIn('status', ['pending', 'registered'])
                    ->get(['client_user_id']);
                foreach ($participants as $p) {
                    if (Schema::hasTable('gymies_notification_queue')) {
                        DB::table('gymies_notification_queue')->insert([
                            'user_id' => (int) $p->client_user_id,
                            'channel' => 'in_app',
                            'event_type' => 'group_session_cancelled_min_not_reached',
                            'payload_json' => json_encode([
                                'group_session_id' => (string) $session->id,
                                'title' => $session->title,
                            ], JSON_UNESCAPED_UNICODE),
                            'scheduled_for' => now(),
                            'created_at' => now(),
                        ]);
                    }
                }
                if (Schema::hasTable('gymies_notification_queue')) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $session->trainer_user_id,
                        'channel' => 'in_app',
                        'event_type' => 'group_session_cancelled_min_not_reached_trainer',
                        'payload_json' => json_encode([
                            'group_session_id' => (string) $session->id,
                            'title' => $session->title,
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => now(),
                        'created_at' => now(),
                    ]);
                }
                $cancelled++;
            }
        }

        return response()->json(['cancelled' => $cancelled]);
    }

    /**
     * Groepslessen: wachtlijst-claim verlopen (15 min) – zet terug naar waitlist en bied plek aan volgende.
     */
    public function expireGroupSessionClaimPending(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_group_session_participants') || !Schema::hasColumn('gymies_group_session_participants', 'claim_deadline_at')) {
            return response()->json(['expired' => 0]);
        }

        $now = now();
        $expired = DB::table('gymies_group_session_participants as p')
            ->join('gymies_group_sessions as g', 'p.group_session_id', '=', 'g.id')
            ->where('p.status', 'payment_pending')
            ->whereNotNull('p.claim_deadline_at')
            ->where('p.claim_deadline_at', '<', $now)
            ->select(['p.id as participant_id', 'p.group_session_id', 'g.trainer_user_id', 'g.title', 'g.scheduled_at', 'g.price_cents'])
            ->get();

        $sessionIdsDone = [];
        foreach ($expired as $row) {
            DB::table('gymies_group_session_participants')->where('id', $row->participant_id)->update([
                'status' => 'waitlist',
                'amount_cents' => null,
                'platform_fee_cents' => null,
                'trainer_payout_cents' => null,
                'claim_deadline_at' => null,
            ]);
            $sessionIdsDone[(int) $row->group_session_id] = true;
        }

        foreach (array_keys($sessionIdsDone) as $sessionId) {
            $session = DB::table('gymies_group_sessions')->where('id', $sessionId)->first();
            if (!$session || ($session->status ?? '') !== 'confirmed_by_trainer') {
                continue;
            }
            $first = DB::table('gymies_group_session_participants')
                ->where('group_session_id', $sessionId)
                ->where('status', 'waitlist')
                ->orderBy('created_at')
                ->first();
            if (!$first) {
                continue;
            }
            $priceCents = (int) $session->price_cents;
            $feeCents = 199;
            $payoutCents = max(0, $priceCents - $feeCents);
            $claimDeadline = $now->copy()->addMinutes(15);
            DB::table('gymies_group_session_participants')->where('id', $first->id)->update([
                'status' => 'payment_pending',
                'amount_cents' => $priceCents,
                'platform_fee_cents' => $feeCents,
                'trainer_payout_cents' => $payoutCents,
                'claim_deadline_at' => $claimDeadline,
            ]);
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $first->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'group_session_waitlist_spot_available',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $sessionId,
                        'title' => $session->title,
                        'scheduled_at' => $session->scheduled_at,
                        'claim_minutes' => 15,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => $now,
                    'created_at' => $now,
                ]);
            }
        }

        return response()->json(['expired' => $expired->count()]);
    }

    /**
     * Subscription reminders: herinnering bij naderende betaling of mislukte incasso.
     */
    public function subscriptionReminders(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['reminded' => 0]);
        }

        $reminded = 0;
        $now = now();

        // Trial/referral verlopen: trialing zonder Mollie, trial_ends_at < now → expired
        if (Schema::hasColumn('gymies_subscriptions', 'trial_ends_at')) {
            $expiredTrials = DB::table('gymies_subscriptions')
                ->where('status', 'trialing')
                ->whereNull('mollie_customer_id')
                ->whereNotNull('trial_ends_at')
                ->where('trial_ends_at', '<', $now)
                ->get(['id', 'trainer_user_id']);
            foreach ($expiredTrials as $sub) {
                DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
                    'status' => 'expired',
                    'updated_at' => $now,
                ]);
                if (Schema::hasTable('gymies_notification_queue')) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $sub->trainer_user_id,
                        'channel' => 'in_app',
                        'event_type' => 'subscription_trial_expired',
                        'payload_json' => json_encode([
                            'message' => 'Je Pro trial is afgelopen. Betaal via Inkomsten om door te gaan.',
                            'action_url' => '/trainer/revenue',
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                }
            }
        }

        $pastDue = DB::table('gymies_subscriptions')
            ->where('status', 'past_due')
            ->get(['id', 'trainer_user_id']);

        foreach ($pastDue as $sub) {
            if (Schema::hasTable('gymies_notification_queue')) {
                $alreadySent = DB::table('gymies_notification_queue')
                    ->where('user_id', (int) $sub->trainer_user_id)
                    ->where('event_type', 'subscription_payment_reminder')
                    ->where('created_at', '>=', $now->copy()->subDay())
                    ->exists();

                if (!$alreadySent) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $sub->trainer_user_id,
                        'channel' => 'in_app',
                        'event_type' => 'subscription_payment_reminder',
                        'payload_json' => json_encode([
                            'message' => 'Je abonnementsbetaling is mislukt. Update je betaalgegevens om je account actief te houden.',
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                    $reminded++;
                }
            }
        }

        return response()->json(['reminded' => $reminded]);
    }

    /**
     * Auto-facturen genereren voor voltooide sessies (Pro/Studio trainers).
     */
    public function generateSessionInvoices(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_invoices')) {
            return response()->json(['generated' => 0, 'message' => 'Invoice tabel niet beschikbaar']);
        }

        $bookings = DB::table('gymies_bookings as b')
            ->where('b.status', 'completed')
            ->whereNotExists(function ($q) {
                $q->select(DB::raw(1))
                    ->from('gymies_trainer_invoices')
                    ->whereColumn('gymies_trainer_invoices.booking_id', 'b.id');
            })
            ->limit(100)
            ->get();

        $generated = 0;
        foreach ($bookings as $booking) {
            $hasInvoicing = false;
            if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                $plan = DB::table('gymies_trainer_profiles')
                    ->where('user_id', (int) $booking->trainer_user_id)
                    ->value('subscription_plan');
                if ($plan !== null) {
                    $hasInvoicing = (bool) DB::table('gymies_plans')
                        ->where('slug', $plan)
                        ->value('has_invoicing');
                }
            }

            if ($hasInvoicing) {
                $invoiceId = \App\Http\Controllers\Gymies\GymiesInvoiceController::generateForBooking($booking);
                if ($invoiceId !== null) {
                    $generated++;
                }
            }
        }

        return response()->json(['generated' => $generated]);
    }

    /**
     * Groepslessen: betaaldeadline na tipping point (60 min). Wie niet betaalt, gaat terug naar waitlist.
     */
    public function expireGroupSessionPaymentDeadline(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_group_session_participants') || !Schema::hasColumn('gymies_group_session_participants', 'payment_deadline_at')) {
            return response()->json(['expired' => 0, 'message' => 'Payment deadline column not available']);
        }

        $now = now();
        $expired = DB::table('gymies_group_session_participants')
            ->where('status', 'payment_pending')
            ->whereNotNull('payment_deadline_at')
            ->where('payment_deadline_at', '<', $now)
            ->get(['id', 'group_session_id', 'client_user_id']);

        $sessionIds = [];
        foreach ($expired as $row) {
            DB::table('gymies_group_session_participants')->where('id', $row->id)->update([
                'status' => 'cancelled',
                'payment_deadline_at' => null,
            ]);

            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $row->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'group_session_payment_deadline_expired',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $row->group_session_id,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => $now,
                    'created_at' => $now,
                ]);
            }
            $sessionIds[(int) $row->group_session_id] = true;
        }

        // Promote waitlist for freed spots
        foreach (array_keys($sessionIds) as $sessionId) {
            $session = DB::table('gymies_group_sessions')->where('id', $sessionId)->first();
            if (!$session || !in_array($session->status ?? '', ['confirmed_by_trainer', 'collecting'], true)) {
                continue;
            }
            $first = DB::table('gymies_group_session_participants')
                ->where('group_session_id', $sessionId)
                ->where('status', 'waitlist')
                ->orderBy('created_at')
                ->first();
            if (!$first) {
                continue;
            }
            $priceCents = (int) $session->price_cents;
            $feeCents = 199;
            $payoutCents = max(0, $priceCents - $feeCents);
            $claimDeadline = $now->copy()->addMinutes(15);
            $updateData = [
                'status' => 'payment_pending',
                'amount_cents' => $priceCents,
                'platform_fee_cents' => $feeCents,
                'trainer_payout_cents' => $payoutCents,
                'claim_deadline_at' => $claimDeadline,
            ];
            DB::table('gymies_group_session_participants')->where('id', $first->id)->update($updateData);
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $first->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'group_session_waitlist_spot_available',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $sessionId,
                        'title' => $session->title,
                        'scheduled_at' => $session->scheduled_at,
                        'claim_minutes' => 15,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => $now,
                    'created_at' => $now,
                ]);
            }
        }

        return response()->json(['expired' => $expired->count()]);
    }

    /**
     * Safe-Session: als trainer niet heeft uitgecheckt 15 min na sessie-einde, melding naar admin.
     */
    public function checkSafeSessionOverdue(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasColumn('gymies_bookings', 'safe_session_active') || !Schema::hasColumn('gymies_bookings', 'check_out_at')) {
            return response()->json(['alerted' => 0, 'message' => 'Safe-session niet beschikbaar']);
        }

        $now = now();
        $overdue = DB::table('gymies_bookings')
            ->where('safe_session_active', 1)
            ->whereNull('check_out_at')
            ->where('status', 'confirmed')
            ->whereRaw('DATE_ADD(scheduled_at, INTERVAL COALESCE(duration_minutes, 60) + 15 MINUTE) < ?', [$now])
            ->get(['id', 'trainer_user_id', 'client_user_id', 'scheduled_at', 'duration_minutes']);

        $alerted = 0;
        if (Schema::hasTable('gymies_notification_queue')) {
            $adminIds = DB::table('gymies_users')->where('is_admin', 1)->pluck('id');
            foreach ($overdue as $b) {
                foreach ($adminIds as $adminId) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $adminId,
                        'channel' => 'in_app',
                        'event_type' => 'safe_session_overdue',
                        'payload_json' => json_encode([
                            'booking_id' => (string) $b->id,
                            'trainer_user_id' => (string) $b->trainer_user_id,
                            'scheduled_at' => $b->scheduled_at,
                            'message' => 'Safe-Session trainer heeft niet uitgecheckt 15 min na sessie-einde!',
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                }
                $alerted++;
            }
        }

        return response()->json(['alerted' => $alerted]);
    }

    /**
     * Cron: verlopen substitute-verzoeken sluiten.
     */
    public function expireSubstituteRequests(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_substitute_requests')) {
            return response()->json(['expired' => 0, 'message' => 'Tabel niet beschikbaar']);
        }

        $expired = DB::table('gymies_substitute_requests')
            ->where('status', 'open')
            ->whereNotNull('expires_at')
            ->where('expires_at', '<', now())
            ->get(['id', 'group_session_id', 'original_trainer_id']);

        foreach ($expired as $sub) {
            DB::table('gymies_substitute_requests')->where('id', $sub->id)->update(['status' => 'expired']);
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $sub->original_trainer_id,
                    'channel' => 'in_app',
                    'event_type' => 'substitute_request_expired',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $sub->group_session_id,
                        'message' => 'Geen vervanger gevonden. Overweeg de les te annuleren.',
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }
        }

        return response()->json(['expired' => $expired->count()]);
    }

    /**
     * Cron: Ghost-Rating push 1 uur na voltooide sessie (met check-in).
     */
    public function triggerGhostRatings(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_ghost_ratings')) {
            return response()->json(['triggered' => 0, 'message' => 'Ghost-rating tabel niet beschikbaar']);
        }

        $now = now();
        $oneHourAgo = $now->copy()->subHour();
        $twoHoursAgo = $now->copy()->subHours(2);

        $bookings = DB::table('gymies_bookings')
            ->where('status', 'completed')
            ->whereNotNull('check_in_at')
            ->where('updated_at', '>=', $twoHoursAgo)
            ->where('updated_at', '<=', $oneHourAgo)
            ->whereNotExists(function ($q) {
                $q->select(DB::raw(1))
                    ->from('gymies_ghost_ratings')
                    ->whereColumn('gymies_ghost_ratings.booking_id', 'gymies_bookings.id');
            })
            ->get(['id', 'client_user_id', 'trainer_user_id']);

        $triggered = 0;
        foreach ($bookings as $b) {
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $b->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'ghost_rating_request',
                    'payload_json' => json_encode([
                        'booking_id' => (string) $b->id,
                        'trainer_user_id' => (string) $b->trainer_user_id,
                        'message' => 'Hoe was je training? Geef snel feedback met 3 emoji-vragen!',
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => $now,
                    'created_at' => $now,
                ]);
                $triggered++;
            }
        }

        return response()->json(['triggered' => $triggered]);
    }

    /**
     * Cron: Ghost-Rating structureel lage scores detecteren en admin waarschuwen.
     */
    public function ghostRatingAlerts(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_ghost_ratings')) {
            return response()->json(['alerts' => 0]);
        }

        $thirtyDaysAgo = now()->subDays(30);
        $trainers = DB::table('gymies_ghost_ratings')
            ->select('trainer_user_id', DB::raw('AVG(energy) as avg_energy'), DB::raw('AVG(would_rebook) as avg_rebook'), DB::raw('COUNT(*) as total'))
            ->where('created_at', '>=', $thirtyDaysAgo)
            ->groupBy('trainer_user_id')
            ->havingRaw('COUNT(*) >= 3')
            ->havingRaw('(AVG(energy) < 1.8 OR AVG(would_rebook) < 1.5)')
            ->get();

        $alerts = 0;
        foreach ($trainers as $t) {
            if (Schema::hasTable('gymies_admin_alerts')) {
                $alreadyAlerted = DB::table('gymies_admin_alerts')
                    ->where('alert_type', 'ghost_rating_low_score')
                    ->where('entity_type', 'user')
                    ->where('entity_id', (int) $t->trainer_user_id)
                    ->where('created_at', '>=', $thirtyDaysAgo)
                    ->exists();
                if (!$alreadyAlerted) {
                    DB::table('gymies_admin_alerts')->insert([
                        'alert_type' => 'ghost_rating_low_score',
                        'entity_type' => 'user',
                        'entity_id' => (int) $t->trainer_user_id,
                        'severity' => 'warning',
                        'message' => "Trainer lage Ghost-Rating: energie {$t->avg_energy}/3, aanbeveling {$t->avg_rebook}/3 ({$t->total} beoordelingen)",
                        'created_at' => now(),
                    ]);
                    $alerts++;
                }
            }
        }

        return response()->json(['alerts' => $alerts]);
    }

    /**
     * Verwerk in-app notificaties die ook per e-mail naar trainers moeten.
     * Selecteert: channel=in_app, sent_at IS NULL, event_type in trainer-email-events.
     * Stuurt e-mail via Brevo/Laravel Mail, zet sent_at of failed_at.
     * Aanroep: GET/POST /api/gymies/cron/process-notification-emails?key=...
     * Plan: elke 1–5 minuten.
     */
    public function processNotificationEmails(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_notification_queue') || !Schema::hasTable('gymies_users')) {
            return response()->json(['sent' => 0, 'failed' => 0, 'message' => 'Tabellen ontbreken']);
        }

        $trainerEmailEvents = [
            'booking_created_for_trainer',
            'spoed_inval_offer',
            'spoed_inval_accepted',
            'group_session_new_registration',
            'substitute_request',
        ];

        $rows = DB::table('gymies_notification_queue as n')
            ->join('gymies_users as u', 'n.user_id', '=', 'u.id')
            ->where('n.channel', 'in_app')
            ->whereNull('n.sent_at')
            ->whereNull('n.failed_at')
            ->whereIn('n.event_type', $trainerEmailEvents)
            ->whereNotNull('u.email')
            ->where('u.email', '!=', '')
            ->select(['n.id', 'n.user_id', 'n.event_type', 'n.payload_json', 'u.email', 'u.display_name'])
            ->orderBy('n.created_at')
            ->limit(50)
            ->get();

        $sent = 0;
        $failed = 0;
        $appName = \App\Helpers\GymiesNotificationEmail::mailBrandName();
        $baseUrl = \App\Helpers\GymiesNotificationEmail::mailPublicBaseUrl();

        foreach ($rows as $r) {
            $payload = [];
            if (!empty($r->payload_json)) {
                $decoded = json_decode((string) $r->payload_json, true);
                if (is_array($decoded)) {
                    $payload = $decoded;
                }
            }
            $greeting = trim((string) ($r->display_name ?? '')) !== ''
                ? 'Hoi ' . $r->display_name . ','
                : 'Hoi,';

            [$subject, $textBody, $htmlBody] = $this->buildNotificationEmail(
                $r->event_type,
                $payload,
                $greeting,
                $appName,
                $baseUrl,
            );
            if ($subject === null) {
                continue;
            }

            $ok = \App\Helpers\GymiesNotificationEmail::send(
                trim((string) $r->email),
                $subject,
                $textBody,
                $htmlBody,
            );
            if ($ok) {
                DB::table('gymies_notification_queue')->where('id', $r->id)->update(['sent_at' => now()]);
                $sent++;
            } else {
                DB::table('gymies_notification_queue')->where('id', $r->id)->update(['failed_at' => now()]);
                $failed++;
            }
        }

        return response()->json(['sent' => $sent, 'failed' => $failed, 'processed' => $rows->count()]);
    }

    /**
     * @return array{0: string|null, 1: string, 2: string|null} [subject, textBody, htmlBody]
     */
    private function buildNotificationEmail(
        string $eventType,
        array $payload,
        string $greeting,
        string $appName,
        string $baseUrl,
    ): array {
        $link = $baseUrl . '/trainer';
        $linkEsc = htmlspecialchars($link, ENT_QUOTES, 'UTF-8');
        $cta = "Open de app of ga naar: {$link}";

        switch ($eventType) {
            case 'booking_created_for_trainer':
                $scheduledAt = $payload['scheduled_at'] ?? '';
                $clientId = $payload['client_user_id'] ?? '';
                $bookingId = $payload['booking_id'] ?? '';
                $duration = $payload['duration_minutes'] ?? 60;
                $clientName = $clientId && Schema::hasTable('gymies_users')
                    ? (DB::table('gymies_users')->where('id', (int) $clientId)->value('display_name') ?? 'Een klant')
                    : 'Een klant';
                $subject = "{$appName} – Nieuwe boeking van {$clientName}";
                $text = "{$greeting}\n\nEr is een nieuwe boeking binnengekomen van {$clientName}.\n\n"
                    . "Gepland: {$scheduledAt} ({$duration} min)\n\n"
                    . "Bevestig of wijzig de boeking in de app.\n\n{$cta}\n\nMet vriendelijke groet,\n{$appName}";
                $html = '<p style="margin:0 0 16px;">' . nl2br(htmlspecialchars($greeting, ENT_QUOTES, 'UTF-8')) . '</p>'
                    . '<p style="margin:0 0 16px;">Er is een <strong>nieuwe boeking</strong> binnengekomen van ' . htmlspecialchars($clientName, ENT_QUOTES, 'UTF-8') . '.</p>'
                    . '<p style="margin:0 0 16px;">Gepland: ' . htmlspecialchars($scheduledAt, ENT_QUOTES, 'UTF-8') . ' (' . (int) $duration . ' min)</p>'
                    . '<p style="margin:0 0 20px;"><a href="' . $linkEsc . '" style="display:inline-block;background:#FF8A00;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:600;">Bevestig in de app</a></p>'
                    . '<p style="margin:0;color:#5C6773;font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';
                return [$subject, $text, \App\Helpers\GymiesNotificationEmail::htmlWrapper($subject, $html, $appName)];

            case 'spoed_inval_offer':
                $count = (int) ($payload['count'] ?? 1);
                $sessions = $payload['sessions'] ?? [];
                $first = is_array($sessions) && !empty($sessions) ? reset($sessions) : null;
                $when = is_array($first) && isset($first['scheduled_at']) ? $first['scheduled_at'] : ($payload['scheduled_at'] ?? '');
                $subject = "{$appName} – Spoed inval: wil je deze sessie(s) overnemen?";
                $text = "{$greeting}\n\nEr is een spoed inval aanbod: {$count} sessie(s) om over te nemen.\n\n"
                    . "Start: {$when}\n\n"
                    . "Reageer snel in de app – ja of nee.\n\n{$cta}\n\nMet vriendelijke groet,\n{$appName}";
                $html = '<p style="margin:0 0 16px;">' . nl2br(htmlspecialchars($greeting, ENT_QUOTES, 'UTF-8')) . '</p>'
                    . '<p style="margin:0 0 16px;"><strong>Spoed inval</strong> – ' . $count . ' sessie(s) om over te nemen.</p>'
                    . '<p style="margin:0 0 16px;">Start: ' . htmlspecialchars($when, ENT_QUOTES, 'UTF-8') . '</p>'
                    . '<p style="margin:0 0 20px;"><a href="' . $linkEsc . '" style="display:inline-block;background:#FF8A00;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:600;">Reageer in de app</a></p>'
                    . '<p style="margin:0;color:#5C6773;font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';
                return [$subject, $text, \App\Helpers\GymiesNotificationEmail::htmlWrapper($subject, $html, $appName)];

            case 'spoed_inval_accepted':
                $subName = $payload['substitute_display_name'] ?? 'Een trainer';
                $subject = "{$appName} – Spoed inval geaccepteerd";
                $text = "{$greeting}\n\n{$subName} heeft je spoed-invalverzoek geaccepteerd. De sessies zijn overgedragen.\n\n{$cta}\n\nMet vriendelijke groet,\n{$appName}";
                $html = '<p style="margin:0 0 16px;">' . nl2br(htmlspecialchars($greeting, ENT_QUOTES, 'UTF-8')) . '</p>'
                    . '<p style="margin:0 0 16px;">' . htmlspecialchars($subName, ENT_QUOTES, 'UTF-8') . ' heeft je spoed-invalverzoek geaccepteerd.</p>'
                    . '<p style="margin:0 0 20px;"><a href="' . $linkEsc . '" style="display:inline-block;background:#FF8A00;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:600;">Bekijk in de app</a></p>'
                    . '<p style="margin:0;color:#5C6773;font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';
                return [$subject, $text, \App\Helpers\GymiesNotificationEmail::htmlWrapper($subject, $html, $appName)];

            case 'group_session_new_registration':
                $title = $payload['title'] ?? $payload['session_title'] ?? 'Groepsles';
                $subject = "{$appName} – Nieuwe aanmelding: {$title}";
                $text = "{$greeting}\n\nEr is een nieuwe aanmelding voor je groepsles \"{$title}\".\n\n{$cta}\n\nMet vriendelijke groet,\n{$appName}";
                $html = '<p style="margin:0 0 16px;">' . nl2br(htmlspecialchars($greeting, ENT_QUOTES, 'UTF-8')) . '</p>'
                    . '<p style="margin:0 0 16px;">Nieuwe aanmelding voor <strong>' . htmlspecialchars($title, ENT_QUOTES, 'UTF-8') . '</strong>.</p>'
                    . '<p style="margin:0 0 20px;"><a href="' . $linkEsc . '" style="display:inline-block;background:#FF8A00;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:600;">Bekijk in de app</a></p>'
                    . '<p style="margin:0;color:#5C6773;font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';
                return [$subject, $text, \App\Helpers\GymiesNotificationEmail::htmlWrapper($subject, $html, $appName)];

            case 'substitute_request':
                $title = $payload['session_title'] ?? 'Groepsles';
                $subject = "{$appName} – Invaller gezocht: {$title}";
                $text = "{$greeting}\n\nEr is een verzoek voor een invaller voor \"{$title}\".\n\n{$cta}\n\nMet vriendelijke groet,\n{$appName}";
                $html = '<p style="margin:0 0 16px;">' . nl2br(htmlspecialchars($greeting, ENT_QUOTES, 'UTF-8')) . '</p>'
                    . '<p style="margin:0 0 16px;">Invaller gezocht voor <strong>' . htmlspecialchars($title, ENT_QUOTES, 'UTF-8') . '</strong>.</p>'
                    . '<p style="margin:0 0 20px;"><a href="' . $linkEsc . '" style="display:inline-block;background:#FF8A00;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:600;">Bekijk in de app</a></p>'
                    . '<p style="margin:0;color:#5C6773;font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';
                return [$subject, $text, \App\Helpers\GymiesNotificationEmail::htmlWrapper($subject, $html, $appName)];

            default:
                return [null, '', null];
        }
    }

    /**
     * Auto-Pilot retentie: klant met resterende strippenkaart-sessies 10+ dagen niet geboekt →
     * "We missen je" in-app met link naar boeken bij trainer. Bron: gymies_packages + package_id op boekingen (geen wallet).
     * Max 1x per 14 dagen per client+trainer. GET/POST ?key=... — draai dagelijks.
     */
    public function autoPilotRetention(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_notification_queue') || !Schema::hasTable('gymies_bookings')) {
            return response()->json(['sent' => 0, 'message' => 'Queue of bookings ontbreekt']);
        }
        if (!Schema::hasTable('gymies_packages') || !Schema::hasColumn('gymies_bookings', 'package_id')) {
            return response()->json(['sent' => 0, 'message' => 'Pakketten/package_id niet beschikbaar']);
        }

        $daysInactive = min(max((int) ($request->input('days_inactive') ?? 10), 3), 90);
        $minRemaining = min(max((int) ($request->input('min_remaining_sessions') ?? 1), 1), 100);
        $cooldownDays = min(max((int) ($request->input('cooldown_days') ?? 14), 1), 60);
        $cutoff = now()->subDays($daysInactive)->toDateTimeString();
        $cooldown = now()->subDays($cooldownDays);

        $trainers = DB::table('gymies_bookings')
            ->distinct()
            ->pluck('trainer_user_id')
            ->filter()
            ->values()
            ->all();
        $sent = 0;
        $now = now();

        foreach ($trainers as $trainerUserId) {
            $packages = DB::table('gymies_packages')
                ->where('trainer_user_id', $trainerUserId)
                ->get(['id', 'sessions_count']);
            if ($packages->isEmpty()) {
                continue;
            }
            $clientIds = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerUserId)
                ->distinct()
                ->pluck('client_user_id')
                ->filter()
                ->unique()
                ->values()
                ->all();
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
                    ->where('trainer_user_id', $trainerUserId)
                    ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                    ->orderByDesc('scheduled_at')
                    ->value('scheduled_at');
                if ($lastBooking !== null && (string) $lastBooking >= $cutoff) {
                    continue;
                }
                $payloadNeedle = '"trainer_user_id":"' . (string) $trainerUserId . '"';
                $already = DB::table('gymies_notification_queue')
                    ->where('user_id', (int) $clientUserId)
                    ->where('event_type', 'retention_we_miss_you')
                    ->where('created_at', '>=', $cooldown)
                    ->where('payload_json', 'like', '%' . $payloadNeedle . '%')
                    ->exists();
                if ($already) {
                    continue;
                }
                $trainerName = (string) (DB::table('gymies_users')->where('id', $trainerUserId)->value('display_name') ?? 'je trainer');
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $clientUserId,
                    'channel' => 'in_app',
                    'event_type' => 'retention_we_miss_you',
                    'payload_json' => json_encode([
                        'trainer_user_id' => (string) $trainerUserId,
                        'trainer_name' => $trainerName,
                        'message' => "We missen je! Je hebt nog {$remainingTotal} sessie(s) te plannen bij {$trainerName}.",
                        'action_url' => '/boeken?trainerId=' . (string) $trainerUserId,
                        'sessions_remaining_total' => $remainingTotal,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => $now,
                    'created_at' => $now,
                ]);
                $sent++;
            }
        }

        $result = ['sent' => $sent, 'days_inactive' => $daysInactive];
        $this->logCronResult('autoPilotRetention', $result);
        return response()->json($result);
    }

    /**
     * Low-Credit upsell: resterende strippen <= drempel → in-app "laatste strip bijna op"
     * met loyalty-copy en link naar trainer (package_id-logica, zelfde als CRM).
     * Dedup: max 1x per cooldown per client+trainer. GET/POST ?key=... — bij voorkeur dagelijks na boekingen.
     */
    public function autoPilotLowCredit(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_notification_queue') || !Schema::hasTable('gymies_bookings')) {
            return response()->json(['sent' => 0, 'message' => 'Queue of bookings ontbreekt']);
        }
        if (!Schema::hasTable('gymies_packages') || !Schema::hasColumn('gymies_bookings', 'package_id')) {
            return response()->json(['sent' => 0, 'message' => 'Pakketten/package_id niet beschikbaar']);
        }

        // Stuur alleen als er nog precies 1 (of max N) sessies over zijn — voorkom spam bij 0 of veel
        $maxRemaining = min(max((int) ($request->input('max_remaining_sessions') ?? 1), 1), 5);
        $cooldownDays = min(max((int) ($request->input('cooldown_days') ?? 14), 1), 90);
        $cooldown = now()->subDays($cooldownDays);
        $sent = 0;
        $now = now();

        $trainers = DB::table('gymies_bookings')
            ->distinct()
            ->pluck('trainer_user_id')
            ->filter()
            ->values()
            ->all();

        // Batch: alle packages per trainer + trainer display names
        $packagesByTrainer = DB::table('gymies_packages')
            ->whereIn('trainer_user_id', $trainers)
            ->get(['id', 'trainer_user_id', 'sessions_count', 'name'])
            ->groupBy('trainer_user_id');
        $trainerDisplayNames = DB::table('gymies_users')
            ->whereIn('id', $trainers)
            ->pluck('display_name', 'id')
            ->all();

        // Batch: used per (client, package)
        $usedByClientPackage = DB::table('gymies_bookings')
            ->whereIn('trainer_user_id', $trainers)
            ->whereNotNull('package_id')
            ->whereNotIn('status', ['cancelled'])
            ->selectRaw('client_user_id, package_id, COUNT(*) as used')
            ->groupBy('client_user_id', 'package_id')
            ->get()
            ->keyBy(fn ($r) => (int) $r->client_user_id . '_' . (int) $r->package_id);

        // Batch: recent upsell notifications (client + trainer in payload)
        $recentUpsells = DB::table('gymies_notification_queue')
            ->where('event_type', 'upsell_low_credit_loyalty')
            ->where('created_at', '>=', $cooldown)
            ->get(['user_id', 'payload_json']);

        $alreadySent = [];
        foreach ($recentUpsells as $n) {
            $uid = (int) $n->user_id;
            if (preg_match('/"trainer_user_id":"(\d+)"/', (string) $n->payload_json, $m)) {
                $alreadySent[$uid . '_' . $m[1]] = true;
            }
        }

        foreach ($trainers as $trainerUserId) {
            $packages = $packagesByTrainer->get($trainerUserId) ?? collect();
            if ($packages->isEmpty()) {
                continue;
            }
            $clientIds = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerUserId)
                ->distinct()
                ->pluck('client_user_id')
                ->filter()
                ->unique()
                ->values()
                ->all();

            $trainerName = (string) ($trainerDisplayNames[$trainerUserId] ?? 'je trainer');

            foreach ($clientIds as $clientUserId) {
                $remainingTotal = 0;
                foreach ($packages as $pkg) {
                    $sessionsCount = (int) ($pkg->sessions_count ?? 0);
                    if ($sessionsCount <= 0) {
                        continue;
                    }
                    $key = (int) $clientUserId . '_' . (int) $pkg->id;
                    $used = (int) ($usedByClientPackage->get($key)?->used ?? 0);
                    $remainingTotal += max(0, $sessionsCount - $used);
                }
                if ($remainingTotal <= 0 || $remainingTotal > $maxRemaining) {
                    continue;
                }

                if (isset($alreadySent[(int) $clientUserId . '_' . (int) $trainerUserId])) {
                    continue;
                }

                $stripLabel = $remainingTotal === 1 ? 'Je laatste strip is bijna op' : "Nog {$remainingTotal} sessies over";
                $message = "{$stripLabel}! Koop nu je nieuwe rittenkaart bij {$trainerName} — als dank 5% loyaltykorting op je volgende pakket.";

                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $clientUserId,
                    'channel' => 'in_app',
                    'event_type' => 'upsell_low_credit_loyalty',
                    'payload_json' => json_encode([
                        'trainer_user_id' => (string) $trainerUserId,
                        'trainer_name' => $trainerName,
                        'message' => $message,
                        'action_url' => '/trainer-profiel/' . (string) $trainerUserId,
                        'sessions_remaining_total' => $remainingTotal,
                        'loyalty_discount_percent' => 5,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => $now,
                    'created_at' => $now,
                ]);
                $sent++;
                $alreadySent[(int) $clientUserId . '_' . (int) $trainerUserId] = true;
            }
        }

        $result = [
            'sent' => $sent,
            'max_remaining_sessions' => $maxRemaining,
            'cooldown_days' => $cooldownDays,
        ];
        $this->logCronResult('autoPilotLowCredit', $result);
        return response()->json($result);
    }

    /**
     * Cron: herbereken quality_score voor alle trainers.
     * Formule: reviews (40%) + voltooide sessies (25%) + responssnelheid (20%) + profielvolledigheid (15%)
     * Draai dagelijks: POST cron/recalculate-quality-scores?key=...
     */
    public function recalculateQualityScores(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_profiles') || !Schema::hasColumn('gymies_trainer_profiles', 'quality_score')) {
            return response()->json(['message' => 'quality_score kolom niet beschikbaar.'], 404);
        }

        $trainers = DB::table('gymies_users as u')
            ->join('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id')
            ->where('u.role', 'trainer')
            ->select('u.id as user_id', 'p.bio', 'p.specialty', 'p.avatar_url', 'p.certifications',
                     'p.experience_years', 'p.languages', 'p.hourly_rate_cents', 'p.region')
            ->get();

        if ($trainers->isEmpty()) {
            return response()->json(['message' => 'Geen trainers gevonden.', 'updated' => 0]);
        }

        $trainerIds = $trainers->pluck('user_id')->all();

        // ── Reviews component (40%) ──
        $reviewStats = [];
        if (Schema::hasTable('gymies_reviews')) {
            $rows = DB::table('gymies_reviews')
                ->whereIn('trainer_user_id', $trainerIds)
                ->where('status', 'approved')
                ->groupBy('trainer_user_id')
                ->select('trainer_user_id', DB::raw('AVG(rating) as avg_rating'), DB::raw('COUNT(*) as cnt'))
                ->get();
            foreach ($rows as $r) {
                $reviewStats[(int) $r->trainer_user_id] = ['avg' => (float) $r->avg_rating, 'cnt' => (int) $r->cnt];
            }
        }

        // ── Sessies component (25%) ──
        $sessionStats = [];
        $rows = DB::table('gymies_bookings')
            ->whereIn('trainer_user_id', $trainerIds)
            ->where('status', 'completed')
            ->groupBy('trainer_user_id')
            ->select('trainer_user_id', DB::raw('COUNT(*) as completed'))
            ->get();
        foreach ($rows as $r) {
            $sessionStats[(int) $r->trainer_user_id] = (int) $r->completed;
        }

        // ── Responssnelheid component (20%) — gemeten via confirm-snelheid ──
        $responseStats = [];
        if (Schema::hasColumn('gymies_bookings', 'confirmed_at')) {
            $rows = DB::table('gymies_bookings')
                ->whereIn('trainer_user_id', $trainerIds)
                ->whereNotNull('confirmed_at')
                ->where('status', '!=', 'cancelled')
                ->groupBy('trainer_user_id')
                ->select('trainer_user_id', DB::raw('AVG(TIMESTAMPDIFF(MINUTE, created_at, confirmed_at)) as avg_response_min'))
                ->get();
            foreach ($rows as $r) {
                $responseStats[(int) $r->trainer_user_id] = (float) ($r->avg_response_min ?? 9999);
            }
        }

        $updated = 0;
        foreach ($trainers as $t) {
            $uid = (int) $t->user_id;

            // Reviews: 0-40 punten (avg_rating 1-5 → 0-32, plus bonus voor aantal reviews max 8)
            $rev = $reviewStats[$uid] ?? null;
            $reviewScore = 0;
            if ($rev && $rev['cnt'] > 0) {
                $ratingPart = (($rev['avg'] - 1) / 4) * 32; // 1→0, 5→32
                $countBonus = min($rev['cnt'], 20) / 20 * 8;  // max 8 punten bij 20+ reviews
                $reviewScore = round($ratingPart + $countBonus);
            }

            // Sessies: 0-25 punten (0 sessies → 0, 50+ sessies → 25)
            $completed = $sessionStats[$uid] ?? 0;
            $sessionScore = round(min($completed, 50) / 50 * 25);

            // Responssnelheid: 0-20 punten (<30 min → 20, >24u → 0)
            $avgMin = $responseStats[$uid] ?? 9999;
            $responseScore = 0;
            if ($avgMin <= 30) {
                $responseScore = 20;
            } elseif ($avgMin <= 120) {
                $responseScore = 15;
            } elseif ($avgMin <= 480) {
                $responseScore = 10;
            } elseif ($avgMin <= 1440) {
                $responseScore = 5;
            }

            // Profielvolledigheid: 0-15 punten
            $profileScore = 0;
            if (!empty($t->avatar_url)) $profileScore += 3;
            if (!empty($t->bio) && strlen($t->bio) >= 20) $profileScore += 3;
            if (!empty($t->specialty)) $profileScore += 2;
            if (!empty($t->certifications)) $profileScore += 2;
            if (!empty($t->experience_years)) $profileScore += 1;
            if (!empty($t->languages)) $profileScore += 1;
            if (!empty($t->hourly_rate_cents)) $profileScore += 1;
            if (!empty($t->region)) $profileScore += 1;
            $profileScore = min($profileScore, 15); // cap at 15, but can't exceed 14 naturally

            $total = min(100, max(0, $reviewScore + $sessionScore + $responseScore + $profileScore));

            DB::table('gymies_trainer_profiles')
                ->where('user_id', $uid)
                ->update(['quality_score' => $total]);
            $updated++;
        }

        return response()->json([
            'message' => "Quality scores herberekend voor {$updated} trainers.",
            'updated' => $updated,
        ]);
    }

    /**
     * POST /api/gymies/cron/evaluate-ambassador-tiers
     * Maandelijkse tier-evaluatie voor ambassadeurs.
     * Vereist: ?key=... of X-Cron-Key header
     */
    public function evaluateAmbassadorTiers(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $results = \App\Http\Controllers\Gymies\GymiesAmbassadorController::runTierEvaluation();

        return response()->json([
            'message' => "Ambassador tiers geëvalueerd: {$results['evaluated']} beoordeeld, {$results['upgraded']} omhoog, {$results['downgraded']} omlaag, {$results['deactivated']} gedeactiveerd.",
            ...$results,
        ]);
    }
}
