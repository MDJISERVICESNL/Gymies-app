<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class TrainerMediaUploadRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Validation for trainer media uploads (photos, portfolio, etc).
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'file' => [
                'required',
                'file',
                'image',
                'mimes:jpeg,jpg,png,webp',
                'max:5120', // 5MB
                'dimensions:min_width=400,min_height=300,max_width=8000,max_height=8000'
            ],
            'type' => ['required', 'string', 'in:photo,portfolio,certificate'],
            'usage' => ['required', 'string', 'in:avatar,gallery,portfolio,document'],
            'title' => ['nullable', 'string', 'max:200'],
            'description' => ['nullable', 'string', 'max:1000'],
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
            'file.required' => 'Bestand is verplicht.',
            'file.image' => 'Het bestand moet een afbeelding zijn.',
            'file.mimes' => 'Alleen JPEG, PNG of WebP afbeeldingen zijn toegestaan.',
            'file.max' => 'Bestand mag maximaal 5MB zijn.',
            'file.dimensions' => 'Afbeelding moet tussen 400x300 en 8000x8000 pixels zijn.',
            'type.required' => 'Type is verplicht.',
            'type.in' => 'Ongeldig type.',
            'usage.required' => 'Gebruik is verplicht.',
            'usage.in' => 'Ongeldig gebruik.',
            'title.max' => 'Titel mag maximaal 200 tekens zijn.',
            'description.max' => 'Beschrijving mag maximaal 1000 tekens zijn.',
        ];
    }
}
