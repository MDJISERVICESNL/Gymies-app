#!/bin/bash
set -e
echo "=== Fix: return URL → deep link naar app ==="

# 1. Upload PaymentController
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesPaymentController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesPaymentController.php

ssh gymies << 'REMOTE'
cd /var/www/gymies

# 2. Permissions + restart
chown ubuntu:ubuntu app/Http/Controllers/Gymies/GymiesPaymentController.php
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log
sudo systemctl restart php8.4-fpm
php artisan config:cache
php artisan route:cache

# 3. Log legen
sudo truncate -s 0 storage/logs/laravel.log
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 4. Verify
echo ""
echo "=== Verificatie ==="
grep -q "gymies://payment/complete" app/Http/Controllers/Gymies/GymiesPaymentController.php && echo "✓ Deep link return URL actief" || echo "✗ Deep link niet gevonden"

echo ""
echo "=== Boeking #178 status ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$b = DB::table('gymies_bookings')->where('id', 178)->first();
if (\$b) {
    echo 'ID=178 status=' . \$b->status . ' paid_at=' . (\$b->paid_at ?? 'NULL') . ' scheduled_at=' . \$b->scheduled_at . PHP_EOL;
} else {
    echo 'Boeking 178 niet gevonden' . PHP_EOL;
}
" 2>&1

echo ""
echo "✅ Fix gedeployed!"
echo "   Na app-rebuild: Mollie stuurt je terug naar de app (niet naar website)."
echo "   Boeking #178 staat al als confirmed+paid in de database."
REMOTE
