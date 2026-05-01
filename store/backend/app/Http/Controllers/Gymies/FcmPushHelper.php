<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Verstuur push notifications via Firebase Cloud Messaging (FCM).
 * FCM levert aan Android; voor iOS routeert FCM via APNs.
 *
 * Zet FCM_SERVER_KEY in .env (Firebase Console → Project Settings → Cloud Messaging → Server key).
 */
final class FcmPushHelper
{
    private const FCM_URL = 'https://fcm.googleapis.com/fcm/send';

    public static function sendToUser(
        int $userId,
        string $title,
        string $body,
        array $data = []
    ): int {
        $tokens = self::getTokensForUser($userId);
        if (empty($tokens)) {
            return 0;
        }
        return self::sendToTokens($tokens, $title, $body, $data);
    }

    /**
     * Verstuur naar een lijst FCM-tokens.
     */
    public static function sendToTokens(
        array $tokens,
        string $title,
        string $body,
        array $data = []
    ): int {
        $key = config('services.fcm.server_key') ?: env('FCM_SERVER_KEY');
        if (empty($key)) {
            Log::warning('[FcmPush] FCM_SERVER_KEY niet geconfigureerd.');
            return 0;
        }

        $sent = 0;
        foreach (array_chunk($tokens, 500) as $chunk) {
            $payload = [
                'registration_ids' => $chunk,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                    'sound' => 'default',
                ],
                'data' => $data,
                'priority' => 'high',
            ];
            try {
                $response = Http::withHeaders([
                    'Authorization' => 'key=' . $key,
                    'Content-Type' => 'application/json',
                ])->post(self::FCM_URL, $payload);

                if ($response->successful()) {
                    $json = $response->json();
                    $sent += ($json['success'] ?? 0);
                    $failed = $json['failure'] ?? 0;
                    if ($failed > 0) {
                        $results = $json['results'] ?? [];
                        foreach ($results as $i => $r) {
                            if (!empty($r['error'])) {
                                if (($r['error'] ?? '') === 'InvalidRegistration' || ($r['error'] ?? '') === 'NotRegistered') {
                                    self::removeInvalidToken($chunk[$i] ?? '');
                                }
                            }
                        }
                    }
                }
            } catch (\Throwable $e) {
                Log::error('[FcmPush] FCM request failed: ' . $e->getMessage());
            }
        }
        return $sent;
    }

    private static function getTokensForUser(int $userId): array
    {
        if (!\Illuminate\Support\Facades\Schema::hasTable('gymies_device_tokens')) {
            return [];
        }
        $rows = DB::table('gymies_device_tokens')
            ->where('user_id', $userId)
            ->whereNotNull('fcm_token')
            ->where('fcm_token', '!=', '')
            ->pluck('fcm_token')
            ->unique()
            ->values()
            ->all();
        return $rows;
    }

    private static function removeInvalidToken(string $token): void
    {
        if (empty($token)) return;
        try {
            DB::table('gymies_device_tokens')
                ->where('fcm_token', $token)
                ->delete();
        } catch (\Throwable $e) {
            Log::warning('[FcmPush] Could not remove invalid token: ' . $e->getMessage());
        }
    }
}
