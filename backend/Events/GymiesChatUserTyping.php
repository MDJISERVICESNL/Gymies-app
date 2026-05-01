<?php

declare(strict_types=1);

namespace App\Events\Gymies;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Broadcast naar de andere partij wanneer iemand aan het typen is.
 * Kanaal: gymies.chat.{receiverUserId}
 */
class GymiesChatUserTyping implements ShouldBroadcast
{
    use Dispatchable;
    use SerializesModels;

    public function __construct(
        public int $receiverUserId,
        public string $conversationId,
        public int $typingUserId,
        public string $typingUserName,
    ) {
    }

    public function broadcastOn(): Channel
    {
        return new PrivateChannel('gymies.chat.' . $this->receiverUserId);
    }

    public function broadcastAs(): string
    {
        return 'user.typing';
    }

    /** @return array<string, mixed> */
    public function broadcastWith(): array
    {
        return [
            'conversation_id' => $this->conversationId,
            'typing_user_id' => (string) $this->typingUserId,
            'typing_user_name' => $this->typingUserName,
        ];
    }
}
