<?php

declare(strict_types=1);

/**
 * Gymies Redis & Horizontale Schaling Configuratie
 * ─────────────────────────────────────────────────
 * Configureer Redis als cache/session/queue driver voor horizontale schaling.
 *
 * Stappen om Redis te activeren:
 *
 * 1. Installeer Redis op server:
 *      sudo apt install redis-server
 *      sudo systemctl enable redis-server
 *
 * 2. Installeer PHP Redis extensie:
 *      sudo apt install php8.4-redis
 *      sudo systemctl restart php8.4-fpm
 *
 * 3. Of gebruik predis via composer:
 *      composer require predis/predis
 *
 * 4. Update .env:
 *      CACHE_STORE=redis
 *      SESSION_DRIVER=redis
 *      QUEUE_CONNECTION=redis
 *      REDIS_HOST=127.0.0.1
 *      REDIS_PORT=6379
 *      REDIS_PASSWORD=null
 *
 * 5. Voor AWS ElastiCache (multi-instance):
 *      REDIS_HOST=gymies-cache.xxxxxx.euw1.cache.amazonaws.com
 *      REDIS_PORT=6379
 *
 * Merge in config/database.php → 'redis':
 *   'redis' => array_merge(
 *       config('database.redis', []),
 *       config('gymies_redis.connections', [])
 *   ),
 */
return [
    // ── Redis client ───────────────────────────────────────────────────────
    // 'phpredis' (native, sneller) of 'predis' (pure PHP, geen extensie nodig)
    'client' => env('REDIS_CLIENT', 'phpredis'),

    // ── Connections ────────────────────────────────────────────────────────
    'connections' => [
        'default' => [
            'url'      => env('REDIS_URL'),
            'host'     => env('REDIS_HOST', '127.0.0.1'),
            'username' => env('REDIS_USERNAME'),
            'password' => env('REDIS_PASSWORD'),
            'port'     => env('REDIS_PORT', '6379'),
            'database' => env('REDIS_DB', '0'),
            'prefix'   => env('REDIS_PREFIX', 'gymies:'),
        ],

        // Aparte database voor cache (voorkomt conflict met sessions)
        'cache' => [
            'url'      => env('REDIS_URL'),
            'host'     => env('REDIS_HOST', '127.0.0.1'),
            'username' => env('REDIS_USERNAME'),
            'password' => env('REDIS_PASSWORD'),
            'port'     => env('REDIS_PORT', '6379'),
            'database' => env('REDIS_CACHE_DB', '1'),
            'prefix'   => env('REDIS_PREFIX', 'gymies:'),
        ],

        // Aparte database voor sessions
        'session' => [
            'url'      => env('REDIS_URL'),
            'host'     => env('REDIS_HOST', '127.0.0.1'),
            'username' => env('REDIS_USERNAME'),
            'password' => env('REDIS_PASSWORD'),
            'port'     => env('REDIS_PORT', '6379'),
            'database' => env('REDIS_SESSION_DB', '2'),
            'prefix'   => env('REDIS_PREFIX', 'gymies_session:'),
        ],

        // Queue connection (als QUEUE_CONNECTION=redis)
        'queue' => [
            'url'      => env('REDIS_URL'),
            'host'     => env('REDIS_HOST', '127.0.0.1'),
            'username' => env('REDIS_USERNAME'),
            'password' => env('REDIS_PASSWORD'),
            'port'     => env('REDIS_PORT', '6379'),
            'database' => env('REDIS_QUEUE_DB', '3'),
            'prefix'   => env('REDIS_PREFIX', 'gymies_queue:'),
        ],
    ],

    // ── Horizontale schaling checklist ──────────────────────────────────────
    // Dit blok is puur documentatie — geen runtime effect.
    //
    // Pre-requisites voor meerdere EC2 instances:
    //
    // [x] Sessions in Redis i.p.v. file (SESSION_DRIVER=redis)
    //     → Alle instances delen dezelfde sessies
    //
    // [x] Cache in Redis i.p.v. file (CACHE_STORE=redis)
    //     → Feature flags, circuit breaker, rate limiting gedeeld
    //
    // [x] Queue in Redis of database (QUEUE_CONNECTION=redis)
    //     → Jobs worden niet dubbel verwerkt
    //
    // [x] File uploads naar S3 (FILESYSTEM_DISK=s3)
    //     → Avatar/media niet lokaal opgeslagen
    //
    // [x] Stateless API (token-based auth, geen PHP sessions voor API)
    //     → Gymies gebruikt al Bearer token auth
    //
    // [ ] Load balancer (ALB) met health check op /api/gymies/health
    //     → ALB stuurt verkeer naar gezonde instances
    //
    // [ ] Shared storage voor logs (CloudWatch of centraal logging)
    //     → Sentry vangt errors al centraal op
    //
    // [ ] Database: RDS met read replicas voor zware queries
    //     → Gymies draait al op AWS RDS

    // ── Horizontale schaling helpers ───────────────────────────────────────
    'scaling' => [
        // Instance ID voor logging (automatisch op EC2, fallback hostname)
        'instance_id' => env('EC2_INSTANCE_ID', gethostname()),

        // Health check pad voor ALB
        'health_path' => '/api/gymies/health',

        // Sticky sessions uitschakelen (stateless API = geen sticky nodig)
        'sticky_sessions' => false,
    ],
];
