<?php

declare(strict_types=1);

namespace App\Services;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Cancellation Policy Service.
 *
 * Berekent annulerings-fees op basis van:
 * 1. Per-trainer policy (gymies_cancellation_policies)
 * 2. Platform defaults als fallback
 * 3. Bedenktijd (15 min na boeking = altijd gratis)
 *
 * Gebruik: $outcome = CancellationPolicyService::evaluate($booking, $isTrainer);
 */
class CancellationPolicyService
{
    /** Platform defaults (fallback als trainer geen custom policy heeft). */
    private const PLATFORM_FREE_CANCEL_HOURS = 48;
    private const PLATFORM_LATE_CANCEL_FEE_PCT = 50;
    private const PLATFORM_NO_SHOW_FEE_PCT = 100;
    private const PLATFORM_RESCHEDULE_LIMIT_HOURS = 4;
    private const GRACE_PERIOD_MINUTES = 15;
    private const TRAINER_PENALTY_CENTS = 2500;

    /**
     * Evalueer annuleringsbeleid voor een boeking.
     *
     * @param object $booking    DB row uit gymies_bookings
     * @param bool   $isTrainer  Wordt geannuleerd door de trainer?
     * @return array{
     *   refund_percent: int,
     *   fee_percent: int,
     *   fee_cents: int,
     *   refund_method_allowed: string,
     *   cancellation_policy_message: string,
     *   grace_period: bool,
     *   penalty_applies: bool,
     *   penalty_cents: int,
     *   allow_reschedule: bool,
     *   can_cancel_free: bool,
     * }
     */
    public static function evaluate(object $booking, bool $isTrainer): array
    {
        $policy = self::loadPolicy((int) $booking->trainer_user_id);
        $scheduledAt = Carbon::parse($booking->scheduled_at);
        $createdAt = isset($booking->created_at) ? Carbon::parse($booking->created_at) : null;
        $hoursUntil = $scheduledAt->isFuture()
            ? $scheduledAt->diffInSeconds(now()) / 3600.0
            : 0.0;
        $amountCents = (int) ($booking->amount_cents ?? 0);

        // Bedenktijd: binnen 15 min na boeking = altijd 100% gratis
        $isGracePeriod = false;
        if ($createdAt && $createdAt->diffInMinutes(now()) <= self::GRACE_PERIOD_MINUTES) {
            $isGracePeriod = true;
        }

        if ($isGracePeriod) {
            return [
                'refund_percent' => 100,
                'fee_percent' => 0,
                'fee_cents' => 0,
                'refund_method_allowed' => 'bank_or_wallet',
                'cancellation_policy_message' => 'Bedenktijd (15 min). 100% teruggestort, geen kosten.',
                'grace_period' => true,
                'penalty_applies' => false,
                'penalty_cents' => 0,
                'allow_reschedule' => true,
                'can_cancel_free' => true,
            ];
        }

        // Trainer annuleert
        if ($isTrainer) {
            $penaltyApplies = $hoursUntil < 24;
            return [
                'refund_percent' => 100,
                'fee_percent' => 0,
                'fee_cents' => 0,
                'refund_method_allowed' => 'wallet',
                'cancellation_policy_message' => $penaltyApplies
                    ? 'Trainer annulering <24u: klant krijgt 100% tegoed, trainer betaalt €25 boete.'
                    : 'Trainer annulering: klant krijgt 100% tegoed terug.',
                'grace_period' => false,
                'penalty_applies' => $penaltyApplies,
                'penalty_cents' => $penaltyApplies ? self::TRAINER_PENALTY_CENTS : 0,
                'allow_reschedule' => true,
                'can_cancel_free' => true,
            ];
        }

        // Klant annuleert — check per-trainer policy
        $freeCancelHours = $policy['free_cancel_hours'];
        $lateCancelFeePct = $policy['late_cancel_fee_pct'];

        // Check max gratis annuleringen per maand
        $freeCountExceeded = false;
        if ($policy['max_free_cancels_per_month'] !== null) {
            $monthStart = now()->startOfMonth();
            $cancelCount = self::countClientCancelsThisMonth(
                (int) $booking->client_user_id,
                (int) $booking->trainer_user_id,
                $monthStart,
            );
            if ($cancelCount >= $policy['max_free_cancels_per_month']) {
                $freeCountExceeded = true;
            }
        }

        // Gratis annulering
        if ($hoursUntil >= $freeCancelHours && !$freeCountExceeded) {
            return [
                'refund_percent' => 100,
                'fee_percent' => 0,
                'fee_cents' => 0,
                'refund_method_allowed' => 'bank_or_wallet',
                'cancellation_policy_message' => "Gratis annulering (>{$freeCancelHours}u van tevoren).",
                'grace_period' => false,
                'penalty_applies' => false,
                'penalty_cents' => 0,
                'allow_reschedule' => $policy['allow_reschedule'],
                'can_cancel_free' => true,
            ];
        }

        // Late cancel: fee toepassen
        $feeCents = (int) round($amountCents * ($lateCancelFeePct / 100));
        $refundPercent = 100 - $lateCancelFeePct;
        $refundMethod = $refundPercent > 0 ? 'wallet_only' : 'none';

        $message = $freeCountExceeded
            ? "Maximum gratis annuleringen ({$policy['max_free_cancels_per_month']}/maand) bereikt. {$lateCancelFeePct}% fee."
            : "Late annulering (<{$freeCancelHours}u). {$lateCancelFeePct}% fee.";

        if ($policy['custom_message']) {
            $message .= ' ' . $policy['custom_message'];
        }

        return [
            'refund_percent' => $refundPercent,
            'fee_percent' => $lateCancelFeePct,
            'fee_cents' => $feeCents,
            'refund_method_allowed' => $refundMethod,
            'cancellation_policy_message' => $message,
            'grace_period' => false,
            'penalty_applies' => false,
            'penalty_cents' => 0,
            'allow_reschedule' => $policy['allow_reschedule'] && $hoursUntil >= $policy['reschedule_limit_hours'],
            'can_cancel_free' => false,
        ];
    }

    /**
     * No-show fee berekening.
     */
    public static function noShowFee(object $booking): array
    {
        $policy = self::loadPolicy((int) $booking->trainer_user_id);
        $amountCents = (int) ($booking->amount_cents ?? 0);
        $feePct = $policy['no_show_fee_pct'];
        $feeCents = (int) round($amountCents * ($feePct / 100));

        return [
            'fee_percent' => $feePct,
            'fee_cents' => $feeCents,
            'message' => "No-show: {$feePct}% fee (€" . number_format($feeCents / 100, 2, ',', '.') . ').',
        ];
    }

    /**
     * Laad per-trainer policy met platform defaults als fallback.
     */
    private static function loadPolicy(int $trainerId): array
    {
        $defaults = [
            'free_cancel_hours' => self::PLATFORM_FREE_CANCEL_HOURS,
            'late_cancel_fee_pct' => self::PLATFORM_LATE_CANCEL_FEE_PCT,
            'no_show_fee_pct' => self::PLATFORM_NO_SHOW_FEE_PCT,
            'allow_reschedule' => true,
            'reschedule_limit_hours' => self::PLATFORM_RESCHEDULE_LIMIT_HOURS,
            'max_free_cancels_per_month' => null,
            'custom_message' => null,
        ];

        if (!Schema::hasTable('gymies_cancellation_policies')) {
            return $defaults;
        }

        $policy = DB::table('gymies_cancellation_policies')
            ->where('trainer_user_id', $trainerId)
            ->first();

        if (!$policy) {
            return $defaults;
        }

        $row = (array) $policy;

        return [
            'free_cancel_hours' => (int) ($row['free_cancel_hours'] ?? $defaults['free_cancel_hours']),
            'late_cancel_fee_pct' => min(100, max(0, (int) ($row['late_cancel_fee_pct'] ?? $defaults['late_cancel_fee_pct']))),
            'no_show_fee_pct' => min(100, max(0, (int) ($row['no_show_fee_pct'] ?? $defaults['no_show_fee_pct']))),
            'allow_reschedule' => (bool) ($row['allow_reschedule'] ?? $defaults['allow_reschedule']),
            'reschedule_limit_hours' => (int) ($row['reschedule_limit_hours'] ?? $defaults['reschedule_limit_hours']),
            'max_free_cancels_per_month' => isset($row['max_free_cancels_per_month']) ? (int) $row['max_free_cancels_per_month'] : null,
            'custom_message' => $row['custom_message'] ?? null,
        ];
    }

    /**
     * Tel hoeveel keer een klant deze maand al heeft geannuleerd bij deze trainer.
     */
    private static function countClientCancelsThisMonth(int $clientId, int $trainerId, Carbon $monthStart): int
    {
        if (!Schema::hasTable('gymies_bookings') || !Schema::hasColumn('gymies_bookings', 'cancelled_at')) {
            return 0;
        }

        return (int) DB::table('gymies_bookings')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->where('status', 'cancelled')
            ->where('cancelled_at', '>=', $monthStart)
            ->count();
    }
}
