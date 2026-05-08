<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use App\Rules\NoXSSInput;

class GymiesDisputeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Validation for dispute creation.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'booking_id' => ['required', 'integer', 'min:1', 'exists:gymies_bookings,id'],
            'reason' => ['required', 'string', 'max:100'],
            'details' => ['required', 'string', 'max:2000', new NoXSSInput()],
            'evidence_urls' => ['nullable', 'array', 'max:5'],
            'evidence_urls.*' => ['string', 'url', 'max:2000'],
        ];
    }

    /**
     * Custom validation messages.
     *
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'booking_id.required' => 'Boeking-ID is verplicht.',
            'booking_id.exists' => 'Deze boeking bestaat niet.',
            'reason.required' => 'Reden voor geschil is verplicht.',
            'reason.max' => 'Reden mag maximaal 100 tekens zijn.',
            'details.required' => 'Details zijn verplicht.',
            'details.max' => 'Details mogen maximaal 2000 tekens zijn.',
            'evidence_urls.max' => 'Maximaal 5 bewijs URL\'s toegestaan.',
            'evidence_urls.*.url' => 'Alle bewijs items moeten geldige URL\'s zijn.',
        ];
    }
}
