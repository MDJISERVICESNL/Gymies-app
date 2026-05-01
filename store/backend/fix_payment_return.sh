#!/bin/bash
set -e
echo "=== Fix: server-side return URL fallback ==="

ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Laatste boekingen + payment status ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

echo '--- Boekingen ---' . PHP_EOL;
\$bookings = DB::table('gymies_bookings')->orderBy('id', 'desc')->limit(5)->get();
foreach (\$bookings as \$b) {
    echo 'ID=' . \$b->id . ' status=' . \$b->status . ' amount=' . \$b->amount_cents
         . ' paid_at=' . (\$b->paid_at ?? 'NULL')
         . ' method=' . (\$b->payment_method ?? 'null')
         . ' reserved_until=' . (\$b->reserved_until ?? 'null')
         . ' at=' . \$b->created_at . PHP_EOL;
}

echo PHP_EOL . '--- Payment transactions ---' . PHP_EOL;
if (Schema::hasTable('gymies_payment_transactions')) {
    \$txs = DB::table('gymies_payment_transactions')->orderBy('id', 'desc')->limit(5)->get();
    foreach (\$txs as \$t) {
        echo 'ID=' . \$t->id . ' booking=' . (\$t->booking_id ?? '?')
             . ' status=' . \$t->status
             . ' provider_tx=' . (\$t->provider_transaction_id ?? '?')
             . ' paid_at=' . (\$t->paid_at ?? 'NULL')
             . ' at=' . \$t->created_at . PHP_EOL;
    }
} else {
    echo 'Tabel bestaat niet' . PHP_EOL;
}

echo PHP_EOL . '--- Webhook events ---' . PHP_EOL;
if (Schema::hasTable('gymies_payment_webhook_events')) {
    \$events = DB::table('gymies_payment_webhook_events')->orderBy('id', 'desc')->limit(5)->get();
    foreach (\$events as \$e) {
        echo 'ID=' . \$e->id . ' payment=' . \$e->payment_id . ' status=' . \$e->status . ' at=' . \$e->created_at . PHP_EOL;
    }
} else {
    echo 'Tabel bestaat niet' . PHP_EOL;
}
" 2>&1

echo ""
echo "=== Laravel log ==="
if [ -s storage/logs/laravel.log ]; then
    tail -30 storage/logs/laravel.log
else
    echo "(leeg)"
fi
REMOTE
