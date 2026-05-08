<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class TrainerPayoutSettingsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Validation for trainer payout settings (IBAN, KvK, frequency).
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'iban' => [
                'nullable',
                'string',
                'max:34',
                'regex:/^NL[0-9]{2}[A-Z]{4}[0-9]{10}$/'
            ],
            'iban_name' => ['nullable', 'string', 'max:200'],
            'kvk_number' => [
                'nullable',
                'string',
                'max:8',
                'regex:/^[0-9]{8}$/'
            ],
            'frequency' => ['nullable', 'string', 'in:weekly,biweekly,monthly'],
            'hourly_rate_cents' => [
                'nullable',
                'integer',
                'min:500',    // €5.00 minimum
                'max:5000000' // €50,000 maximum
            ],
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
            'iban.regex' => 'IBAN moet in NL format zijn (NL + 2 cijfers + 4 letters + 10 cijfers).',
            'iban.max' => 'IBAN mag maximaal 34 tekens zijn.',
            'kvk_number.regex' => 'KvK-nummer moet uit 8 cijfers bestaan.',
            'kvk_number.max' => 'KvK-nummer mag maximaal 8 tekens zijn.',
            'frequency.in' => 'Uitbetalingsfrequentie moet wekelijks, tweewekelijks of maandelijks zijn.',
            'hourly_rate_cents.min' => 'Uurtarief moet minimaal €5.00 zijn.',
            'hourly_rate_cents.max' => 'Uurtarief mag maximaal €50.000,00 zijn.',
            'iban_name.max' => 'Naam op rekening mag maximaal 200 tekens zijn.',
        ];
    }
}
