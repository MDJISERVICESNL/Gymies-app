<?php

declare(strict_types=1);

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * TrainerResource
 * ───────────────
 * Consistent response contract voor trainer profielen.
 * Filtert automatisch gevoelige velden (tokens, hashes).
 *
 * Gebruik:
 *   return new TrainerResource($trainer);
 *   return TrainerResource::collection($trainers);
 */
class TrainerResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $data = $this->toBase();

        return [
            'user_id'              => (int) ($data['user_id'] ?? $data['id'] ?? 0),
            'display_name'         => $data['display_name'] ?? $data['name'] ?? null,
            'email'                => $data['email'] ?? null,
            'specialty'            => $data['specialty'] ?? null,
            'region'               => $data['region'] ?? null,
            'city'                 => $data['city'] ?? null,
            'bio'                  => $data['bio'] ?? null,
            'hourly_rate_cents'    => $this->intOrNull($data, 'hourly_rate_cents'),
            'avatar_url'           => $data['avatar_url'] ?? null,
            'profile_slug'         => $data['profile_slug'] ?? null,
            'booking_advance_days' => $this->intOrNull($data, 'booking_advance_days'),
            'payment_method'       => $data['payment_method'] ?? null,

            // Conditioneel
            'distance_km'          => $this->when(isset($data['distance_km']), fn () => round((float) ($data['distance_km'] ?? 0), 1)),
            'boosted_until'        => $this->when(isset($data['boosted_until']), $data['boosted_until'] ?? null),
            'rating'               => $this->when(isset($data['rating']), fn () => round((float) ($data['rating'] ?? 0), 1)),
            'review_count'         => $this->when(isset($data['review_count']), fn () => (int) ($data['review_count'] ?? 0)),
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
