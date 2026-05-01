<?php

declare(strict_types=1);

namespace App\Helpers;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Sync tussen support tickets en berichten: ticket-berichten verschijnen als GYMIES-gesprek
 * in de berichten van klant/trainer. Admin-antwoorden komen in berichten als afzender GYMIES.
 */
final class GymiesSupportSync
{
    private const GYMIES_SUPPORT_EMAIL = 'support@gymies.internal';

    public static function getGymiesSupportUserId(): ?int
    {
        if (!Schema::hasTable('gymies_users')) {
            return null;
        }
        $id = DB::table('gymies_users')
            ->where('email', self::GYMIES_SUPPORT_EMAIL)
            ->value('id');

        return $id ? (int) $id : null;
    }

    /**
     * Maak support-conversatie voor ticket en voeg eerste bericht toe.
     * client_user_id = submitter, trainer_user_id = GYMIES.
     */
    public static function ensureSupportConversationForTicket(int $ticketId, int $submitterUserId, string $firstMessage): ?string
    {
        $gymiesId = self::getGymiesSupportUserId();
        if (!$gymiesId || !Schema::hasTable('gymies_conversations') || !Schema::hasTable('gymies_messages')) {
            return null;
        }
        if (!Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
            return null;
        }

        $existing = DB::table('gymies_conversations')
            ->where('support_ticket_id', $ticketId)
            ->first();

        if ($existing) {
            return (string) $existing->id;
        }

        $convId = DB::table('gymies_conversations')->insertGetId([
            'client_user_id' => $submitterUserId,
            'trainer_user_id' => $gymiesId,
            'booking_id' => null,
            'support_ticket_id' => $ticketId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        DB::table('gymies_messages')->insert([
            'conversation_id' => $convId,
            'from_user_id' => $submitterUserId,
            'body' => $firstMessage,
            'created_at' => now(),
        ]);

        return (string) $convId;
    }

    /**
     * Voeg admin-antwoord (is_internal=false) toe aan support-conversatie als bericht van GYMIES.
     */
    public static function syncAdminReplyToConversation(int $ticketId, string $messageBody): void
    {
        $gymiesId = self::getGymiesSupportUserId();
        if (!$gymiesId || !Schema::hasTable('gymies_conversations') || !Schema::hasTable('gymies_messages')) {
            return;
        }

        $conv = DB::table('gymies_conversations')
            ->where('support_ticket_id', $ticketId)
            ->first();

        if (!$conv) {
            return;
        }

        $msgId = DB::table('gymies_messages')->insertGetId([
            'conversation_id' => $conv->id,
            'from_user_id' => $gymiesId,
            'body' => $messageBody,
            'created_at' => now(),
        ]);

        DB::table('gymies_conversations')->where('id', $conv->id)->update(['updated_at' => now()]);

        if (class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
            \App\Helpers\GymiesChatBroadcast::afterMessageInserted((string) $conv->id, (int) $msgId, $gymiesId, $messageBody);
        }
    }

    /**
     * Voeg gebruikersbericht (ticket reply) toe aan support-conversatie.
     */
    public static function syncUserReplyToConversation(int $ticketId, int $userId, string $messageBody): void
    {
        if (!Schema::hasTable('gymies_conversations') || !Schema::hasTable('gymies_messages')) {
            return;
        }

        $conv = DB::table('gymies_conversations')
            ->where('support_ticket_id', $ticketId)
            ->first();

        if (!$conv) {
            return;
        }

        $msgId = DB::table('gymies_messages')->insertGetId([
            'conversation_id' => $conv->id,
            'from_user_id' => $userId,
            'body' => $messageBody,
            'created_at' => now(),
        ]);

        DB::table('gymies_conversations')->where('id', $conv->id)->update(['updated_at' => now()]);

        if (class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
            \App\Helpers\GymiesChatBroadcast::afterMessageInserted((string) $conv->id, (int) $msgId, $userId, $messageBody);
        }
    }

    /**
     * Sync bericht uit conversatie naar ticket (user antwoordt via berichten).
     */
    public static function syncConversationMessageToTicket(string $conversationId, int $fromUserId, string $body): void
    {
        if (!Schema::hasTable('gymies_conversations') || !Schema::hasTable('gymies_support_tickets') || !Schema::hasTable('gymies_support_ticket_messages')) {
            return;
        }
        if (!Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
            return;
        }

        $conv = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->whereNotNull('support_ticket_id')
            ->first();

        if (!$conv || $conv->client_user_id != $fromUserId) {
            return;
        }

        $gymiesId = self::getGymiesSupportUserId();
        if ($fromUserId === $gymiesId) {
            return;
        }

        DB::table('gymies_support_ticket_messages')->insert([
            'ticket_id' => (int) $conv->support_ticket_id,
            'author_user_id' => $fromUserId,
            'message' => $body,
            'is_internal' => 0,
            'created_at' => now(),
        ]);

        DB::table('gymies_support_tickets')->where('id', $conv->support_ticket_id)->update([
            'updated_at' => now(),
            'status' => 'in_progress',
        ]);
    }
}
