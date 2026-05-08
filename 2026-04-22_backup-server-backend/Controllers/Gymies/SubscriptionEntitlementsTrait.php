<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Services\SubscriptionBillingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trait voor GymiesSubscriptionController – GET subscription/features (entitlements voor trainer).
 * Leest feature-matrix uit gymies_subscription_features, valt terug op hardcoded defaults.
 * Voeg toe: use SubscriptionEntitlementsTrait;
 */
trait SubscriptionEntitlementsTrait
{
    private const FEATURES_TABLE = 'gymies_subscription_features';

    /** GET subscription/features – entitlements voor ingelogde trainer. */
    public function subscriptionFeatures(): JsonResponse
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['message' => 'Unauthenticated'], 401);
        }

        $tier = $this->resolveTrainerTier($user);
        $features = $this->buildEntitlementsForTier($tier);
        $validUntil = $this->getSubscriptionValidUntil($user);
        $pendingDowngrade = $this->getPendingDowngradeInfo($user);

        $nextBillingDate = SubscriptionBillingService::nextBillingDate();

        return response()->json([
            'tier' => $tier,
            'features' => $features,
            'valid_until' => $validUntil,
            'is_pending_downgrade' => $pendingDowngrade['is_pending_downgrade'],
            'downgrades_at' => $pendingDowngrade['downgrades_at'],
            'downgrade_to' => $pendingDowngrade['downgrade_to'],
            'next_billing_date' => $nextBillingDate,
        ]);
    }

    private function resolveTrainerTier($user): string
    {
        $profile = $this->getTrainerProfileForUser($user->id ?? 0);

        // 1. Trial verlopen? → Starter
        if ($profile && $this->isSubscriptionExpired($profile)) {
            return 'starter';
        }

        // 2. Pending downgrade ingegaan? (downgrades_at <= vandaag) → downgrade_to
        if ($profile && $this->isPendingDowngradeEffective($profile)) {
            return $this->normalizeTier($profile['subscription_downgrade_to'] ?? 'starter');
        }

        // 3. Huidige tier uit user of profile
        $tier = $this->getFromUser($user, ['subscription_tier', 'subscription_plan', 'plan', 'tier', 'plan_slug', 'plan_name']);
        if ($tier === '' && $profile) {
            $tier = $this->getFromArray($profile, ['subscription_plan', 'subscription_tier', 'plan', 'tier']);
        }
        return $this->normalizeTier($tier) ?: 'starter';
    }

    /** Of pending downgrade al is ingegaan (downgrades_at <= vandaag). */
    private function isPendingDowngradeEffective(array $profile): bool
    {
        $pending = $profile['subscription_pending_downgrade'] ?? null;
        if (!$pending || ($pending !== 1 && $pending !== true)) {
            return false;
        }
        $downgradesAt = $profile['subscription_downgrades_at'] ?? null;
        if ($downgradesAt === null) {
            return false;
        }
        $date = \Carbon\Carbon::parse($downgradesAt)->startOfDay();
        return $date->isPast() || $date->isToday();
    }

    private function normalizeTier(?string $tier): string
    {
        if ($tier === null || trim($tier) === '') {
            return '';
        }
        $t = strtolower(trim($tier));
        if (str_contains($t, 'elite') || str_contains($t, 'studio')) return 'elite';
        if (str_contains($t, 'pro')) return 'pro';
        if (str_contains($t, 'starter') || str_contains($t, 'basic')) return 'starter';
        return '';
    }

    /** @return array{is_pending_downgrade: bool, downgrades_at: ?string, downgrade_to: ?string} */
    private function getPendingDowngradeInfo($user): array
    {
        $profile = $this->getTrainerProfileForUser($user->id ?? 0);
        if (!$profile || $this->isPendingDowngradeEffective($profile)) {
            return ['is_pending_downgrade' => false, 'downgrades_at' => null, 'downgrade_to' => null];
        }
        $pending = $profile['subscription_pending_downgrade'] ?? null;
        if (!$pending || ($pending !== 1 && $pending !== true)) {
            return ['is_pending_downgrade' => false, 'downgrades_at' => null, 'downgrade_to' => null];
        }
        $downgradesAt = $profile['subscription_downgrades_at'] ?? null;
        $downgradeTo = $profile['subscription_downgrade_to'] ?? null;
        return [
            'is_pending_downgrade' => true,
            'downgrades_at' => $downgradesAt ? \Carbon\Carbon::parse($downgradesAt)->format('Y-m-d') : null,
            'downgrade_to' => $downgradeTo ? $this->normalizeTier($downgradeTo) ?: null : null,
        ];
    }

    private function isSubscriptionExpired(array $profile): bool
    {
        $validUntil = $profile['subscription_valid_until'] ?? null;
        if ($validUntil === null) {
            return false;
        }
        $date = \Carbon\Carbon::parse($validUntil)->startOfDay();
        return $date->isPast();
    }

    /** @return string|null ISO-datum (Y-m-d) als proefperiode actief, anders null. */
    private function getSubscriptionValidUntil($user): ?string
    {
        $profile = $this->getTrainerProfileForUser($user->id ?? 0);
        if (!$profile || $this->isSubscriptionExpired($profile)) {
            return null;
        }
        $v = $profile['subscription_valid_until'] ?? null;
        return $v ? \Carbon\Carbon::parse($v)->format('Y-m-d') : null;
    }

    private function getFromUser($user, array $keys): string
    {
        foreach ($keys as $k) {
            $v = $user->{$k} ?? ($user[$k] ?? null);
            if ($v !== null && trim((string) $v) !== '') {
                return trim((string) $v);
            }
        }
        return '';
    }

    private function getFromArray(array $arr, array $keys): string
    {
        foreach ($keys as $k) {
            $v = $arr[$k] ?? null;
            if ($v !== null && trim((string) $v) !== '') {
                return trim((string) $v);
            }
        }
        return '';
    }

    private function getTrainerProfileForUser(int $userId): ?array
    {
        if (!$userId || !\Illuminate\Support\Facades\Schema::hasTable('gymies_trainer_profiles')) {
            return null;
        }
        $row = \Illuminate\Support\Facades\DB::table('gymies_trainer_profiles')
            ->where('user_id', $userId)
            ->first();
        return $row ? (array) $row : null;
    }

    private function buildEntitlementsForTier(string $tier): array
    {
        $rows = $this->getFeatureMatrixFromDb();
        if (empty($rows)) {
            return $this->buildEntitlementsFallback($tier);
        }

        $tierRank = ['starter' => 1, 'pro' => 2, 'elite' => 3];
        $rank = $tierRank[$tier] ?? 1;

        $out = [];
        foreach ($rows as $r) {
            $minRank = $tierRank[$r['enabled_from']] ?? 1;
            if ($rank < $minRank) {
                $out[$r['key']] = ($r['type'] ?? 'boolean') === 'limit' ? 0 : false;
                continue;
            }
            if (($r['type'] ?? 'boolean') === 'limit') {
                $col = 'limit_' . $tier;
                $out[$r['key']] = isset($r[$col]) ? (int) $r[$col] : -1;
            } else {
                $out[$r['key']] = true;
            }
        }
        return $out;
    }

    private function getFeatureMatrixFromDb(): array
    {
        if (!Schema::hasTable('gymies_subscription_features')) {
            return [];
        }
        $rows = DB::table('gymies_subscription_features')->orderBy('sort_order')->get();
        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'key' => $r->key,
                'enabled_from' => $r->enabled_from,
                'type' => $r->type ?? 'boolean',
                'limit_starter' => $r->limit_starter,
                'limit_pro' => $r->limit_pro,
                'limit_elite' => $r->limit_elite,
            ];
        }
        return $out;
    }

    private function buildEntitlementsFallback(string $tier): array
    {
        $proKeys = ['dossier', 'goals', 'health_score', 'upsell', 'rebook', 'priority_support', 'bulk_message', 'client_tags', 'profile_videos', 'profile_stories'];
        $eliteKeys = ['advanced_reporting', 'suite_tools', 'promoted_profile'];
        $out = [];
        foreach ($proKeys as $k) {
            $out[$k] = in_array($tier, ['pro', 'elite'], true);
        }
        foreach ($eliteKeys as $k) {
            $out[$k] = $tier === 'elite';
        }
        $out['max_clients'] = $tier === 'starter' ? 25 : -1;
        $out['profile_videos'] = $tier === 'pro' ? 1 : ($tier === 'elite' ? -1 : 0);
        $out['profile_stories'] = $tier === 'pro' ? 1 : ($tier === 'elite' ? -1 : 0);
        return $out;
    }
}
