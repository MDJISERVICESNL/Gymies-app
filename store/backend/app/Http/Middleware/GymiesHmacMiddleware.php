<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;

/**
 * HMAC Request Signing Middleware voor Gymies API.
 *
 * Valideert dat elk request afkomstig is van de officiële Gymies app
 * en niet is gemanipuleerd (request tampering / replay attack preventie).
 *
 * De Flutter app stuurt bij elk request drie headers mee:
 *   X-Gymies-Timestamp:  Unix timestamp (seconden)
 *   X-Gymies-Signature:  HMAC-SHA256 hex digest
 *   X-Gymies-Body-Hash:  SHA-256 hex digest van de request body
 *
 * Signature payload: "{timestamp}:{METHOD}:{path}:{bodyHash}"
 *
 * Beveiliging:
 * 1. Timestamp mag max 5 minuten oud zijn (replay attack preventie)
 * 2. Signature moet exact overeenkomen (constant-time comparison)
 * 3. Body hash moet kloppen met daadwerkelijke request body
 * 4. Zonder geldige signature: 403 Forbidden
 *
 * Config: GYMIES_HMAC_SECRET in .env (moet hetzelfde zijn als Flutter --dart-define)
 */
class GymiesHmacMiddleware
{
    /**
     * Maximum leeftijd van een request in seconden (5 minuten).
     * Voorkomt replay attacks: gestolen requests kunnen niet later opnieuw
     * worden afgespeeld.
     */
    private const MAX_AGE_SECONDS = 300;

    /**
     * HMAC secret moet via GYMIES_HMAC_SECRET in .env geconfigureerd worden.
     * Zonder secret worden requests doorgelaten met een warning in productie.
     */

    /**
     * Routes die GEEN HMAC validatie krijgen (externe callbacks, webhooks, cron).
     * Mollie stuurt webhooks naar deze endpoints — die hebben geen HMAC headers.
     */
    private const EXCLUDED_PATHS = [
        'api/gymies/webhooks/',           // Mollie payment + subscription webhooks
        'api/gymies/onboarding/mollie',   // Mollie Connect OAuth callback
        'api/gymies/cron/',               // Cron endpoints (server → server)
    ];

    public function handle(Request $request, Closure $next): Response
    {
        // Skip HMAC voor externe callbacks (Mollie webhooks, cron, etc.)
        $path = $request->path();
        foreach (self::EXCLUDED_PATHS as $excluded) {
            if (str_starts_with($path, $excluded)) {
                return $next($request);
            }
        }

        $secret = $this->getHmacSecret();

        // Geen secret geconfigureerd: laat request door maar log warning
        if ($secret === '') {
            if (app()->environment('production')) {
                Log::channel('single')->warning('[HMAC] CRITICAL: Geen productie HMAC secret geconfigureerd!', [
                    'path' => $request->path(),
                    'ip' => $request->ip(),
                ]);
            }
            return $next($request);
        }

        // ── Enforce mode ────────────────────────────────────────────
        // GYMIES_HMAC_ENFORCE=false → log-only (dev), true → blokkeer (productie)
        $enforce = config('gymies.hmac_enforce', true);

        // ── Headers ophalen ──────────────────────────────────────────
        $timestamp = $request->header('X-Gymies-Timestamp');
        $signature = $request->header('X-Gymies-Signature');
        $bodyHash  = $request->header('X-Gymies-Body-Hash');

        // Alle drie headers zijn verplicht
        if ($timestamp === null || $signature === null || $bodyHash === null) {
            Log::channel('single')->info('[HMAC] Ontbrekende HMAC headers', [
                'path' => $request->path(),
                'ip' => $request->ip(),
                'enforce' => $enforce,
                'has_timestamp' => $timestamp !== null,
                'has_signature' => $signature !== null,
                'has_body_hash' => $bodyHash !== null,
            ]);
            if (!$enforce) {
                return $next($request); // Log-only: laat door
            }
            return response()->json([
                'message' => 'Ongeldige request — HMAC headers ontbreken.',
            ], 403);
        }

        // ── Timestamp validatie (replay attack preventie) ───────────
        $now = time();
        $requestTime = (int) $timestamp;
        $age = abs($now - $requestTime);

        if ($age > self::MAX_AGE_SECONDS) {
            Log::channel('single')->warning('[HMAC 403] Timestamp te oud', [
                'path' => $request->path(),
                'ip' => $request->ip(),
                'request_time' => $requestTime,
                'server_time' => $now,
                'age_seconds' => $age,
                'max_age' => self::MAX_AGE_SECONDS,
            ]);
            return response()->json([
                'message' => 'Request verlopen — probeer opnieuw.',
            ], 403);
        }

        // ── Body hash validatie ─────────────────────────────────────
        $rawBody = $request->getContent();
        $expectedBodyHash = hash('sha256', $rawBody !== '' ? $rawBody : '');

        if (!hash_equals($expectedBodyHash, $bodyHash)) {
            Log::channel('single')->warning('[HMAC 403] Body hash mismatch', [
                'path' => $request->path(),
                'ip' => $request->ip(),
                'expected_hash_prefix' => substr($expectedBodyHash, 0, 16),
                'received_hash_prefix' => substr($bodyHash, 0, 16),
                'body_length' => strlen($rawBody),
            ]);
            return response()->json([
                'message' => 'Ongeldige request — body integriteit mislukt.',
            ], 403);
        }

        // ── Signature validatie ─────────────────────────────────────
        // Path: relatief API pad zonder leading slash
        // De Flutter app signed het pad relatief aan de base URL (/api/gymies/...)
        $path = $this->extractApiPath($request);
        $method = strtoupper($request->method());

        $payload = "{$timestamp}:{$method}:{$path}:{$bodyHash}";
        $expectedSignature = hash_hmac('sha256', $payload, $secret);

        if (!hash_equals($expectedSignature, $signature)) {
            Log::channel('single')->warning('[HMAC 403] Signature mismatch', [
                'path' => $request->path(),
                'api_path' => $path,
                'method' => $method,
                'ip' => $request->ip(),
                'payload_preview' => substr($payload, 0, 80),
                'expected_sig_prefix' => substr($expectedSignature, 0, 16),
                'received_sig_prefix' => substr($signature, 0, 16),
            ]);
            return response()->json([
                'message' => 'Ongeldige request — authenticatie mislukt.',
            ], 403);
        }

        return $next($request);
    }

    /**
     * Haal het HMAC secret op via config (→ .env).
     */
    private function getHmacSecret(): string
    {
        // Primair: config/gymies.php
        $key = config('gymies.hmac_secret');
        if (is_string($key) && $key !== '') {
            return $key;
        }

        // Fallback: direct env (voor servers zonder config:cache)
        $key = env('GYMIES_HMAC_SECRET', '');
        return is_string($key) ? $key : '';
    }

    /**
     * Extraheer het relatieve API pad dat de Flutter app heeft gesigned.
     *
     * De Flutter ApiClient signed het pad relatief aan de base URL.
     * Bijv: bij URL https://gymies.nl/api/gymies/trainer/revenue
     * signed Flutter: "trainer/revenue"
     *
     * We moeten het exacte pad reconstrueren zodat de signature klopt.
     */
    private function extractApiPath(Request $request): string
    {
        $fullPath = $request->path(); // bijv. "api/gymies/trainer/revenue"

        // Strip "api/gymies/" prefix — dat is de base URL die Flutter al kent
        $prefix = 'api/gymies/';
        if (str_starts_with($fullPath, $prefix)) {
            return substr($fullPath, strlen($prefix));
        }

        // Fallback: als de route anders is gemount
        return $fullPath;
    }
}
