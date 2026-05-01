<?php

declare(strict_types=1);

namespace App\Services;

use Carbon\Carbon;

/**
 * Berekent volgende factuurdatum o.b.v. config gymies_subscription.billing_day_of_month.
 */
final class SubscriptionBillingService
{
    /**
     * Berekent de volgende factuurdatum (Y-m-d).
     * Gebruikt config('gymies_subscription.billing_day_of_month') (standaard 25e).
     * Als de datum in het weekend valt (zaterdag/zondag), wordt de eerste volgende werkdag gebruikt.
     */
    public static function nextBillingDate(?Carbon $from = null): string
    {
        $from = $from ?? Carbon::now();
        $billingDay = self::getBillingDay();

        $candidate = $from->copy()->day($billingDay)->startOfDay();

        if ($candidate->isPast() && !$candidate->isToday()) {
            $candidate = $from->copy()->addMonth()->day($billingDay)->startOfDay();
        }

        return self::toNextWorkingDay($candidate)->format('Y-m-d');
    }

    /**
     * Verschuift de datum naar de eerste volgende werkdag als het een weekend (za/zo) is.
     */
    private static function toNextWorkingDay(Carbon $date): Carbon
    {
        $date = $date->copy();
        while ($date->isWeekend()) {
            $date->addDay();
        }
        return $date;
    }

    /**
     * Billing day uit config (1-28).
     */
    public static function getBillingDay(): int
    {
        $day = (int) (config('gymies_subscription.billing_day_of_month', 1));
        return max(1, min(28, $day));
    }
}
