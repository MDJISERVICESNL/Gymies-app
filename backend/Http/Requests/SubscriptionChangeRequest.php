<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class SubscriptionChangeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Validation for subscription plan changes.
     *
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'plan_id' => [
                'required',
                'integer',
                'min:1',
                'max:2147483647',
                'exists:subscription_plans,id'
            ],
            'billing_cycle' => [
                'required',
                'string',
                'in:monthly,quarterly,annual'
            ],
            'payment_method_id' => [
                'nullable',
                'integer',
                'min:1',
                'max:2147483647'
            ],
            'coupon_code' => [
                'nullable',
                'string',
                'max:50',
                'alpha_dash'
            ],
            'auto_renew' => ['nullable', 'boolean'],
            'notes' => ['nullable', 'string', 'max:500'],
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
            'plan_id.required' => 'Plan-ID is verplicht.',
            'plan_id.exists' => 'Dit abonnementplan bestaat niet.',
            'billing_cycle.required' => 'Factureringscyclus is verplicht.',
            'billing_cycle.in' => 'Factureringscyclus moet maandelijks, driemaandelijks of jaarlijks zijn.',
            'coupon_code.alpha_dash' => 'Coupon-code mag alleen letters, getallen en streepjes bevatten.',
            'coupon_code.max' => 'Coupon-code mag maximaal 50 tekens zijn.',
            'notes.max' => 'Notities mogen maximaal 500 tekens zijn.',
        ];
    }
}
