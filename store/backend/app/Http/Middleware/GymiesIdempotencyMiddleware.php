<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\Response;

/**
 * V2 Booking Architecture — Idempotency Middleware.
 *
 * Voorkomt dubbele bookings/betalingen bij netwerk-retries of dubbele klikken.
 *
 * Werking:
 * 1. Client stuurt X-Idempotency-Key header (UUID v4) bij POST/PUT requests
 * 2. Middleware checkt of deze key al verwerkt is
 * 3. Zo ja → return cached response (geen dubbele actie)
 * 4. Zo nee → verwerk request, sla response op met key
 *
 * Flutter-side: genereer UUID bij elke booking-poging, hergebruik bij retry.
 *
 * TTL: 24 uur. Cleanup via scheduled artisan command.
 */
class GymiesIdempotencyMiddleware
{
    private const TABLE = 'gymies_idempotency_keys';
    private const TTL_HOURS = 24;
    private const HEADER = 'X-Idempotency-Key';
    private const MAX_KEY_LENGTH = 64;

    public function handle(Request $request, Closure $next): Response
    {
        // Alleen op muterende requests (POST, PUT, PATCH)
        if (!in_array($request->method(), ['POST', 'PUT', 'PATCH'], true)) {
            return $next($request);
        }

        // Geen header → geen idempotency check, request gaat gewoon door
        $key = $request->header(self::HEADER);
        if (!$key || strlen($key) > self::MAX_KEY_LENGTH) {
            return $next($request);
        }

        // Tabel moet bestaan
        if (!Schema::hasTable(self::TABLE)) {
            return $next($request);
        }

        // Sanitize key: alleen alphanumeriek + hyphens (UUID format)
        $key = preg_replace('/[^a-zA-Z0-9\-]/', '', $key);
        if (strlen($key) < 8) {
            return $next($request);
        }

        // Check of key al bestaat en niet verlopen is
        $existing = DB::table(self::TABLE)
            ->where('idempotency_key', $key)
            ->where('expires_at', '>', now())
            ->first();

        if ($existing) {
            // Cached response retourneren
            $body = json_decode($existing->response_body, true) ?? [];
            return response()->json($body, (int) $existing->response_code)
                ->header('X-Idempotency-Replayed', 'true');
        }

        // Verwerk het request
        /** @var Response $response */
        $response = $next($request);

        // Sla response op voor toekomstige retries
        // Alleen JSON responses cachen
        if ($response instanceof \Illuminate\Http\JsonResponse) {
            $userId = 0;
            $user = $request->attributes->get('gymies_user') ?? $request->user();
            if ($user && isset($user->id)) {
                $userId = (int) $user->id;
            }

            try {
                DB::table(self::TABLE)->insert([
                    'idempotency_key' => $key,
                    'user_id' => $userId,
                    'endpoint' => substr($request->path(), 0, 120),
                    'method' => $request->method(),
                    'response_code' => $response->getStatusCode(),
                    'response_body' => $response->getContent(),
                    'created_at' => now(),
                    'expires_at' => now()->addHours(self::TTL_HOURS),
                ]);
            } catch (\Illuminate\Database\QueryException $e) {
                // Duplicate key → race condition, negeer
                // De eerste request wint, de tweede krijgt volgende keer de cached response
            }
        }

        return $response;
    }
}
