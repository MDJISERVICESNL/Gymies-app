<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * GymiesPerformanceMiddleware
 *
 * Monitors request timing and slow queries.
 * Logs all requests >= slowRequestThreshold to storage/logs/performance.log
 * Logs very slow requests (>5s) to Sentry if configured.
 *
 * Configuration via env:
 *   GYMIES_SLOW_REQUEST_THRESHOLD_MS=1000  (default)
 *   GYMIES_LOG_QUERIES=true                (log slow queries)
 *   GYMIES_QUERY_THRESHOLD_MS=500          (query slow threshold)
 */
final class GymiesPerformanceMiddleware
{
    private int $slowRequestThreshold;
    private int $queryThreshold;
    private bool $logQueries;
    private float $startTime;

    public function __construct()
    {
        $this->slowRequestThreshold = (int) (env('GYMIES_SLOW_REQUEST_THRESHOLD_MS', '1000'));
        $this->queryThreshold = (int) (env('GYMIES_QUERY_THRESHOLD_MS', '500'));
        $this->logQueries = (bool) env('GYMIES_LOG_QUERIES', app()->environment('local', 'testing'));
    }

    public function handle(Request $request, Closure $next): Response
    {
        $this->startTime = hrtime(true);
        $queryCount = 0;

        // Start query logging if enabled
        if ($this->logQueries && app()->environment('local', 'testing', 'development')) {
            DB::listen(function ($query) {
                if ($query->time >= $this->queryThreshold) {
                    Log::channel('performance')->warning('Slow Query', [
                        'query' => $query->sql,
                        'bindings' => $query->bindings,
                        'time_ms' => $query->time,
                    ]);
                }
            });
        }

        /** @var Response $response */
        $response = $next($request);

        $duration = (int) round((hrtime(true) - $this->startTime) / 1_000_000);

        // Log slow requests
        if ($duration >= $this->slowRequestThreshold) {
            $this->logSlowRequest($request, $response, $duration);
        }

        // Add timing headers for debugging
        if (app()->environment('local', 'testing', 'development')) {
            $response->headers->set('X-Response-Time-Ms', (string) $duration);
            $response->headers->set('X-Db-Query-Count', (string) DB::getQueryLog() ? count(DB::getQueryLog()) : '0');
        }

        return $response;
    }

    private function logSlowRequest(Request $request, Response $response, int $durationMs): void
    {
        $data = [
            'method' => $request->method(),
            'path' => $request->path(),
            'status' => $response->getStatusCode(),
            'duration_ms' => $durationMs,
            'query_count' => DB::getQueryLog() ? count(DB::getQueryLog()) : 0,
            'timestamp' => now()->toIso8601String(),
            'user_id' => $request->attributes->get('gymies_user')?->id,
        ];

        Log::channel('performance')->warning("Slow Request: {$durationMs}ms {$request->method()} {$request->path()}", $data);

        // Store in database if table exists
        if (DB::getSchemaBuilder()->hasTable('gymies_performance_logs')) {
            try {
                DB::table('gymies_performance_logs')->insert([
                    'method' => $request->method(),
                    'path' => mb_substr($request->path(), 0, 255),
                    'status_code' => $response->getStatusCode(),
                    'duration_ms' => $durationMs,
                    'query_count' => $data['query_count'],
                    'user_id' => $data['user_id'],
                    'created_at' => now(),
                ]);
            } catch (\Throwable $e) {
                Log::error('Failed to log performance: ' . $e->getMessage());
            }
        }

        // Alert to Sentry for very slow requests (>5 seconds) or errors
        if ($durationMs > 5000 || $response->getStatusCode() >= 500) {
            if (function_exists('\\Sentry\\captureMessage')) {
                \Sentry\captureMessage(
                    "Slow/Error request: {$durationMs}ms {$request->method()} {$request->path()}",
                    \Sentry\Severity::warning(),
                    $data
                );
            }
        }
    }
}
