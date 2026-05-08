<?php

declare(strict_types=1);

namespace App\Helpers;

use App\Events\Gymies\GymiesChatMessageSent;
use App\Http\Controllers\Gymies\FcmPushHelper;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Na insert in gymies_messages: broadcast naar de andere partij (best effort).
 * Ook: persoonlijk bevestigingsbericht van trainer naar klant in chat.
 */
final class GymiesChatBroadcast
{
    /**
     * Stuurt een persoonlijk bericht van de trainer naar de klant in de chat.
     * Gebruikt bij bevestiging, verplaatsing, cash-accept, Mollie-betaling.
     */
    public static function sendTrainerConfirmationToClient(
        int $clientId,
        int $trainerId,
        string $scheduledAt,
        ?string $confirmationNote = null,
        ?int $bookingId = null,
    ): void {
        if (!Schema::hasTable('gymies_conversations') || !Schema::hasTable('gymies_messages')) {
            return;
        }
        $body = null;
        if ($confirmationNote !== null && trim($confirmationNote) !== '') {
            $body = trim($confirmationNote);
        } else {
            try {
                $dt = Carbon::parse($scheduledAt)->locale('nl');
                $body = 'We zien elkaar op ' . $dt->translatedFormat('j F') . ' om ' . $dt->format('H:i') . ', tot snel!';
            } catch (\Throwable $e) {
                $body = 'We zien elkaar binnenkort, tot snel!';
            }
        }

        $conv = DB::table('gymies_conversations')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->orderByDesc('id')
            ->first();
        if ($conv === null) {
            $convId = DB::table('gymies_conversations')->insertGetId([
                'client_user_id' => $clientId,
                'trainer_user_id' => $trainerId,
                'booking_id' => $bookingId,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } else {
            $convId = (int) $conv->id;
        }

        $messageId = DB::table('gymies_messages')->insertGetId([
            'conversation_id' => $convId,
            'from_user_id' => $trainerId,
            'body' => $body,
            'created_at' => now(),
        ]);
        DB::table('gymies_conversations')->where('id', $convId)->update(['updated_at' => now()]);
        self::afterMessageInserted((string) $convId, (int) $messageId, $trainerId, $body);
    }

    public static function afterMessageInserted(
        string $conversationId,
        int $messageId,
        int $fromUserId,
        string $body,
    ): void {
        $conv = DB::table('gymies_conversations')->where('id', $conversationId)->first();
        if (!$conv) {
            return;
        }
        $trainerId = (int) $conv->trainer_user_id;
        $clientId = (int) $conv->client_user_id;
        $receiverId = $fromUserId === $trainerId ? $clientId : $trainerId;
        $senderType = $fromUserId === $trainerId ? 'trainer' : 'client';
        if ($receiverId <= 0) {
            return;
        }
        $preview = mb_substr($body, 0, 200);
        $createdAt = now()->toIso8601String();

        // 1) WebSocket broadcast (Reverb)
        try {
            if (class_exists(GymiesChatMessageSent::class)) {
                event(new GymiesChatMessageSent(
                    $receiverId,
                    (string) $conversationId,
                    (string) $messageId,
                    (string) $fromUserId,
                    $preview,
                    $createdAt,
                    null,
                    $senderType,
                ));
            }
        } catch (\Throwable $e) {
            \Log::warning('[GymiesChatBroadcast] Broadcast failed: ' . $e->getMessage());
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
        }

        // 2) FCM push notification (best effort, valt stil als geen tokens/key)
        try {
            $senderName = self::resolveUserName($fromUserId) ?? ($senderType === 'trainer' ? 'Je trainer' : 'Je klant');
            FcmPushHelper::sendToUser(
                $receiverId,
                $senderName,
                $preview,
                [
                    'type' => 'chat_message',
                    'conversation_id' => (string) $conversationId,
                    'message_id' => (string) $messageId,
                    'from_user_id' => (string) $fromUserId,
                    'sender_type' => $senderType,
                ]
            );
        } catch (\Throwable $e) {
            \Log::warning('[GymiesChatBroadcast] FCM push failed: ' . $e->getMessage());
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
        }
    }

    /**
     * Haal de naam op van een user (voor push notification titel).
     */
    private static function resolveUserName(int $userId): ?string
    {
        try {
            $user = DB::table('users')->where('id', $userId)->first(['name']);
            if ($user && !empty($user->name)) {
                return $user->name;
            }
        } catch (\Throwable $e) {
            // Stil falen — fallback wordt gebruikt
        }
        return null;
    }
}
