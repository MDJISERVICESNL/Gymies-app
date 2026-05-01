#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Laravel log (alles) ==="
if [ -s storage/logs/laravel.log ]; then
    cat storage/logs/laravel.log
else
    echo "(log is leeg — geen errors)"
fi

echo ""
echo "=== Controller versie check ==="
grep -c "isOAuthToken" app/Http/Controllers/Gymies/GymiesPaymentController.php 2>/dev/null && echo "✓ isOAuthToken fix ACTIEF" || echo "✗ isOAuthToken fix NIET gevonden"

echo ""
echo "=== Direct Mollie API test (zonder applicationFee) ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$apiKey = config('gymies.mollie_api_key');
echo 'API key: ' . substr(\$apiKey, 0, 8) . '...' . PHP_EOL;

\$body = [
    'amount' => ['currency' => 'EUR', 'value' => '40.00'],
    'description' => 'Test boeking #999',
    'redirectUrl' => 'https://gymies.nl/betaling-terug?booking_id=999',
    'webhookUrl' => 'https://gymies.nl/api/gymies/webhooks/mollie',
];

// Probeer ZONDER profileId en applicationFee
echo 'Test 1: Zonder profileId...' . PHP_EOL;
\$response = \Illuminate\Support\Facades\Http::withToken(\$apiKey)
    ->timeout(15)
    ->post('https://api.mollie.com/v2/payments', \$body);

echo 'Status: ' . \$response->status() . PHP_EOL;
\$json = \$response->json();
if (\$response->successful()) {
    echo '✓ Payment aangemaakt! ID=' . (\$json['id'] ?? '?') . PHP_EOL;
    echo 'Checkout URL: ' . (\$json['_links']['checkout']['href'] ?? 'GEEN') . PHP_EOL;
} else {
    echo 'FOUT: ' . (\$json['detail'] ?? json_encode(\$json)) . PHP_EOL;
}

// Probeer MET profileId
\$profileId = config('gymies.mollie_profile_id', '');
if (\$profileId !== '') {
    echo PHP_EOL . 'Test 2: Met profileId=' . \$profileId . '...' . PHP_EOL;
    \$body2 = \$body;
    \$body2['profileId'] = \$profileId;
    \$body2['testmode'] = true;
    \$response2 = \Illuminate\Support\Facades\Http::withToken(\$apiKey)
        ->timeout(15)
        ->post('https://api.mollie.com/v2/payments', \$body2);
    echo 'Status: ' . \$response2->status() . PHP_EOL;
    \$json2 = \$response2->json();
    if (\$response2->successful()) {
        echo '✓ Payment aangemaakt! ID=' . (\$json2['id'] ?? '?') . PHP_EOL;
    } else {
        echo 'FOUT: ' . (\$json2['detail'] ?? json_encode(\$json2)) . PHP_EOL;
    }
} else {
    echo PHP_EOL . 'Geen mollie_profile_id in config.' . PHP_EOL;
}
" 2>&1

echo ""
echo "=== Laatste boekingen ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();
\$bookings = DB::table('gymies_bookings')->orderBy('id', 'desc')->limit(5)->get(['id', 'status', 'amount_cents', 'payment_method', 'created_at']);
foreach (\$bookings as \$b) {
    echo 'ID=' . \$b->id . ' status=' . \$b->status . ' amount=' . \$b->amount_cents . ' method=' . (\$b->payment_method ?? 'null') . ' at=' . \$b->created_at . PHP_EOL;
}
" 2>&1
REMOTE
