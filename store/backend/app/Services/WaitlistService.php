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

        // Bepaal positie
        $maxPosition = (int) DB::table(self::TABLE)
            ->where('trainer_user_id', $trainerUserId)
            ->where('desired_date', $desiredDate)
            ->where('desired_time', $desiredTime)
            ->whereIn('status', ['waiting', 'offered'])
            ->max('position');

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
                ->whereRaw("? < DATE_ADD(scheduled_at, INTERVAL duration_minutes MINUTE) AND DATE_ADD(?, INTERVAL ? MINUTE) > scheduled_at", [
                    $scheduledAt, $scheduledAt, $duration,
                ])
                ->lockForUpdate()
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
        if (!Schema::hasTable('gymies_notification_queue')) {
            return;
        }

        $formattedDate = Carbon::parse($date)->format('d-m-Y');

        try {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $entry->client_user_id,
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
            // Log failure silently
        }
    }
}
