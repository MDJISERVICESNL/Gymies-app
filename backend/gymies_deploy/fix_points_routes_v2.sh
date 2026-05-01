#!/bin/bash
# Fix: voeg points routes toe aan gymies_deploy/routes_gymies_full.php op server
# Run: ssh gymies "bash -s" < backend/gymies_deploy/fix_points_routes_v2.sh
set -e
cd /var/www/gymies

ROUTES="/var/www/gymies/gymies_deploy/routes_gymies_full.php"

echo "▸ Patching $ROUTES ..."

if grep -q "points/balance" "$ROUTES" 2>/dev/null; then
    echo "  ⏭️ Points routes bestaan al"
else
    php -r "
\$file = '$ROUTES';
\$content = file_get_contents(\$file);

// Zoek 'referral' in het bestand
\$markers = ['referral', 'conversations', 'bookings/standby', 'trainer/summary'];
\$inserted = false;

foreach (\$markers as \$marker) {
    \$pos = strpos(\$content, \$marker);
    if (\$pos === false) continue;

    // Vind het einde van die regel
    \$lineEnd = strpos(\$content, \"\\n\", \$pos);
    if (\$lineEnd === false) continue;

    \$routes = \"\\n\" .
        \"        // Gymies Punten: saldo, geschiedenis, inwisselen\\n\" .
        \"        Route::get('points/balance', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'balance'])->name('points.balance');\\n\" .
        \"        Route::get('points/history', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'history'])->name('points.history');\\n\" .
        \"        Route::post('points/redeem', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'redeem'])->name('points.redeem');\\n\";

    \$content = substr(\$content, 0, \$lineEnd + 1) . \$routes . substr(\$content, \$lineEnd + 1);
    file_put_contents(\$file, \$content);
    echo \"  ✅ Points routes toegevoegd na '\$marker'\\n\";
    \$inserted = true;
    break;
}

if (!\$inserted) {
    echo \"  ❌ Geen marker gevonden\\n\";
}
"
fi

# Cache legen
echo "▸ Caches legen..."
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

# Verificatie
echo "▸ Verificatie..."
php artisan tinker --execute="
\$has = \Illuminate\Support\Facades\Route::has('api.gymies.points.balance');
echo \$has ? '✅ Route points/balance actief!' : '❌ Route NIET gevonden';
echo \"\n\";
"
