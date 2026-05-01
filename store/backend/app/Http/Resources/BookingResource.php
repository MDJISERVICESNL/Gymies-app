<?php

declare(strict_types=1);

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * BookingResource
 * ───────────────
 * Consistent response contract voor boekingen.
 * Gebruik:
 *   return new BookingResource($booking);           // enkel
 *   return BookingResource::collection($bookings);  // lijst
 *
 * Input kan een Eloquent model, stdClass (DB::table) of array zijn.
 */
class BookingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $data = $this->toBase();

        return [
            'id'                  => (int) ($data['id'] ?? 0),
            'client_user_id'      => $this->intOrNull($data, 'client_user_id'),
            'trainer_user_id'     => $this->intOrNull($data, 'trainer_user_id'),
            'scheduled_at'        => $data['scheduled_at'] ?? null,
            'duration_minutes'    => $this->intOrNull($data, 'duration_minutes'),
            'status'              => $data['status'] ?? 'pending',
            'amount_cents'        => $this->intOrNull($data, 'amount_cents'),
            'paid_at'             => $data['paid_at'] ?? null,

            // Display names
            'trainer_name'        => $data['trainer_name'] ?? null,
            'client_name'         => $data['client_name'] ?? null,

            // Optionele velden — alleen meesturen als ze bestaan
            'organisation_id'     => $this->when(isset($data['organisation_id']), fn () => $this->intOrNull($data, 'organisation_id')),
            'payout_route'        => $this->when(isset($data['payout_route']), $data['payout_route'] ?? null),
            'location_type'       => $this->when(isset($data['location_type']), $data['location_type'] ?? null),
            'location_notes'      => $this->when(isset($data['location_notes']), $data['location_notes'] ?? null),
            'confirmation_note'   => $this->when(isset($data['confirmation_note']), $data['confirmation_note'] ?? null),
            'payment_method'      => $this->when(isset($data['payment_method']), $data['payment_method'] ?? null),
            'package_id'          => $this->when(isset($data['package_id']), fn () => $this->intOrNull($data, 'package_id')),
            'package_name'        => $this->when(isset($data['package_name']), $data['package_name'] ?? null),
            'buddy_user_id'       => $this->when(isset($data['buddy_user_id']), fn () => $this->intOrNull($data, 'buddy_user_id')),

            // Voorstel (reschedule)
            'proposed_scheduled_at'      => $this->when(isset($data['proposed_scheduled_at']), $data['proposed_scheduled_at'] ?? null),
            'proposed_duration_minutes'  => $this->when(isset($data['proposed_duration_minutes']), fn () => $this->intOrNull($data, 'proposed_duration_minutes')),
            'proposed_by_user_id'        => $this->when(isset($data['proposed_by_user_id']), fn () => $this->intOrNull($data, 'proposed_by_user_id')),

            // Slot/planning
            'reserved_until'      => $this->when(isset($data['reserved_until']), $data['reserved_until'] ?? null),
            'day_of_week'         => $this->when(isset($data['day_of_week']), $data['day_of_week'] ?? null),
            'week_number'         => $this->when(isset($data['week_number']), fn () => $this->intOrNull($data, 'week_number')),
            'slot_date'           => $this->when(isset($data['slot_date']), $data['slot_date'] ?? null),
            'slot_start_time'     => $this->when(isset($data['slot_start_time']), $data['slot_start_time'] ?? null),
        ];
    }

    /**
     * Converteer het resource naar een plat array (werkt met stdClass, array, en model).
     */
    private function toBase(): array
    {
        if ($this->resource instanceof \stdClass) {
            return (array) $this->resource;
        }
        if (is_array($this->resource)) {
            return $this->resource;
        }
        // Eloquent model
        return $this->resource->toArray();
    }

    private function intOrNull(array $data, string $key): ?int
    {
        return isset($data[$key]) && $data[$key] !== null ? (int) $data[$key] : null;
    }
}
