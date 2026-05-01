<?php

declare(strict_types=1);

namespace App\Events;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * PaymentStatusUpdated
 * ────────────────────
 * Broadcast payment status wijzigingen via Reverb naar de Flutter app.
 * Hierdoor hoeft de client niet te pollen — de status komt via WebSocket.
 *
 * Luistert in Flutter op:
 *   channel: private-gymies.payments.{userId}
 *   event: PaymentStatusUpdated
 *
 * Gebruik:
 *   event(new PaymentStatusUpdated($clientUserId, $bookingId, 'paid', $amountCents));
 */
class PaymentStatusUpdated implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly int $userId,
        public readonly int $bookingId,
        public readonly string $status,
        public readonly int $amountCents = 0,
        public readonly ?string $paymentId = null,
        public readonly ?string $paidAt = null,
    ) {}

    /**
     * Privé kanaal per gebruiker zodat alleen de juiste client de update ontvangt.
     */
    public function broadcastOn(): array
    {
        return [
            new PrivateChannel("gymies.payments.{$this->userId}"),
        ];
    }

    public function broadcastAs(): string
    {
        return 'PaymentStatusUpdated';
    }

    /**
     * Data die naar de client wordt gestuurd.
     */
    public function broadcastWith(): array
    {
        return [
            'booking_id'   => $this->bookingId,
            'status'       => $this->status,
            'amount_cents' => $this->amountCents,
            'payment_id'   => $this->paymentId,
            'paid_at'      => $this->paidAt,
            'timestamp'    => now()->toIso8601String(),
        ];
    }
}
