<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpFoundation\Response;

/**
 * Bearer-token authenticatie voor Gymies API.
 * Token in header: Authorization: Bearer <token> of X-Gymies-Access-Token: <token>
 */
class EnsureGymiesUserFromToken
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user() !== null) {
            return $next($request);
        }

        $token = $this->getToken($request);
        $tokenSource = $this->getTokenSource($request);
        if ($token === null || $token === '') {
            Log::channel('single')->info('[GymiesAuth 401] Geen token', [
                'path' => $request->path(),
                'has_auth_header' => $request->hasHeader('Authorization'),
                'has_x_gymies' => $request->hasHeader('X-Gymies-Access-Token'),
                'has_access_token_query' => $request->filled('access_token'),
                'user_agent' => substr($request->userAgent() ?? '', 0, 80),
            ]);
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $plainToken = str_contains($token, '|') ? substr($token, strpos($token, '|') + 1) : $token;
        $accessToken = null;

        // Try to find token via DB (try all registered tables)
        if (Schema::hasTable('gymies_personal_access_tokens') || Schema::hasTable('personal_access_tokens')) {
            $accessToken = $this->findTokenViaDb($plainToken);
        }

        // Fallback: try Sanctum's PersonalAccessToken model (only if not found)
        if ($accessToken === null && class_exists(PersonalAccessToken::class)) {
            try {
                $accessToken = PersonalAccessToken::findToken($token);
            } catch (\Throwable $e) {
                $accessToken = null;
            }
        }

        $tokenableId = $accessToken?->tokenable_id ?? null;

        // Check token expiry if applicable
        // FIX-AUD-005: Always use UTC for token expiry comparisons to prevent DST boundary issues
        if ($tokenableId !== null && $accessToken !== null) {
            if (isset($accessToken->expires_at) && $accessToken->expires_at !== null) {
                // Use UTC for comparison to prevent issues when clocks spring forward/backward
                $expiryTime = \Carbon\Carbon::parse($accessToken->expires_at)->setTimezone('UTC');
                $currentTime = \Carbon\Carbon::now('UTC');
                if ($expiryTime->isPast($currentTime)) {
                    Log::channel('single')->warning('[GymiesAuth 401] Token expired', [
                        'path' => $request->path(),
                        'token_source' => $tokenSource,
                        'expires_at' => $accessToken->expires_at,
                        'current_time_utc' => $currentTime->toDateTimeString(),
                    ]);
                    return response()->json(['message' => 'Ongeldige of verlopen sessie. Log opnieuw in.'], 401);
                }
            }
        }

        if ($tokenableId === null) {
            $row = $this->findUserByApiToken($token);
            if ($row !== null) {
                $request->setUserResolver(fn () => new \Illuminate\Auth\GenericUser((array) $row));
                return $next($request);
            }
            Log::channel('single')->warning('[GymiesAuth 401] Token niet gevonden in DB', [
                'path' => $request->path(),
                'token_source' => $tokenSource,
                'token_length' => strlen($token),
                'token_preview' => strlen($token) > 8 ? substr($token, 0, 8) . '...' . substr($token, -4) : '***',
                'token_has_pipe' => str_contains($token, '|'),
                'user_agent' => substr($request->userAgent() ?? '', 0, 80),
            ]);
            return response()->json(['message' => 'Ongeldige of verlopen sessie. Log opnieuw in.'], 401);
        }

        $usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
        $row = DB::table($usersTable)->where('id', (int) $tokenableId)->first();
        if ($row === null) {
            return response()->json(['message' => 'Gebruiker niet gevonden. Log opnieuw in.'], 401);
        }

        $request->setUserResolver(fn () => new \Illuminate\Auth\GenericUser((array) $row));
        return $next($request);
    }

    /**
     * Haal token uit request. access_token in query heeft VOORRANG – app stuurt zo;
     * proxies kunnen Authorization header vervangen met verkeerde waarde.
     */
    private function getToken(Request $request): ?string
    {
        // 1. Query param eerst – Flutter-app stuurt token hier; proxy kan headers vervangen
        if ($request->filled('access_token')) {
            $t = trim((string) $request->input('access_token'));
            if ($t !== '') {
                $decoded = rawurldecode($t);
                return $decoded !== '' ? $decoded : $t;
            }
        }
        // 2. Headers (curl, Postman, etc.)
        $h = $request->header('Authorization');
        if (is_string($h) && $h !== '' && str_starts_with($h, 'Bearer ')) {
            return trim(substr($h, 7));
        }
        $h = $request->header('X-Gymies-Access-Token');
        if (is_string($h) && $h !== '') {
            return trim($h);
        }
        $server = $request->server();
        foreach (['REDIRECT_HTTP_AUTHORIZATION', 'HTTP_AUTHORIZATION'] as $key) {
            $v = $server[$key] ?? null;
            if (is_string($v) && $v !== '' && str_starts_with($v, 'Bearer ')) {
                return trim(substr($v, 7));
            }
        }
        $xToken = $server['HTTP_X_GYMIES_ACCESS_TOKEN'] ?? null;
        if (is_string($xToken) && $xToken !== '') {
            return trim($xToken);
        }
        return null;
    }

    private function getTokenSource(Request $request): string
    {
        if ($request->header('Authorization') && str_starts_with((string) $request->header('Authorization'), 'Bearer ')) {
            return 'Authorization';
        }
        if ($request->header('X-Gymies-Access-Token')) {
            return 'X-Gymies-Access-Token';
        }
        if ($request->filled('access_token')) {
            return 'access_token_query';
        }
        $server = $request->server();
        foreach (['REDIRECT_HTTP_AUTHORIZATION', 'HTTP_AUTHORIZATION'] as $key) {
            if (!empty($server[$key]) && str_starts_with($server[$key], 'Bearer ')) {
                return "server_{$key}";
            }
        }
        return 'none';
    }

    private function findTokenViaDb(string $plainToken): ?object
    {
        $hashedToken = hash('sha256', $plainToken);
        $tables = Schema::hasTable('gymies_users') && Schema::hasTable('gymies_personal_access_tokens')
            ? ['gymies_personal_access_tokens', 'personal_access_tokens']
            : ['personal_access_tokens', 'gymies_personal_access_tokens'];
        foreach ($tables as $table) {
            if (!Schema::hasTable($table)) continue;
            $row = DB::table($table)->where('token', $hashedToken)->first();
            if ($row !== null) return $row;
        }
        return null;
    }

    private function findUserByApiToken(string $token): ?object
    {
        $tokensToTry = [$token];
        if (str_contains($token, '|')) {
            $tokensToTry[] = substr($token, strpos($token, '|') + 1);
        }
        foreach (['gymies_users', 'users'] as $table) {
            if (!Schema::hasTable($table) || !Schema::hasColumn($table, 'api_token')) continue;
            foreach ($tokensToTry as $t) {
                $row = DB::table($table)->where('api_token', $t)->first();
                if ($row !== null) return $row;
            }
        }
        return null;
    }
}
