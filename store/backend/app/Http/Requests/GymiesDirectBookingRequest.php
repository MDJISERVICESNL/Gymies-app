<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Validation voor directe boeking (klant → trainer, zonder tussenkomst).
 * amount_cents wordt server-side berekend (P-FIX-1) en is dus NIET required.
 */
class GymiesDirectBookingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Auth wordt afgehandeld door middleware
    }

    public function rules(): array
    {
        return [
            'trainer_user_id' => 'required|integer|min:1',
            'trainer_id'      => 'nullable|integer|min:1',
            'scheduled_at'    => 'required|date',
            'duration_minutes'=> 'nullable|integer|min:15|max:480',
            'amount_cents'    => 'nullable|integer|min:0',
            'package_id'      => 'nullable|integer|min:1',
            'service_id'      => 'nullable|integer|min:1',
            'note'            => 'nullable|string|max:1000',
            'notes'           => 'nullable|string|max:1000',
            'payment_method'  => 'nullable|string|in:mollie,cash,online',
            'gym_location_id' => 'nullable|integer|min:1',
            'availability_slot_id' => 'nullable|string|max:255',
            'hold_id'         => 'nullable|string|max:255',
            'hold_token'      => 'nullable|string|max:255',
        ];
    }

    public function messages(): array
    {
        return [
            'trainer_user_id.required' => 'Trainer ID is verplicht.',
            'scheduled_at.required' => 'Datum/tijd is verplicht.',
            'scheduled_at.date' => 'Ongeldige datum/tijd.',
        ];
    }
}
