<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * GymiesPerformanceMiddleware
 * ───────────────────────────
 * Meet API response times en logt trage requests.
 * Voegt X-Response-Time header toe aan elke response.
 *
 * Stuurt slow requests naar Sentry als breadcrumb wanneer
 * ze het performance budget overschrijden.
 *
 * Registreer in de gymies middleware group:
 *   \App\Http\Middleware\GymiesPerformanceMiddleware::class
 */
class GymiesPerformanceMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        $start = hrtime(true);

        /** @var Response $response */
        $response = $next($request);

        $durationMs = (int) round((hrtime(true) - $start) / 1_000_000);

        // Voeg timing header toe
        $response->headers->set('X-Response-Time', "{$durationMs}ms");
        $response->headers->set('Server-Timing', "total;dur={$durationMs}");

        // Instance ID voor horizontale schaling debugging
        $instanceId = config('gymies_redis.scaling.instance_id');
        if ($instanceId) {
            $response->headers->set('X-Instance-Id', (string) $instanceId);
        }

        // Check against performance budget (with defaults if config missing)
        $budget = config('gymies_performance.response_time');
        if (!is_array($budget)) {
            $budget = [];
        }
        $p95    = (int) ($budget['p95'] ?? 500);
        $p99    = (int) ($budget['p99'] ?? 1500);

        if ($durationMs > $p99) {
            // Kritiek trage request
            Log::warning("[Perf] CRITICAL slow request: {$durationMs}ms", [
                'method'   => $request->method(),
                'path'     => $request->path(),
                'duration' => $durationMs,
                'budget'   => $p99,
                'status'   => $response->getStatusCode(),
            ]);

            // Stuur naar Sentry als breadcrumb
            if (app()->bound('sentry') && class_exists(\Sentry\Breadcrumb::class)) {
                try {
                    \Sentry\addBreadcrumb(new \Sentry\Breadcrumb(
                        \Sentry\Breadcrumb::LEVEL_WARNING,
                        \Sentry\Breadcrumb::TYPE_HTTP,
                        'performance',
                        "Slow request: {$request->method()} {$request->path()} took {$durationMs}ms (budget: {$p99}ms)",
                        ['duration_ms' => $durationMs, 'budget_ms' => $p99]
                    ));
                } catch (\Throwable $e) {
                    // Sentry niet beschikbaar — negeer
                }
            }
        } elseif ($durationMs > $p95) {
            // Waarschuwing — boven p95 maar onder p99
            Log::info("[Perf] Slow request: {$durationMs}ms > p95 ({$p95}ms)", [
                'method' => $request->method(),
                'path'   => $request->path(),
            ]);
        }

        return $response;
    }
}
