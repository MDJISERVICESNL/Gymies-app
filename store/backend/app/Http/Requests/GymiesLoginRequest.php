<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Validation voor Gymies login.
 *
 * Opmerking: GymiesAuthController::login() gebruikt momenteel Request met
 * inline validation. Dit bestand bestaat zodat de import in de controller
 * niet crasht. Wanneer login overstapt naar FormRequest injection, is dit
 * bestand al klaar.
 */
class GymiesLoginRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Publieke route
    }

    public function rules(): array
    {
        return [
            'email'    => 'required|email|max:255',
            'password' => 'required|string|min:1|max:255',
        ];
    }

    public function messages(): array
    {
        return [
            'email.required'    => 'E-mailadres is verplicht.',
            'email.email'       => 'Vul een geldig e-mailadres in.',
            'password.required' => 'Wachtwoord is verplicht.',
        ];
    }
}
