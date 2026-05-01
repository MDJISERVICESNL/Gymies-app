<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

final class GymiesIdempotencyMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_idempotency_keys')) {
            return $next($request);
        }

        $key = trim((string) ($request->header('Idempotency-Key') ?? ''));
        if ($key === '') {
            return response()->json(['message' => 'Idempotency-Key header is verplicht voor deze actie.'], 422);
        }

        $hash = hash('sha256', (string) $request->getContent());
        $endpoint = (string) $request->path();
        $user = $request->attributes->get('gymies_user');
        $userId = $user ? (int) $user->id : null;

        $existing = DB::table('gymies_idempotency_keys')
            ->where('idempotency_key', $key)
            ->where('endpoint', $endpoint)
            ->where('user_id', $userId)
            ->where('expires_at', '>', now())
            ->first();

        if ($existing) {
            if ((string) ($existing->request_hash ?? '') !== $hash) {
                return response()->json(['message' => 'Idempotency key is al gebruikt met andere payload.'], 409);
            }
            $stored = json_decode((string) ($existing->response_json ?? '{}'), true);
            return response()->json(is_array($stored) ? $stored : [], (int) ($existing->status_code ?? 200));
        }

        /** @var Response $response */
        $response = $next($request);
        $body = method_exists($response, 'getContent') ? (string) $response->getContent() : '{}';
        $decoded = json_decode($body, true);
        $safeBody = is_array($decoded) ? $decoded : ['raw' => $body];

        DB::table('gymies_idempotency_keys')->insert([
            'user_id' => $userId,
            'endpoint' => $endpoint,
            'idempotency_key' => $key,
            'request_hash' => $hash,
            'status_code' => $response->getStatusCode(),
            'response_json' => json_encode($safeBody, JSON_UNESCAPED_UNICODE),
            'created_at' => now(),
            'expires_at' => now()->addHours(24),
        ]);

        return $response;
    }
}
