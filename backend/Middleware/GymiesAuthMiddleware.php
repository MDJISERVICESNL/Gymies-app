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
 * Valideert Bearer token tegen gymies_sessions en zet user op de request.
 * Registreer in bootstrap/app.php of Kernel als 'gymies.auth'.
 */
final class GymiesAuthMiddleware
{
    private const SESSION_TTL_DAYS = 14;

    /** 401-diagnose: header X-Gymies-Auth-Fail geeft reden (DevTools → Network → Response Headers). */
    private function unauthorized(string $reason, int $status = 401, ?Request $request = null): Response
    {
        if ($request) {
            Log::channel('single')->warning('GymiesAuth 401', [
                'reason' => $reason,
                'path' => $request->path(),
                'has_auth_header' => $request->hasHeader('Authorization'),
                'has_x_token' => $request->hasHeader('X-Gymies-Token'),
            ]);
        }
        $body = ['message' => 'Unauthorized', 'auth_fail' => $reason];
        return response()->json($body, $status)
            ->header('X-Gymies-Auth-Fail', $reason);
    }

    public function handle(Request $request, Closure $next): Response
    {
        $token = $this->extractToken($request);
        if ($token === null || $token === '') {
            return $this->unauthorized('no_token', 401, $request);
        }

        $token = trim($token);
        // Normalize: alleen hex, max 64 chars (Flutter web/SharedPreferences kan \r\n, BOM, spaties toevoegen)
        $hexOnly = preg_replace('/[^a-fA-F0-9]/', '', $token);
        if (strlen($hexOnly) >= 64) {
            $token = substr($hexOnly, 0, 64);
        }
        $session = DB::table('gymies_sessions')
            ->where('token', $token)
            ->when(
                Schema::hasColumn('gymies_sessions', 'revoked_at'),
                fn ($q) => $q->whereNull('revoked_at')
            )
            ->first();

        if (!$session) {
            return $this->unauthorized('session_not_found', 401, $request);
        }

        $expiresAt = $session->expires_at ? \Carbon\Carbon::parse($session->expires_at) : null;
        if ($expiresAt && $expiresAt <= now()) {
            return $this->unauthorized('session_expired', 401, $request);
        }

        $user = DB::table('gymies_users')->where('id', $session->user_id)->first();
        if (!$user) {
            return $this->unauthorized('user_not_found', 401, $request);
        }
        if ($this->isUserSuspended($user)) {
            return response()->json(['message' => 'Account is tijdelijk geblokkeerd.'], 403);
        }
        if ($this->hasSuspiciousSessionFingerprint($request, $session)) {
            return $this->unauthorized('user_agent_mismatch', 401, $request);
        }

        // Sliding session window: actieve gebruikers blijven ingelogd.
        DB::table('gymies_sessions')
            ->where('id', $session->id)
            ->update(['expires_at' => now()->addDays(self::SESSION_TTL_DAYS)]);

        $request->attributes->set('gymies_session', $session);
        $request->attributes->set('gymies_token', $token);
        $request->attributes->set('gymies_user', $user);
        return $next($request);
    }

    /** Haalt Bearer token uit Authorization, X-Authorization of X-Gymies-Token. */
    private function extractToken(Request $request): ?string
    {
        $raw = $request->bearerToken();
        if ($raw !== null && $raw !== '') {
            return $raw;
        }
        $h = $request->header('X-Authorization');
        if (is_string($h) && str_starts_with($h, 'Bearer ')) {
            return trim(substr($h, 7));
        }
        $h = $request->header('X-Gymies-Token');
        if (is_string($h) && $h !== '') {
            return trim($h);
        }
        return null;
    }

    private function isUserSuspended(object $user): bool
    {
        if (Schema::hasColumn('gymies_users', 'is_suspended') && (int) ($user->is_suspended ?? 0) === 1) {
            return true;
        }
        if (Schema::hasColumn('gymies_users', 'suspended_at') && !empty($user->suspended_at)) {
            return true;
        }
        if (Schema::hasColumn('gymies_users', 'deleted_at') && !empty($user->deleted_at)) {
            return true;
        }
        return false;
    }

    private function hasSuspiciousSessionFingerprint(Request $request, object $session): bool
    {
        if (filter_var(config('gymies.session_skip_ua_check', false), FILTER_VALIDATE_BOOLEAN)) {
            return false; // Optioneel uitschakelen bij Flutter web / proxy waar UA kan verschillen
        }
        if (Schema::hasColumn('gymies_sessions', 'user_agent')) {
            $stored = mb_substr((string) ($session->user_agent ?? ''), 0, 255);
            $current = mb_substr((string) ($request->userAgent() ?? ''), 0, 255);
            if ($stored === '' || $current === '') {
                return false;
            }
            // Vergelijk platform-prefix in plaats van exact match.
            // "Dart/3.2 (dart:io)" vs "Dart/3.3 (dart:io)" → zelfde device, andere versie = OK.
            // "Dart/3.2 (dart:io)" vs "Mozilla/5.0 ..." → ander platform = verdacht.
            $storedPlatform = $this->extractUserAgentPlatform($stored);
            $currentPlatform = $this->extractUserAgentPlatform($current);
            if ($storedPlatform !== '' && $currentPlatform !== '' && $storedPlatform !== $currentPlatform) {
                return true;
            }
        }

        return false;
    }

    /**
     * Extraheer platform-identifier uit user agent.
     * "Dart/3.2 (dart:io)" → "Dart", "Mozilla/5.0 ..." → "Mozilla", "okhttp/4.x" → "okhttp"
     */
    private function extractUserAgentPlatform(string $ua): string
    {
        $ua = trim($ua);
        if ($ua === '') {
            return '';
        }
        // Neem alles tot de eerste '/' of spatie als platformnaam
        if (preg_match('/^([a-zA-Z]+)/', $ua, $m)) {
            return strtolower($m[1]);
        }
        return '';
    }
}
