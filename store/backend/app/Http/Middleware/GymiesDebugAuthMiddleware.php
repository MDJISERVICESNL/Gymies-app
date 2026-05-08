<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gymies Debug Auth Middleware
 * ────────────────────────────
 * Blokkeert debug-auth endpoints in productie.
 * Alleen toegankelijk als:
 *  - APP_ENV=local of APP_ENV=staging
 *  - OF GYMIES_DEBUG_AUTH=true in .env (voor tijdelijke productie-diagnose)
 *
 * Registreer als 'gymies.debug.auth' in Kernel of bootstrap.
 */
class GymiesDebugAuthMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        $env = config('app.env', 'production');
        $debugAllowed = filter_var(
            config('gymies.debug_auth_enabled', env('GYMIES_DEBUG_AUTH', false)),
            FILTER_VALIDATE_BOOLEAN
        );

        // Alleen local, staging, of expliciete override
        if (!in_array($env, ['local', 'staging', 'testing'], true) && !$debugAllowed) {
            return response()->json([
                'message' => 'Debug endpoints zijn uitgeschakeld in productie.',
            ], 403);
        }

        return $next($request);
    }
}
