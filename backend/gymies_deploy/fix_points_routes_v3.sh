#!/bin/bash
set -e
cd /var/www/gymies

ROUTES="/var/www/gymies/gymies_deploy/routes_gymies_full.php"

echo "▸ Fixing permissions..."
sudo chmod 664 "$ROUTES"
sudo chown www-data:www-data "$ROUTES" 2>/dev/null || true

echo "▸ Patching routes..."

if grep -q "points/balance" "$ROUTES" 2>/dev/null; then
    echo "  ⏭️ Points routes bestaan al"
else
    # Gebruik sudo tee voor schrijfrechten
    cp "$ROUTES" /tmp/routes_backup.php

    php -r "
\$file = '/tmp/routes_backup.php';
\$content = file_get_contents(\$file);

\$pos = strpos(\$content, 'referral');
if (\$pos === false) {
    \$pos = strpos(\$content, 'bookings');
}
if (\$pos !== false) {
    \$lineEnd = strpos(\$content, \"\\n\", \$pos);
    \$routes = \"\\n\" .
        \"        // Gymies Punten: saldo, geschiedenis, inwisselen\\n\" .
        \"        Route::get('points/balance', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'balance'])->name('points.balance');\\n\" .
        \"        Route::get('points/history', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'history'])->name('points.history');\\n\" .
        \"        Route::post('points/redeem', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'redeem'])->name('points.redeem');\\n\";
    \$content = substr(\$content, 0, \$lineEnd + 1) . \$routes . substr(\$content, \$lineEnd + 1);
    file_put_contents(\$file, \$content);
    echo \"  ✅ Routes gepatcht\\n\";
} else {
    echo \"  ❌ Geen marker gevonden\\n\";
}
"

    sudo cp /tmp/routes_backup.php "$ROUTES"
    sudo chown www-data:www-data "$ROUTES" 2>/dev/null || true
    rm -f /tmp/routes_backup.php
    echo "  ✅ Bestand geschreven"
fi

echo "▸ Caches legen..."
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true

echo "▸ Verificatie..."
php artisan tinker --execute="
\$has = \Illuminate\Support\Facades\Route::has('api.gymies.points.balance');
echo \$has ? '✅ Points routes actief!' : '❌ Route NIET gevonden';
echo \"\n\";
if (\$has) {
    \$routes = collect(\Illuminate\Support\Facades\Route::getRoutes())->filter(fn(\$r) => str_contains(\$r->uri(), 'points'));
    foreach (\$routes as \$r) echo '  ' . \$r->methods()[0] . ' ' . \$r->uri() . \"\n\";
}
"
