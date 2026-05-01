<?php

declare(strict_types=1);

namespace App\Events\Gymies;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Broadcast naar ontvanger na nieuw chatbericht.
 * Kanaal: gymies.chat.{receiverUserId} — authorize in routes/channels.php
 * Zonder Reverb/Pusher: event wordt genegeerd; HTTP blijft bron van waarheid.
 */
class GymiesChatMessageSent implements ShouldBroadcast
{
    use Dispatchable;
    use SerializesModels;

    public function __construct(
        public int $receiverUserId,
        public string $conversationId,
        public string $messageId,
        public string $fromUserId,
        public string $bodyPreview,
        public string $createdAt,
        public ?string $conversationType = null,
    ) {
    }

    public function broadcastOn(): Channel
    {
        return new PrivateChannel('gymies.chat.' . $this->receiverUserId);
    }

    public function broadcastAs(): string
    {
        return 'message.sent';
    }

    /** @return array<string, mixed> */
    public function broadcastWith(): array
    {
        $payload = [
            'conversation_id' => $this->conversationId,
            'message_id' => $this->messageId,
            'from_user_id' => $this->fromUserId,
            'body_preview' => $this->bodyPreview,
            'created_at' => $this->createdAt,
        ];
        if ($this->conversationType !== null) {
            $payload['conversation_type'] = $this->conversationType;
        }
        return $payload;
    }
}
