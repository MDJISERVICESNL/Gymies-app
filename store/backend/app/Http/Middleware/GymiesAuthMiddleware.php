<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\Response;

/**
 * Sessietoken-authenticatie voor Gymies API.
 *
 * Tokenbron: gymies_sessions (kolom token)
 * Formaat: 64 hex karakters (bin2hex(random_bytes(32)))
 *
 * Token wordt gelezen (in volgorde):
 * 1. access_token in query (fallback als Nginx/proxy Authorization header strippen)
 * 2. Authorization: Bearer <token> – via $request->bearerToken()
 * 3. X-Authorization: Bearer <token>
 * 4. X-Gymies-Token: <token>
 *
 * Token wordt genormaliseerd: alleen hex, max 64 tekens.
 * Bij gevonden sessie: gymies_user wordt op de request gezet.
 */
class GymiesAuthMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user() !== null) {
            return $next($request);
        }

        $rawToken = $this->getToken($request);
        if ($rawToken === null || $rawToken === '') {
            Log::channel('single')->info('[GymiesAuth 401] Geen token', [
                'path' => $request->path(),
                'has_auth_header' => $request->hasHeader('Authorization'),
                'has_x_auth' => $request->hasHeader('X-Authorization'),
                'has_x_gymies_token' => $request->hasHeader('X-Gymies-Token'),
                'has_access_token_query' => $request->filled('access_token'),
            ]);
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $token = $this->normalizeToken($rawToken);
        if ($token === null) {
            $hexOnly = preg_replace('/[^a-fA-F0-9]/', '', $rawToken);
            Log::channel('single')->warning('[GymiesAuth 401] Ongeldig token-formaat', [
                'path' => $request->path(),
                'raw_length' => strlen($rawToken),
                'hex_only_length' => strlen($hexOnly),
                'raw_preview' => strlen($rawToken) > 8 ? substr($rawToken, 0, 4) . '...' . substr($rawToken, -4) : '***',
                'expects' => '64 hex',
            ]);
            return response()->json(['message' => 'Ongeldige of verlopen sessie. Log opnieuw in.'], 401);
        }

        $user = $this->resolveUserFromSessionToken($token);
        if ($user === null) {
            Log::channel('single')->warning('[GymiesAuth 401] Token niet gevonden in gymies_sessions', [
                'path' => $request->path(),
                'token_length' => strlen($token),
                'token_preview' => substr($token, 0, 4) . '...' . substr($token, -4),
            ]);
            return response()->json(['message' => 'Ongeldige of verlopen sessie. Log opnieuw in.'], 401);
        }

        $request->setUserResolver(fn () => $user);
        return $next($request);
    }

    private function getToken(Request $request): ?string
    {
        // 0. access_token in query (fallback als Nginx/proxy Authorization header strippen)
        if ($request->filled('access_token')) {
            $t = trim((string) $request->input('access_token'));
            if ($t !== '') {
                return $t;
            }
        }

        // 1. Authorization: Bearer <token>
        $h = $request->bearerToken();
        if ($h !== null && $h !== '') {
            return trim($h);
        }
        $h = $request->header('Authorization') ?? $request->server('HTTP_AUTHORIZATION');
        if (is_string($h) && str_starts_with($h, 'Bearer ')) {
            return trim(substr($h, 7));
        }

        // 2. X-Authorization: Bearer <token>
        $h = $request->header('X-Authorization');
        if (is_string($h) && str_starts_with($h, 'Bearer ')) {
            return trim(substr($h, 7));
        }

        // 3. X-Gymies-Token: <token>
        $h = $request->header('X-Gymies-Token');
        if (is_string($h) && $h !== '') {
            return trim($h);
        }

        return null;
    }

    /**
     * Normaliseer token: alleen hex, max 64 tekens.
     */
    private function normalizeToken(string $raw): ?string
    {
        $t = preg_replace('/[^a-fA-F0-9]/', '', $raw);
        if ($t === '' || strlen($t) > 64) {
            return null;
        }
        return strlen($t) === 64 ? $t : null;
    }

    private function resolveUserFromSessionToken(string $token): ?\Illuminate\Contracts\Auth\Authenticatable
    {
        if (!Schema::hasTable('gymies_sessions') || !Schema::hasColumn('gymies_sessions', 'token')) {
            return null;
        }

        $query = DB::table('gymies_sessions')->where('token', $token);
        if (Schema::hasColumn('gymies_sessions', 'expires_at')) {
            $query->where(function ($q) {
                $q->whereNull('expires_at')->orWhere('expires_at', '>', now());
            });
        }
        if (Schema::hasColumn('gymies_sessions', 'revoked_at')) {
            $query->whereNull('revoked_at');
        }
        $row = $query->first();
        if ($row === null || !isset($row->user_id)) {
            return null;
        }

        // last_activity updaten (optioneel)
        try {
            DB::table('gymies_sessions')->where('token', $token)->update(['last_activity' => now()]);
        } catch (\Throwable $e) {
            // negeer
        }

        return $this->userFromId((int) $row->user_id);
    }

    private function userFromId(int $userId): ?\Illuminate\Contracts\Auth\Authenticatable
    {
        $usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
        $row = DB::table($usersTable)->where('id', $userId)->first();
        if ($row === null) {
            return null;
        }
        return new \Illuminate\Auth\GenericUser((array) $row);
    }
}
