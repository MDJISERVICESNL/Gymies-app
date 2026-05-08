<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Carbon\Carbon;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Cron-endpoints voor Ghosting-preventie e.d.
 * Beveiligd met ?key= of header X-Cron-Key (config: gymies.cron_key of GYMIES_CRON_KEY).
 */
final class GymiesCronController extends Controller
{
    /** Platform-fee in eurocenten (€1,99) — één plek om te wijzigen. */
    private const PLATFORM_FEE_CENTS = 199;

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
            ->get(['id', 'client_user_id', 'trainer_user_id', 'created_at']);

        if ($rows->isEmpty()) {
            return response()->json(['expired' => 0, 'cutoff' => $cutoff->toIso8601String()]);
        }

        $now = now();
        if (!Schema::hasTable('gymies_notification_queue')) {
            $cancelled = 0;
            foreach ($rows as $b) {
                $affected = DB::table('gymies_bookings')
                    ->where('id', $b->id)
                    ->where('status', 'pending')
                    ->update([
                        'status' => 'cancelled',
                        'cancelled_at' => $now,
                        'cancelled_by_user_id' => null,
                        'updated_at' => $now,
                    ]);
                if ($affected > 0) {
                    $cancelled++;
                }
            }
            return response()->json(['expired' => $cancelled, 'cutoff' => $cutoff->toIso8601String()]);
        }

        foreach ($rows as $b) {
            // B37: Controleer status opnieuw bij de update om dubbele verwerking bij gelijktijdige cron-runs te voorkomen.
            $affected = DB::table('gymies_bookings')
                ->where('id', $b->id)
                ->where('status', 'pending') // Alleen aanpassen als nog steeds pending
                ->update([
                    'status' => 'cancelled',
                    'cancelled_at' => $now,
                    'cancelled_by_user_id' => null,
                    'updated_at' => $now,
                ]);
            if ($affected === 0) {
                continue; // Al verwerkt door een andere cron-run
            }
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
            ->get(['id', 'client_user_id', 'trainer_user_id', 'scheduled_at', 'duration_minutes']);
        // Batch-laad alle trainer-namen in één query (vermijdt N+1)
        $trainerIds = $rows->pluck('trainer_user_id')->unique()->values()->toArray();
        $trainerNames = $trainerIds
            ? DB::table('gymies_users')->whereIn('id', $trainerIds)->pluck('display_name', 'id')->toArray()
            : [];
        $sent = 0;
        foreach ($rows as $b) {
            $trainerName = $trainerNames[(int) $b->trainer_user_id] ?? null;
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

        $rows = $query->get(['id', 'client_user_id', 'trainer_user_id']);
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
     * Beveiligd met deduplicate guard: max 1x per 24h, ongeacht hoe vaak de cron draait.
     * N-037 FIXED: email header injection prevention
     */
    public function availabilityCheck(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        // ── Deduplicate guard: max 1x per 24 uur ──
        $cacheKey = 'gymies:cron:availability-check:last-run';
        $lastRun = null;
        try {
            $lastRun = Cache::get($cacheKey);
        } catch (\Throwable $e) {
            // Cache niet beschikbaar — check database als fallback
        }
        if ($lastRun !== null) {
            return response()->json(['skipped' => true, 'reason' => 'Already ran within 24h', 'last_run' => $lastRun]);
        }
        try {
            Cache::put($cacheKey, now()->toIso8601String(), 86400);
        } catch (\Throwable $e) {
            // Doorgaan zonder cache guard
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
            if ($lastAt === null || Carbon::parse((string) $lastAt)->timestamp < $cutoff->timestamp) {
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
            // N-037 FIXED: strip newlines and carriage returns from email headers
            $name = str_replace(["\r", "\n", "\t"], ' ', $name);
            $appName = str_replace(["\r", "\n", "\t"], ' ', $appName);
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
        if ($key === '') {
            return false;
        }
        $provided = $request->input('key') ?: $request->header('X-Cron-Key');
        return $provided !== null && hash_equals($key, (string) $provided);
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
        foreach ($trainerIds as $trainerId) {
            $clientIds = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->distinct()
                ->pluck('client_user_id')
                ->map(fn ($id) => (int) $id)
                ->filter(fn ($id) => $id > 0)
                ->values()
                ->all();
            foreach ($clientIds as $clientId) {
                $recent = DB::table('gymies_bookings')
                    ->where('trainer_user_id', $trainerId)
                    ->where('client_user_id', $clientId)
                    ->orderByDesc('scheduled_at')
                    ->limit(20)
                    ->get(['status', 'scheduled_at']);
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
                    ->first()->scheduled_at ?? null;
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
            $feeCents = self::PLATFORM_FEE_CENTS;
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
     * Send trial conversion emails at key intervals:
     * - 7 days before trial ends
     * - 1 day before trial ends
     * - At trial expiry
     */
    private function sendTrialConversionEmails(Carbon $now): void
    {
        // Check if feature is enabled
        $conversionEmailEnabled = true;
        if (Schema::hasTable('gymies_system_settings')) {
            $setting = DB::table('gymies_system_settings')
                ->where('setting_key', 'trial_conversion_email_enabled')
                ->first();
            if ($setting !== null) {
                $conversionEmailEnabled = (bool) $setting->setting_value;
            }
        }

        if (!$conversionEmailEnabled) {
            return;
        }

        if (!Schema::hasTable('gymies_subscriptions')) {
            return;
        }

        // 1. Email 7 days before trial ends (day 23 of 30-day trial)
        if (Schema::hasColumn('gymies_subscriptions', 'conversion_email_7d_sent_at')) {
            $upcoming7d = DB::table('gymies_subscriptions as s')
                ->join('gymies_users as u', 'u.id', '=', 's.trainer_user_id')
                ->where('s.status', 'trialing')
                ->whereNull('s.mollie_customer_id')
                ->whereNull('s.conversion_email_7d_sent_at')
                ->whereNotNull('s.trial_ends_at')
                ->whereBetween('s.trial_ends_at', [
                    $now->copy()->addDays(6),
                    $now->copy()->addDays(8),
                ])
                ->get(['s.id', 's.trainer_user_id', 's.trial_ends_at', 's.trial_source', 'u.email', 'u.display_name']);

            foreach ($upcoming7d as $record) {
                // Send in-app notification
                if (Schema::hasTable('gymies_notification_queue')) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $record->trainer_user_id,
                        'channel' => 'in_app',
                        'event_type' => 'trial_conversion_7d_reminder',
                        'payload_json' => json_encode([
                            'message' => 'Je Gymies trial loopt over 7 dagen af.',
                            'action_url' => '/trainer/subscription',
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                }

                // Send email
                if (!empty($record->email)) {
                    Mail::raw(
                        "Hoi {$record->display_name},\n\n" .
                        "Je gratis Gymies trial loopt af op " . Carbon::parse($record->trial_ends_at)->format('d M Y') . ".\n\n" .
                        "Wil je doorgaan met Gymies? Kies dan je plan via de app.\n\n" .
                        "Als je geen interesse hebt, hoef je niets te doen.\n\n" .
                        "Gymies Team",
                        function ($message) use ($record) {
                            $message->to($record->email)
                                ->subject('Je Gymies trial loopt over 7 dagen af 🏋️');
                        }
                    );
                }

                // Mark as sent
                DB::table('gymies_subscriptions')
                    ->where('id', (int) $record->id)
                    ->update(['conversion_email_7d_sent_at' => $now]);
            }
        }

        // 2. Email 1 day before trial ends (day 29 of 30-day trial)
        if (Schema::hasColumn('gymies_subscriptions', 'conversion_email_1d_sent_at')) {
            $upcoming1d = DB::table('gymies_subscriptions as s')
                ->join('gymies_users as u', 'u.id', '=', 's.trainer_user_id')
                ->where('s.status', 'trialing')
                ->whereNull('s.mollie_customer_id')
                ->whereNull('s.conversion_email_1d_sent_at')
                ->whereNotNull('s.trial_ends_at')
                ->whereBetween('s.trial_ends_at', [
                    $now->copy()->addHours(20),
                    $now->copy()->addHours(28),
                ])
                ->get(['s.id', 's.trainer_user_id', 's.trial_ends_at', 's.trial_source', 'u.email', 'u.display_name']);

            foreach ($upcoming1d as $record) {
                // Send in-app notification
                if (Schema::hasTable('gymies_notification_queue')) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $record->trainer_user_id,
                        'channel' => 'in_app',
                        'event_type' => 'trial_conversion_1d_reminder',
                        'payload_json' => json_encode([
                            'message' => 'Morgen eindigt je gratis maand.',
                            'action_url' => '/trainer/subscription',
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                }

                // Send email
                if (!empty($record->email)) {
                    Mail::raw(
                        "Hoi {$record->display_name},\n\n" .
                        "Morgen is het zover — je gratis maand eindigt.\n\n" .
                        "Wil je doorgaan met Gymies? Kies dan je plan in de app.\n\n" .
                        "Gymies Team",
                        function ($message) use ($record) {
                            $message->to($record->email)
                                ->subject('Morgen is het zover — je gratis maand eindigt');
                        }
                    );
                }

                // Mark as sent
                DB::table('gymies_subscriptions')
                    ->where('id', (int) $record->id)
                    ->update(['conversion_email_1d_sent_at' => $now]);
            }
        }
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

        // Send trial conversion emails (7 days before, 1 day before, and at expiry)
        $this->sendTrialConversionEmails($now);

        // Trial/referral verlopen: trialing zonder Mollie, trial_ends_at < now → expired
        if (Schema::hasColumn('gymies_subscriptions', 'trial_ends_at')) {
            $expiredTrials = DB::table('gymies_subscriptions')
                ->where('status', 'trialing')
                ->whereNull('mollie_customer_id')
                ->whereNotNull('trial_ends_at')
                ->where('trial_ends_at', '<', $now)
                ->get(['id', 'trainer_user_id']);
            foreach ($expiredTrials as $sub) {
                $updateData = [
                    'status' => 'expired',
                    'updated_at' => $now,
                ];

                // Add conversion_email_expired_sent_at if column exists
                if (Schema::hasColumn('gymies_subscriptions', 'conversion_email_expired_sent_at')) {
                    $updateData['conversion_email_expired_sent_at'] = $now;
                }

                DB::table('gymies_subscriptions')->where('id', $sub->id)->update($updateData);

                // Pause trainer profile moderation status if column exists
                if (Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
                    DB::table('gymies_trainer_profiles')
                        ->where('user_id', (int) $sub->trainer_user_id)
                        ->update(['moderation_status' => 'paused']);
                }

                if (Schema::hasTable('gymies_notification_queue')) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $sub->trainer_user_id,
                        'channel' => 'in_app',
                        'event_type' => 'subscription_trial_expired',
                        'payload_json' => json_encode([
                            'message' => 'Je account is tijdelijk gepauzeerd. Je gegevens blijven 90 dagen behouden.',
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
            $feeCents = self::PLATFORM_FEE_CENTS;
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
     * Safe-Session overdue detectie met 3-niveau escalatie.
     *
     * Escalatie-niveaus:
     * 1. warning  — Sessie duurt > verwacht + 30 min → melding naar trainer + klant
     * 2. emergency — Sessie duurt > verwacht + 60 min → noodcontact e-mail + admin alert
     * 3. critical  — Sessie duurt > verwacht + 120 min → kritiek admin alert
     *
     * Duplicate-preventie via gymies_audit_logs: elk niveau wordt max 1× per sessie gestuurd.
     * Draait elke minuut via scheduler (veiligheid = prioriteit).
     */
    public function checkSafeSessionOverdue(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasColumn('gymies_bookings', 'safe_session_active')) {
            return response()->json(['message' => 'Safe session kolommen ontbreken.', 'processed' => 0]);
        }

        $now = now();
        $processed = 0;
        $alerts = [];

        try {
            $bookings = DB::table('gymies_bookings')
                ->where('safe_session_active', 1)
                ->whereNull('check_out_at')
                ->where('status', 'confirmed')
                ->limit(100)
                ->get();

            foreach ($bookings as $booking) {
                // Bepaal starttijd: safe_session_started_at of scheduled_at
                $startedAt = $booking->safe_session_started_at
                    ?? $booking->scheduled_at
                    ?? null;
                if (!$startedAt) continue;

                $started = Carbon::parse($startedAt);

                // Verwachte sessieduur
                $durationMinutes = (int) ($booking->duration_minutes ?? 60);

                // Bereken hoe lang de sessie al duurt
                $minutesElapsed = (int) $started->diffInMinutes($now);

                // Bepaal escalatie-niveau
                $escalation = null;
                if ($minutesElapsed > $durationMinutes + 120) {
                    $escalation = 'critical';   // > 2 uur over tijd
                } elseif ($minutesElapsed > $durationMinutes + 60) {
                    $escalation = 'emergency';  // > 1 uur over tijd
                } elseif ($minutesElapsed > $durationMinutes + 30) {
                    $escalation = 'warning';    // > 30 min over verwachte einde
                }

                if ($escalation === null) continue;

                // Duplicate-preventie via audit_logs
                if (Schema::hasTable('gymies_audit_logs')) {
                    $alreadySent = DB::table('gymies_audit_logs')
                        ->where('type', "safe_session_{$escalation}")
                        ->where('booking_id', $booking->id)
                        ->where('created_at', '>=', $started)
                        ->exists();
                    if ($alreadySent) continue;

                    // Log in audit trail
                    $insert = [
                        'type' => "safe_session_{$escalation}",
                        'booking_id' => $booking->id,
                        'created_at' => $now,
                    ];
                    if (Schema::hasColumn('gymies_audit_logs', 'details')) {
                        $insert['details'] = json_encode([
                            'minutes_elapsed' => $minutesElapsed,
                            'expected_duration' => $durationMinutes,
                            'escalation' => $escalation,
                        ]);
                    }
                    if (Schema::hasColumn('gymies_audit_logs', 'data')) {
                        $insert['data'] = json_encode([
                            'minutes_elapsed' => $minutesElapsed,
                            'expected_duration' => $durationMinutes,
                            'escalation' => $escalation,
                        ]);
                    }
                    try {
                        DB::table('gymies_audit_logs')->insert($insert);
                    } catch (\Throwable $e) {
                        Log::error('Gymies cron checkSafeSessionOverdue: audit log insert failed', ['trace' => $e->getTraceAsString(), 'error' => $e->getMessage()]);
                        if (app()->bound('sentry')) {
                            \Sentry\captureException($e);
                        }
                    }
                }

                // Stuur notificaties op basis van escalatie-niveau
                $this->sendSafeSessionAlerts($booking, $escalation, $minutesElapsed, $durationMinutes);

                $alerts[] = [
                    'booking_id' => (string) $booking->id,
                    'escalation' => $escalation,
                    'minutes_elapsed' => $minutesElapsed,
                ];
                $processed++;
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('[Cron] checkSafeSessionOverdue fout', ['error' => $e->getMessage()]);
            }
            return response()->json([
                'message' => 'Fout bij verwerking.',
                'processed' => $processed,
            ], 500);
        }

        $this->logCronResult('checkSafeSessionOverdue', ['processed' => $processed, 'alerts' => count($alerts)]);

        return response()->json([
            'message' => 'Safe session overdue check voltooid.',
            'processed' => $processed,
            'alerts' => $alerts,
        ]);
    }

    /**
     * Stuur safe-session alerts op basis van escalatie-niveau.
     *
     * warning:   push naar trainer + klant
     * emergency: + noodcontact e-mail + admin e-mail
     * critical:  + admin e-mail (herhaling)
     */
    private function sendSafeSessionAlerts(
        object $booking,
        string $escalation,
        int $minutesElapsed,
        int $durationMinutes
    ): void {
        $trainerId = $booking->trainer_user_id ?? null;
        $clientId = $booking->client_user_id ?? null;
        $overMinutes = $minutesElapsed - $durationMinutes;
        $now = now();

        $trainerName = 'Trainer';
        $clientName = 'Klant';
        $clientUser = null;

        if ($trainerId) {
            $trainer = DB::table('gymies_users')->where('id', $trainerId)->first();
            $trainerName = $trainer->display_name ?? $trainer->name ?? 'Trainer';
        }
        if ($clientId) {
            $clientUser = DB::table('gymies_users')->where('id', $clientId)->first();
            $clientName = $clientUser->display_name ?? $clientUser->name ?? 'Klant';
        }

        // ── Niveau 1: Warning (> 30 min over) → In-app + FCM push naar trainer + klant
        if (in_array($escalation, ['warning', 'emergency', 'critical'], true)) {
            if (Schema::hasTable('gymies_notification_queue')) {
                // Push naar trainer
                if ($trainerId) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $trainerId,
                        'channel' => 'in_app',
                        'event_type' => 'safe_session_overdue',
                        'payload_json' => json_encode([
                            'booking_id' => (string) $booking->id,
                            'escalation' => $escalation,
                            'title' => 'Sessie duurt langer dan gepland',
                            'body' => "Je sessie met {$clientName} duurt al {$overMinutes} minuten langer dan gepland. Vergeet niet uit te checken.",
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                }

                // Push naar klant
                if ($clientId) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $clientId,
                        'channel' => 'in_app',
                        'event_type' => 'safe_session_overdue',
                        'payload_json' => json_encode([
                            'booking_id' => (string) $booking->id,
                            'escalation' => $escalation,
                            'title' => 'Alles goed?',
                            'body' => "Je sessie duurt langer dan verwacht. Tik op 'Ik ben OK' als alles goed gaat, of gebruik de SOS-knop als je hulp nodig hebt.",
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                }
            }

            // FCM push notificaties
            if (class_exists(FcmPushHelper::class)) {
                if ($trainerId) {
                    try {
                        FcmPushHelper::sendToUser((int) $trainerId, 'Sessie duurt langer dan gepland', "Vergeet niet uit te checken na je sessie met {$clientName}.", [
                            'type' => 'safe_session_overdue',
                            'booking_id' => (string) $booking->id,
                        ]);
                    } catch (\Throwable $e) {
                        Log::error('Gymies cron checkSafeSessionOverdue: FCM push to trainer failed', ['user_id' => $trainerId, 'trace' => $e->getTraceAsString(), 'error' => $e->getMessage()]);
                        if (app()->bound('sentry')) {
                            \Sentry\captureException($e);
                        }
                    }
                }
                if ($clientId) {
                    try {
                        FcmPushHelper::sendToUser((int) $clientId, 'Alles goed?', 'Je sessie duurt langer dan verwacht. Open de app om te bevestigen dat alles OK is.', [
                            'type' => 'safe_session_overdue',
                            'booking_id' => (string) $booking->id,
                        ]);
                    } catch (\Throwable $e) {
                        Log::error('Gymies cron checkSafeSessionOverdue: FCM push to client failed', ['user_id' => $clientId, 'trace' => $e->getTraceAsString(), 'error' => $e->getMessage()]);
                        if (app()->bound('sentry')) {
                            \Sentry\captureException($e);
                        }
                    }
                }
            }
        }

        // ── Niveau 2: Emergency (> 60 min over) → Noodcontact e-mail + Admin e-mail
        if (in_array($escalation, ['emergency', 'critical'], true)) {
            // Noodcontact e-mail
            if ($clientUser && Schema::hasColumn('gymies_users', 'emergency_contact_email')) {
                $emergencyEmail = $clientUser->emergency_contact_email ?? null;
                $emergencyName = $clientUser->emergency_contact_name ?? 'Noodcontact';

                if ($emergencyEmail) {
                    try {
                        Mail::raw(
                            "Dit is een automatisch veiligheidsbericht van Gymies.\n\n"
                            . "{$clientName} heeft een trainingssessie die al {$overMinutes} minuten langer duurt dan gepland.\n\n"
                            . "Sessie met: {$trainerName}\n"
                            . "Gestart om: " . Carbon::parse($booking->safe_session_started_at ?? $booking->scheduled_at)->format('H:i') . "\n"
                            . "Verwachte duur: {$durationMinutes} minuten\n\n"
                            . "Dit kan normaal zijn, maar we willen je op de hoogte stellen voor de zekerheid.\n"
                            . "Neem contact op met {$clientName} als je je zorgen maakt.\n\n"
                            . "– Gymies Veiligheidssysteem",
                            function ($message) use ($emergencyEmail, $emergencyName, $clientName) {
                                $message->to($emergencyEmail, $emergencyName);
                                $message->subject("Gymies: Sessie van {$clientName} duurt langer dan verwacht");
                            }
                        );
                    } catch (\Throwable $e) {
                        Log::error('Gymies cron checkSafeSessionOverdue: emergency contact email failed', ['email' => $emergencyEmail, 'booking_id' => $booking->id, 'trace' => $e->getTraceAsString(), 'error' => $e->getMessage()]);
                        if (app()->bound('sentry')) {
                            \Sentry\captureException($e);
                        }
                    }
                }
            }

            // Admin e-mail
            $adminEmail = config('gymies.admin_email', env('GYMIES_ADMIN_EMAIL', 'safety@gymies.nl'));
            if ($adminEmail) {
                try {
                    Mail::raw(
                        "[Safe Session Overdue - {$escalation}]\n\n"
                        . "Booking ID: {$booking->id}\n"
                        . "Klant: {$clientName} (ID: {$clientId})\n"
                        . "Trainer: {$trainerName} (ID: {$trainerId})\n"
                        . "Gestart: " . ($booking->safe_session_started_at ?? $booking->scheduled_at ?? '?') . "\n"
                        . "Verstreken: {$minutesElapsed} minuten (verwacht: {$durationMinutes})\n"
                        . "Over tijd: {$overMinutes} minuten\n"
                        . "Escalatie: {$escalation}\n",
                        function ($message) use ($adminEmail, $escalation) {
                            $message->to($adminEmail);
                            $message->subject("[Gymies Safety] Safe Session Overdue ({$escalation})");
                        }
                    );
                } catch (\Throwable $e) {
                    Log::error('Gymies cron checkSafeSessionOverdue: admin email failed', ['email' => $adminEmail, 'booking_id' => $booking->id, 'escalation' => $escalation, 'trace' => $e->getTraceAsString(), 'error' => $e->getMessage()]);
                    if (app()->bound('sentry')) {
                        \Sentry\captureException($e);
                    }
                }
            }

            // Admin in-app notificatie
            if (Schema::hasTable('gymies_notification_queue')) {
                $adminIds = DB::table('gymies_users')->where('is_admin', 1)->pluck('id');
                foreach ($adminIds as $adminId) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $adminId,
                        'channel' => 'in_app',
                        'event_type' => "safe_session_{$escalation}",
                        'payload_json' => json_encode([
                            'booking_id' => (string) $booking->id,
                            'trainer_user_id' => (string) $trainerId,
                            'client_user_id' => (string) $clientId,
                            'minutes_elapsed' => $minutesElapsed,
                            'escalation' => $escalation,
                            'message' => "Safe-Session {$escalation}: sessie {$overMinutes} min over tijd!",
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => $now,
                        'created_at' => $now,
                    ]);
                }
            }
        }
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
                trim((string) ($r->display_name ?? '')),
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
        string $recipientName = '',
    ): array {
        switch ($eventType) {
            case 'booking_created_for_trainer':
                $scheduledAt = $payload['scheduled_at'] ?? '';
                $clientId    = $payload['client_user_id'] ?? '';
                $duration    = (int) ($payload['duration_minutes'] ?? 60);
                $clientName  = $clientId && Schema::hasTable('gymies_users')
                    ? (DB::table('gymies_users')->where('id', (int) $clientId)->value('display_name') ?? 'Een klant')
                    : 'Een klant';
                return \App\Helpers\GymiesMailTemplates::nieuweBoeking(
                    $recipientName,
                    (string) $clientName,
                    $scheduledAt,
                    $duration,
                    $appName,
                    $baseUrl,
                );

            case 'spoed_inval_offer':
                $count    = (int) ($payload['count'] ?? 1);
                $sessions = $payload['sessions'] ?? [];
                $first    = is_array($sessions) && !empty($sessions) ? reset($sessions) : null;
                $when     = is_array($first) && isset($first['scheduled_at'])
                    ? $first['scheduled_at']
                    : ($payload['scheduled_at'] ?? '');
                return \App\Helpers\GymiesMailTemplates::spoedInvalAanbod(
                    $recipientName,
                    $count,
                    $when,
                    $appName,
                    $baseUrl,
                );

            case 'spoed_inval_accepted':
                $subName = $payload['substitute_display_name'] ?? 'Een trainer';
                return \App\Helpers\GymiesMailTemplates::spoedInvalGeaccepteerd(
                    $recipientName,
                    $subName,
                    $appName,
                    $baseUrl,
                );

            case 'group_session_new_registration':
                $title               = $payload['title'] ?? $payload['session_title'] ?? 'Groepsles';
                $regClientName       = $payload['client_display_name'] ?? $payload['client_name'] ?? 'Een klant';
                $sessionAt           = $payload['scheduled_at'] ?? $payload['session_at'] ?? '';
                $currentParticipants = (int) ($payload['current_participants'] ?? 1);
                $maxParticipants     = (int) ($payload['max_participants'] ?? 0);
                return \App\Helpers\GymiesMailTemplates::nieuweGroepslesAanmelding(
                    $recipientName,
                    $title,
                    $regClientName,
                    $sessionAt,
                    $currentParticipants,
                    $maxParticipants,
                    $appName,
                    $baseUrl,
                );

            case 'substitute_request':
                $title     = $payload['session_title'] ?? $payload['title'] ?? 'Groepsles';
                $sessionAt = $payload['scheduled_at'] ?? $payload['session_at'] ?? '';
                return \App\Helpers\GymiesMailTemplates::invallerGezocht(
                    $recipientName,
                    $title,
                    $sessionAt,
                    $appName,
                    $baseUrl,
                );

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
        // Batch-laad trainer-namen in één query (vermijdt N+1 in de inner loop)
        $trainerNameMap = $trainers
            ? DB::table('gymies_users')->whereIn('id', $trainers)->pluck('display_name', 'id')->toArray()
            : [];
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
                $trainerName = (string) ($trainerNameMap[(int) $trainerUserId] ?? 'je trainer');
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
     * Ambassador tier evaluatie — maandelijks uitvoeren.
     * Delegeert volledig naar GymiesAmbassadorController::runTierEvaluation().
     * Idempotent: ingebouwde guard controleert of evaluatie al ≤20 dagen geleden liep.
     */
    public function evaluateAmbassadorTiers(Request $request): JsonResponse
    {
        if (!class_exists(\App\Http\Controllers\Gymies\GymiesAmbassadorController::class)) {
            return response()->json(['skipped' => true, 'reason' => 'controller_not_found']);
        }

        try {
            $result = \App\Http\Controllers\Gymies\GymiesAmbassadorController::runTierEvaluation();
            $this->logCronResult('evaluateAmbassadorTiers', $result);
            return response()->json($result);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('[Cron] evaluateAmbassadorTiers mislukt', ['error' => $e->getMessage()]);
            }
            // Stuur geen interne foutdetails naar de client (exception messages kunnen
            // tabelstructuren, bestandspaden of SQL-queries bevatten).
            return response()->json(['ok' => false, 'error' => 'Serverfout bij verwerking.'], 500);
        }
    }

    /**
     * V2: Genereer concrete bookings vanuit recurring patterns (2 weken vooruit).
     * Draait dagelijks.
     */
    public function generateRecurringBookings(Request $request): JsonResponse
    {
        try {
            $service = new \App\Services\RecurringBookingService();
            $generated = $service->generateAll();
            $this->logCronResult('generateRecurringBookings', ['generated' => $generated]);
            return response()->json(['ok' => true, 'generated' => $generated]);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('[Cron] generateRecurringBookings mislukt', ['error' => $e->getMessage()]);
            }
            return response()->json(['ok' => false, 'error' => 'Serverfout bij verwerking.'], 500);
        }
    }

    /**
     * V2: Verlopen waitlist-aanbiedingen afhandelen en doorschuiven naar volgende.
     * Draait elke minuut.
     */
    public function expireWaitlistOffers(Request $request): JsonResponse
    {
        try {
            $service = new \App\Services\WaitlistService();
            $expired = $service->expireOffers();
            $this->logCronResult('expireWaitlistOffers', ['expired' => $expired]);
            return response()->json(['ok' => true, 'expired' => $expired]);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('[Cron] expireWaitlistOffers mislukt', ['error' => $e->getMessage()]);
            }
            return response()->json(['ok' => false, 'error' => 'Serverfout bij verwerking.'], 500);
        }
    }

    /**
     * V2: Verlopen idempotency keys opruimen (ouder dan 24 uur).
     * Draait dagelijks.
     */
    public function cleanupIdempotencyKeys(Request $request): JsonResponse
    {
        try {
            $deleted = 0;
            if (Schema::hasTable('gymies_idempotency_keys')) {
                $deleted = DB::table('gymies_idempotency_keys')
                    ->where('expires_at', '<', now())
                    ->delete();
            }
            $this->logCronResult('cleanupIdempotencyKeys', ['deleted' => $deleted]);
            return response()->json(['ok' => true, 'deleted' => $deleted]);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('[Cron] cleanupIdempotencyKeys mislukt', ['error' => $e->getMessage()]);
            }
            return response()->json(['ok' => false, 'error' => 'Serverfout bij verwerking.'], 500);
        }
    }

    /**
     * Verlopen stories opruimen (soft-delete: verwijder rijen met expires_at < now()).
     * Draait dagelijks samen met idempotency cleanup.
     */
    public function cleanupExpiredStories(Request $request): JsonResponse
    {
        try {
            $deleted = 0;
            if (Schema::hasTable('gymies_trainer_media') && Schema::hasColumn('gymies_trainer_media', 'expires_at')) {
                $deleted = DB::table('gymies_trainer_media')
                    ->where('usage', 'story')
                    ->whereNotNull('expires_at')
                    ->where('expires_at', '<', now())
                    ->delete();
            }
            $this->logCronResult('cleanupExpiredStories', ['deleted' => $deleted]);
            return response()->json(['ok' => true, 'deleted' => $deleted]);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('[Cron] cleanupExpiredStories mislukt', ['error' => $e->getMessage()]);
            }
            return response()->json(['ok' => false, 'error' => 'Serverfout bij verwerking.'], 500);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // MOLLIE PAYMENT RECONCILIATION
    // ════════════════════════════════════════════════════════════════════

    /**
     * Reconcilieer betalingen die in onze DB nog 'pending' staan maar bij Mollie
     * al betaald, verlopen of geannuleerd zijn (gemiste webhooks).
     *
     * Controleert transacties van de afgelopen 48 uur die nog status 'pending'
     * of 'open' hebben, haalt de werkelijke status op bij Mollie, en synchroniseert.
     *
     * Draait elke 30 minuten via scheduler.
     */
    public function reconcileMolliePayments(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_payment_transactions')) {
            return response()->json(['reconciled' => 0, 'message' => 'Payment transactions tabel ontbreekt.']);
        }

        $apiKey = config('gymies.mollie_api_key') ?: (getenv('MOLLIE_API_KEY') ?: '');
        if ($apiKey === '') {
            return response()->json(['reconciled' => 0, 'message' => 'Mollie API key niet geconfigureerd.']);
        }

        $cutoff = now()->subHours(48);
        $reconciled = 0;
        $errors = 0;
        $details = [];

        try {
            // Haal alle "pending" Mollie transacties op die ouder zijn dan 15 min
            // (geef de webhook even de tijd) en jonger dan 48 uur
            $pendingTxs = DB::table('gymies_payment_transactions')
                ->where('provider', 'mollie')
                ->whereIn('status', ['pending', 'open'])
                ->where('created_at', '>', $cutoff)
                ->where('created_at', '<', now()->subMinutes(15))
                ->whereNotNull('provider_transaction_id')
                ->limit(50) // max 50 per run om Mollie rate limits te respecteren
                ->get();

            if ($pendingTxs->isEmpty()) {
                return response()->json([
                    'reconciled' => 0,
                    'checked' => 0,
                    'message' => 'Geen pending transacties om te reconciliëren.',
                ]);
            }

            foreach ($pendingTxs as $tx) {
                try {
                    $mollieId = (string) $tx->provider_transaction_id;
                    if (!preg_match('/^tr_[a-zA-Z0-9]{8,35}$/', $mollieId)) {
                        continue;
                    }

                    // Haal status op bij Mollie
                    $molliePayment = $this->fetchMolliePaymentStatus($apiKey, $mollieId);
                    if ($molliePayment === null) {
                        $errors++;
                        continue;
                    }

                    $mollieStatus = strtolower($molliePayment['status'] ?? '');
                    $ourStatus = strtolower($tx->status ?? '');

                    // Mapping Mollie status → onze status
                    $newStatus = null;
                    $paidAt = null;
                    switch ($mollieStatus) {
                        case 'paid':
                            $newStatus = 'paid';
                            $paidAt = $molliePayment['paidAt'] ?? now()->toIso8601String();
                            break;
                        case 'expired':
                            $newStatus = 'expired';
                            break;
                        case 'canceled':
                        case 'cancelled':
                            $newStatus = 'cancelled';
                            break;
                        case 'failed':
                            $newStatus = 'failed';
                            break;
                        default:
                            // 'open', 'pending' — nog steeds pending bij Mollie, skip
                            continue 2;
                    }

                    // Update transactie
                    $txUpdate = [
                        'status' => $newStatus,
                        'updated_at' => now(),
                    ];
                    if ($paidAt !== null) {
                        $txUpdate['paid_at'] = Carbon::parse($paidAt);
                    }

                    DB::table('gymies_payment_transactions')
                        ->where('id', (int) $tx->id)
                        ->where('status', $ourStatus) // optimistic lock
                        ->update($txUpdate);

                    // Als betaald: update ook de booking status
                    if ($newStatus === 'paid' && !empty($tx->booking_id)) {
                        $this->reconcileBookingStatus((int) $tx->booking_id, $paidAt);
                    }

                    // Als verlopen/geannuleerd: update booking
                    if (in_array($newStatus, ['expired', 'cancelled', 'failed'], true) && !empty($tx->booking_id)) {
                        DB::table('gymies_bookings')
                            ->where('id', (int) $tx->booking_id)
                            ->whereIn('status', ['pending', 'awaiting_payment'])
                            ->update([
                                'status' => 'cancelled',
                                'cancelled_at' => now(),
                                'updated_at' => now(),
                            ]);
                    }

                    $reconciled++;
                    $details[] = [
                        'tx_id' => $tx->id,
                        'mollie_id' => $mollieId,
                        'old_status' => $ourStatus,
                        'new_status' => $newStatus,
                    ];

                } catch (\Throwable $e) {
                    $errors++;
                    Log::warning('[Cron] Mollie reconciliation: fout bij tx', [
                        'tx_id' => $tx->id ?? null,
                        'error' => $e->getMessage(),
                    ]);
                }
            }
        } catch (\Throwable $e) {
            Log::error('[Cron] reconcileMolliePayments fout', ['error' => $e->getMessage()]);
            return response()->json(['ok' => false, 'error' => 'Serverfout bij reconciliatie.'], 500);
        }

        $this->logCronResult('reconcileMolliePayments', [
            'reconciled' => $reconciled,
            'checked' => $pendingTxs->count(),
            'errors' => $errors,
        ]);

        return response()->json([
            'reconciled' => $reconciled,
            'checked' => $pendingTxs->count(),
            'errors' => $errors,
            'details' => $details,
        ]);
    }

    /**
     * Haal payment status op bij Mollie via hun REST API.
     */
    private function fetchMolliePaymentStatus(string $apiKey, string $paymentId): ?array
    {
        try {
            $ch = curl_init("https://api.mollie.com/v2/payments/{$paymentId}");
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTPHEADER => [
                    "Authorization: Bearer {$apiKey}",
                    'Content-Type: application/json',
                ],
                CURLOPT_TIMEOUT => 10,
                CURLOPT_CONNECTTIMEOUT => 5,
            ]);

            $response = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($httpCode !== 200 || $response === false) {
                Log::warning('[Mollie Reconciliation] HTTP fout', [
                    'payment_id' => $paymentId,
                    'http_code' => $httpCode,
                ]);
                return null;
            }

            $data = json_decode($response, true);
            return is_array($data) ? $data : null;

        } catch (\Throwable $e) {
            Log::warning('[Mollie Reconciliation] Curl fout', [
                'payment_id' => $paymentId,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Update booking status na succesvolle betaling (reconciliatie).
     */
    private function reconcileBookingStatus(int $bookingId, ?string $paidAt): void
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return;
        }

        $booking = DB::table('gymies_bookings')
            ->where('id', $bookingId)
            ->first(['id', 'status', 'trainer_user_id', 'client_user_id']);

        if (!$booking) {
            return;
        }

        // Alleen bijwerken als de booking nog in een pre-payment status staat
        if (!in_array($booking->status, ['pending', 'awaiting_payment'], true)) {
            return;
        }

        $update = [
            'status' => 'confirmed',
            'paid_at' => $paidAt ? Carbon::parse($paidAt) : now(),
            'updated_at' => now(),
        ];

        DB::table('gymies_bookings')
            ->where('id', $bookingId)
            ->whereIn('status', ['pending', 'awaiting_payment']) // optimistic lock
            ->update($update);

        // Stuur notificatie naar trainer
        if (Schema::hasTable('gymies_notification_queue')) {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => (int) $booking->trainer_user_id,
                'channel' => 'in_app',
                'event_type' => 'payment_reconciled',
                'payload_json' => json_encode([
                    'booking_id' => (string) $bookingId,
                    'message' => 'Betaling ontvangen (reconciliatie). De boeking is bevestigd.',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        }

        Log::info('[Mollie Reconciliation] Booking gereconcilieerd', [
            'booking_id' => $bookingId,
            'old_status' => $booking->status,
            'new_status' => 'confirmed',
        ]);
    }

    // ─── PAYOUT CRON ───────────────────────────────────────────────────

    /**
     * Verwerk automatische uitbetalingen — 1 dag VAN TEVOREN klaarzetten.
     * Draait dagelijks (bijv. 09:00):
     * - weekly trainers → op DONDERDAG (uitbetaling vrijdag)
     * - monthly trainers → op LAATSTE DAG van de maand (uitbetaling 1e)
     * - daily trainers → direct bij aanvraag (geen cron nodig, gaat via POST payout/request)
     *
     * De cron maakt requests aan met status=pending.
     * Admin ziet ze in het admin-scherm en maakt de volgende dag het geld over.
     *
     * GET/POST cron/process-payouts?key=...
     */
    public function processPayouts(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        GymiesPayoutService::ensureSchema();

        $today = Carbon::today();
        $isThursday = $today->isThursday();
        $isLastDayOfMonth = $today->day === $today->daysInMonth;

        $processed = 0;
        $skipped = 0;
        $errors = 0;
        $details = [];

        // Haal alle trainers op met payout_mode=gymies en saldo >= minimum
        $trainers = DB::table('gymies_trainer_payouts')
            ->where('payout_mode', 'gymies')
            ->where('balance_cents', '>=', GymiesPayoutService::MINIMUM_PAYOUT_CENTS)
            ->whereNotNull('iban')
            ->where('iban', '!=', '')
            ->get();

        foreach ($trainers as $trainer) {
            $frequency = $trainer->payout_frequency;

            // Check of vandaag een voorbereidingsdag is (1 dag voor uitbetaling)
            // Daily trainers doen het zelf via POST payout/request → geen cron
            $shouldProcess = match ($frequency) {
                'weekly' => $isThursday,
                'monthly' => $isLastDayOfMonth,
                default => false, // 'daily' wordt direct afgehandeld bij aanvraag
            };

            if (!$shouldProcess) {
                $skipped++;
                continue;
            }

            // Check of er al een pending request is
            $hasPending = DB::table('gymies_payout_requests')
                ->where('user_id', $trainer->user_id)
                ->where('status', 'pending')
                ->exists();

            if ($hasPending) {
                $skipped++;
                continue;
            }

            try {
                $result = GymiesPayoutService::requestPayout((int) $trainer->user_id, $frequency);
                if ($result['success']) {
                    $processed++;
                    $details[] = [
                        'user_id' => $trainer->user_id,
                        'frequency' => $frequency,
                        'request_id' => $result['request_id'] ?? null,
                    ];

                    // Push notificatie naar trainer: "Je uitbetaling staat klaar"
                    try {
                        if (class_exists(FcmPushHelper::class)) {
                            FcmPushHelper::sendToUser(
                                (int) $trainer->user_id,
                                'Uitbetaling klaar',
                                'Je uitbetaling van €' . number_format(($result['net_amount'] ?? ((int) $trainer->balance_cents - GymiesPayoutService::payoutFeeForFrequency($frequency))) / 100, 2, ',', '.') . ' wordt morgen overgemaakt.',
                                ['type' => 'payout_ready', 'request_id' => (string) ($result['request_id'] ?? '')]
                            );
                        }
                    } catch (\Throwable $pushEx) {
                        // Push mag nooit falen
                    }
                } else {
                    $skipped++;
                }
            } catch (\Throwable $e) {
                $errors++;
                Log::warning('[Cron] processPayouts: fout bij trainer', [
                    'user_id' => $trainer->user_id,
                    'error' => $e->getMessage(),
                ]);
                if (app()->bound('sentry')) {
                    app('sentry')->captureException($e);
                }
            }
        }

        $this->logCronResult('processPayouts', [
            'processed' => $processed,
            'skipped' => $skipped,
            'errors' => $errors,
            'is_thursday' => $isThursday,
            'is_last_day_of_month' => $isLastDayOfMonth,
        ]);

        return response()->json([
            'processed' => $processed,
            'skipped' => $skipped,
            'errors' => $errors,
            'total_trainers_checked' => $trainers->count(),
            'details' => $details,
        ]);
    }

    /**
     * Verwerk gym-settlementementen automatisch op vaste schema (maandelijks op 1e, wekelijks op maandag).
     * Calculeert inkomsten, past platform-fee toe, en maakt settlement record (status 'pending').
     * Cron: maandelijks op 1e om 06:00, wekelijks op maandag om 06:00.
     */
    public function processGymSettlements(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_organisation_settlements') || !Schema::hasTable('gymies_organisations')) {
            return response()->json(['message' => 'Tabellen ontbreken', 'processed' => 0], 422);
        }

        if (!Schema::hasTable('gymies_payment_transactions')) {
            return response()->json(['message' => 'Payment transactions tabel ontbreekt', 'processed' => 0], 422);
        }

        $today = Carbon::today();
        $isMonday = $today->isMonday();
        $isFirstDayOfMonth = $today->day === 1;

        $processed = 0;
        $skipped = 0;
        $errors = 0;
        $details = [];

        // Bepaal period (vorige dag voor wekelijks, vorige maand voor maandelijks)
        if ($isMonday) {
            // Wekelijks: vorige week (maandag-zondag)
            $periodEnd = $today->copy()->subDay();
            $periodStart = $periodEnd->copy()->startOfWeek();
        } else if ($isFirstDayOfMonth) {
            // Maandelijks: vorige maand (1e-laatste dag)
            $periodEnd = $today->copy()->subDay();
            $periodStart = $periodEnd->copy()->startOfMonth();
        } else {
            // Niet op een planningsdag
            return response()->json([
                'processed' => 0,
                'message' => 'Geen settlement planning voor vandaag',
                'is_monday' => $isMonday,
                'is_first_of_month' => $isFirstDayOfMonth,
            ]);
        }

        // Haal alle organisaties op met payout_mode='gymies'
        $organisations = DB::table('gymies_organisations')
            ->where('payout_mode', 'gymies')
            ->whereNotNull('payout_iban')
            ->where('payout_iban', '!=', '')
            ->get();

        foreach ($organisations as $org) {
            $frequency = $org->payout_frequency;

            // Check of deze org vandaag moet worden verwerkt
            $shouldProcess = match ($frequency) {
                'weekly' => $isMonday,
                'monthly' => $isFirstDayOfMonth,
                default => false,
            };

            if (!$shouldProcess) {
                $skipped++;
                continue;
            }

            // Check of er al een pending settlement voor deze periode bestaat
            $hasPending = DB::table('gymies_organisation_settlements')
                ->where('organisation_id', (int) $org->id)
                ->where('period_start', $periodStart->toDateString())
                ->where('period_end', $periodEnd->toDateString())
                ->where('status', 'pending')
                ->exists();

            if ($hasPending) {
                $skipped++;
                continue;
            }

            try {
                DB::transaction(function () use ($org, $periodStart, $periodEnd, &$processed, &$details) {
                    // Bereken inkomsten: payments waar mollie_account_source='organisation' en org_id matcht
                    $transactions = DB::table('gymies_payment_transactions')
                        ->where('organisation_id', (int) $org->id)
                        ->where('mollie_account_source', 'organisation')
                        ->whereBetween('created_at', [
                            $periodStart->startOfDay(),
                            $periodEnd->endOfDay(),
                        ])
                        ->whereIn('status', ['success', 'paid'])
                        ->get(['id', 'amount_cents']);

                    $grossCents = (int) $transactions->sum('amount_cents');
                    $numBookings = $transactions->count();
                    $feeCents = $numBookings * GymiesPayoutService::BOOKING_FEE_CENTS;
                    $netAmountCents = max($grossCents - $feeCents, 0);

                    // Maak settlement record
                    $settlementId = DB::table('gymies_organisation_settlements')->insertGetId([
                        'organisation_id' => (int) $org->id,
                        'amount_cents' => $grossCents,
                        'fee_cents' => $feeCents,
                        'net_amount_cents' => $netAmountCents,
                        'status' => 'pending',
                        'period_start' => $periodStart->toDateString(),
                        'period_end' => $periodEnd->toDateString(),
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);

                    $processed++;
                    $details[] = [
                        'organisation_id' => (int) $org->id,
                        'settlement_id' => $settlementId,
                        'frequency' => $frequency,
                        'gross_cents' => $grossCents,
                        'fee_cents' => $feeCents,
                        'net_cents' => $netAmountCents,
                        'num_transactions' => $numBookings,
                    ];
                });
            } catch (\Throwable $e) {
                $errors++;
                Log::warning('[Cron] processGymSettlements: fout bij organisatie', [
                    'organisation_id' => $org->id,
                    'error' => $e->getMessage(),
                ]);
                if (app()->bound('sentry')) {
                    app('sentry')->captureException($e);
                }
            }
        }

        $this->logCronResult('processGymSettlements', [
            'processed' => $processed,
            'skipped' => $skipped,
            'errors' => $errors,
            'is_monday' => $isMonday,
            'is_first_of_month' => $isFirstDayOfMonth,
            'period_start' => $periodStart->toDateString(),
            'period_end' => $periodEnd->toDateString(),
        ]);

        return response()->json([
            'processed' => $processed,
            'skipped' => $skipped,
            'errors' => $errors,
            'total_organisations_checked' => $organisations->count(),
            'details' => $details,
        ]);
    }

    // ─────────────────────────────────────────────────────────
    //  ONBOARDING CRON JOBS (Fase D)
    // ─────────────────────────────────────────────────────────

    /**
     * Trial reminders: stuur push naar trainers met trial halverwege of bijna afgelopen.
     * Cron: dagelijks om 09:00.
     */
    public function onboardingTrialReminders(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Tabel niet gevonden', 'sent' => 0]);
        }

        $notifier = new \App\Services\OnboardingNotificationService();
        $now = now();
        $sent = ['halfway' => 0, 'expiring_soon' => 0];

        // Actieve trainers met lopende trial
        $trainers = DB::table('gymies_trainer_profiles')
            ->join('gymies_users', 'gymies_trainer_profiles.user_id', '=', 'gymies_users.id')
            ->where('gymies_trainer_profiles.onboarding_status', 'active')
            ->whereNotNull('gymies_trainer_profiles.trial_started_at')
            ->whereNotNull('gymies_trainer_profiles.trial_ends_at')
            ->where('gymies_trainer_profiles.trial_ends_at', '>', $now)
            ->get([
                'gymies_trainer_profiles.user_id',
                'gymies_trainer_profiles.trial_started_at',
                'gymies_trainer_profiles.trial_ends_at',
                'gymies_users.display_name',
            ]);

        foreach ($trainers as $t) {
            $trialStart = \Carbon\Carbon::parse($t->trial_started_at);
            $trialEnd = \Carbon\Carbon::parse($t->trial_ends_at);
            $totalDays = $trialStart->diffInDays($trialEnd);
            $daysLeft = (int) $now->diffInDays($trialEnd, false);
            $halfwayDay = (int) ceil($totalDays / 2);
            $daysPassed = (int) $trialStart->diffInDays($now);
            $name = $t->display_name ?? 'Trainer';

            // Halverwege: stuur exact op de dag dat de helft bereikt is
            if ($daysPassed === $halfwayDay) {
                $notifier->notifyTrialHalfway($t->user_id, $name, $daysLeft);
                $sent['halfway']++;
            }

            // Bijna afgelopen: 3 dagen resterend
            if ($daysLeft === 3) {
                $notifier->notifyTrialExpiringSoon($t->user_id, $name, $daysLeft);
                $sent['expiring_soon']++;
            }
        }

        $this->logCronResult('onboarding_trial_reminders', $sent);
        return response()->json($sent);
    }

    /**
     * Onboarding nudges: herinnering aan trainers die registratie niet afmaken.
     * Cron: dagelijks om 10:00.
     */
    public function onboardingNudges(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Tabel niet gevonden', 'sent' => 0]);
        }

        $notifier = new \App\Services\OnboardingNotificationService();
        $now = now();
        $sent = ['push_nudge' => 0, 'email_24h' => 0, 'email_72h' => 0];

        // Trainers met status 'incomplete' — onboarding niet afgemaakt
        $incomplete = DB::table('gymies_trainer_profiles')
            ->join('gymies_users', 'gymies_trainer_profiles.user_id', '=', 'gymies_users.id')
            ->where('gymies_trainer_profiles.onboarding_status', 'incomplete')
            ->where('gymies_trainer_profiles.created_at', '>', $now->copy()->subDays(7))
            ->get([
                'gymies_trainer_profiles.user_id',
                'gymies_trainer_profiles.created_at',
                'gymies_users.display_name',
            ]);

        foreach ($incomplete as $t) {
            $createdAt = \Carbon\Carbon::parse($t->created_at);
            $hoursAgo = (int) $createdAt->diffInHours($now);
            $name = $t->display_name ?? 'Trainer';

            // 24u email herinnering (22-26u window om edge cases op te vangen)
            if ($hoursAgo >= 22 && $hoursAgo <= 26) {
                $notifier->sendOnboardingReminder24h($t->user_id, $name);
                $sent['email_24h']++;
            }

            // 72u email nudge (70-74u window)
            if ($hoursAgo >= 70 && $hoursAgo <= 74) {
                $notifier->sendOnboardingNudge72h($t->user_id, $name);
                $notifier->notifyOnboardingNudge($t->user_id, $name); // ook push
                $sent['email_72h']++;
                $sent['push_nudge']++;
            }
        }

        $this->logCronResult('onboarding_nudges', $sent);
        return response()->json($sent);
    }

    /**
     * Betaalherinneringen: trainers die goedgekeurd zijn maar mandaat niet afgerond.
     * Cron: dagelijks om 11:00.
     */
    public function onboardingPaymentReminders(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Tabel niet gevonden', 'sent' => 0]);
        }

        $notifier = new \App\Services\OnboardingNotificationService();
        $now = now();
        $sent = 0;

        // Goedgekeurde trainers zonder mandaat (approved maar niet active)
        $pending = DB::table('gymies_trainer_profiles')
            ->join('gymies_users', 'gymies_trainer_profiles.user_id', '=', 'gymies_users.id')
            ->where('gymies_trainer_profiles.onboarding_status', 'approved')
            ->whereNull('gymies_trainer_profiles.mollie_mandate_id')
            ->whereNotNull('gymies_trainer_profiles.approved_at')
            ->get([
                'gymies_trainer_profiles.user_id',
                'gymies_trainer_profiles.approved_at',
                'gymies_users.display_name',
            ]);

        foreach ($pending as $t) {
            $approvedAt = \Carbon\Carbon::parse($t->approved_at);
            $hoursAgo = (int) $approvedAt->diffInHours($now);
            $name = $t->display_name ?? 'Trainer';

            // Herinnering na 24u, 72u en 168u (1 week)
            $attempt = match (true) {
                $hoursAgo >= 22 && $hoursAgo <= 26   => 1,
                $hoursAgo >= 70 && $hoursAgo <= 74   => 2,
                $hoursAgo >= 166 && $hoursAgo <= 170 => 3,
                default => 0,
            };

            if ($attempt > 0) {
                $notifier->notifyPaymentReminder($t->user_id, $name, $attempt);
                $sent++;
            }
        }

        $this->logCronResult('onboarding_payment_reminders', ['sent' => $sent]);
        return response()->json(['sent' => $sent]);
    }

    /**
     * Smart trial suggesties: detecteer actieve trainers waarvan trial bijna afloopt.
     * Cron: dagelijks om 08:00.
     */
    public function onboardingSmartTrialSuggestions(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        // Check of smart trial extension flag actief is
        if (!GymiesFeatureFlags::isEnabled('smart_trial_extension')) {
            return response()->json(['message' => 'Smart trial extension uitgeschakeld', 'suggestions' => 0]);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Tabel niet gevonden', 'suggestions' => 0]);
        }

        $trialService = new \App\Services\TrialExtensionService();
        $notifier = new \App\Services\OnboardingNotificationService();
        $now = now();
        $suggested = 0;

        // Trainers waarvan trial over 5 dagen of minder afloopt
        $trainers = DB::table('gymies_trainer_profiles')
            ->join('gymies_users', 'gymies_trainer_profiles.user_id', '=', 'gymies_users.id')
            ->where('gymies_trainer_profiles.onboarding_status', 'active')
            ->whereNotNull('gymies_trainer_profiles.trial_ends_at')
            ->whereBetween('gymies_trainer_profiles.trial_ends_at', [$now, $now->copy()->addDays(5)])
            ->get([
                'gymies_trainer_profiles.id as trainer_id',
                'gymies_trainer_profiles.user_id',
                'gymies_trainer_profiles.trial_ends_at',
                'gymies_users.display_name',
            ]);

        foreach ($trainers as $t) {
            // Check of verlenging nog mogelijk is
            $canExtend = $trialService->canExtend($t->trainer_id);
            if (!$canExtend['can_extend']) {
                continue;
            }

            // Bereken activiteitsscore
            $snapshot = $trialService->getActivitySnapshot($t->trainer_id);
            $score = (float) ($snapshot['activity_score'] ?? 0);

            // Alleen suggereren bij actieve trainers (score > 30%)
            if ($score < 30) {
                continue;
            }

            $daysLeft = (int) $now->diffInDays(\Carbon\Carbon::parse($t->trial_ends_at), false);
            $name = $t->display_name ?? 'Trainer';

            $notifier->notifyStaffSmartTrialSuggestion($t->trainer_id, $name, $score, $daysLeft);
            $suggested++;
        }

        $this->logCronResult('onboarding_smart_trial_suggestions', ['suggested' => $suggested]);
        return response()->json(['suggestions' => $suggested]);
    }

    /**
     * SLA waarschuwingen: reviews die langer dan 24u wachten.
     * Cron: elk uur.
     */
    public function onboardingSlaWarnings(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Tabel niet gevonden', 'warnings' => 0]);
        }

        $notifier = new \App\Services\OnboardingNotificationService();
        $now = now();
        $warned = 0;

        // SLA uren uit feature flag (standaard 48 uur)
        $slaHours = GymiesFeatureFlags::getInt('review_sla_hours', 48);

        // Trainers in pending_review langer dan SLA uren
        $pending = DB::table('gymies_trainer_profiles')
            ->join('gymies_users', 'gymies_trainer_profiles.user_id', '=', 'gymies_users.id')
            ->where('gymies_trainer_profiles.onboarding_status', 'pending_review')
            ->where('gymies_trainer_profiles.updated_at', '<', $now->copy()->subHours($slaHours))
            ->get([
                'gymies_trainer_profiles.id as trainer_id',
                'gymies_trainer_profiles.user_id',
                'gymies_trainer_profiles.updated_at',
                'gymies_users.display_name',
            ]);

        foreach ($pending as $t) {
            $hoursWaiting = (int) \Carbon\Carbon::parse($t->updated_at)->diffInHours($now);
            $name = $t->display_name ?? 'Trainer';

            // Stuur waarschuwing elke SLA-interval (bijv. 48, 96, 144, etc.)
            if ($hoursWaiting % $slaHours < 2) { // 2u window rond elk SLA mark
                $notifier->notifyStaffSlaWarning($t->trainer_id, $name, $hoursWaiting);
                $warned++;
            }
        }

        $this->logCronResult('onboarding_sla_warnings', ['warned' => $warned]);
        return response()->json(['warnings' => $warned]);
    }

    /**
     * cron/evaluate-regions
     * For each region with status != 'open':
     *   1. Call GymiesLaunchGateService::updateRegionCounters()
     *   2. Call GymiesLaunchGateService::evaluateRegionReadiness()
     *   3. If ready AND status is currently 'waitlist' or 'invite_only': auto-change to 'open' + activate waitlist
     *   4. Log results
     *
     * For each region with status = 'open':
     *   1. Update counters
     *   2. Check if ratio is getting too high (> max_client_trainer_ratio) — log warning
     *
     * Send weekly status emails to waitlist users (check notified_at to avoid spam —
     * only if notified_at is null or > 7 days ago).
     *
     * Return summary JSON.
     */
    public function evaluateRegions(Request $request): JsonResponse
    {
        if (!$this->validateCronKey($request)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        GymiesLaunchGateService::ensureSchema();

        $results = [
            'evaluated_regions' => 0,
            'auto_opened' => 0,
            'warnings' => [],
            'notified_waitlist_users' => 0,
        ];

        try {
            $regions = DB::table('gymies_launch_regions')->get();

            foreach ($regions as $region) {
                $slug = (string) $region->slug;
                $status = (string) $region->status;

                // Step 1: Update counters
                GymiesLaunchGateService::updateRegionCounters($slug);

                // Step 2: Evaluate readiness
                $readiness = GymiesLaunchGateService::evaluateRegionReadiness($slug);

                if ($status !== 'open') {
                    // Step 3: Auto-open if ready and status is waitlist or invite_only
                    if ($readiness['ready'] && in_array($status, ['waitlist', 'invite_only'], true)) {
                        DB::table('gymies_launch_regions')
                            ->where('slug', $slug)
                            ->update([
                                'status' => 'open',
                                'opened_at' => now(),
                                'updated_at' => now(),
                            ]);

                        $activated = GymiesLaunchGateService::activateWaitlistForRegion($slug);
                        $results['auto_opened']++;

                        Log::info('[CronController] Auto-opened region', [
                            'slug' => $slug,
                            'previous_status' => $status,
                            'activated_users' => $activated,
                        ]);
                    } else {
                        // Log the recommendation
                        Log::info('[CronController] Region readiness', [
                            'slug' => $slug,
                            'status' => $status,
                            'ready' => $readiness['ready'],
                            'recommendation' => $readiness['recommendation'],
                        ]);
                    }

                    $results['evaluated_regions']++;
                } else {
                    // Region is already open
                    $maxRatio = (int) $region->max_client_trainer_ratio;
                    $currentRatio = $readiness['ratio'];

                    if ($currentRatio > $maxRatio) {
                        $results['warnings'][] = [
                            'slug' => $slug,
                            'message' => 'Client-trainer ratio too high',
                            'current_ratio' => $currentRatio,
                            'max_ratio' => $maxRatio,
                            'trainers' => $readiness['trainers'],
                            'clients' => $readiness['clients'],
                        ];

                        Log::warning('[CronController] Region ratio warning', [
                            'slug' => $slug,
                            'current_ratio' => $currentRatio,
                            'max_ratio' => $maxRatio,
                        ]);
                    }

                    $results['evaluated_regions']++;
                }
            }

            // Send weekly notification emails to waitlist users
            if (Schema::hasTable('gymies_waitlist')) {
                $now = now();
                $sevenDaysAgo = $now->copy()->subDays(7);

                $waitlistUsers = DB::table('gymies_waitlist')
                    ->where('status', 'waiting')
                    ->where(function ($q) use ($sevenDaysAgo) {
                        $q->whereNull('notified_at')
                            ->orWhere('notified_at', '<', $sevenDaysAgo);
                    })
                    ->get(['id', 'user_id', 'region_slug', 'role', 'position']);

                foreach ($waitlistUsers as $entry) {
                    try {
                        // Send notification email
                        if (Schema::hasTable('gymies_users')) {
                            $user = DB::table('gymies_users')
                                ->where('id', $entry->user_id)
                                ->first(['email', 'first_name', 'last_name']);

                            if ($user && $user->email) {
                                // Get region details
                                $region = DB::table('gymies_launch_regions')
                                    ->where('slug', $entry->region_slug)
                                    ->first();

                                // Build notification (simplified)
                                $message = "Je staat op de wachtlijst voor {$region->city} (positie {$entry->position}).";

                                // In production, send email here
                                // Mail::to($user->email)->send(new WaitlistStatusNotification($message));

                                // Update notified_at
                                DB::table('gymies_waitlist')
                                    ->where('id', $entry->id)
                                    ->update(['notified_at' => $now]);

                                $results['notified_waitlist_users']++;
                            }
                        }
                    } catch (\Throwable $e) {
                        Log::error('[CronController] Failed to notify waitlist user', [
                            'user_id' => $entry->user_id,
                            'error' => $e->getMessage(),
                        ]);
                    }
                }
            }

            $this->logCronResult('evaluate_regions', $results);

            return response()->json([
                'success' => true,
                'message' => 'Regio evaluatie voltooid',
                'data' => $results,
            ]);
        } catch (\Throwable $e) {
            Log::error('[CronController] evaluateRegions failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Regio evaluatie mislukt',
                'error' => $e->getMessage(),
            ], 500);
        }
    }
}
