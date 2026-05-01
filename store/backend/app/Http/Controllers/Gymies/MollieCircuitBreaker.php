<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

/**
 * MollieCircuitBreaker
 * ────────────────────
 * Voorkomt dat de app herhaaldelijk probeert Mollie te bereiken
 * als de API down is. Na te veel failures gaat de circuit "open"
 * en falen requests direct (fast fail) in plaats van 15s te wachten.
 *
 * States:
 *   CLOSED  → Alles normaal, requests gaan door
 *   OPEN    → Te veel failures, requests worden direct afgewezen
 *   HALF    → Na cooldown, laat 1 request door om te testen
 *
 * Gebruik:
 *   $cb = new MollieCircuitBreaker();
 *   if (!$cb->isAvailable()) {
 *       return response()->json(['message' => 'Betaaldienst tijdelijk niet beschikbaar'], 503);
 *   }
 *   try {
 *       $result = Http::post('https://api.mollie.com/...');
 *       $cb->recordSuccess();
 *   } catch (\Throwable $e) {
 *       $cb->recordFailure();
 *       throw $e;
 *   }
 */
final class MollieCircuitBreaker
{
    private const CACHE_KEY_FAILURES   = 'mollie_cb_failures';
    private const CACHE_KEY_OPENED_AT  = 'mollie_cb_opened_at';
    private const CACHE_KEY_HALF_OPEN  = 'mollie_cb_half_open';

    /** Maximaal aantal failures voordat circuit opent. */
    private const MAX_FAILURES = 5;

    /** TTL voor het failures window (seconden). */
    private const WINDOW_TTL = 300; // 5 minuten

    /** Hoe lang de circuit open blijft voordat half-open (seconden). */
    private const COOLDOWN = 60; // 1 minuut

    /**
     * Is Mollie beschikbaar?
     * Returns false als de circuit open is (te veel failures).
     */
    public function isAvailable(): bool
    {
        $failures = (int) Cache::get(self::CACHE_KEY_FAILURES, 0);

        // CLOSED — alles OK
        if ($failures < self::MAX_FAILURES) {
            return true;
        }

        // OPEN — check of cooldown verlopen is
        $openedAt = Cache::get(self::CACHE_KEY_OPENED_AT);
        if ($openedAt !== null) {
            $elapsed = time() - (int) $openedAt;
            if ($elapsed >= self::COOLDOWN) {
                // HALF-OPEN — laat 1 request door
                if (!Cache::get(self::CACHE_KEY_HALF_OPEN)) {
                    Cache::put(self::CACHE_KEY_HALF_OPEN, true, self::COOLDOWN);
                    Log::info('[CircuitBreaker] Mollie circuit HALF-OPEN — test request toegestaan');
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * Registreer een succesvolle Mollie call.
     * Reset de circuit naar CLOSED.
     */
    public function recordSuccess(): void
    {
        $wasOpen = (int) Cache::get(self::CACHE_KEY_FAILURES, 0) >= self::MAX_FAILURES;

        Cache::forget(self::CACHE_KEY_FAILURES);
        Cache::forget(self::CACHE_KEY_OPENED_AT);
        Cache::forget(self::CACHE_KEY_HALF_OPEN);

        if ($wasOpen) {
            Log::info('[CircuitBreaker] Mollie circuit CLOSED — service hersteld');
        }
    }

    /**
     * Registreer een gefaalde Mollie call.
     * Na MAX_FAILURES gaat de circuit open.
     */
    public function recordFailure(): void
    {
        $failures = (int) Cache::increment(self::CACHE_KEY_FAILURES);

        // Zet TTL als dit de eerste failure is
        if ($failures === 1) {
            Cache::put(self::CACHE_KEY_FAILURES, $failures, self::WINDOW_TTL);
        }

        if ($failures >= self::MAX_FAILURES) {
            Cache::put(self::CACHE_KEY_OPENED_AT, time(), self::WINDOW_TTL);
            Cache::forget(self::CACHE_KEY_HALF_OPEN);

            Log::warning('[CircuitBreaker] Mollie circuit OPEN — te veel failures', [
                'failures' => $failures,
                'cooldown' => self::COOLDOWN,
            ]);
        }
    }

    /**
     * Huidige status voor health check / monitoring.
     */
    public function getStatus(): array
    {
        $failures = (int) Cache::get(self::CACHE_KEY_FAILURES, 0);
        $openedAt = Cache::get(self::CACHE_KEY_OPENED_AT);

        $state = 'closed';
        if ($failures >= self::MAX_FAILURES) {
            $state = Cache::get(self::CACHE_KEY_HALF_OPEN) ? 'half-open' : 'open';
        }

        return [
            'state'           => $state,
            'failures'        => $failures,
            'max_failures'    => self::MAX_FAILURES,
            'opened_at'       => $openedAt ? date('c', (int) $openedAt) : null,
            'cooldown_s'      => self::COOLDOWN,
            'window_ttl_s'    => self::WINDOW_TTL,
        ];
    }
}
