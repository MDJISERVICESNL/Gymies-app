<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Feature Flags
 * ────────────────────
 * Centraal systeem voor feature toggles. Controleert of een feature
 * ingeschakeld is voor een specifieke gebruiker.
 *
 * Gebruik:
 *   GymiesFeatureFlags::isEnabled('buddy_bookings');              // globaal check
 *   GymiesFeatureFlags::isEnabled('buddy_bookings', $userId, 'trainer'); // per user
 *   GymiesFeatureFlags::all();                                    // alle flags (voor Flutter sync)
 *
 * Cache: flags worden 5 minuten gecachet om DB queries te minimaliseren.
 */
final class GymiesFeatureFlags
{
    private static ?array $cache = null;
    private const CACHE_KEY = 'gymies_feature_flags';
    private const CACHE_TTL = 300; // 5 minuten

    /**
     * Check of een feature ingeschakeld is.
     */
    public static function isEnabled(string $key, ?int $userId = null, ?string $role = null): bool
    {
        $flags = self::loadFlags();
        $flag  = $flags[$key] ?? null;

        if (!$flag) return false;
        if (!(bool) $flag['enabled']) return false;

        // Role check
        if (!empty($flag['allowed_roles'])) {
            $roles = is_string($flag['allowed_roles'])
                ? json_decode($flag['allowed_roles'], true)
                : $flag['allowed_roles'];
            if (is_array($roles) && $role !== null && !in_array($role, $roles, true)) {
                return false;
            }
        }

        // User ID allowlist (beta testers)
        if (!empty($flag['allowed_user_ids']) && $userId !== null) {
            $userIds = is_string($flag['allowed_user_ids'])
                ? json_decode($flag['allowed_user_ids'], true)
                : $flag['allowed_user_ids'];
            if (is_array($userIds) && !empty($userIds) && !in_array($userId, $userIds, true)) {
                // Niet op de allowlist — check rollout percentage
                $percentage = (float) ($flag['rollout_percentage'] ?? 100);
                if ($percentage < 100) {
                    // Deterministic rollout gebaseerd op user ID
                    $hash = crc32("{$key}:{$userId}") % 100;
                    if ($hash >= $percentage) return false;
                }
            }
        } else {
            // Geen user-specifieke allowlist — check rollout percentage
            $percentage = (float) ($flag['rollout_percentage'] ?? 100);
            if ($percentage < 100 && $userId !== null) {
                $hash = abs(crc32("{$key}:{$userId}")) % 100;
                if ($hash >= $percentage) return false;
            }
        }

        return true;
    }

    /**
     * Alle flags ophalen (voor sync naar Flutter app).
     * Retourneert een key→enabled map.
     */
    public static function all(?int $userId = null, ?string $role = null): array
    {
        $flags  = self::loadFlags();
        $result = [];

        foreach ($flags as $key => $flag) {
            $result[$key] = self::isEnabled($key, $userId, $role);
        }

        return $result;
    }

    /**
     * Cache invalideren (na admin wijziging).
     */
    public static function clearCache(): void
    {
        Cache::forget(self::CACHE_KEY);
        self::$cache = null;
    }

    /**
     * Laad flags uit DB met cache.
     */
    private static function loadFlags(): array
    {
        if (self::$cache !== null) return self::$cache;

        self::$cache = Cache::remember(self::CACHE_KEY, self::CACHE_TTL, function () {
            if (!Schema::hasTable('gymies_feature_flags')) return [];

            $rows = DB::table('gymies_feature_flags')->get();
            $map  = [];
            foreach ($rows as $row) {
                $map[$row->key] = (array) $row;
            }
            return $map;
        });

        return self::$cache;
    }
}
