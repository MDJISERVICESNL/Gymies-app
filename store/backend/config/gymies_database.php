<?php

declare(strict_types=1);

/**
 * Gymies Database Resilience Configuration
 * ─────────────────────────────────────────
 * Extra database-instellingen voor resilience en performance.
 *
 * Voeg toe aan config/database.php → 'mysql' → 'options':
 *
 *   'options' => array_merge(
 *       config('gymies_database.pdo_options', []),
 *       $existingOptions ?? []
 *   ),
 *
 * Of merge handmatig in .env:
 *   DB_TIMEOUT=5
 *   DB_PERSISTENT=true
 */
return [
    // ── PDO Options ─────────────────────────────────────────────────
    'pdo_options' => [
        // Persistent connections: herbruik TCP connectie tussen requests
        // Vermindert connect-overhead onder load significant
        PDO::ATTR_PERSISTENT => (bool) env('DB_PERSISTENT', true),

        // Connection timeout (seconden) — voorkom hangen bij DB restart
        PDO::ATTR_TIMEOUT => (int) env('DB_TIMEOUT', 5),

        // Fout-modus: exceptions (Laravel standaard, maar expliciteer)
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,

        // Fetch-modus: standaard associative array
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_OBJ,

        // Emulated prepares UIT voor echte server-side prepared statements
        PDO::ATTR_EMULATE_PREPARES => false,
    ],

    // ── Retry configuratie ──────────────────────────────────────────
    'retry' => [
        'times' => (int) env('DB_RETRY_TIMES', 3),
        'sleep_ms' => (int) env('DB_RETRY_SLEEP_MS', 100),
    ],

    // ── Slow query drempel ──────────────────────────────────────────
    'slow_query_threshold_ms' => (int) env('DB_SLOW_QUERY_MS', 500),

    // ── Connection pool ─────────────────────────────────────────────
    // Max connections per Laravel worker (PHP-FPM process)
    'max_connections' => (int) env('DB_MAX_CONNECTIONS', 50),
];
