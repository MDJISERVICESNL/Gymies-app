<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trait voor admin: abonnement toewijzen met proefperiode en/of pending downgrade.
 *
 * POST vault-console/users/{userId}/assign-subscription
 * Body: { "tier": "pro"|"elite"|"starter", "valid_until": "2025-04-01" (optie),
 *        "pending_downgrade": true (optie), "downgrades_at": "2025-03-30", "downgrade_to": "pro" }
 */
trait AssignSubscriptionTrait
{
    public function performAssignSubscription(Request $request, string $userId): JsonResponse
    {
        $validated = $request->validate([
            'tier' => 'required_without:pending_downgrade|string|in:starter,pro,elite',
            'valid_until' => 'nullable|date',
            'pending_downgrade' => 'nullable|boolean',
            'downgrades_at' => 'nullable|date|required_if:pending_downgrade,1',
            'downgrade_to' => 'nullable|string|in:starter,pro,elite|required_if:pending_downgrade,1',
        ]);

        $pendingDowngrade = filter_var($validated['pending_downgrade'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $downgradesAt = $pendingDowngrade && !empty($validated['downgrades_at'])
            ? \Carbon\Carbon::parse($validated['downgrades_at'])->format('Y-m-d')
            : null;
        $downgradeTo = $pendingDowngrade && !empty($validated['downgrade_to'])
            ? ucfirst(strtolower(trim($validated['downgrade_to'])))
            : null;

        $tier = isset($validated['tier']) ? strtolower(trim($validated['tier'])) : null;
        $validUntil = isset($validated['valid_until'])
            ? \Carbon\Carbon::parse($validated['valid_until'])->format('Y-m-d')
            : null;

        $planLabel = match ($tier) {
            'pro' => 'Pro',
            'elite' => 'Elite',
            default => 'Starter',
        };

        $pendingDowngrade = ($validated['pending_downgrade'] ?? false) ? true : false;
        $downgradesAt = $pendingDowngrade && isset($validated['downgrades_at'])
            ? \Carbon\Carbon::parse($validated['downgrades_at'])->format('Y-m-d')
            : null;
        $downgradeTo = $pendingDowngrade && isset($validated['downgrade_to'])
            ? ucfirst(strtolower(trim($validated['downgrade_to'])))
            : null;

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Tabel gymies_trainer_profiles ontbreekt'], 500);
        }

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', (int) $userId)->first();

        $updateData = [
            'subscription_plan' => $planLabel,
            'subscription_tier' => $planLabel,
        ];

        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_valid_until')) {
            $updateData['subscription_valid_until'] = $validUntil;
        }

        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_pending_downgrade')) {
            $updateData['subscription_pending_downgrade'] = $pendingDowngrade;
            $updateData['subscription_downgrades_at'] = $downgradesAt;
            $updateData['subscription_downgrade_to'] = $downgradeTo;
        }

        // Wrap profile update/insert in transaction
        DB::transaction(function() use ($profile, $userId, $updateData) {
            if ($profile) {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', (int) $userId)
                    ->update($updateData);
            } else {
                $insertData = $updateData;
                $insertData['user_id'] = (int) $userId;
                $insertData['created_at'] = now();
                $insertData['updated_at'] = now();
                DB::table('gymies_trainer_profiles')->insert($insertData);
            }
        });

        return response()->json([
            'message' => 'Abonnement toegewezen',
            'tier' => $tier,
            'plan' => $planLabel,
            'valid_until' => $validUntil,
            'is_pending_downgrade' => $pendingDowngrade,
            'downgrades_at' => $downgradesAt,
            'downgrade_to' => $downgradeTo,
        ]);
    }
}
