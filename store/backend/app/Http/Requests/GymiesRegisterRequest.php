<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Validation voor Gymies registratie.
 *
 * Velden:
 *  - email (verplicht, uniek)
 *  - password (verplicht, min 8)
 *  - role (verplicht: client|klant|trainer)
 *  - display_name (optioneel, max 100)
 *  - phone (optioneel, NL formaat)
 *  - gender (optioneel: male|female)
 *  - newsletter_subscribe (optioneel, boolean)
 *  - referral_code (optioneel, max 50, alphanumeric+dash)
 *  - invite_code (optioneel, max 50, alphanumeric+dash)
 *  - city (optioneel, max 100)
 *  - gym_invite_token (optioneel, max 255)
 */
class GymiesRegisterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Publieke route — iedereen mag registreren
    }

    public function rules(): array
    {
        return [
            'email'                => 'required|email|max:255',
            'password'             => 'required|string|min:8|max:255',
            'role'                 => 'required|string|in:client,klant,trainer',
            'display_name'         => 'nullable|string|max:100',
            'phone'                => ['nullable', 'string', 'max:20', 'regex:/^(\+31|0)[1-9][0-9]{1,12}$/'],
            'gender'               => 'nullable|string|in:male,female',
            'newsletter_subscribe' => 'nullable|boolean',
            'referral_code'        => ['nullable', 'string', 'max:50', 'regex:/^[A-Za-z0-9\-_]+$/'],
            'invite_code'          => ['nullable', 'string', 'max:50', 'regex:/^[A-Za-z0-9\-_]+$/'],
            'city'                 => 'nullable|string|max:100',
            'gym_invite_token'     => 'nullable|string|max:255',
        ];
    }

    public function messages(): array
    {
        return [
            'email.required'       => 'E-mailadres is verplicht.',
            'email.email'          => 'Vul een geldig e-mailadres in.',
            'password.required'    => 'Wachtwoord is verplicht.',
            'password.min'         => 'Wachtwoord moet minimaal 8 tekens bevatten.',
            'role.required'        => 'Rol is verplicht.',
            'role.in'              => 'Ongeldige rol. Kies client of trainer.',
            'phone.regex'          => 'Vul een geldig Nederlands telefoonnummer in.',
            'gender.in'            => 'Geslacht moet male of female zijn.',
            'referral_code.regex'  => 'Referralcode bevat ongeldige tekens.',
            'invite_code.regex'    => 'Uitnodigingscode bevat ongeldige tekens.',
            'city.max'             => 'Stadsnaam mag maximaal 100 tekens zijn.',
            'display_name.max'     => 'Weergavenaam mag maximaal 100 tekens zijn.',
        ];
    }
}
