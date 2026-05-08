<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use App\Rules\NoXSSInput;

class GymiesDisputeMessageRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Validation for dispute messages.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'message' => ['required', 'string', 'max:2000', 'min:1', new NoXSSInput()],
            'attachments' => ['nullable', 'array', 'max:3'],
            'attachments.*' => [
                'file',
                'max:5120', // 5MB
                'mimes:pdf,doc,docx,jpg,jpeg,png,gif'
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
            'message.required' => 'Bericht is verplicht.',
            'message.max' => 'Bericht mag maximaal 2000 tekens zijn.',
            'message.min' => 'Bericht mag niet leeg zijn.',
            'attachments.max' => 'Maximaal 3 bijlagen per bericht.',
            'attachments.*.max' => 'Bijlage mag maximaal 5MB zijn.',
            'attachments.*.mimes' => 'Alleen PDF, DOC, DOCX, JPG, PNG, GIF zijn toegestaan.',
        ];
    }
}
