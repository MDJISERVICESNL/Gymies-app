<?php

declare(strict_types=1);

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * PaymentResource
 * ───────────────
 * Consistent response contract voor betalingen.
 *
 * Gebruik:
 *   return new PaymentResource($paymentData);
 */
class PaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $data = $this->toBase();

        return [
            'payment_id'       => $data['payment_id'] ?? $data['reference_id'] ?? null,
            'booking_id'       => $this->when(isset($data['booking_id']), fn () => (int) $data['booking_id']),
            'status'           => $data['status'] ?? 'unknown',
            'payment_method'   => $data['payment_method'] ?? null,
            'reference_id'     => $data['reference_id'] ?? $data['payment_id'] ?? null,
            'amount_cents'     => $this->intOrNull($data, 'amount_cents'),
            'currency'         => $data['currency'] ?? 'EUR',
            'paid_at'          => $data['paid_at'] ?? null,

            // Conditioneel
            'payment_url'              => $this->when(isset($data['payment_url']), $data['payment_url'] ?? null),
            'redirect_url'             => $this->when(isset($data['redirect_url']), $data['redirect_url'] ?? null),
            'status_raw'               => $this->when(isset($data['status_raw']), $data['status_raw'] ?? null),
            'discount_applied_cents'   => $this->when(isset($data['discount_applied_cents']), fn () => $this->intOrNull($data, 'discount_applied_cents')),
        ];
    }

    private function toBase(): array
    {
        if ($this->resource instanceof \stdClass) {
            return (array) $this->resource;
        }
        if (is_array($this->resource)) {
            return $this->resource;
        }
        return $this->resource->toArray();
    }

    private function intOrNull(array $data, string $key): ?int
    {
        return isset($data[$key]) && $data[$key] !== null ? (int) $data[$key] : null;
    }
}
