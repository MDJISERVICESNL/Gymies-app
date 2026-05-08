<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Sentry User Context Middleware
 * ──────────────────────────────
 * Koppelt de ingelogde Gymies-gebruiker aan Sentry events.
 * Draait NA auth middleware zodat $request->user() beschikbaar is.
 *
 * Wat wordt meegestuurd:
 *  - user ID (integer)
 *  - email (voor error lookup)
 *  - role (trainer/client/admin)
 *  - display_name
 *
 * Sentry SDK moet geïnstalleerd zijn: composer require sentry/sentry-laravel
 * Als Sentry niet actief is (geen DSN), doet deze middleware niets.
 */
class GymiesSentryContextMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        // Alleen uitvoeren als Sentry daadwerkelijk geconfigureerd is
        if (!app()->bound('sentry') || empty(config('gymies.sentry_dsn'))) {
            return $next($request);
        }

        $user = $request->user();

        if ($user && isset($user->id)) {
            \Sentry\configureScope(function (\Sentry\State\Scope $scope) use ($user, $request): void {
                $userData = [
                    'id' => (string) $user->id,
                ];

                // Only add email if present and not empty
                if (!empty($user->email)) {
                    $userData['email'] = (string) $user->email;
                }

                // Only add username if present and not empty
                $username = $user->display_name ?? $user->name ?? null;
                if (!empty($username)) {
                    $userData['username'] = (string) $username;
                }

                $scope->setUser($userData);

                // Role as tag for Sentry dashboard filtering
                $role = $user->role ?? $user->user_role ?? null;
                if (!empty($role)) {
                    $scope->setTag('user.role', (string) $role);
                }

                // Extra request context
                $scope->setContext('request', [
                    'url'    => $request->fullUrl(),
                    'method' => $request->method(),
                    'ip'     => $request->ip(),
                    'user_agent' => substr((string) $request->userAgent(), 0, 200),
                ]);
            });
        }

        return $next($request);
    }
}
