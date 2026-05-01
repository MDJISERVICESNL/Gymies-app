<?php

declare(strict_types=1);

/**
 * Gymies Performance Budget
 * ─────────────────────────
 * Definieert de maximale waarden voor API responstijden,
 * foutpercentages en andere performance metrics.
 *
 * Gebruik in health checks, k6 tests en Sentry alerts.
 */
return [
    // ── API Response Time Budgets (ms) ──────────────────────────
    'response_time' => [
        'p50'  => (int) env('PERF_P50_MS', 100),    // Mediaan
        'p95'  => (int) env('PERF_P95_MS', 500),    // 95e percentiel
        'p99'  => (int) env('PERF_P99_MS', 1500),   // 99e percentiel
        'max'  => (int) env('PERF_MAX_MS', 5000),   // Absolute max
    ],

    // ── Error Rate Budgets (%) ──────────────────────────────────
    'error_rate' => [
        'warning'  => (float) env('PERF_ERROR_WARN', 1.0),    // >1% = waarschuwing
        'critical' => (float) env('PERF_ERROR_CRIT', 5.0),    // >5% = kritiek
    ],

    // ── Endpoint-specifieke budgets (ms) ────────────────────────
    'endpoints' => [
        'health'         => 50,     // Health check moet razendsnel zijn
        'login'          => 300,    // Bcrypt is traag, 300ms OK
        'search'         => 400,    // Zoeken met spatial queries
        'bookings_list'  => 200,    // Lijst ophalen
        'bookings_create'=> 500,    // Transactie + notificaties
        'conversations'  => 200,    // Chat lijst
        'messages'       => 150,    // Berichten laden
        'webhook'        => 1000,   // Mollie webhook (ext API call)
        'feature_flags'  => 50,     // Gecachet, moet snel zijn
    ],

    // ── Queue Budgets ───────────────────────────────────────────
    'queue' => [
        'max_pending'    => (int) env('PERF_QUEUE_MAX_PENDING', 100),
        'max_age_s'      => (int) env('PERF_QUEUE_MAX_AGE', 600),     // 10 min
        'max_failed_1h'  => (int) env('PERF_QUEUE_MAX_FAILED', 10),
    ],

    // ── Database Budgets ────────────────────────────────────────
    'database' => [
        'query_warn_ms'  => (int) env('PERF_DB_QUERY_WARN', 100),    // Langzame query
        'query_crit_ms'  => (int) env('PERF_DB_QUERY_CRIT', 1000),   // Zeer trage query
        'max_connections' => (int) env('PERF_DB_MAX_CONN', 50),
    ],

    // ── Sentry Configuration ────────────────────────────────────
    'sentry' => [
        'traces_sample_rate'   => (float) env('SENTRY_TRACES_SAMPLE_RATE', 0.2),
        'profiles_sample_rate' => (float) env('SENTRY_PROFILES_SAMPLE_RATE', 0.1),
        'environment'          => env('SENTRY_ENVIRONMENT', env('APP_ENV', 'production')),
    ],

    // ── Slow Query Logging ──────────────────────────────────────
    'slow_query_log' => (bool) env('PERF_SLOW_QUERY_LOG', true),
];
