<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Cron: verlopen proefabonnementen terugzetten naar Starter.
 * Voeg toe in GymiesCronController: use ExpireSubscriptionTrialsTrait;
 * Of roep aan via ExpireSubscriptionTrialsController.
 *
 * Route: POST api/gymies/cron/expire-subscription-trials
 */
trait ExpireSubscriptionTrialsTrait
{
    public function expireSubscriptionTrials(): JsonResponse
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['expired' => 0, 'downgrades' => 0, 'message' => 'Niet van toepassing']);
        }

        $today = now()->format('Y-m-d');
        $expired = 0;
        $downgrades = 0;

        // 1. Verlopen proefabonnementen → Starter
        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_valid_until')) {
            $expired = DB::table('gymies_trainer_profiles')
                ->whereNotNull('subscription_valid_until')
                ->where('subscription_valid_until', '<', $today)
                ->where(function ($q) {
                    $q->where('subscription_plan', 'Pro')
                        ->orWhere('subscription_plan', 'Elite')
                        ->orWhere('subscription_tier', 'Pro')
                        ->orWhere('subscription_tier', 'Elite');
                })
                ->update([
                    'subscription_plan' => 'Starter',
                    'subscription_tier' => 'Starter',
                    'subscription_valid_until' => null,
                    'updated_at' => now(),
                ]);
        }

        // 2. Ingegane pending downgrades → plan bijwerken, flags wissen
        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_pending_downgrade')) {
            $rows = DB::table('gymies_trainer_profiles')
                ->where('subscription_pending_downgrade', true)
                ->whereNotNull('subscription_downgrades_at')
                ->where('subscription_downgrades_at', '<=', $today)
                ->get();

            foreach ($rows as $row) {
                $to = strtolower(trim((string) ($row->subscription_downgrade_to ?? 'starter')));
                $planLabel = match ($to) {
                    'pro' => 'Pro',
                    'elite', 'studio' => 'Elite',
                    default => 'Starter',
                };
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', $row->user_id)
                    ->update([
                        'subscription_plan' => $planLabel,
                        'subscription_tier' => $planLabel,
                        'subscription_pending_downgrade' => false,
                        'subscription_downgrades_at' => null,
                        'subscription_downgrade_to' => null,
                        'updated_at' => now(),
                    ]);
                $downgrades++;
            }
        }

        $msg = [];
        if ($expired > 0) $msg[] = "{$expired} proefabonnement(en) teruggezet";
        if ($downgrades > 0) $msg[] = "{$downgrades} pending downgrade(s) doorgevoerd";
        $message = empty($msg) ? 'Geen verlopen proefperiodes of downgrades' : implode(', ', $msg);

        return response()->json([
            'expired' => $expired,
            'downgrades' => $downgrades,
            'message' => $message,
        ]);
    }
}
