<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| Gymies Platform Configuratie
|--------------------------------------------------------------------------
|
| Centrale config voor de Gymies fitness marketplace.
| Alle waarden worden uit .env gelezen — draai `php artisan config:cache`
| na elke .env wijziging op productie.
|
*/

return [

    /*
    |--------------------------------------------------------------------------
    | API versie
    |--------------------------------------------------------------------------
    */
    'api_version' => env('GYMIES_API_VERSION', '1.0'),

    /*
    |--------------------------------------------------------------------------
    | Mollie Payments
    |--------------------------------------------------------------------------
    | MOLLIE_API_KEY: test_ prefix = testmode, live_ prefix = productie.
    | MOLLIE_TESTMODE: forceer testmode (handig bij Mollie Connect profileId).
    | MOLLIE_PROFILE_ID: platform profiel-ID (fallback als trainer geen Connect heeft).
    | MOLLIE_WEBHOOK_SECRET: optionele webhook signature verificatie.
    */
    'mollie_api_key'        => env('MOLLIE_API_KEY', ''),
    'mollie_testmode'       => (bool) env('MOLLIE_TESTMODE', false),
    'mollie_profile_id'     => env('MOLLIE_PROFILE_ID', ''),
    'mollie_webhook_secret' => env('MOLLIE_WEBHOOK_SECRET', ''),

    /*
    |--------------------------------------------------------------------------
    | Mollie Connect (OAuth — trainer onboarding)
    |--------------------------------------------------------------------------
    | Client credentials van je Mollie Partner/App dashboard.
    */
    'mollie_client_id'     => env('MOLLIE_CLIENT_ID', ''),
    'mollie_client_secret' => env('MOLLIE_CLIENT_SECRET', ''),

    /*
    |--------------------------------------------------------------------------
    | Service Fees
    |--------------------------------------------------------------------------
    | Platform service fee in centen (wordt opgeteld bij klantprijs of afgetrokken
    | van trainer-uitbetaling, afhankelijk van fee_settings per trainer).
    */
    'service_fee_cents' => (int) env('GYMIES_SERVICE_FEE_CENTS', 49),

    /*
    |--------------------------------------------------------------------------
    | HMAC Request Signing
    |--------------------------------------------------------------------------
    | Gedeeld secret tussen Flutter app en backend voor request integriteit.
    | Moet identiek zijn aan de --dart-define=GYMIES_HMAC_SECRET waarde.
    | Zonder dit secret worden requests NIET gevalideerd (onveilig).
    | hmac_enforce: false = log-only (dev), true = blokkeer ongeldige requests (productie).
    */
    'hmac_secret' => env('GYMIES_HMAC_SECRET', ''),
    'hmac_enforce' => (bool) env('GYMIES_HMAC_ENFORCE', true),

    /*
    |--------------------------------------------------------------------------
    | Cron & Admin
    |--------------------------------------------------------------------------
    */
    'cron_key'    => env('GYMIES_CRON_KEY', ''),
    'admin_email' => env('GYMIES_ADMIN_EMAIL', 'safety@gymies.nl'),

    /*
    |--------------------------------------------------------------------------
    | App URLs
    |--------------------------------------------------------------------------
    */
    'flutter_web_url' => env('GYMIES_APP_URL', 'https://gymiesapp.nl'),

    /*
    |--------------------------------------------------------------------------
    | App Versie (Force Update)
    |--------------------------------------------------------------------------
    | min_app_version: laagste versie die nog met de API werkt.
    | latest_app_version: nieuwste release versie.
    | Zet min_app_version hoger na breaking API changes → app dwingt update af.
    */
    'min_app_version'    => env('GYMIES_MIN_APP_VERSION', '1.0.0'),
    'latest_app_version' => env('GYMIES_LATEST_APP_VERSION', '1.2.1'),

    /*
    |--------------------------------------------------------------------------
    | Sentry Error Tracking
    |--------------------------------------------------------------------------
    | DSN ophalen op https://sentry.io → Settings → Projects → Gymies Backend.
    | traces_sample_rate: 0.0 = uit, 1.0 = alle requests, 0.2 = 20% sampling.
    | Installatie: composer require sentry/sentry-laravel
    | Publiceer config: php artisan sentry:publish
    */
    'sentry_dsn'               => env('SENTRY_LARAVEL_DSN', ''),
    'sentry_traces_sample_rate' => (float) env('SENTRY_TRACES_SAMPLE_RATE', 0.2),
];
