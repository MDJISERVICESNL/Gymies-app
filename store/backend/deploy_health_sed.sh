#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health Route — sed fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
ROUTES="$LP/routes/gymies.php"
cd "$LP"

echo "═══ 1. Backup ═══"
sudo cp "$ROUTES" "$ROUTES.bak_before_sed"
echo "  ✓ Backup"

echo ""
echo "═══ 2. Voeg health route toe met sed ═══"
# Voeg 4 regels toe NA de regel die "Route::prefix('api/gymies')" bevat
sudo sed -i "/Route::prefix('api\/gymies')->name('api.gymies.')->group(function/a\\
\\
    \/\/ --- Health check (publiek, geen auth nodig) ---\\
    Route::get('health', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'ping'])->name('health');\\
\\
    \/\/ --- App versie check (publiek, geen auth nodig) ---\\
    Route::get('app-version', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'appVersion'])->name('app-version');" "$ROUTES"

echo "  ✓ Routes ingevoegd"

echo ""
echo "═══ 3. Verificatie: juiste positie ═══"
grep -n "health\|app-version\|prefix.*api/gymies" "$ROUTES" | head -15

echo ""
echo "═══ 4. Cache opbouwen ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache"

echo ""
echo "═══ 5. PHP-FPM restart ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ PHP-FPM"

echo ""
echo "═══ 6. Route cache check ═══"
sudo -u www-data php -r "
    \$c = file_get_contents('$LP/bootstrap/cache/routes-v7.php');
    echo (strpos(\$c, 'api/gymies/health') !== false) ? '  ✓ health IN cache' : '  ✗ health NIET in cache';
    echo PHP_EOL;
    echo (strpos(\$c, 'app-version') !== false) ? '  ✓ app-version IN cache' : '  ✗ app-version NIET in cache';
    echo PHP_EOL;
"

echo ""
echo "═══ 7. Test ═══"
curl -sk -H "Host: gymies.nl" https://127.0.0.1/api/gymies/health 2>/dev/null | head -5
echo ""
echo "═══ Done ═══"
REMOTE

echo ""
echo "🚀 Test: curl https://gymies.nl/api/gymies/health"
