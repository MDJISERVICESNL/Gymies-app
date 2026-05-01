#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Laravel log (payment errors) ==="
if [ -s storage/logs/laravel.log ]; then
    cat storage/logs/laravel.log | head -80
else
    echo "(log is leeg)"
fi

echo ""
echo "=== Mollie config check ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$key = config('gymies.mollie_api_key');
if (\$key && strlen(\$key) > 10) {
    echo 'Mollie API key: ' . substr(\$key, 0, 8) . '...' . substr(\$key, -4) . ' (' . strlen(\$key) . ' chars)' . PHP_EOL;
    echo 'Type: ' . (str_starts_with(\$key, 'test_') ? 'TEST' : (str_starts_with(\$key, 'live_') ? 'LIVE' : 'ONBEKEND')) . PHP_EOL;
} else {
    echo 'Mollie API key: NIET GECONFIGUREERD!' . PHP_EOL;
    // Check .env direct
    \$env = file_get_contents('/var/www/gymies/.env');
    preg_match('/MOLLIE_API_KEY=(.*)/', \$env, \$m);
    echo '.env MOLLIE_API_KEY: ' . (isset(\$m[1]) && trim(\$m[1]) !== '' ? substr(trim(\$m[1]), 0, 8) . '...' : 'LEEG') . PHP_EOL;
    // Check config/gymies.php
    if (file_exists('/var/www/gymies/config/gymies.php')) {
        echo 'config/gymies.php: BESTAAT' . PHP_EOL;
        \$cfg = include '/var/www/gymies/config/gymies.php';
        echo 'mollie_api_key in config: ' . (isset(\$cfg['mollie_api_key']) ? 'JA' : 'NEE') . PHP_EOL;
    } else {
        echo 'config/gymies.php: BESTAAT NIET!' . PHP_EOL;
    }
}

echo PHP_EOL . '=== Payment tabel check ===' . PHP_EOL;
echo 'gymies_payment_transactions: ' . (Schema::hasTable('gymies_payment_transactions') ? 'JA' : 'NEE') . PHP_EOL;

echo PHP_EOL . '=== Laatste boekingen ===' . PHP_EOL;
\$bookings = DB::table('gymies_bookings')->orderBy('id', 'desc')->limit(3)->get(['id', 'status', 'amount_cents', 'payment_method', 'created_at']);
foreach (\$bookings as \$b) {
    echo 'ID=' . \$b->id . ' status=' . \$b->status . ' amount=' . \$b->amount_cents . ' method=' . (\$b->payment_method ?? 'null') . ' at=' . \$b->created_at . PHP_EOL;
}
" 2>&1

echo ""
echo "=== Nginx access: payment requests ==="
sudo tail -200 /var/log/nginx/access.log | grep -i "payment" | tail -10
REMOTE
