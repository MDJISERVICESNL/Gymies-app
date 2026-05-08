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

        // Self-healing: maak tabel aan als die nog niet bestaat
        GymiesSchemaEnsure::deviceTokensTable();

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

        $userId = (int) $user->id;
        $now = now();

        // Kolom heet 'token' in migration, niet 'fcm_token'
        $tokenCol = Schema::hasColumn($this->table(), 'fcm_token') ? 'fcm_token' : 'token';

        DB::table($this->table())->updateOrInsert(
            [
                'user_id' => $userId,
                $tokenCol => $token,
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

        $tokenCol = Schema::hasColumn($this->table(), 'fcm_token') ? 'fcm_token' : 'token';
        $query = DB::table($this->table())->where('user_id', $userId);
        if ($token !== '') {
            $query->where($tokenCol, $token);
        }
        $query->delete();

        return response()->json(['message' => 'OK']);
    }
}
