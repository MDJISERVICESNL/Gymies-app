<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * GymiesApiDeprecationMiddleware
 * ──────────────────────────────
 * Voegt deprecation headers toe aan API responses en logt gebruik
 * van verouderde endpoints zodat we veilig kunnen afbouwen.
 *
 * Headers die worden toegevoegd:
 *   Deprecation: true                  (RFC 8594)
 *   Sunset: Sat, 01 Nov 2025 00:00:00 GMT
 *   Link: </api/gymies/v2/bookings>; rel="successor-version"
 *   X-API-Warn: "Dit endpoint is deprecated. Gebruik /api/gymies/v2/bookings"
 *
 * Registreer in server_gymies_routes.php of per route:
 *   ->middleware(GymiesApiDeprecationMiddleware::class)
 *
 * Configuratie via config/gymies_deprecation.php
 */
class GymiesApiDeprecationMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        $path = $request->path();
        $deprecated = $this->findDeprecation($path);

        if ($deprecated === null) {
            return $response;
        }

        // RFC 8594 Deprecation header
        $response->headers->set('Deprecation', 'true');

        // Sunset header (wanneer het endpoint definitief verdwijnt)
        if (!empty($deprecated['sunset'])) {
            $sunset = (new \DateTimeImmutable($deprecated['sunset']))->format(\DateTimeInterface::RFC7231);
            $response->headers->set('Sunset', $sunset);
        }

        // Link naar opvolger
        if (!empty($deprecated['successor'])) {
            $response->headers->set(
                'Link',
                '<' . url($deprecated['successor']) . '>; rel="successor-version"'
            );
        }

        // Waarschuwing in custom header
        $message = $deprecated['message'] ?? 'Dit endpoint is deprecated.';
        $response->headers->set('X-API-Warn', $message);

        // Log gebruik van deprecated endpoints (max 1x per minuut per IP+path)
        $this->logDeprecatedUsage($request, $path, $deprecated);

        return $response;
    }

    /**
     * Zoek deprecation config voor het huidige pad.
     */
    private function findDeprecation(string $path): ?array
    {
        $endpoints = config('gymies_deprecation.endpoints', []);

        foreach ($endpoints as $pattern => $config) {
            // Exacte match of wildcard
            if ($path === $pattern || fnmatch($pattern, $path)) {
                return $config;
            }
        }

        return null;
    }

    /**
     * Log deprecated endpoint gebruik (rate-limited per IP).
     */
    private function logDeprecatedUsage(Request $request, string $path, array $deprecated): void
    {
        if (!config('gymies_deprecation.log_usage', true)) {
            return;
        }

        $cacheKey = 'deprecated_log:' . md5($request->ip() . $path);

        // Max 1 log per minuut per IP+path
        if (cache()->has($cacheKey)) {
            return;
        }
        cache()->put($cacheKey, true, 60);

        Log::info('[API:Deprecated] Gebruik van verouderd endpoint', [
            'path'      => $path,
            'method'    => $request->method(),
            'ip'        => $request->ip(),
            'user_id'   => $request->user()?->id ?? null,
            'successor' => $deprecated['successor'] ?? null,
            'sunset'    => $deprecated['sunset'] ?? null,
            'user_agent' => \Illuminate\Support\Str::limit($request->userAgent() ?? '', 100),
        ]);
    }
}
