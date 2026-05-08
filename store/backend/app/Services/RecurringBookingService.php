<?php

declare(strict_types=1);

namespace App\Services;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Recurring Booking Service.
 *
 * Genereert concrete bookings vanuit recurring patterns.
 * Wordt aangeroepen als scheduled job (bijv. dagelijks om 02:00).
 *
 * Flow:
 * 1. Haal alle actieve recurring bookings op
 * 2. Voor elk: genereer concrete bookings tot 2 weken vooruit
 * 3. Check per datum: is de trainer beschikbaar? Is er een conflict?
 * 4. Bij conflict: skip + notificatie naar klant
 * 5. Update generated_until op het recurring record
 */
class RecurringBookingService
{
    private const GENERATE_AHEAD_WEEKS = 2;
    private const TABLE = 'gymies_recurring_bookings';

    /**
     * Genereer alle openstaande recurring bookings.
     * Retourneert aantal gegenereerde bookings.
     */
    public function generateAll(): int
    {
        if (!Schema::hasTable(self::TABLE) || !Schema::hasTable('gymies_bookings')) {
            return 0;
        }

        // BUG-007: Wrap in transaction to handle partial failures gracefully
        try {
            return DB::transaction(function () {
                $recurrings = DB::table(self::TABLE)
                    ->where('status', 'active')
                    ->get();

                $totalGenerated = 0;

                foreach ($recurrings as $recurring) {
                    try {
                        $generated = $this->generateForRecurring($recurring);
                        $totalGenerated += $generated;
                    } catch (\Throwable $e) {
                        \Log::error('RecurringBookingService: failed to generate for recurring ID ' . $recurring->id, [
                            'error' => $e->getMessage(),
                        ]);
                        // Continue with next recurring booking
                        continue;
                    }
                }

                return $totalGenerated;
            });
        } catch (\Throwable $e) {
            \Log::error('RecurringBookingService::generateAll failed', [
                'error' => $e->getMessage(),
            ]);
            return 0;
        }
    }

    /**
     * Genereer bookings voor één recurring record.
     */
    public function generateForRecurring(object $recurring): int
    {
        // BUG-008: Wrap generation in transaction to ensure atomic updates
        return DB::transaction(function () use ($recurring) {
            $generatedUntil = $recurring->generated_until
                ? Carbon::parse($recurring->generated_until)
                : Carbon::today();

            $targetDate = Carbon::today()->addWeeks(self::GENERATE_AHEAD_WEEKS);

            // Respecteer repeat_until
            if ($recurring->repeat_until) {
                $repeatUntil = Carbon::parse($recurring->repeat_until);
                if ($targetDate->gt($repeatUntil)) {
                    $targetDate = $repeatUntil;
                }
            }

            if ($generatedUntil->gte($targetDate)) {
                return 0; // Al bijgewerkt
            }

            $dayOfWeek = (int) $recurring->day_of_week;
            $startTime = $recurring->start_time;
            $duration = (int) $recurring->duration_minutes;
            $repeatEvery = (int) ($recurring->repeat_every_weeks ?? 1);
            $amountCents = (int) ($recurring->amount_cents ?? 0);

            $generated = 0;
            $date = $generatedUntil->copy()->addDay();

            // Spring naar de eerste matching weekdag
            while ($date->dayOfWeekIso !== $dayOfWeek && $date->lte($targetDate)) {
                $date->addDay();
            }

            while ($date->lte($targetDate)) {
                $dateStr = $date->format('Y-m-d');
                $scheduledAt = "{$dateStr} {$startTime}:00";

                // Check: al een booking voor deze datum+tijd?
                $exists = DB::table('gymies_bookings')
                    ->where('client_user_id', $recurring->client_user_id)
                    ->where('trainer_user_id', $recurring->trainer_user_id)
                    ->where('scheduled_at', $scheduledAt)
                    ->whereNotIn('status', ['cancelled'])
                    ->exists();

                if (!$exists) {
                    // Check: trainer exception?
                    $blocked = $this->isDateBlocked(
                        (int) $recurring->trainer_user_id,
                        $dateStr,
                    );

                    if ($blocked) {
                        // Notificatie: "Je wekelijkse sessie op {datum} kan niet doorgaan"
                        $this->notifyConflict($recurring, $dateStr);
                    } else {
                        // Check: overlap met andere bookings
                        $overlap = $this->hasOverlap(
                            (int) $recurring->trainer_user_id,
                            $scheduledAt,
                            $duration,
                        );

                        if (!$overlap) {
                            $this->createBooking($recurring, $scheduledAt, $duration, $amountCents);
                            $generated++;
                        } else {
                            $this->notifyConflict($recurring, $dateStr);
                        }
                    }
                }

                $date->addWeeks($repeatEvery);
            }

            // Update generated_until
            DB::table(self::TABLE)
                ->where('id', $recurring->id)
                ->update([
                    'generated_until' => $targetDate->format('Y-m-d'),
                    'updated_at' => now(),
                ]);

            return $generated;
        });
    }

    /**
     * Maak een concrete booking aan vanuit een recurring pattern.
     */
    private function createBooking(object $recurring, string $scheduledAt, int $duration, int $amountCents): void
    {
        $scheduledCarbon = Carbon::parse($scheduledAt);

        $payload = [
            'client_user_id' => $recurring->client_user_id,
            'trainer_user_id' => $recurring->trainer_user_id,
            'scheduled_at' => $scheduledAt,
            'duration_minutes' => $duration,
            'status' => 'confirmed',
            'amount_cents' => $amountCents,
            'created_at' => now(),
            'updated_at' => now(),
        ];

        if (Schema::hasColumn('gymies_bookings', 'recurring_booking_id')) {
            $payload['recurring_booking_id'] = $recurring->id;
        }
        if (Schema::hasColumn('gymies_bookings', 'package_id') && $recurring->package_id) {
            $payload['package_id'] = $recurring->package_id;
        }
        if (Schema::hasColumn('gymies_bookings', 'slot_date')) {
            $payload['slot_date'] = $scheduledCarbon->format('Y-m-d');
        }
        if (Schema::hasColumn('gymies_bookings', 'day_of_week')) {
            $payload['day_of_week'] = (int) $scheduledCarbon->format('N');
        }
        if (Schema::hasColumn('gymies_bookings', 'week_number')) {
            $payload['week_number'] = (int) $scheduledCarbon->format('W');
        }

        DB::table('gymies_bookings')->insert($payload);
    }

    /**
     * Check of een datum geblokkeerd is voor de trainer.
     */
    private function isDateBlocked(int $trainerId, string $dateStr): bool
    {
        if (!Schema::hasTable('gymies_availability_exceptions')) {
            return false;
        }

        $userIdCol = Schema::hasColumn('gymies_availability_exceptions', 'trainer_user_id')
            ? 'trainer_user_id'
            : 'user_id';
        $dateCol = Schema::hasColumn('gymies_availability_exceptions', 'blocked_date')
            ? 'blocked_date'
            : 'date';

        return DB::table('gymies_availability_exceptions')
            ->where($userIdCol, $trainerId)
            ->where($dateCol, $dateStr)
            ->where('is_available', false)
            ->exists();
    }

    /**
     * Check of er een overlap is met bestaande bookings.
     */
    private function hasOverlap(int $trainerId, string $scheduledAt, int $duration): bool
    {
        return DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereIn('status', ['pending', 'confirmed', 'reserved'])
            ->whereRaw("? < DATE_ADD(scheduled_at, INTERVAL duration_minutes MINUTE) AND DATE_ADD(?, INTERVAL ? MINUTE) > scheduled_at", [
                $scheduledAt,
                $scheduledAt,
                $duration,
            ])
            ->exists();
    }

    /**
     * Stuur notificatie naar klant over conflict.
     */
    private function notifyConflict(object $recurring, string $dateStr): void
    {
        if (!Schema::hasTable('gymies_notification_queue')) {
            return;
        }

        $formattedDate = Carbon::parse($dateStr)->format('d-m-Y');

        try {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $recurring->client_user_id,
                'channel' => 'in_app',
                'event_type' => 'recurring_booking_conflict',
                'payload_json' => json_encode([
                    'recurring_booking_id' => (string) $recurring->id,
                    'trainer_user_id' => (string) $recurring->trainer_user_id,
                    'date' => $dateStr,
                    'message' => "Je wekelijkse sessie op {$formattedDate} om {$recurring->start_time} kan niet doorgaan. De trainer is niet beschikbaar.",
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        } catch (\Throwable) {
            // Log failure silently
        }
    }
}
