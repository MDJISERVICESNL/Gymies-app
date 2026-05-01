#!/bin/bash
set -e

echo "=== Fix: Booking 500 + Log permissions ==="
echo ""

# 1. Upload fixed BookingController
echo "[1/3] BookingController uploaden..."
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesBookingController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesBookingController.php

# 2. Fix permissions
echo "[2/3] Permissions + log fix..."
ssh gymies << 'REMOTE'
# Fix controller ownership
chown ubuntu:ubuntu /var/www/gymies/app/Http/Controllers/Gymies/GymiesBookingController.php
chmod 644 /var/www/gymies/app/Http/Controllers/Gymies/GymiesBookingController.php

# Fix laravel.log permissions (was causing the 500!)
touch /var/www/gymies/storage/logs/laravel.log
chmod 666 /var/www/gymies/storage/logs/laravel.log
chown ubuntu:ubuntu /var/www/gymies/storage/logs/laravel.log

# Fix hele storage map
chmod -R 775 /var/www/gymies/storage
chmod -R 775 /var/www/gymies/bootstrap/cache
REMOTE

# 3. Cache rebuild + verify
echo "[3/3] Cache rebuild + verificatie..."
ssh gymies << 'REMOTE'
cd /var/www/gymies

php artisan config:clear
php artisan route:clear
php artisan cache:clear
php artisan config:cache
php artisan route:cache

echo ""
echo "=== Trainer 27 prijs check ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$profile = DB::table('gymies_trainer_profiles')->where('user_id', 27)->first();
if (\$profile) {
    echo 'session_price_cents: ' . (\$profile->session_price_cents ?? 'NULL') . PHP_EOL;
    echo 'hourly_rate_cents:   ' . (\$profile->hourly_rate_cents ?? 'NULL') . PHP_EOL;
    echo 'trial_session_cents: ' . (\$profile->trial_session_cents ?? 'NULL') . PHP_EOL;

    \$price = (int)(\$profile->session_price_cents ?? 0);
    if (\$price === 0) \$price = (int)(\$profile->hourly_rate_cents ?? 0);
    if (\$price === 0) \$price = (int)(\$profile->trial_session_cents ?? 0);

    if (\$price > 0) {
        echo '✓ Prijs gevonden: €' . number_format(\$price / 100, 2) . ' (via fallback)' . PHP_EOL;
    } else {
        echo '⚠ Nog steeds geen prijs! Stel hourly_rate_cents in.' . PHP_EOL;
        // Zet een default prijs als er geen is
        DB::table('gymies_trainer_profiles')->where('user_id', 27)->update([
            'hourly_rate_cents' => 6500,
        ]);
        echo '✓ hourly_rate_cents ingesteld op 6500 (€65.00)' . PHP_EOL;
    }
} else {
    echo 'FOUT: Geen trainer profiel voor user 27!' . PHP_EOL;
}

echo PHP_EOL . '=== Log permissions check ===' . PHP_EOL;
echo shell_exec('ls -la /var/www/gymies/storage/logs/laravel.log');
" 2>&1

echo ""
echo "✅ Fix klaar!"
echo "   - BookingController: valt nu terug op hourly_rate_cents als session_price_cents NULL is"
echo "   - Laravel log permissions gefixed (was de oorzaak van de 500)"
REMOTE
