<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class GymiesRegisterRequest extends FormRequest
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
            'email' => ['required', 'email', 'unique:gymies_users,email'],
            'password' => ['required', 'min:8'],
            'role' => ['required', 'in:klant,trainer,client'],
            'display_name' => ['nullable', 'string', 'max:255'],
            'phone' => ['nullable', 'string', 'max:32'],
            'gender' => ['required', 'in:female,male,non_binary,not_specified'],
            'newsletter_subscribe' => ['nullable', 'boolean'],
            'referral_code' => ['nullable', 'string', 'max:64'],
            'gym_invite_token' => ['nullable', 'string', 'min:32'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'email.required' => 'Vul je e-mailadres in.',
            'email.email' => 'Vul een geldig e-mailadres in.',
            'email.unique' => 'Dit e-mailadres is al geregistreerd. Log in of gebruik een ander adres.',
            'password.required' => 'Vul een wachtwoord in.',
            'password.min' => 'Het wachtwoord moet minimaal 8 tekens zijn.',
            'role.required' => 'Kies of je als klant of trainer wilt registreren.',
            'role.in' => 'Kies een geldige rol (klant of trainer).',
            'gender.required' => 'Kies man of vrouw.',
            'gender.in' => 'Kies man of vrouw.',
        ];
    }
}
