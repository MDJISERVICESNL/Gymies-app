#!/bin/bash
set -e
echo "=== Fix: is_active kolom check in availability slots ==="

# Upload
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesBookingController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesBookingController.php

ssh gymies << 'REMOTE'
cd /var/www/gymies

# Permissions
chown ubuntu:ubuntu app/Http/Controllers/Gymies/GymiesBookingController.php

# Restart juiste PHP-FPM
sudo systemctl restart php8.4-fpm

# Cache rebuild
php artisan config:cache
php artisan route:cache

echo ""
echo "=== Kolommen gymies_availability_slots ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$cols = DB::getSchemaBuilder()->getColumnListing('gymies_availability_slots');
echo implode(', ', \$cols) . PHP_EOL;
echo 'is_active kolom: ' . (in_array('is_active', \$cols) ? 'JA' : 'NEE') . PHP_EOL;
" 2>&1

echo ""
echo "✅ Fix gedeployed + php8.4-fpm herstart"
echo "   Test de boeking opnieuw!"
REMOTE
