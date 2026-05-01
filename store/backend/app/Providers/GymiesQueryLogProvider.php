<?php

declare(strict_types=1);

namespace App\Providers;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;

/**
 * GymiesQueryLogProvider
 * ──────────────────────
 * Logt langzame database queries naar het logbestand en Sentry.
 *
 * Registreer in config/app.php → providers:
 *   App\Providers\GymiesQueryLogProvider::class,
 *
 * Configuratie via .env:
 *   DB_SLOW_QUERY_MS=500       (drempel in milliseconden)
 *   PERF_SLOW_QUERY_LOG=true   (aan/uit)
 */
class GymiesQueryLogProvider extends ServiceProvider
{
    public function boot(): void
    {
        if (!config('gymies_performance.slow_query_log', true)) {
            return;
        }

        $threshold = (int) config('gymies_database.slow_query_threshold_ms', 500);

        DB::listen(function ($query) use ($threshold) {
            if ($query->time < $threshold) {
                return;
            }

            $context = [
                'sql'      => $query->sql,
                'time_ms'  => round($query->time, 2),
                'bindings' => $this->sanitizeBindings($query->bindings),
            ];

            // Kritiek langzame queries (>2x drempel)
            if ($query->time >= $threshold * 2) {
                Log::error("[SlowQuery] CRITICAL {$query->time}ms", $context);
            } else {
                Log::warning("[SlowQuery] {$query->time}ms", $context);
            }

            // Stuur naar Sentry als breadcrumb
            if (app()->bound('sentry') && class_exists(\Sentry\Breadcrumb::class)) {
                try {
                    \Sentry\addBreadcrumb(new \Sentry\Breadcrumb(
                        $query->time >= $threshold * 2
                            ? \Sentry\Breadcrumb::LEVEL_ERROR
                            : \Sentry\Breadcrumb::LEVEL_WARNING,
                        \Sentry\Breadcrumb::TYPE_QUERY,
                        'db.query',
                        "Slow query: {$query->time}ms",
                        [
                            'sql'     => \Illuminate\Support\Str::limit($query->sql, 500),
                            'time_ms' => $query->time,
                        ]
                    ));
                } catch (\Throwable $e) {
                    // Sentry niet beschikbaar
                }
            }
        });
    }

    /**
     * Verwijder gevoelige data uit bindings (wachtwoorden, tokens).
     */
    private function sanitizeBindings(array $bindings): array
    {
        return array_map(function ($value) {
            if (is_string($value) && strlen($value) > 100) {
                return '[truncated ' . strlen($value) . ' chars]';
            }
            // Verberg waarden die op wachtwoord-hashes lijken
            if (is_string($value) && preg_match('/^\$2[ayb]\$/', $value)) {
                return '[bcrypt hash]';
            }
            return $value;
        }, $bindings);
    }
}
