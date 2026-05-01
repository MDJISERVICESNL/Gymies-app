#!/bin/bash
set -e
echo "=== FINALE Mollie fix: geen profileId/appFee bij reguliere keys ==="

# 1. Upload
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesPaymentController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesPaymentController.php

ssh gymies << 'REMOTE'
cd /var/www/gymies

# 2. Permissions + log
chown ubuntu:ubuntu app/Http/Controllers/Gymies/GymiesPaymentController.php
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 3. FPM restart + caches
sudo systemctl restart php8.4-fpm
php artisan config:cache
php artisan route:cache

# 4. Log legen
sudo truncate -s 0 storage/logs/laravel.log
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 5. Verlopen reserved boekingen opruimen
echo ""
echo "=== Verlopen reserveringen opruimen ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$reserved = DB::table('gymies_bookings')
    ->where('status', 'reserved')
    ->get(['id', 'scheduled_at', 'reserved_until']);
foreach (\$reserved as \$b) {
    echo 'ID=' . \$b->id . ' reserved_until=' . (\$b->reserved_until ?? 'null') . PHP_EOL;
    DB::table('gymies_bookings')->where('id', \$b->id)->update(['status' => 'cancelled', 'updated_at' => now()]);
    echo '  → cancelled' . PHP_EOL;
}
if (\$reserved->isEmpty()) echo 'Geen reserveringen.' . PHP_EOL;
" 2>&1

# 6. Verify
echo ""
echo "=== Verificatie ==="
if grep -q 'isOAuthToken' app/Http/Controllers/Gymies/GymiesPaymentController.php; then
    echo "✓ OAuth check actief"
fi
# Test Mollie API direct
echo ""
echo "=== Mollie API test ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$apiKey = config('gymies.mollie_api_key');
\$body = [
    'amount' => ['currency' => 'EUR', 'value' => '1.00'],
    'description' => 'Test payment',
    'redirectUrl' => 'https://gymies.nl/betaling-terug?booking_id=test',
    'webhookUrl' => 'https://gymies.nl/api/gymies/webhooks/mollie',
];
\$response = \Illuminate\Support\Facades\Http::withToken(\$apiKey)->timeout(15)->post('https://api.mollie.com/v2/payments', \$body);
if (\$response->successful()) {
    \$data = \$response->json();
    echo '✓ Mollie OK! ID=' . (\$data['id'] ?? '?') . PHP_EOL;
    echo '  Checkout: ' . (\$data['_links']['checkout']['href'] ?? 'GEEN') . PHP_EOL;
} else {
    echo '✗ Mollie FOUT: ' . (\$response->json()['detail'] ?? 'onbekend') . PHP_EOL;
}
" 2>&1

echo ""
echo "✅ Fix gedeployed! Test de boeking opnieuw in de app."
REMOTE
