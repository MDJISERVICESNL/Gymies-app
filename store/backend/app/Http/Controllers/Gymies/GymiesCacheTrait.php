<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\Cache;

/**
 * GymiesCacheTrait
 * ────────────────
 * Herbruikbare cache helpers voor Gymies controllers.
 * Biedt consistente key-generatie en TTL via gymies_cache config.
 *
 * Gebruik:
 *   use GymiesCacheTrait;
 *
 *   $result = $this->cacheRemember('trainer_profile', [$trainerId], function () {
 *       return DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->first();
 *   });
 *
 *   $this->cacheForget('trainer_profile', [$trainerId]);
 */
trait GymiesCacheTrait
{
    /**
     * Cache met consistente key en TTL uit config.
     *
     * @param string $type   Key uit gymies_cache.keys (bv. 'trainer_profile')
     * @param array  $parts  Extra key-onderdelen (bv. [123] → gymies:trainer:profile:123)
     * @param callable $callback Data op te halen als cache leeg is
     * @param int|null $ttl  Override TTL (seconden), anders uit config
     */
    protected function cacheRemember(string $type, array $parts, callable $callback, ?int $ttl = null): mixed
    {
        $key = $this->cacheKey($type, $parts);
        $ttl = $ttl ?? $this->cacheTtl($type);

        return Cache::remember($key, $ttl, $callback);
    }

    /**
     * Verwijder cache entry.
     */
    protected function cacheForget(string $type, array $parts = []): void
    {
        Cache::forget($this->cacheKey($type, $parts));
    }

    /**
     * Genereer consistente cache key.
     */
    protected function cacheKey(string $type, array $parts = []): string
    {
        $prefix = config("gymies_cache.keys.{$type}", "gymies:{$type}");
        if (empty($parts)) {
            return $prefix;
        }
        return $prefix . ':' . implode(':', array_map('strval', $parts));
    }

    /**
     * Haal TTL op uit config.
     */
    protected function cacheTtl(string $type): int
    {
        return (int) config("gymies_cache.ttl.{$type}", 300);
    }

    /**
     * Cache invalidatie na een mutation.
     * Verwijdert alle gerelateerde cache entries.
     *
     * @param string $type  Cache type (bv. 'trainer_profile')
     * @param array  $keys  Lijst van key-onderdelen om te flushen
     */
    protected function cacheInvalidate(string $type, array $keys): void
    {
        foreach ($keys as $key) {
            $this->cacheForget($type, is_array($key) ? $key : [$key]);
        }
    }
}
