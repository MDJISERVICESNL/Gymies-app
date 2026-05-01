<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Broadcasting auth voor Gymies Bearer token — Laravel Reverb.
 *
 * Reverb spreekt het Pusher protocol (v7), dus Flutter gebruikt
 * web_socket_channel met wss://host/app/{key}?protocol=7.
 *
 * Verwijderd: Pusher SDK/keys. Reverb is de enige WebSocket provider.
 */
final class GymiesBroadcastController
{
    /**
     * POST broadcasting/auth — body: channel_name, socket_id (Pusher protocol).
     * Middleware gymies.auth heeft user in request->attributes->get('gymies_user').
     */
    public function authenticate(Request $request): JsonResponse
    {
        $channelName = $request->input('channel_name');
        $socketId = $request->input('socket_id');

        if (empty($channelName) || empty($socketId)) {
            return response()->json(['message' => 'channel_name and socket_id required'], 422);
        }

        $user = $request->attributes->get('gymies_user');
        if (!$user || !isset($user->id)) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        // T-041 FIXED: strict type checking + channel naam validatie
        // Alleen private-gymies.chat.{userId} waar userId == ingelogde user
        $prefix = 'private-gymies.chat.';
        if (!str_starts_with($channelName, $prefix)) {
            return response()->json(['message' => 'Invalid channel'], 403);
        }
        $userId = trim(substr($channelName, strlen($prefix)));
        if (!preg_match('/^\d+$/', (string)$userId)) {
            return response()->json(['message' => 'Ongeldig channel.'], 403);
        }
        if ((int)$userId !== (int)$user->id) {
            return response()->json(['message' => 'Geen toegang tot dit kanaal.'], 403);
        }

        $appKey = config('broadcasting.connections.reverb.key')
            ?? env('REVERB_APP_KEY', '');
        $appSecret = config('broadcasting.connections.reverb.secret')
            ?? env('REVERB_APP_SECRET', '');

        if (empty($appKey) || empty($appSecret)) {
            return response()->json(['message' => 'Reverb not configured. Set REVERB_APP_KEY and REVERB_APP_SECRET in .env'], 503);
        }

        $signature = hash_hmac(
            'sha256',
            $socketId . ':' . $channelName,
            $appSecret,
            true,
        );
        $auth = $appKey . ':' . base64_encode($signature);

        return response()->json(['auth' => $auth]);
    }

    /**
     * GET broadcasting/config — Reverb connection info voor Flutter client.
     * Middleware gymies.auth.
     */
    public function config(Request $request): JsonResponse
    {
        $appKey = config('broadcasting.connections.reverb.key')
            ?? env('REVERB_APP_KEY', '');

        if (empty($appKey)) {
            return response()->json(['enabled' => false, 'message' => 'Reverb not configured'], 503);
        }

        $host = env('REVERB_HOST') ?? env('GYMIES_WS_HOST');
        $port = (int) (env('REVERB_PORT') ?? env('GYMIES_WS_PORT') ?? 443);
        $scheme = (env('REVERB_SCHEME', 'https') === 'https') ? 'wss' : 'ws';

        if (empty($host)) {
            $url = rtrim(config('app.url', ''), '/');
            $host = $url ? parse_url($url, PHP_URL_HOST) : 'localhost';
        }

        return response()->json([
            'enabled' => true,
            'key' => $appKey,
            'host' => $host,
            'port' => $port,
            'scheme' => $scheme,
            'cluster' => 'mt1', // Reverb ignoreert cluster, Flutter client verwacht het veld
        ]);
    }
}
