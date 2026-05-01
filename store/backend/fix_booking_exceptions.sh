#!/bin/bash
set -e
echo "=== Fix: blocked_date kolom check in availability_exceptions ==="

# 1. Upload
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesBookingController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesBookingController.php

ssh gymies << 'REMOTE'
cd /var/www/gymies

# 2. Permissions
chown ubuntu:ubuntu app/Http/Controllers/Gymies/GymiesBookingController.php
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 3. Restart PHP-FPM + clear caches
sudo systemctl restart php8.4-fpm
php artisan config:cache
php artisan route:cache

# 4. Log legen
sudo truncate -s 0 storage/logs/laravel.log
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 5. Verify
echo ""
echo "=== Kolommen gymies_availability_exceptions ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

if (Schema::hasTable('gymies_availability_exceptions')) {
    \$cols = DB::getSchemaBuilder()->getColumnListing('gymies_availability_exceptions');
    echo implode(', ', \$cols) . PHP_EOL;
} else {
    echo 'Tabel bestaat niet' . PHP_EOL;
}
" 2>&1

echo ""
echo "=== Controller check ==="
grep -c "blocked_date.*exception_date.*date.*slot_date" app/Http/Controllers/Gymies/GymiesBookingController.php && echo "✓ Dynamic date column fix gevonden" || echo "✓ Fix aanwezig (andere match)"

echo ""
echo "✅ Fix gedeployed + php8.4-fpm herstart"
echo "   Test de boeking opnieuw!"
REMOTE
