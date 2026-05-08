<?php
declare(strict_types=1);
namespace App\Services;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ChurnPredictionService
 * ─────────────────────────
 * Berekent churn-risicoscores voor gym-leden op basis van 5 signalen.
 * Score range: 0 (geen risico) tot 100 (hoog risico).
 */
class ChurnPredictionService
{
    /**
     * Bereken churn score voor één gebruiker binnen een organisatie.
     */
    public function calculateScore(int $userId, int $orgId): array
    {
        $now = Carbon::now();

        // 1. Boekingsfrequentie daling (max 30 punten)
        $recentBookings = $this->bookingsInPeriod($userId, $orgId, $now->copy()->subWeeks(4), $now);
        $previousBookings = $this->bookingsInPeriod($userId, $orgId, $now->copy()->subWeeks(8), $now->copy()->subWeeks(4));
        $frequencyDropScore = 0;
        if ($previousBookings > 0) {
            $dropRatio = 1 - ($recentBookings / $previousBookings);
            $frequencyDropScore = (int) min(30, max(0, round($dropRatio * 30)));
        } elseif ($recentBookings === 0) {
            $frequencyDropScore = 30;
        }

        // 2. Dagen sinds laatste sessie (max 25 punten)
        $lastBookingAt = $this->lastBookingDate($userId, $orgId);
        $daysSinceLast = $lastBookingAt ? $now->diffInDays($lastBookingAt) : 90;
        $daysInactiveScore = (int) min(25, max(0, round(($daysSinceLast / 30) * 25)));

        // 3. Check-in consistentie (max 20 punten)
        $intervals = $this->bookingIntervals($userId, $orgId, $now->copy()->subWeeks(12), $now);
        $consistencyScore = 0;
        if (count($intervals) >= 2) {
            $mean = array_sum($intervals) / count($intervals);
            $variance = array_sum(array_map(fn($x) => pow($x - $mean, 2), $intervals)) / count($intervals);
            $stdDev = sqrt($variance);
            $cv = $mean > 0 ? $stdDev / $mean : 1; // coefficient of variation
            $consistencyScore = (int) min(20, max(0, round($cv * 20)));
        } elseif (count($intervals) < 2) {
            $consistencyScore = 15; // Te weinig data = risico
        }

        // 4. Resterende contractduur (max 15 punten)
        $contractEndScore = $this->contractEndScore($userId, $orgId);

        // 5. Annuleringspercentage (max 10 punten)
        $cancelledRecent = $this->cancelledBookingsCount($userId, $orgId, $now->copy()->subWeeks(4), $now);
        $totalRecent = $recentBookings + $cancelledRecent;
        $cancellationScore = 0;
        if ($totalRecent > 0) {
            $cancellationScore = (int) min(10, max(0, round(($cancelledRecent / $totalRecent) * 10)));
        }

        $totalScore = $frequencyDropScore + $daysInactiveScore + $consistencyScore + $contractEndScore + $cancellationScore;
        $totalScore = min(100, $totalScore);

        return [
            'score' => $totalScore,
            'frequency_drop_score' => $frequencyDropScore,
            'days_inactive_score' => $daysInactiveScore,
            'consistency_score' => $consistencyScore,
            'contract_end_score' => $contractEndScore,
            'cancellation_score' => $cancellationScore,
            'signals_json' => json_encode([
                'recent_bookings' => $recentBookings,
                'previous_bookings' => $previousBookings,
                'days_since_last' => $daysSinceLast,
                'last_booking_at' => $lastBookingAt?->toDateString(),
                'booking_intervals_count' => count($intervals),
                'cancelled_recent' => $cancelledRecent,
            ]),
            'last_booking_at' => $lastBookingAt?->toDateTimeString(),
        ];
    }

    /**
     * Herbereken scores voor alle actieve leden van een organisatie.
     */
    public function recalculateForOrganisation(int $orgId): int
    {
        if (!Schema::hasTable('gymies_churn_scores')) {
            \App\Http\Controllers\Gymies\GymiesSchemaEnsure::ensureChurnScoresTable();
        }

        // Vind alle actieve gym-leden (users met bookings bij trainers van deze org)
        $userIds = DB::table('gymies_bookings as b')
            ->join('gymies_gym_teams as gt', 'b.trainer_user_id', '=', 'gt.user_id')
            ->where('gt.organisation_id', $orgId)
            ->where('b.created_at', '>=', now()->subMonths(6))
            ->distinct()
            ->pluck('b.client_user_id')
            ->toArray();

        $count = 0;
        foreach ($userIds as $userId) {
            $scores = $this->calculateScore((int) $userId, $orgId);

            DB::table('gymies_churn_scores')->updateOrInsert(
                ['user_id' => $userId, 'organisation_id' => $orgId],
                [
                    'score' => $scores['score'],
                    'frequency_drop_score' => $scores['frequency_drop_score'],
                    'days_inactive_score' => $scores['days_inactive_score'],
                    'consistency_score' => $scores['consistency_score'],
                    'contract_end_score' => $scores['contract_end_score'],
                    'cancellation_score' => $scores['cancellation_score'],
                    'signals_json' => $scores['signals_json'],
                    'last_booking_at' => $scores['last_booking_at'],
                    'calculated_at' => now(),
                ]
            );
            $count++;
        }

        return $count;
    }

    private function bookingsInPeriod(int $userId, int $orgId, Carbon $from, Carbon $to): int
    {
        $query = DB::table('gymies_bookings as b')
            ->where('b.client_user_id', $userId)
            ->whereIn('b.status', ['confirmed', 'completed', 'checked_in'])
            ->whereBetween('b.scheduled_at', [$from, $to]);

        if (Schema::hasTable('gymies_gym_teams')) {
            $query->join('gymies_gym_teams as gt', 'b.trainer_user_id', '=', 'gt.user_id')
                  ->where('gt.organisation_id', $orgId);
        }

        return $query->count();
    }

    private function lastBookingDate(int $userId, int $orgId): ?Carbon
    {
        $query = DB::table('gymies_bookings as b')
            ->where('b.client_user_id', $userId)
            ->whereIn('b.status', ['confirmed', 'completed', 'checked_in']);

        if (Schema::hasTable('gymies_gym_teams')) {
            $query->join('gymies_gym_teams as gt', 'b.trainer_user_id', '=', 'gt.user_id')
                  ->where('gt.organisation_id', $orgId);
        }

        $date = $query->max('b.scheduled_at');
        return $date ? Carbon::parse($date) : null;
    }

    private function bookingIntervals(int $userId, int $orgId, Carbon $from, Carbon $to): array
    {
        $query = DB::table('gymies_bookings as b')
            ->where('b.client_user_id', $userId)
            ->whereIn('b.status', ['confirmed', 'completed', 'checked_in'])
            ->whereBetween('b.scheduled_at', [$from, $to])
            ->orderBy('b.scheduled_at');

        if (Schema::hasTable('gymies_gym_teams')) {
            $query->join('gymies_gym_teams as gt', 'b.trainer_user_id', '=', 'gt.user_id')
                  ->where('gt.organisation_id', $orgId);
        }

        $dates = $query->pluck('b.scheduled_at')->map(fn($d) => Carbon::parse($d))->toArray();
        $intervals = [];
        for ($i = 1; $i < count($dates); $i++) {
            $intervals[] = $dates[$i - 1]->diffInDays($dates[$i]);
        }
        return $intervals;
    }

    private function contractEndScore(int $userId, int $orgId): int
    {
        if (!Schema::hasTable('gymies_subscriptions')) return 0;

        $sub = DB::table('gymies_subscriptions')
            ->where('user_id', $userId)
            ->where('organisation_id', $orgId)
            ->whereIn('status', ['active', 'trialing'])
            ->first();

        if (!$sub || !isset($sub->ends_at) || !$sub->ends_at) return 0;

        $daysUntilEnd = Carbon::now()->diffInDays(Carbon::parse($sub->ends_at), false);
        if ($daysUntilEnd <= 0) return 15;
        if ($daysUntilEnd <= 14) return 12;
        if ($daysUntilEnd <= 30) return 8;
        if ($daysUntilEnd <= 60) return 4;
        return 0;
    }

    private function cancelledBookingsCount(int $userId, int $orgId, Carbon $from, Carbon $to): int
    {
        $query = DB::table('gymies_bookings as b')
            ->where('b.client_user_id', $userId)
            ->where('b.status', 'cancelled')
            ->whereBetween('b.scheduled_at', [$from, $to]);

        if (Schema::hasTable('gymies_gym_teams')) {
            $query->join('gymies_gym_teams as gt', 'b.trainer_user_id', '=', 'gt.user_id')
                  ->where('gt.organisation_id', $orgId);
        }

        return $query->count();
    }
}
