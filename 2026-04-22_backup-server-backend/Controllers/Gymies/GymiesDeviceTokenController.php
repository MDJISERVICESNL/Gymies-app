<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Device token registratie voor push-notificaties (FCM Android, APNs iOS).
 * POST notifications/register-device – registreer FCM-token.
 * DELETE notifications/register-device – verwijder token (bij logout).
 */
class GymiesDeviceTokenController
{
    private function table(): string
    {
        return 'gymies_device_tokens';
    }

    /**
     * POST notifications/register-device
     * Body: { fcm_token: "...", platform: "android"|"ios" }
     */
    public function register(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable($this->table())) {
            return response()->json(['message' => 'Device tokens niet geconfigureerd.'], 503);
        }

        $token = trim((string) ($request->input('fcm_token') ?? $request->input('token') ?? ''));
        $platform = strtolower(trim((string) ($request->input('platform') ?? 'android')));
        if (!in_array($platform, ['android', 'ios'], true)) {
            $platform = 'android';
        }

        if ($token === '') {
            return response()->json(['message' => 'fcm_token verplicht.'], 422);
        }

        // FCM tokens are typically 100-300 chars; reject clearly invalid values
        if (strlen($token) < 32 || strlen($token) > 4096) {
            return response()->json(['message' => 'Ongeldig fcm_token formaat.'], 422);
        }
        if (!preg_match('/^[A-Za-z0-9\-_:]+$/', $token)) {
            return response()->json(['message' => 'Ongeldig fcm_token formaat.'], 422);
        }

        $userId = (int) $user->id;
        $now = now();

        // Limit device tokens per user to prevent token flooding
        $maxTokens = 5;
        $tokenCount = DB::table($this->table())->where('user_id', $userId)->count();
        if ($tokenCount >= $maxTokens) {
            DB::table($this->table())
                ->where('user_id', $userId)
                ->orderBy('created_at', 'asc')
                ->limit($tokenCount - $maxTokens + 1)
                ->delete();
        }

        DB::table($this->table())->updateOrInsert(
            [
                'user_id' => $userId,
                'fcm_token' => $token,
            ],
            [
                'platform' => $platform,
                'updated_at' => $now,
            ]
        );

        return response()->json(['message' => 'OK', 'registered' => true]);
    }

    /**
     * DELETE notifications/register-device
     * Body: { fcm_token: "..." } of leeg om alle tokens van user te verwijderen.
     */
    public function unregister(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable($this->table())) {
            return response()->json(['message' => 'OK']);
        }

        $userId = (int) $user->id;
        $token = trim((string) ($request->input('fcm_token') ?? $request->input('token') ?? ''));

        $query = DB::table($this->table())->where('user_id', $userId);
        if ($token !== '') {
            $query->where('fcm_token', $token);
        }
        $query->delete();

        return response()->json(['message' => 'OK']);
    }
}
