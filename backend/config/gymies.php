<?php

declare(strict_types=1);

/**
 * Gymies — Mollie Connect OAuth.
 * Zet in Laravel config/ (of symlink) zodat config:cache de waarden uit .env meeneemt.
 * Na wijziging .env: php artisan config:clear
 */
return [
    'cron_key' => env('GYMIES_CRON_KEY', ''),
    'mollie_client_id' => env('MOLLIE_CLIENT_ID', ''),
    'mollie_client_secret' => env('MOLLIE_CLIENT_SECRET', ''),
    'mollie_api_key' => env('MOLLIE_API_KEY', ''),
    'mollie_profile_id' => env('MOLLIE_PROFILE_ID', ''),
    'mollie_testmode' => env('MOLLIE_TESTMODE', null),

    /** Service fee (cent) bij betaling — "Eigen Baas": klant betaalt bovenop of trainer absorbeert. */
    'service_fee_cents' => (int) (env('GYMIES_SERVICE_FEE_CENTS', '49')),

    // ── Mail & branding (voorheen direct env() in controllers) ──
    'mail_brand' => env('GYMIES_MAIL_BRAND', ''),
    'public_url' => env('GYMIES_PUBLIC_URL', ''),
    'brevo_api_key' => env('BREVO_API_KEY', ''),

    // ── Debug/security flags ──
    'debug_auth' => env('GYMIES_DEBUG_AUTH', false),
    'session_skip_ua_check' => env('GYMIES_SESSION_SKIP_USER_AGENT_CHECK', false),
];
