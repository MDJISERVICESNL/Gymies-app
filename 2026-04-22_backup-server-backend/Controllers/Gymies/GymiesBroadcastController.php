<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Broadcasting auth voor Gymies Bearer token.
 * Pusher/Reverb private channel: POST channel_name + socket_id → JSON { auth: "key:signature" }.
 */
final class GymiesBroadcastController
{
    /**
     * POST broadcasting/auth — body: channel_name, socket_id (Pusher protocol).
     * Middelware gymies.auth heeft user in request->attributes->get('gymies_user').
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
        // Valideer: alleen digits toegestaan
        if (!preg_match('/^\d+$/', (string)$userId)) {
            return response()->json(['message' => 'Ongeldig channel.'], 403);
        }
        if ((int)$userId !== (int)$user->id) {
            return response()->json(['message' => 'Geen toegang tot dit kanaal.'], 403);
        }

        $appKey = config('broadcasting.connections.reverb.key')
            ?? config('broadcasting.connections.pusher.key')
            ?? env('REVERB_APP_KEY') ?? env('PUSHER_APP_KEY');
        $appSecret = config('broadcasting.connections.reverb.secret')
            ?? config('broadcasting.connections.pusher.secret')
            ?? env('REVERB_APP_SECRET') ?? env('PUSHER_APP_SECRET');

        if (empty($appKey) || empty($appSecret)) {
            return response()->json(['message' => 'Broadcasting not configured'], 503);
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
     * GET broadcasting/config — app key + host voor client (niet-geheim).
     * Middelware gymies.auth.
     */
    public function config(Request $request): JsonResponse
    {
        $appKey = config('broadcasting.connections.reverb.key')
            ?? config('broadcasting.connections.pusher.key')
            ?? env('REVERB_APP_KEY') ?? env('PUSHER_APP_KEY');

        if (empty($appKey)) {
            return response()->json(['enabled' => false, 'message' => 'Broadcasting not configured'], 503);
        }

        $host = env('GYMIES_WS_HOST') ?? env('PUSHER_HOST') ?? env('REVERB_HOST');
        $port = (int) (env('GYMIES_WS_PORT') ?? env('PUSHER_PORT') ?? env('REVERB_PORT') ?? 443);
        $scheme = (env('GYMIES_WS_SCHEME') ?? env('PUSHER_SCHEME') ?? 'https') === 'https' ? 'wss' : 'ws';

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
            'cluster' => env('PUSHER_APP_CLUSTER', 'mt1'),
        ]);
    }
}
