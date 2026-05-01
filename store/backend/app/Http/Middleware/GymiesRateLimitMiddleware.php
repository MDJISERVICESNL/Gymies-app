<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * Rate Limiting middleware voor Gymies API.
 *
 * Gebruik als middleware alias: gymies.rate.limit:{type}
 *
 * Types en limieten:
 *   login      → 5 pogingen / minuut per IP
 *   register   → 3 pogingen / minuut per IP
 *   verify     → 5 pogingen / minuut per IP
 *   api        → 60 requests / minuut (auth: per user, anon: per IP)
 *   search     → 30/min (auth) of 10/min (anon) per IP
 *   webhook    → 30 requests / minuut per IP (Mollie callbacks)
 *
 * Rate limiter gebruikt Cache (file/redis — afhankelijk van config).
 * Bij overschrijding retourneert 429 met Retry-After header.
 *
 * Registratie (bootstrap/app.php of Kernel.php):
 *   'gymies.rate.limit' => \App\Http\Middleware\GymiesRateLimitMiddleware::class,
 */
final class GymiesRateLimitMiddleware
{
    /**
     * Limieten per type: [max_requests, decay_seconds].
     */
    private const LIMITS = [
        'login'    => [5,  60],
        'register' => [3,  60],
        'verify'   => [5,  60],
        'api'      => [60, 60],
        'search'   => [30, 60],   // voor ingelogde users
        'webhook'  => [30, 60],
    ];

    /**
     * Strengere limieten voor anonieme (niet-ingelogde) requests.
     */
    private const ANON_LIMITS = [
        'search' => [10, 60],
        'api'    => [30, 60],
    ];

    /**
     * Handle het request.
     *
     * @param  string  $type  Rate limit type (login, api, search, etc.)
     */
    public function handle(Request $request, Closure $next, string $type = 'api'): Response
    {
        // Bepaal limiet
        $isAuthenticated = $this->isAuthenticated($request);
        $limits = $this->getLimits($type, $isAuthenticated);
        [$maxAttempts, $decaySeconds] = $limits;

        // Bouw cache key
        $identifier = $isAuthenticated
            ? 'user:' . $this->getUserId($request)
            : 'ip:' . $request->ip();
        $key = "gymies_rate_limit:{$type}:{$identifier}";

        // Check huidige count
        $attempts = (int) Cache::get($key, 0);

        if ($attempts >= $maxAttempts) {
            $retryAfter = Cache::get("{$key}:timer", $decaySeconds);

            Log::warning('[RateLimit] Limiet bereikt', [
                'type'       => $type,
                'identifier' => $identifier,
                'attempts'   => $attempts,
                'max'        => $maxAttempts,
                'ip'         => $request->ip(),
                'path'       => $request->path(),
            ]);

            return response()->json([
                'error'   => 'rate_limit_exceeded',
                'message' => 'Te veel verzoeken. Probeer het over een moment opnieuw.',
            ], 429, [
                'Retry-After'           => (string) $retryAfter,
                'X-RateLimit-Limit'     => (string) $maxAttempts,
                'X-RateLimit-Remaining' => '0',
            ]);
        }

        // Verhoog counter
        if ($attempts === 0) {
            Cache::put($key, 1, $decaySeconds);
            Cache::put("{$key}:timer", $decaySeconds, $decaySeconds);
        } else {
            Cache::increment($key);
        }

        $remaining = max(0, $maxAttempts - $attempts - 1);

        /** @var Response $response */
        $response = $next($request);

        // Voeg rate limit headers toe
        $response->headers->set('X-RateLimit-Limit', (string) $maxAttempts);
        $response->headers->set('X-RateLimit-Remaining', (string) $remaining);

        return $response;
    }

    /**
     * Controleer of het request een geauthenticeerde user heeft.
     */
    private function isAuthenticated(Request $request): bool
    {
        return $request->attributes->has('gymies_user_id')
            || $request->bearerToken() !== null
            || $request->query('access_token') !== null;
    }

    /**
     * Haal de user ID op (als beschikbaar).
     */
    private function getUserId(Request $request): string
    {
        $userId = $request->attributes->get('gymies_user_id');
        if ($userId) {
            return (string) $userId;
        }

        // Fallback: hash het token zodat we niet het echte token als key gebruiken
        $token = $request->bearerToken() ?? $request->query('access_token');
        return $token ? substr(hash('sha256', $token), 0, 16) : 'anon';
    }

    /**
     * Bepaal de juiste limieten op basis van type en authenticatiestatus.
     *
     * @return array{int, int} [max_attempts, decay_seconds]
     */
    private function getLimits(string $type, bool $isAuthenticated): array
    {
        // Anonieme limieten (strenger)
        if (!$isAuthenticated && isset(self::ANON_LIMITS[$type])) {
            return self::ANON_LIMITS[$type];
        }

        return self::LIMITS[$type] ?? self::LIMITS['api'];
    }
}
