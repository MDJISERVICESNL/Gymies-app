<?php

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * GymiesCyberAuthController
 *
 * Beheert de geïsoleerde cyber-sessies los van de normale Sanctum auth.
 *
 * Endpoints (vereisen normale Bearer auth):
 *   POST   /api/gymies/cyber/auth            → PIN verifiëren + cyber token uitgeven
 *   POST   /api/gymies/cyber/auth/setup-pin  → PIN instellen / wijzigen
 *   DELETE /api/gymies/cyber/auth            → Huidige cyber sessie intrekken (logout)
 *   GET    /api/gymies/cyber/auth/status     → Check of huidige cyber sessie actief is
 *
 * Beveiligingslaag:
 *   • PIN wordt als bcrypt hash opgeslagen in gymies_users.cyber_pin_hash
 *   • Max 5 PIN-pogingen per IP per 15 min (gymies_cyber_pin_lockouts)
 *   • Cyber token = 32 random bytes → hex (64 chars), TTL = 30 minuten
 *   • Token zelf wordt NOOIT opgeslagen — alleen SHA-256 hash in DB
 *   • Alle cyber login/logout/acties worden gelogd in gymies_cyber_audit_log
 */
class GymiesCyberAuthController
{
    private const TOKEN_TTL_MINUTES   = 30;
    private const MAX_PIN_ATTEMPTS    = 5;
    private const LOCKOUT_MINUTES     = 15;
    private const PIN_LENGTH          = 6;

    // ─────────────────────────────────────────────────────────────────────────
    // POST /cyber/auth  — PIN verifiëren + cyber token uitgeven
    // ─────────────────────────────────────────────────────────────────────────
    public function login(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        // is_cyber of is_admin check
        $isCyber = ((int)($user->is_cyber ?? 0)) === 1;
        $isAdmin = ((int)($user->is_admin ?? 0)) === 1;
        if (!$isCyber && !$isAdmin) {
            return response()->json(['message' => 'Geen cyber toegang.'], 403);
        }

        $ip = $request->ip() ?? '0.0.0.0';

        // ── Lockout check ────────────────────────────────────────────────────
        $lockout = DB::table('gymies_cyber_pin_lockouts')
            ->where('user_id', $user->id)
            ->where('ip_address', $ip)
            ->first();

        if ($lockout && $lockout->locked_until && now()->lt($lockout->locked_until)) {
            $remaining = now()->diffInMinutes($lockout->locked_until) + 1;
            $this->auditLog($user->id, null, 'cyber.login.blocked', '/cyber/auth', 'POST', $ip, 429);
            return response()->json([
                'message'          => "Te veel pogingen. Probeer over {$remaining} minuten opnieuw.",
                'locked_until'     => $lockout->locked_until,
                'remaining_minutes'=> $remaining,
            ], 429);
        }

        // T-055 FIXED: globale (user-based) rate limit toegevoegd naast IP-based
        // BUG-013: Add transaction wrapping to prevent race condition on rate limit check
        try {
            return DB::transaction(function () use ($user, $ip, $lockout, $request) {
                $globalKey = 'cyber_pin_global:' . (int)$user->id;
                $globalWindowStart = now()->subMinutes(15);
                $globalAttempts = DB::table('gymies_rate_limits')
                    ->where('key', $globalKey)
                    ->where('window_start', '>=', $globalWindowStart)
                    ->count();
                if ($globalAttempts >= 10) {
                    return response()->json([
                        'message' => 'Te veel PIN pogingen. Account tijdelijk geblokkeerd.',
                        'retry_after' => 15 * 60,
                    ], 429);
                }
                // Log ook de globale poging
                DB::table('gymies_rate_limits')->insert([
                    'key' => $globalKey,
                    'window_start' => now(),
                    'created_at' => now(),
                ]);

                // Continue with PIN validation (rest of login logic)
                $pin = (string)($request->input('pin') ?? '');
                if (strlen($pin) !== self::PIN_LENGTH || !ctype_digit($pin)) {
                    return response()->json(['message' => 'PIN moet precies ' . self::PIN_LENGTH . ' cijfers zijn.'], 422);
                }

                $pinHash = DB::table('gymies_users')
                    ->where('id', $user->id)
                    ->value('cyber_pin_hash');

                if (!$pinHash || !Hash::check($pin, $pinHash)) {
                    // Mislukte poging registreren
                    $attempts = ($lockout->attempts ?? 0) + 1;
                    $lockedUntil = $attempts >= self::MAX_PIN_ATTEMPTS
                        ? now()->addMinutes(self::LOCKOUT_MINUTES)->toDateTimeString()
                        : null;

                    DB::table('gymies_cyber_pin_lockouts')->updateOrInsert(
                        ['user_id' => $user->id, 'ip_address' => $ip],
                        ['attempts' => $attempts, 'locked_until' => $lockedUntil, 'last_attempt' => now()]
                    );

                    $this->auditLog($user->id, null, 'cyber.login.failed', '/cyber/auth', 'POST', $ip, 401);

                    $remaining = max(0, self::MAX_PIN_ATTEMPTS - $attempts);
                    return response()->json([
                        'message'           => !$pinHash
                            ? 'Geen PIN ingesteld. Stel eerst een PIN in.'
                            : "Onjuiste PIN. Nog {$remaining} poging" . ($remaining !== 1 ? 'en' : '') . " over.",
                        'attempts_remaining'=> $remaining,
                        'pin_not_set'       => !$pinHash,
                    ], 401);
                }

                // Succesvolle login → reset lockout
                DB::table('gymies_cyber_pin_lockouts')
                    ->where('user_id', $user->id)
                    ->where('ip_address', $ip)
                    ->delete();

                // ── Cyber token genereren ────────────────────────────────────────────
                $rawToken  = bin2hex(random_bytes(32));        // 64 hex chars
                $tokenHash = hash('sha256', $rawToken);
                $expiresAt = now()->addMinutes(self::TOKEN_TTL_MINUTES);

                // Oude sessies van dezelfde user + IP intrekken (1 actieve sessie per user/IP)
                DB::table('gymies_cyber_sessions')
                    ->where('user_id', $user->id)
                    ->where('ip_address', $ip)
                    ->update(['revoked' => 1]);

                $sessionId = DB::table('gymies_cyber_sessions')->insertGetId([
                    'user_id'     => $user->id,
                    'token_hash'  => $tokenHash,
                    'ip_address'  => $ip,
                    'user_agent'  => substr($request->userAgent() ?? '', 0, 500),
                    'last_active' => now(),
                    'expires_at'  => $expiresAt,
                    'revoked'     => 0,
                    'created_at'  => now(),
                ]);

                $this->auditLog($user->id, $sessionId, 'cyber.login.success', '/cyber/auth', 'POST', $ip, 200);

                Log::info('[Cyber] Sessie aangemaakt', [
                    'user_id'    => $user->id,
                    'session_id' => $sessionId,
                    'ip'         => $ip,
                    'expires_at' => $expiresAt,
                ]);

                // S-008: Voorkom dat proxy's/browsers de token cachen door gevoelige headers.
                return response()->json([
                    'cyber_token' => $rawToken,
                    'expires_at'  => $expiresAt->toIso8601String(),
                    'expires_in'  => self::TOKEN_TTL_MINUTES * 60, // seconden
                    'session_id'  => $sessionId,
                ])->withHeaders([
                    'Cache-Control' => 'no-store, no-cache, must-revalidate',
                    'Pragma'        => 'no-cache',
                ]);
            });
        } catch (\Throwable $e) {
            Log::error('[Cyber] Login transaction failed', ['error' => $e->getMessage()]);
            return response()->json(['message' => 'Er is een fout opgetreden. Probeer opnieuw.'], 500);
        }

        // ── PIN valideren ────────────────────────────────────────────────────
        $pin = (string)($request->input('pin') ?? '');
        if (strlen($pin) !== self::PIN_LENGTH || !ctype_digit($pin)) {
            return response()->json(['message' => 'PIN moet precies ' . self::PIN_LENGTH . ' cijfers zijn.'], 422);
        }

        $pinHash = DB::table('gymies_users')
            ->where('id', $user->id)
            ->value('cyber_pin_hash');

        if (!$pinHash || !Hash::check($pin, $pinHash)) {
            // Mislukte poging registreren
            $attempts = ($lockout->attempts ?? 0) + 1;
            $lockedUntil = $attempts >= self::MAX_PIN_ATTEMPTS
                ? now()->addMinutes(self::LOCKOUT_MINUTES)->toDateTimeString()
                : null;

            DB::table('gymies_cyber_pin_lockouts')->updateOrInsert(
                ['user_id' => $user->id, 'ip_address' => $ip],
                ['attempts' => $attempts, 'locked_until' => $lockedUntil, 'last_attempt' => now()]
            );

            $this->auditLog($user->id, null, 'cyber.login.failed', '/cyber/auth', 'POST', $ip, 401);

            $remaining = max(0, self::MAX_PIN_ATTEMPTS - $attempts);
            return response()->json([
                'message'           => !$pinHash
                    ? 'Geen PIN ingesteld. Stel eerst een PIN in.'
                    : "Onjuiste PIN. Nog {$remaining} poging" . ($remaining !== 1 ? 'en' : '') . " over.",
                'attempts_remaining'=> $remaining,
                'pin_not_set'       => !$pinHash,
            ], 401);
        }

        // Succesvolle login → reset lockout
        DB::table('gymies_cyber_pin_lockouts')
            ->where('user_id', $user->id)
            ->where('ip_address', $ip)
            ->delete();

        // ── Cyber token genereren ────────────────────────────────────────────
        $rawToken  = bin2hex(random_bytes(32));        // 64 hex chars
        $tokenHash = hash('sha256', $rawToken);
        $expiresAt = now()->addMinutes(self::TOKEN_TTL_MINUTES);

        // Oude sessies van dezelfde user + IP intrekken (1 actieve sessie per user/IP)
        DB::table('gymies_cyber_sessions')
            ->where('user_id', $user->id)
            ->where('ip_address', $ip)
            ->update(['revoked' => 1]);

        $sessionId = DB::table('gymies_cyber_sessions')->insertGetId([
            'user_id'     => $user->id,
            'token_hash'  => $tokenHash,
            'ip_address'  => $ip,
            'user_agent'  => substr($request->userAgent() ?? '', 0, 500),
            'last_active' => now(),
            'expires_at'  => $expiresAt,
            'revoked'     => 0,
            'created_at'  => now(),
        ]);

        $this->auditLog($user->id, $sessionId, 'cyber.login.success', '/cyber/auth', 'POST', $ip, 200);

        Log::info('[Cyber] Sessie aangemaakt', [
            'user_id'    => $user->id,
            'session_id' => $sessionId,
            'ip'         => $ip,
            'expires_at' => $expiresAt,
        ]);

        // S-008: Voorkom dat proxy's/browsers de token cachen door gevoelige headers.
        return response()->json([
            'cyber_token' => $rawToken,
            'expires_at'  => $expiresAt->toIso8601String(),
            'expires_in'  => self::TOKEN_TTL_MINUTES * 60, // seconden
            'session_id'  => $sessionId,
        ])->withHeaders([
            'Cache-Control' => 'no-store, no-cache, must-revalidate',
            'Pragma'        => 'no-cache',
        ]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /cyber/auth/setup-pin  — PIN instellen of wijzigen
    // ─────────────────────────────────────────────────────────────────────────
    public function setupPin(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $isCyber = ((int)($user->is_cyber ?? 0)) === 1;
        $isAdmin = ((int)($user->is_admin ?? 0)) === 1;
        if (!$isCyber && !$isAdmin) {
            return response()->json(['message' => 'Geen cyber toegang.'], 403);
        }

        // T-059 FIXED: rate limiting op PIN setup
        $setupKey = 'cyber_pin_setup:' . (int)$user->id;
        $windowStart = now()->subMinutes(15);
        $attempts = DB::table('gymies_rate_limits')
            ->where('key', $setupKey)
            ->where('window_start', '>=', $windowStart)
            ->count();
        if ($attempts >= 5) {
            return response()->json(['message' => 'Te veel PIN setup pogingen.'], 429);
        }
        DB::table('gymies_rate_limits')->insert([
            'key' => $setupKey,
            'window_start' => now(),
            'created_at' => now(),
        ]);

        $pin = (string)($request->input('pin') ?? '');
        $confirm = (string)($request->input('pin_confirmation') ?? '');

        if (strlen($pin) !== self::PIN_LENGTH || !ctype_digit($pin)) {
            return response()->json(['message' => 'PIN moet precies ' . self::PIN_LENGTH . ' cijfers zijn.'], 422);
        }
        if ($pin !== $confirm) {
            return response()->json(['message' => 'PIN en bevestiging komen niet overeen.'], 422);
        }

        DB::table('gymies_users')
            ->where('id', $user->id)
            ->update([
                'cyber_pin_hash'   => Hash::make($pin),
                'cyber_pin_set_at' => now(),
            ]);

        $ip = $request->ip() ?? '0.0.0.0';
        $this->auditLog($user->id, null, 'cyber.pin.setup', '/cyber/auth/setup-pin', 'POST', $ip, 200);

        return response()->json(['message' => 'PIN succesvol ingesteld.']);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DELETE /cyber/auth  — Huidige cyber sessie intrekken
    // ─────────────────────────────────────────────────────────────────────────
    public function logout(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $cyberToken = $request->header('X-Cyber-Token');
        $ip         = $request->ip() ?? '0.0.0.0';

        if ($cyberToken) {
            $tokenHash = hash('sha256', $cyberToken);
            DB::table('gymies_cyber_sessions')
                ->where('token_hash', $tokenHash)
                ->where('user_id', $user->id)
                ->update(['revoked' => 1]);
        } else {
            // Geen specifieke token → alle actieve sessies van deze user intrekken
            DB::table('gymies_cyber_sessions')
                ->where('user_id', $user->id)
                ->where('revoked', 0)
                ->update(['revoked' => 1]);
        }

        $this->auditLog($user->id, null, 'cyber.logout', '/cyber/auth', 'DELETE', $ip, 200);

        return response()->json(['message' => 'Cyber sessie beëindigd.']);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET /cyber/auth/status  — Check of cyber sessie actief is
    // ─────────────────────────────────────────────────────────────────────────
    public function status(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['active' => false, 'reason' => 'not_authenticated'], 401);
        }

        $cyberToken = $request->header('X-Cyber-Token');
        if (!$cyberToken) {
            return response()->json([
                'active'       => false,
                'reason'       => 'no_cyber_token',
                'pin_set'      => !empty(DB::table('gymies_users')->where('id', $user->id)->value('cyber_pin_hash')),
            ]);
        }

        $tokenHash = hash('sha256', $cyberToken);
        $session   = DB::table('gymies_cyber_sessions')
            ->where('user_id', $user->id)
            ->where('revoked', 0)
            ->where('expires_at', '>', now())
            ->first();

        // T-056 FIXED: timing-safe token vergelijking
        if (!$session || !hash_equals((string)$session->token_hash, (string)$tokenHash)) {
            return response()->json([
                'active' => false,
                'reason' => 'session_invalid_or_expired',
            ]);
        }

        return response()->json([
            'active'      => true,
            'expires_at'  => $session->expires_at,
            'session_id'  => $session->id,
        ]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper: audit log schrijven
    // ─────────────────────────────────────────────────────────────────────────
    private function auditLog(
        int     $userId,
        ?int    $sessionId,
        string  $action,
        string  $endpoint,
        string  $method,
        string  $ip,
        int     $statusCode,
        ?array  $details = null
    ): void {
        try {
            DB::table('gymies_cyber_audit_log')->insert([
                'user_id'    => $userId,
                'session_id' => $sessionId,
                'action'     => $action,
                'endpoint'   => $endpoint,
                'method'     => $method,
                'ip_address' => $ip,
                'status_code'=> $statusCode,
                'details'    => $details ? json_encode($details) : null,
                'created_at' => now(),
            ]);
        } catch (\Throwable $e) {
            Log::warning('[Cyber] Audit log mislukt: ' . $e->getMessage());
        }
    }
}
