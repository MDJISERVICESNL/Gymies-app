<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Helper: stuur notificatie naar ticket-eigenaar wanneer ticket op "afgehandeld" wordt gezet.
 * Gebruik in GymiesAdminController::updateTicket na het updaten van de status naar 'closed'.
 *
 * Voorbeeld:
 *   if (($updates['status'] ?? null) === 'closed') {
 *       TicketClosedNotificationHelper::notifyTicketOwner($ticketId, $userId, $userNotifiableType);
 *   }
 */
final class TicketClosedNotificationHelper
{
    private static function notificationsTable(): string
    {
        return 'notifications';
    }

    /**
     * Maak een melding aan voor de ticket-eigenaar.
     *
     * @param string|int $ticketId Het ticket-ID (wordt getoond in de melding)
     * @param int $userId De user_id van de klant of trainer (eigenaar van het ticket)
     * @param string $notifiableType Bijv. 'App\Models\User'
     */
    public static function notifyTicketOwner(
        string|int $ticketId,
        int $userId,
        string $notifiableType = 'App\Models\User'
    ): void {
        if (!Schema::hasTable(self::notificationsTable())) {
            return;
        }

        $message = sprintf(
            'Je ticket met ticket id : %s is afgehandeld door Gymies',
            (string) $ticketId
        );

        $data = [
            'title' => 'Ticket afgehandeld',
            'body' => $message,
            'message' => $message,
            'ticket_id' => (string) $ticketId,
            'type' => 'ticket_closed',
        ];

        DB::table(self::notificationsTable())->insert([
            'id' => (string) Str::uuid(),
            'type' => 'App\Notifications\GymiesNotification',
            'notifiable_type' => $notifiableType,
            'notifiable_id' => $userId,
            'data' => json_encode($data),
            'read_at' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }
}
