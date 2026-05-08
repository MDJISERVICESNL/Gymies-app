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
            'password' => ['required', 'min:8', 'regex:/^(?=.*[a-zA-Z])(?=.*[0-9])/', 'max:255'],
            'role' => ['required', 'in:trainer,client'],
            'display_name' => ['nullable', 'string', 'max:100'],
            'phone' => ['nullable', 'string', 'max:20', 'regex:/^(\\+31|0)[1-9]\\d{1,9}$/'],
            'gender' => ['required_if:role,client', 'in:female,male,non_binary,not_specified'],
            'newsletter_subscribe' => ['nullable', 'boolean'],
            'referral_code' => ['nullable', 'string', 'max:50'],
            'gym_invite_token' => ['nullable', 'string', 'min:32', 'max:255'],
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
