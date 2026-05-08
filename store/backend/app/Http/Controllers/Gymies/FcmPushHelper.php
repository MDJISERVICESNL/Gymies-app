<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Verstuur push notifications via Firebase Cloud Messaging V1 API.
 *
 * Gebruikt Service Account (OAuth2 JWT) authenticatie.
 * Configuratie: plaats `firebase-service-account.json` in storage/app/
 * of stel FCM_SERVICE_ACCOUNT_PATH in .env.
 *
 * Project: gymiesapp-d1424
 */
final class FcmPushHelper
{
    private const PROJECT_ID = 'gymiesapp-d1424';
    private const FCM_URL = 'https://fcm.googleapis.com/v1/projects/' . self::PROJECT_ID . '/messages:send';
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    /**
     * Verstuur push naar een specifieke gebruiker (alle devices).
     */
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
     * Verstuur naar een lijst FCM-tokens (V1 API: één bericht per token).
     */
    public static function sendToTokens(
        array $tokens,
        string $title,
        string $body,
        array $data = []
    ): int {
        $accessToken = self::getAccessToken();
        if (!$accessToken) {
            Log::warning('[FcmPush] Kon geen access token verkrijgen. Check service account JSON.');
            return 0;
        }

        $sent = 0;
        foreach ($tokens as $token) {
            if (empty($token)) continue;

            $message = [
                'message' => [
                    'token' => $token,
                    'notification' => [
                        'title' => $title,
                        'body' => $body,
                    ],
                    'data' => array_map('strval', $data), // V1 API vereist string values
                    'android' => [
                        'priority' => 'high',
                        'notification' => [
                            'sound' => 'default',
                            'channel_id' => 'gymies_default',
                        ],
                    ],
                    'apns' => [
                        'payload' => [
                            'aps' => [
                                'sound' => 'default',
                                'badge' => 1,
                            ],
                        ],
                    ],
                ],
            ];

            try {
                $response = Http::withHeaders([
                    'Authorization' => 'Bearer ' . $accessToken,
                    'Content-Type' => 'application/json',
                ])->timeout(10)->post(self::FCM_URL, $message);

                if ($response->successful()) {
                    $sent++;
                } else {
                    $error = $response->json('error.details.0.errorCode') ?? $response->json('error.status') ?? 'unknown';
                    // Only log in debug mode to avoid spam in production
                    if (config('app.debug')) {
                        Log::debug('[FcmPush] Verzending mislukt', ['token' => substr($token, 0, 20) . '...', 'error' => $error]);
                    }

                    // Verwijder ongeldige tokens
                    if (in_array($error, ['UNREGISTERED', 'INVALID_ARGUMENT', 'NOT_FOUND'])) {
                        self::removeInvalidToken($token);
                    }
                }
            } catch (\Throwable $e) {
                Log::error('[FcmPush] Request failed: ' . $e->getMessage());
            }
        }

        return $sent;
    }

    /**
     * Verkrijg een OAuth2 access token via JWT assertion.
     * Token wordt 50 minuten gecacht (geldig 60 min).
     */
    private static function getAccessToken(): ?string
    {
        return Cache::remember('fcm_v1_access_token', 3000, function () {
            $serviceAccount = self::loadServiceAccount();
            if (!$serviceAccount) {
                return null;
            }

            $jwt = self::createJwt($serviceAccount);
            if (!$jwt) {
                return null;
            }

            try {
                $response = Http::asForm()->post(self::TOKEN_URL, [
                    'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                    'assertion' => $jwt,
                ]);

                if ($response->successful()) {
                    return $response->json('access_token');
                }

                Log::error('[FcmPush] Token exchange failed', ['response' => $response->body()]);
                return null;
            } catch (\Throwable $e) {
                Log::error('[FcmPush] Token request failed: ' . $e->getMessage());
                return null;
            }
        });
    }

    /**
     * Maak een signed JWT voor de service account.
     */
    private static function createJwt(array $serviceAccount): ?string
    {
        try {
            $now = time();
            $header = self::base64url(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
            $payload = self::base64url(json_encode([
                'iss' => $serviceAccount['client_email'],
                'scope' => self::SCOPE,
                'aud' => self::TOKEN_URL,
                'iat' => $now,
                'exp' => $now + 3600,
            ]));

            $signInput = "{$header}.{$payload}";
            $privateKey = openssl_pkey_get_private($serviceAccount['private_key']);
            if (!$privateKey) {
                Log::error('[FcmPush] Ongeldige private key in service account JSON.');
                return null;
            }

            $signature = '';
            openssl_sign($signInput, $signature, $privateKey, OPENSSL_ALGO_SHA256);

            return "{$signInput}." . self::base64url($signature);
        } catch (\Throwable $e) {
            Log::error('[FcmPush] JWT creation failed: ' . $e->getMessage());
            return null;
        }
    }

    /**
     * Laad het service account JSON bestand.
     */
    private static function loadServiceAccount(): ?array
    {
        // Optie 1: path uit .env
        $path = env('FCM_SERVICE_ACCOUNT_PATH');
        if ($path && file_exists($path)) {
            $data = json_decode(file_get_contents($path), true);
            if ($data && !empty($data['private_key']) && !empty($data['client_email'])) {
                return $data;
            }
        }

        // Optie 2: standaard locatie in storage
        $storagePath = storage_path('app/firebase-service-account.json');
        if (file_exists($storagePath)) {
            $data = json_decode(file_get_contents($storagePath), true);
            if ($data && !empty($data['private_key']) && !empty($data['client_email'])) {
                return $data;
            }
        }

        // Optie 3: in config directory
        $configPath = base_path('firebase-service-account.json');
        if (file_exists($configPath)) {
            $data = json_decode(file_get_contents($configPath), true);
            if ($data && !empty($data['private_key']) && !empty($data['client_email'])) {
                return $data;
            }
        }

        Log::warning('[FcmPush] Service account JSON niet gevonden. Zoek op: ' . $storagePath);
        return null;
    }

    /**
     * Base64url encoding (RFC 7515).
     */
    private static function base64url(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    /**
     * Haal FCM tokens op voor een user.
     */
    private static function getTokensForUser(int $userId): array
    {
        if (!Schema::hasTable('gymies_device_tokens')) {
            return [];
        }
        return DB::table('gymies_device_tokens')
            ->where('user_id', $userId)
            ->whereNotNull('fcm_token')
            ->where('fcm_token', '!=', '')
            ->pluck('fcm_token')
            ->unique()
            ->values()
            ->all();
    }

    /**
     * Verwijder een ongeldig token uit de database.
     */
    private static function removeInvalidToken(string $token): void
    {
        if (empty($token)) return;
        try {
            DB::table('gymies_device_tokens')
                ->where('fcm_token', $token)
                ->delete();
            Log::info('[FcmPush] Ongeldig token verwijderd', ['token' => substr($token, 0, 20) . '...']);
        } catch (\Throwable $e) {
            Log::warning('[FcmPush] Could not remove invalid token: ' . $e->getMessage());
        }
    }
}
