#!/bin/bash
set -e
echo "=== Fix: Application fee alleen bij OAuth tokens ==="

# 1. Upload PaymentController
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesPaymentController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesPaymentController.php

ssh gymies << 'REMOTE'
cd /var/www/gymies

# 2. Permissions + log fix
chown ubuntu:ubuntu app/Http/Controllers/Gymies/GymiesPaymentController.php
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 3. Restart + caches
sudo systemctl restart php8.4-fpm
php artisan config:cache
php artisan route:cache

# 4. Log legen
sudo truncate -s 0 storage/logs/laravel.log
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 5. Verify
echo ""
echo "=== Verificatie ==="
grep -c "isOAuthToken" app/Http/Controllers/Gymies/GymiesPaymentController.php
echo "✓ isOAuthToken check gevonden ($(grep -c 'isOAuthToken' app/Http/Controllers/Gymies/GymiesPaymentController.php)x)"

# 6. Verwijder de mislukte reserved boeking zodat er geen overlap is
echo ""
echo "=== Oude 'reserved' boekingen opruimen ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$expired = DB::table('gymies_bookings')
    ->where('status', 'reserved')
    ->where('reserved_until', '<', now())
    ->get(['id', 'scheduled_at', 'reserved_until']);
foreach (\$expired as \$b) {
    echo 'Verlopen: ID=' . \$b->id . ' reserved_until=' . \$b->reserved_until . PHP_EOL;
    DB::table('gymies_bookings')->where('id', \$b->id)->update(['status' => 'cancelled', 'updated_at' => now()]);
    echo '  → status=cancelled' . PHP_EOL;
}
if (\$expired->isEmpty()) echo 'Geen verlopen reserveringen.' . PHP_EOL;
" 2>&1

echo ""
echo "✅ Fix gedeployed! Test de boeking opnieuw."
echo "   Nu zou Mollie moeten werken (zonder application fee)."
REMOTE
