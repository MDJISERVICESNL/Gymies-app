<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\HttpFoundation\Response;

/**
 * Preempt middleware: draait vroeg, zet user voor api/gymies Bearer-requests.
 * Zo ziet auth:sanctum (als die draait) al een user en faalt niet met "Unauthorized".
 *
 * Registreer als eerste in de api middleware group via register_gymies_preempt.php.
 */
class EnsureGymiesAuthPreempt
{
    public function handle(Request $request, Closure $next): Response
    {
        $path = $request->path();
        if (!str_starts_with($path, 'api/gymies')) {
            return $next($request);
        }

        if ($request->user() !== null) {
            return $next($request);
        }

        $authHeader = $this->resolveAuthorizationHeader($request);
        if ($authHeader === null || !str_starts_with($authHeader, 'Bearer ')) {
            return $next($request);
        }

        $token = trim(substr($authHeader, 7));
        if ($token === '') {
            return $next($request);
        }

        $plainToken = str_contains($token, '|') ? substr($token, strpos($token, '|') + 1) : $token;

        // 64-hex sessietoken: zoek in gymies_sessions
        if (strlen($plainToken) === 64 && ctype_xdigit($plainToken) && Schema::hasTable('gymies_sessions')) {
            $session = $this->findSessionInGymiesSessions($token, $plainToken);
            if ($session !== null && isset($session->user_id)) {
                $usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
                $row = \Illuminate\Support\Facades\DB::table($usersTable)->where('id', (int) $session->user_id)->first();
                if ($row !== null) {
                    $request->setUserResolver(fn () => new \Illuminate\Auth\GenericUser((array) $row));
                    return $next($request);
                }
            }
        }

        $tokenableId = null;
        $accessToken = null;
        if (Schema::hasTable('gymies_users') && Schema::hasTable('gymies_personal_access_tokens')) {
            $accessToken = $this->findTokenViaDb($plainToken);
            $tokenableId = $accessToken?->tokenable_id ?? null;
        }
        if ($tokenableId === null && class_exists(PersonalAccessToken::class)) {
            try {
                $pat = PersonalAccessToken::findToken($token);
                $tokenableId = $pat?->tokenable_id;
            } catch (\Throwable $e) {
                // ignore
            }
        }
        if ($tokenableId === null) {
            $accessToken = $this->findTokenViaDb($plainToken);
            $tokenableId = $accessToken?->tokenable_id ?? null;
        }
        if ($tokenableId === null && Schema::hasTable('gymies_sessions')) {
            $plainToken = preg_match('/^[a-fA-F0-9]{64}$/', $token) ? $token : null;
            if ($plainToken !== null) {
                $session = $this->findSessionInGymiesSessions($token, $plainToken);
                if ($session !== null && isset($session->user_id)) {
                    $usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
                    $row = DB::table($usersTable)->where('id', (int) $session->user_id)->first();
                    if ($row !== null) {
                        $user = new \Illuminate\Auth\GenericUser((array) $row);
                        $request->setUserResolver(fn () => $user);
                        return $next($request);
                    }
                }
            }
        }
        if ($tokenableId === null) {
            $row = $this->findUserByApiToken($token);
            if ($row !== null) {
                $user = new \Illuminate\Auth\GenericUser((array) $row);
                $request->setUserResolver(fn () => $user);
                return $next($request);
            }
            return $next($request);
        }

        $usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
        $row = DB::table($usersTable)->where('id', (int) $tokenableId)->first();
        if ($row !== null) {
            $user = new \Illuminate\Auth\GenericUser((array) $row);
            $request->setUserResolver(fn () => $user);
        }

        return $next($request);
    }

    /**
     * Query param eerst –zelfde volgorde als EnsureGymiesUserFromToken.
     */
    private function resolveAuthorizationHeader(Request $request): ?string
    {
        if ($request->filled('access_token')) {
            $t = trim((string) $request->input('access_token'));
            if ($t !== '') {
                $decoded = rawurldecode($t);
                return 'Bearer ' . ($decoded !== '' ? $decoded : $t);
            }
        }
        $h = $request->header('Authorization');
        if (is_string($h) && $h !== '' && str_starts_with($h, 'Bearer ')) {
            return $h;
        }
        $h = $request->header('X-Gymies-Access-Token');
        if (is_string($h) && $h !== '') {
            return 'Bearer ' . trim($h);
        }
        $h = $request->header('X-Authorization');
        if (is_string($h) && str_starts_with($h, 'Bearer ')) {
            return $h;
        }
        $h = $request->header('X-Gymies-Token');
        if (is_string($h) && $h !== '') {
            return 'Bearer ' . trim($h);
        }
        $server = $request->server();
        foreach (['REDIRECT_HTTP_AUTHORIZATION', 'HTTP_AUTHORIZATION'] as $key) {
            $v = $server[$key] ?? null;
            if (is_string($v) && $v !== '' && str_starts_with($v, 'Bearer ')) {
                return $v;
            }
        }
        return null;
    }

    private function findTokenViaDb(string $plainToken): ?object
    {
        $hashedToken = hash('sha256', $plainToken);
        $tables = Schema::hasTable('gymies_users') && Schema::hasTable('gymies_personal_access_tokens')
            ? ['gymies_personal_access_tokens', 'personal_access_tokens']
            : ['personal_access_tokens', 'gymies_personal_access_tokens'];
        foreach ($tables as $table) {
            if (!Schema::hasTable($table)) {
                continue;
            }
            $row = DB::table($table)->where('token', $hashedToken)->first();
            if ($row !== null) {
                return $row;
            }
        }
        return null;
    }

    /**
     * Zoek sessie in gymies_sessions (64-hex token, gebruikt door website-login).
     * Ondersteunt token en access_token kolommen.
     */
    private function findSessionInGymiesSessions(string $fullToken, string $plainToken): ?object
    {
        $tokensToTry = [$fullToken, $plainToken];
        if ($fullToken !== $plainToken) {
            $tokensToTry = array_unique($tokensToTry);
        }
        foreach (['token', 'access_token'] as $col) {
            if (!Schema::hasColumn('gymies_sessions', $col)) {
                continue;
            }
            foreach ($tokensToTry as $t) {
                $q = DB::table('gymies_sessions')->where($col, $t);
                if (Schema::hasColumn('gymies_sessions', 'expires_at')) {
                    $q->where(function ($sq) {
                        $sq->whereNull('expires_at')->orWhere('expires_at', '>', now());
                    });
                }
                $row = $q->first();
                if ($row !== null) {
                    return $row;
                }
            }
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
            if (!Schema::hasTable($table) || !Schema::hasColumn($table, 'api_token')) {
                continue;
            }
            foreach ($tokensToTry as $t) {
                $row = DB::table($table)->where('api_token', $t)->first();
                if ($row !== null) {
                    return $row;
                }
            }
        }
        return null;
    }
}
