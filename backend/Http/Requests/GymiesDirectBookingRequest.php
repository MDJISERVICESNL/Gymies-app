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
            'trainer_user_id' => ['required', 'integer', 'min:1', 'exists:gymies_users,id'],
            'scheduled_at' => ['required', 'date_format:Y-m-d H:i:s', 'after:now'],
            'duration_minutes' => ['nullable', 'integer', 'in:45,60,90,120'],
            'amount_cents' => ['required', 'integer', 'min:5000', 'max:5000000'],
            'package_id' => ['nullable', 'integer', 'min:1', 'max:2147483647'],
            'payment_method' => ['nullable', 'string', 'in:online,cash', 'max:20'],
            'gym_location_id' => ['nullable', 'integer', 'min:1', 'max:2147483647'],
        ];
    }
}
