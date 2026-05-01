<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class GymiesDirectBookingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'trainer_user_id' => ['required', 'integer', 'exists:gymies_users,id'],
            'scheduled_at' => ['required', 'date'],
            'duration_minutes' => ['nullable', 'integer'],
            'amount_cents' => ['required', 'integer', 'min:1'],
            'package_id' => ['nullable', 'integer', 'min:1'],
            'payment_method' => ['nullable', 'string', 'in:online,cash'],
            'gym_location_id' => ['nullable', 'integer', 'min:1'],
        ];
    }
}
