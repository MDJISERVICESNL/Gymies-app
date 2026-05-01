#!/bin/bash
set -e

echo "=== Booking 500 Error Diagnose ==="
echo ""

ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Laatste Laravel errors (storage/logs) ==="
LOG=$(ls -t storage/logs/laravel*.log 2>/dev/null | head -1)
if [ -n "$LOG" ]; then
    echo "Log: $LOG"
    echo "---"
    # Zoek laatste 500/exception
    tail -100 "$LOG" | grep -A 20 -i "exception\|error\|500\|SQLSTATE\|stack trace" | tail -60
else
    echo "Geen laravel log gevonden."
fi

echo ""
echo "=== Nginx error log (laatste 20 regels) ==="
sudo tail -20 /var/log/nginx/error.log 2>/dev/null || echo "(geen toegang)"

echo ""
echo "=== GymiesDirectBookingRequest.php op server ==="
if [ -f app/Http/Requests/GymiesDirectBookingRequest.php ]; then
    echo "BESTAAT - inhoud:"
    cat app/Http/Requests/GymiesDirectBookingRequest.php
else
    echo "ONTBREEKT! Dit is waarschijnlijk het probleem."
fi

echo ""
echo "=== gymies_bookings kolommen ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

if (!Schema::hasTable('gymies_bookings')) {
    echo 'FOUT: gymies_bookings tabel bestaat niet!' . PHP_EOL;
    exit;
}
\$cols = DB::getSchemaBuilder()->getColumnListing('gymies_bookings');
echo implode(', ', \$cols) . PHP_EOL;

echo PHP_EOL . '=== gymies_trainer_profiles: session_price_cents check ===' . PHP_EOL;
if (!Schema::hasTable('gymies_trainer_profiles')) {
    echo 'FOUT: gymies_trainer_profiles tabel bestaat niet!' . PHP_EOL;
} else {
    \$cols2 = DB::getSchemaBuilder()->getColumnListing('gymies_trainer_profiles');
    echo 'Kolommen: ' . implode(', ', array_slice(\$cols2, 0, 20)) . '...' . PHP_EOL;

    // Check of er een prijs is voor de demo trainer
    \$profile = DB::table('gymies_trainer_profiles')->where('user_id', 27)->first();
    if (\$profile) {
        echo 'Trainer 27 profiel gevonden.' . PHP_EOL;
        echo '  session_price_cents: ' . (\$profile->session_price_cents ?? 'NULL') . PHP_EOL;
    } else {
        echo 'Trainer 27 heeft GEEN trainer_profiles record!' . PHP_EOL;
    }
}

echo PHP_EOL . '=== Route check: bookings/direct-book ===' . PHP_EOL;
\$routes = app('router')->getRoutes();
foreach (\$routes as \$route) {
    if (str_contains(\$route->uri(), 'direct-book')) {
        echo 'URI: ' . \$route->uri() . '  Methods: ' . implode(',', \$route->methods()) . '  Action: ' . \$route->getActionName() . PHP_EOL;
    }
}
" 2>&1

REMOTE
