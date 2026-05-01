<?php

declare(strict_types=1);

namespace App\Events\Gymies;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Broadcast naar afzender wanneer de andere partij berichten als gelezen markeert.
 * Kanaal: gymies.chat.{receiverUserId} — de afzender van de berichten.
 */
class GymiesChatMessagesRead implements ShouldBroadcast
{
    use Dispatchable;
    use SerializesModels;

    public function __construct(
        public int $receiverUserId,
        public string $conversationId,
        public string $readAt,
    ) {
    }

    public function broadcastOn(): Channel
    {
        return new PrivateChannel('gymies.chat.' . $this->receiverUserId);
    }

    public function broadcastAs(): string
    {
        return 'messages.read';
    }

    /** @return array<string, mixed> */
    public function broadcastWith(): array
    {
        return [
            'conversation_id' => $this->conversationId,
            'read_at' => $this->readAt,
        ];
    }
}
