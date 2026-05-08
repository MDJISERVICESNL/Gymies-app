<?php

declare(strict_types=1);

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * Custom validation rule to prevent XSS attacks in user input.
 * Blocks dangerous HTML/JS patterns while allowing safe content.
 */
class NoXSSInput implements ValidationRule
{
    private const DANGEROUS_PATTERNS = [
        '/<script/',
        '/<iframe/',
        '/onclick\s*=/i',
        '/onerror\s*=/i',
        '/onload\s*=/i',
        '/javascript:/i',
        '/data:text\/html/i',
        '/<embed/',
        '/<object/',
    ];

    /**
     * Run the validation rule.
     *
     * @param \Closure(string): \Illuminate\Translation\PotentiallyTranslatedString $fail
     */
    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (!is_string($value)) {
            return; // Skip non-string values
        }

        foreach (self::DANGEROUS_PATTERNS as $pattern) {
            if (preg_match($pattern, $value)) {
                $fail("Het veld {$attribute} bevat niet-toegestane karakters of tags.");
                return;
            }
        }
    }
}
