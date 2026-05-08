<?php

declare(strict_types=1);

namespace App\Services;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Waitlist Service.
 *
 * Beheert de wachtlijst wanneer slots vol zijn.
 *
 * Flow:
 * 1. Klant wil slot dat vol is → joinWaitlist()
 * 2. Boeking wordt geannuleerd → onBookingCancelled()
 *    → Eerste op wachtlijst krijgt aanbod (status=offered, 15 min claim window)
 * 3. Klant claimt het aanbod → claimOffer()
 *    → Nieuwe booking wordt aangemaakt
 * 4. Claim verloopt → expireOffers() (scheduled job)
 *    → Volgende op wachtlijst krijgt aanbod
 */
class WaitlistService
{
    private const TABLE = 'gymies_waitlist';
    private const CLAIM_WINDOW_MINUTES = 15;

    /**
     * Voeg klant toe aan wachtlijst voor een specifiek slot.
     *
     * @return array{success: bool, message: string, position: int}
     */
    public function joinWaitlist(
        int    $clientUserId,
        int    $trainerUserId,
        string $desiredDate,
        string $desiredTime,
        int    $durationMinutes = 60,
    ): array {
        if (!Schema::hasTable(self::TABLE)) {
            return ['success' => false, 'message' => 'Wachtlijst niet beschikbaar.', 'position' => 0];
        }

        // Check of al op wachtlijst
        $existing = DB::table(self::TABLE)
            ->where('client_user_id', $clientUserId)
            ->where('trainer_user_id', $trainerUserId)
            ->where('desired_date', $desiredDate)
            ->where('desired_time', $desiredTime)
            ->whereIn('status', ['waiting', 'offered'])
            ->first();

        if ($existing) {
            return [
                'success' => false,
                'message' => 'Je staat al op de wachtlijst voor dit tijdslot.',
                'position' => (int) $existing->position,
            ];
        }

        // Bepaal positie binnen transactie met lock om race condition te voorkomen
        $position = null;
        DB::transaction(function() use (
            $clientUserId,
            $trainerUserId,
            $desiredDate,
            $desiredTime,
            $durationMinutes,
            &$position
        ) {
            $maxPosition = (int) DB::table(self::TABLE)
                ->where('trainer_user_id', $trainerUserId)
                ->where('desired_date', $desiredDate)
                ->where('desired_time', $desiredTime)
                ->whereIn('status', ['waiting', 'offered'])
                ->lockForUpdate()
                ->max('position') ?? 0;

            $position = $maxPosition + 1;

            DB::table(self::TABLE)->insert([
                'client_user_id' => $clientUserId,
                'trainer_user_id' => $trainerUserId,
                'desired_date' => $desiredDate,
                'desired_time' => $desiredTime,
                'desired_duration_minutes' => $durationMinutes,
                'position' => $position,
                'status' => 'waiting',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });

        return [
            'success' => true,
            'message' => "Je staat op positie {$position} van de wachtlijst.",
            'position' => $position,
        ];
    }

    /**
     * Trigger wanneer een booking geannuleerd wordt.
     * Biedt het slot aan de eerste op de wachtlijst aan.
     */
    public function onBookingCancelled(int $trainerUserId, string $slotDate, string $slotTime, int $cancelledBookingId): void
    {
        if (!Schema::hasTable(self::TABLE)) {
            return;
        }

        // Vind de eerste wachtende
        $next = DB::table(self::TABLE)
            ->where('trainer_user_id', $trainerUserId)
            ->where('desired_date', $slotDate)
            ->where('desired_time', $slotTime)
            ->where('status', 'waiting')
            ->orderBy('position')
            ->first();

        if (!$next) {
            return;
        }

        $expiresAt = now()->addMinutes(self::CLAIM_WINDOW_MINUTES);

        DB::table(self::TABLE)
            ->where('id', $next->id)
            ->update([
                'status' => 'offered',
                'offered_at' => now(),
                'expires_at' => $expiresAt,
                'released_booking_id' => $cancelledBookingId,
                'updated_at' => now(),
            ]);

        // Stuur push notificatie
        $this->notifyOffer($next, $slotDate, $slotTime, $expiresAt);
    }

    /**
     * Klant claimt een waitlist-aanbod en boekt het slot.
     *
     * @return array{success: bool, message: string, booking_id: ?int}
     */
    public function claimOffer(int $waitlistId, int $clientUserId): array
    {
        if (!Schema::hasTable(self::TABLE)) {
            return ['success' => false, 'message' => 'Wachtlijst niet beschikbaar.', 'booking_id' => null];
        }

        $entry = DB::table(self::TABLE)
            ->where('id', $waitlistId)
            ->where('client_user_id', $clientUserId)
            ->where('status', 'offered')
            ->first();

        if (!$entry) {
            return ['success' => false, 'message' => 'Aanbod niet gevonden of verlopen.', 'booking_id' => null];
        }

        // Check of claim window nog open is
        if ($entry->expires_at && Carbon::parse($entry->expires_at)->isPast()) {
            DB::table(self::TABLE)
                ->where('id', $entry->id)
                ->update(['status' => 'expired', 'updated_at' => now()]);

            // Offer naar volgende
            $this->offerToNext(
                (int) $entry->trainer_user_id,
                $entry->desired_date,
                $entry->desired_time,
                (int) ($entry->released_booking_id ?? 0),
            );

            return ['success' => false, 'message' => 'Aanbod is verlopen. Het slot gaat naar de volgende op de wachtlijst.', 'booking_id' => null];
        }

        // Maak booking aan binnen een transactie
        $bookingId = null;
        DB::beginTransaction();
        try {
            // Check overlap (een andere booking kan intussen zijn gemaakt)
            $scheduledAt = "{$entry->desired_date} {$entry->desired_time}:00";
            $duration = (int) $entry->desired_duration_minutes;

            $overlap = DB::table('gymies_bookings')
                ->where('trainer_user_id', $entry->trainer_user_id)
                ->whereIn('status', ['pending', 'confirmed', 'reserved'])
                ->lockForUpdate()
                ->whereRaw("? < DATE_ADD(scheduled_at, INTERVAL duration_minutes MINUTE) AND DATE_ADD(?, INTERVAL ? MINUTE) > scheduled_at", [
                    $scheduledAt, $scheduledAt, $duration,
                ])
                ->exists();

            if ($overlap) {
                DB::rollBack();
                return ['success' => false, 'message' => 'Het slot is helaas al door iemand anders geboekt.', 'booking_id' => null];
            }

            $scheduledCarbon = Carbon::parse($scheduledAt);
            $payload = [
                'client_user_id' => $entry->client_user_id,
                'trainer_user_id' => $entry->trainer_user_id,
                'scheduled_at' => $scheduledAt,
                'duration_minutes' => $duration,
                'status' => 'confirmed',
                'created_at' => now(),
                'updated_at' => now(),
            ];

            if (Schema::hasColumn('gymies_bookings', 'slot_date')) {
                $payload['slot_date'] = $scheduledCarbon->format('Y-m-d');
            }
            if (Schema::hasColumn('gymies_bookings', 'day_of_week')) {
                $payload['day_of_week'] = (int) $scheduledCarbon->format('N');
            }

            $bookingId = DB::table('gymies_bookings')->insertGetId($payload);

            DB::table(self::TABLE)
                ->where('id', $entry->id)
                ->update([
                    'status' => 'claimed',
                    'claimed_booking_id' => $bookingId,
                    'updated_at' => now(),
                ]);

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            return ['success' => false, 'message' => 'Er ging iets mis bij het boeken. Probeer opnieuw.', 'booking_id' => null];
        }

        return [
            'success' => true,
            'message' => 'Sessie geboekt via de wachtlijst!',
            'booking_id' => $bookingId,
        ];
    }

    /**
     * Verloop verlopen aanbiedingen en schuif door naar de volgende.
     * Wordt aangeroepen als scheduled job (elke minuut).
     *
     * @return int Aantal verlopen aanbiedingen
     */
    public function expireOffers(): int
    {
        if (!Schema::hasTable(self::TABLE)) {
            return 0;
        }

        $expired = DB::table(self::TABLE)
            ->where('status', 'offered')
            ->where('expires_at', '<=', now())
            ->get();

        foreach ($expired as $entry) {
            DB::table(self::TABLE)
                ->where('id', $entry->id)
                ->update(['status' => 'expired', 'updated_at' => now()]);

            // Bied aan de volgende aan
            $this->offerToNext(
                (int) $entry->trainer_user_id,
                $entry->desired_date,
                $entry->desired_time,
                (int) ($entry->released_booking_id ?? 0),
            );
        }

        return count($expired);
    }

    /**
     * Bied het slot aan de volgende wachtende aan.
     */
    private function offerToNext(int $trainerUserId, string $date, string $time, int $releasedBookingId): void
    {
        $next = DB::table(self::TABLE)
            ->where('trainer_user_id', $trainerUserId)
            ->where('desired_date', $date)
            ->where('desired_time', $time)
            ->where('status', 'waiting')
            ->orderBy('position')
            ->first();

        if (!$next) {
            return;
        }

        $expiresAt = now()->addMinutes(self::CLAIM_WINDOW_MINUTES);

        DB::table(self::TABLE)
            ->where('id', $next->id)
            ->update([
                'status' => 'offered',
                'offered_at' => now(),
                'expires_at' => $expiresAt,
                'released_booking_id' => $releasedBookingId,
                'updated_at' => now(),
            ]);

        $this->notifyOffer($next, $date, $time, $expiresAt);
    }

    /**
     * Stuur push notificatie over wachtlijst-aanbod.
     */
    private function notifyOffer(object $entry, string $date, string $time, Carbon $expiresAt): void
    {
        $formattedDate = Carbon::parse($date)->format('d-m-Y');
        $clientUserId = (int) $entry->client_user_id;

        // In-app notification queue
        if (Schema::hasTable('gymies_notification_queue')) {
            try {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => $clientUserId,
                    'channel' => 'push',
                    'event_type' => 'waitlist_slot_available',
                    'payload_json' => json_encode([
                        'waitlist_id' => (string) $entry->id,
                        'trainer_user_id' => (string) $entry->trainer_user_id,
                        'date' => $date,
                        'time' => $time,
                        'expires_at' => $expiresAt->toIso8601String(),
                        'message' => "Er is een plek vrijgekomen op {$formattedDate} om {$time}! Claim binnen 15 minuten.",
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            } catch (\Throwable) {
                // Silently ignore queue failures
            }
        }

        // Direct FCM push notificatie
        try {
            $trainerName = DB::table('gymies_users')
                ->where('id', $entry->trainer_user_id)
                ->value('display_name') ?? 'je trainer';

            \App\Http\Controllers\Gymies\FcmPushHelper::sendToUser(
                $clientUserId,
                "Plek vrijgekomen bij {$trainerName}!",
                "Op {$formattedDate} om {$time} is een plek vrij. Claim binnen 15 minuten!",
                [
                    'type'             => 'waitlist_spot_available',
                    'action'           => 'claim_offer',
                    'screen'           => 'waitlist_offer',
                    'waitlist_id'      => (string) $entry->id,
                    'trainer_user_id'  => (string) $entry->trainer_user_id,
                    'date'             => $date,
                    'time'             => $time,
                    'expires_at'       => $expiresAt->toIso8601String(),
                ]
            );
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('FCM waitlist offer push failed', ['error' => $e->getMessage()]);
        }
    }

    // ─── Groepslessen wachtlijst integratie ─────────────────────

    /**
     * Trigger wanneer een deelnemer zich afmeldt voor een groepsles.
     * Biedt de plek aan de eerste op de groepslessen-wachtlijst aan.
     */
    public function onGroupSessionCancelled(int $groupSessionId): void
    {
        if (!Schema::hasTable('gymies_group_session_waitlist')) {
            return;
        }

        $session = DB::table('gymies_group_sessions')->where('id', $groupSessionId)->first();
        if (!$session) return;

        // Check of er nu plek is
        $participantCount = DB::table('gymies_group_session_participants')
            ->where('group_session_id', $groupSessionId)
            ->whereIn('status', ['confirmed', 'checked_in'])
            ->count();

        $maxParticipants = (int) ($session->max_participants ?? 0);
        if ($maxParticipants > 0 && $participantCount >= $maxParticipants) {
            return; // Nog steeds vol
        }

        // Vind eerste wachtende
        $next = DB::table('gymies_group_session_waitlist')
            ->where('group_session_id', $groupSessionId)
            ->where('status', 'waiting')
            ->orderBy('position')
            ->first();

        if (!$next) return;

        $expiresAt = now()->addMinutes(self::CLAIM_WINDOW_MINUTES);

        DB::table('gymies_group_session_waitlist')
            ->where('id', $next->id)
            ->update([
                'status'     => 'offered',
                'offered_at' => now(),
                'expires_at' => $expiresAt,
                'updated_at' => now(),
            ]);

        // FCM push notificatie
        try {
            $sessionTitle = $session->title ?? 'Groepsles';
            $scheduledAt  = $session->scheduled_at ?? '';

            (new OnboardingNotificationService())->notifyWaitlistSpotAvailable(
                (int) $next->user_id,
                $sessionTitle,
                $scheduledAt,
                $groupSessionId
            );
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('FCM group waitlist push failed', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Klant claimt een groepsles-wachtlijst aanbod.
     *
     * @return array{success: bool, message: string}
     */
    public function claimGroupSessionOffer(int $waitlistId, int $userId): array
    {
        if (!Schema::hasTable('gymies_group_session_waitlist')) {
            return ['success' => false, 'message' => 'Wachtlijst niet beschikbaar.'];
        }

        $entry = DB::table('gymies_group_session_waitlist')
            ->where('id', $waitlistId)
            ->where('user_id', $userId)
            ->where('status', 'offered')
            ->first();

        if (!$entry) {
            return ['success' => false, 'message' => 'Aanbod niet gevonden of verlopen.'];
        }

        // Check expiry
        if ($entry->expires_at && Carbon::parse($entry->expires_at)->isPast()) {
            DB::table('gymies_group_session_waitlist')
                ->where('id', $entry->id)
                ->update(['status' => 'expired', 'updated_at' => now()]);

            $this->onGroupSessionCancelled((int) $entry->group_session_id);
            return ['success' => false, 'message' => 'Aanbod is verlopen. De plek gaat naar de volgende.'];
        }

        // Schrijf in als deelnemer
        DB::beginTransaction();
        try {
            DB::table('gymies_group_session_participants')->insert([
                'group_session_id' => $entry->group_session_id,
                'user_id'          => $userId,
                'status'           => 'confirmed',
                'created_at'       => now(),
            ]);

            DB::table('gymies_group_session_waitlist')
                ->where('id', $entry->id)
                ->update(['status' => 'claimed', 'updated_at' => now()]);

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            return ['success' => false, 'message' => 'Inschrijving mislukt. Probeer opnieuw.'];
        }

        return ['success' => true, 'message' => 'Je bent ingeschreven voor de groepsles!'];
    }

    /**
     * Expire verlopen groepslessen-wachtlijst aanbiedingen.
     *
     * @return int Aantal verlopen aanbiedingen
     */
    public function expireGroupSessionOffers(): int
    {
        if (!Schema::hasTable('gymies_group_session_waitlist')) {
            return 0;
        }

        $expired = DB::table('gymies_group_session_waitlist')
            ->where('status', 'offered')
            ->where('expires_at', '<=', now())
            ->get();

        foreach ($expired as $entry) {
            DB::table('gymies_group_session_waitlist')
                ->where('id', $entry->id)
                ->update(['status' => 'expired', 'updated_at' => now()]);

            $this->onGroupSessionCancelled((int) $entry->group_session_id);
        }

        return count($expired);
    }
}
