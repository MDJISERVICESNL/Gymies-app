<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Services\SubscriptionBillingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trait voor trainer self-service: abonnement wijzigen.
 * Alle wijzigingen (upgrade én downgrade) gaan in bij de volgende factuurdatum.
 * Factuurdatum komt uit config gymies_subscription.billing_day_of_month.
 *
 * POST subscription/change
 * Body: { "tier": "starter"|"pro"|"elite" }
 */
trait ChangeSubscriptionTrait
{
    public function changeSubscription(Request $request): JsonResponse
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['message' => 'Unauthenticated'], 401);
        }

        $validated = $request->validate([
            'tier' => 'required|string|in:starter,pro,elite',
        ]);
        $newTier = strtolower(trim($validated['tier']));
        $planLabel = ucfirst($newTier);

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Tabel gymies_trainer_profiles ontbreekt'], 500);
        }

        $userId = (int) ($user->id ?? 0);
        if ($userId <= 0) {
            return response()->json(['message' => 'Gebruiker niet gevonden'], 400);
        }

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
        $currentPlan = $profile ? ($profile->subscription_plan ?? $profile->subscription_tier ?? 'Starter') : 'Starter';
        $currentTier = strtolower((string) $currentPlan);
        if (str_contains($currentTier, 'elite')) {
            $currentTier = 'elite';
        } elseif (str_contains($currentTier, 'pro')) {
            $currentTier = 'pro';
        } else {
            $currentTier = 'starter';
        }

        if ($currentTier === $newTier) {
            return response()->json([
                'message' => 'Je bent al op dit abonnement',
                'tier' => $newTier,
                'plan' => $planLabel,
                'effective_immediately' => true,
            ]);
        }

        $nextBillingDate = SubscriptionBillingService::nextBillingDate();

        $updateData = [
            'updated_at' => now(),
            'subscription_pending_downgrade' => true,
            'subscription_downgrades_at' => $nextBillingDate,
            'subscription_downgrade_to' => $planLabel,
        ];

        if (!Schema::hasColumn('gymies_trainer_profiles', 'subscription_pending_downgrade')) {
            $updateData = [
                'updated_at' => now(),
                'subscription_plan' => $planLabel,
                'subscription_tier' => $planLabel,
            ];
        }

        if ($profile) {
            if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_pending_downgrade')) {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->update($updateData);
            } else {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->update($updateData);
            }
        } else {
            $updateData['user_id'] = $userId;
            $updateData['created_at'] = now();
            $currentPlan = $profile ? ($profile->subscription_plan ?? $profile->subscription_tier ?? 'Starter') : 'Starter';
            $updateData['subscription_plan'] = $currentPlan;
            $updateData['subscription_tier'] = $currentPlan;
            if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_pending_downgrade')) {
                $updateData['subscription_pending_downgrade'] = true;
                $updateData['subscription_downgrades_at'] = $nextBillingDate;
                $updateData['subscription_downgrade_to'] = $planLabel;
            }
            DB::table('gymies_trainer_profiles')->insert($updateData);
        }

        return response()->json([
            'message' => 'Abonnement wijzigt naar ' . $planLabel . ' op ' . $nextBillingDate,
            'tier' => $newTier,
            'plan' => $planLabel,
            'effective_at' => $nextBillingDate,
            'next_billing_date' => $nextBillingDate,
        ]);
    }
}
