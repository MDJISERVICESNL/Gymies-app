<?php

declare(strict_types=1);

namespace App\Providers;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;

/**
 * GymiesQueryLogProvider
 *
 * Logs slow queries to storage/logs/queries.log when APP_DEBUG=true
 * or when GYMIES_LOG_QUERIES=true.
 *
 * Threshold configurable via GYMIES_QUERY_THRESHOLD_MS (default: 500ms).
 *
 * Usage: Register in config/app.php providers array
 *   App\Providers\GymiesQueryLogProvider::class,
 */
final class GymiesQueryLogProvider extends ServiceProvider
{
    public function boot(): void
    {
        $shouldLog = config('app.debug') || env('GYMIES_LOG_QUERIES', false);
        if (!$shouldLog) {
            return;
        }

        $thresholdMs = (int) env('GYMIES_QUERY_THRESHOLD_MS', '500');

        DB::listen(function ($query) use ($thresholdMs): void {
            // Log only slow queries
            if ($query->time < $thresholdMs) {
                return;
            }

            Log::channel('queries')->warning('Slow Query', [
                'duration_ms' => $query->time,
                'sql' => $query->sql,
                'bindings' => $query->bindings,
                'connection' => $query->connection?->getName(),
            ]);

            // Store in database if table exists
            if (DB::getSchemaBuilder()->hasTable('gymies_slow_queries')) {
                try {
                    DB::table('gymies_slow_queries')->insert([
                        'sql' => mb_substr($query->sql, 0, 2000),
                        'bindings_json' => json_encode($query->bindings, JSON_UNESCAPED_UNICODE),
                        'duration_ms' => (int) $query->time,
                        'connection' => $query->connection?->getName() ?? 'default',
                        'created_at' => now(),
                    ]);
                } catch (\Throwable $e) {
                    // Silently fail to avoid blocking requests
                }
            }
        });
    }
}
