<?php

declare(strict_types=1);

namespace App\Http\Requests;

use App\Rules\NoXSSInput;
use Illuminate\Foundation\Http\FormRequest;

class SupportTicketRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Validation for support ticket creation.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'subject' => [
                'required',
                'string',
                'max:200',
                'min:5',
                new NoXSSInput()
            ],
            'message' => [
                'required',
                'string',
                'max:5000',
                'min:10',
                new NoXSSInput()
            ],
            'category' => [
                'nullable',
                'string',
                'in:billing,booking,profile,payment,technical,other'
            ],
            'priority' => [
                'nullable',
                'string',
                'in:low,medium,high,urgent'
            ],
            'attachment_url' => [
                'nullable',
                'url',
                'max:2000'
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
            'subject.required' => 'Onderwerp is verplicht.',
            'subject.min' => 'Onderwerp moet minimaal 5 tekens zijn.',
            'subject.max' => 'Onderwerp mag maximaal 200 tekens zijn.',
            'message.required' => 'Bericht is verplicht.',
            'message.min' => 'Bericht moet minimaal 10 tekens zijn.',
            'message.max' => 'Bericht mag maximaal 5000 tekens zijn.',
            'category.in' => 'Ongeldig categorie.',
            'priority.in' => 'Ongeldig prioriteit.',
        ];
    }
}
