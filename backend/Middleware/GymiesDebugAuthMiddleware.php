<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Debug-auth routes: alleen toegankelijk in local/testing of als GYMIES_DEBUG_AUTH=true.
 * In productie: 404.
 */
final class GymiesDebugAuthMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        $env = config('app.env', 'production');
        $debugAuth = filter_var(env('GYMIES_DEBUG_AUTH', ''), FILTER_VALIDATE_BOOLEAN);
        if (in_array($env, ['local', 'testing'], true) || $debugAuth) {
            return $next($request);
        }
        return response()->json(['message' => 'Not found'], 404);
    }
}
