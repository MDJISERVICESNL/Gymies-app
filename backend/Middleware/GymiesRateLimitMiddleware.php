<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

final class GymiesRateLimitMiddleware
{
    public function handle(Request $request, Closure $next, string $profile = 'api'): Response
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_rate_limit_events')) {
            return $next($request);
        }

        [$maxAttempts, $windowSeconds, $blockSeconds] = $this->limitsForProfile($profile);
        $ip = (string) ($request->ip() ?? 'unknown');
        $endpoint = (string) $request->path();
        $user = $request->attributes->get('gymies_user');
        $userId = $user ? (int) $user->id : null;

        $blocked = DB::table('gymies_rate_limit_events')
            ->where('ip_address', $ip)
            ->where('endpoint', $endpoint)
            ->whereNotNull('blocked_until')
            ->where('blocked_until', '>', now())
            ->orderByDesc('id')
            ->first();
        if ($blocked) {
            return response()->json(['message' => 'Te veel verzoeken. Probeer het later opnieuw.'], 429);
        }

        $windowStart = now()->subSeconds($windowSeconds);
        $attempts = DB::table('gymies_rate_limit_events')
            ->where('ip_address', $ip)
            ->where('endpoint', $endpoint)
            ->where('created_at', '>=', $windowStart)
            ->count();
        if ($attempts >= $maxAttempts) {
            DB::table('gymies_rate_limit_events')->insert([
                'ip_address' => $ip,
                'user_id' => $userId,
                'endpoint' => $endpoint,
                'blocked_until' => now()->addSeconds($blockSeconds),
                'created_at' => now(),
            ]);
            return response()->json(['message' => 'Te veel verzoeken. Probeer het later opnieuw.'], 429);
        }

        DB::table('gymies_rate_limit_events')->insert([
            'ip_address' => $ip,
            'user_id' => $userId,
            'endpoint' => $endpoint,
            'created_at' => now(),
        ]);

        return $next($request);
    }

    /**
     * @return array{0:int,1:int,2:int}
     */
    private function limitsForProfile(string $profile): array
    {
        return match ($profile) {
            'login' => [5, 60, 600],
            'register' => [4, 300, 900],
            default => [120, 60, 120],
        };
    }
}
