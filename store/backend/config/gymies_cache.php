<?php

declare(strict_types=1);

/**
 * Gymies Caching Strategie Configuratie
 * ──────────────────────────────────────
 * Centrale plek voor alle cache TTLs en keys.
 * Maakt het makkelijk om caching te tunen zonder door controllers te zoeken.
 *
 * Gebruik in controllers:
 *   $ttl = config('gymies_cache.ttl.trainer_search');
 *   Cache::remember("gymies:trainers:search:{$hash}", $ttl, fn () => ...);
 *
 * .env overrides:
 *   GYMIES_CACHE_TRAINER_SEARCH_TTL=600
 *   GYMIES_CACHE_DASHBOARD_TTL=120
 */
return [
    // ── Cache TTLs (seconden) ──────────────────────────────────────────────
    'ttl' => [
        // Publieke data — mag langer gecacht worden
        'trainer_search'       => (int) env('GYMIES_CACHE_TRAINER_SEARCH_TTL', 300),    // 5 min
        'trainer_profile'      => (int) env('GYMIES_CACHE_TRAINER_PROFILE_TTL', 300),   // 5 min
        'trainer_packages'     => (int) env('GYMIES_CACHE_TRAINER_PACKAGES_TTL', 600),  // 10 min
        'group_sessions'       => (int) env('GYMIES_CACHE_GROUP_SESSIONS_TTL', 120),    // 2 min
        'payment_methods'      => (int) env('GYMIES_CACHE_PAYMENT_METHODS_TTL', 3600),  // 1 uur

        // Dashboard/stats — relatief kort vanwege realtime verwachting
        'dashboard_stats'      => (int) env('GYMIES_CACHE_DASHBOARD_TTL', 120),         // 2 min
        'gym_dashboard'        => (int) env('GYMIES_CACHE_GYM_DASHBOARD_TTL', 120),     // 2 min
        'revenue_stats'        => (int) env('GYMIES_CACHE_REVENUE_TTL', 300),           // 5 min

        // Feature flags — kort genoeg voor snelle rollout
        'feature_flags'        => (int) env('GYMIES_CACHE_FEATURE_FLAGS_TTL', 300),     // 5 min

        // Systeem
        'health_check'         => (int) env('GYMIES_CACHE_HEALTH_TTL', 30),             // 30 sec
        'circuit_breaker'      => (int) env('GYMIES_CACHE_CIRCUIT_BREAKER_TTL', 300),   // 5 min
        'rate_limit'           => (int) env('GYMIES_CACHE_RATE_LIMIT_TTL', 60),         // 1 min
    ],

    // ── Cache key prefixes ─────────────────────────────────────────────────
    // Consistent naamgeving voorkomt key collisions
    'keys' => [
        'trainer_search'       => 'gymies:search:trainers',
        'trainer_profile'      => 'gymies:trainer:profile',
        'trainer_packages'     => 'gymies:trainer:packages',
        'group_sessions'       => 'gymies:groups:sessions',
        'dashboard_stats'      => 'gymies:dashboard:stats',
        'gym_dashboard'        => 'gymies:gym:dashboard',
        'revenue_stats'        => 'gymies:revenue',
        'feature_flags'        => 'gymies:feature_flags',
        'circuit_breaker'      => 'gymies:circuit_breaker:mollie',
        'payment_methods'      => 'gymies:mollie:methods',
    ],

    // ── Cache invalidation tags ────────────────────────────────────────────
    // Gebruik Cache::tags(['trainer:123'])->flush() na updates
    // Let op: tags werken alleen met Redis/Memcached, niet met file driver
    'tags' => [
        'trainer'  => 'trainer',  // trainer:{user_id}
        'booking'  => 'booking',  // booking:{id}
        'gym'      => 'gym',      // gym:{org_id}
    ],

    // ── Cache-warming ──────────────────────────────────────────────────────
    // Endpoints die na deploy of cache-flush opgewarmd moeten worden
    'warmup_endpoints' => [
        '/api/gymies/health',
        '/api/gymies/trainers/search?lat=52.37&lng=4.89&radius=50',
    ],
];
