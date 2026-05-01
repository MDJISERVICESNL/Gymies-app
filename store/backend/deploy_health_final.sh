#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health Route — Final Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
ROUTES="$LP/routes/gymies.php"

echo "═══ 1. Verwijder de fout-geïnjecteerde health routes ═══"
# Verwijder de 6 regels die fout zijn ingevoegd (de comments + Route lines)
sudo sed -i '/\/\/ --- App versie check (publiek, geen auth nodig) ---/d' "$ROUTES"
sudo sed -i '/\/\/ --- Health check (publiek, geen auth nodig/d' "$ROUTES"
sudo sed -i "/Route::get('app-version',.*'appVersion'.*'app-version'/d" "$ROUTES"
sudo sed -i "/Route::get('health',.*'ping'.*'health'/d" "$ROUTES"
echo "  ✓ Foute injectie verwijderd"

echo ""
echo "═══ 2. Voeg health route toe op juiste plek ═══"
# Voeg toe DIRECT na de groep-opening: Route::prefix('api/gymies')->name('api.gymies.')->group(function () {
# Dit is regel 15-16 van het bestand. We zoeken de exacte anchor.

sudo -u www-data php -r "
    \$file = '$ROUTES';
    \$lines = file(\$file);
    \$newLines = [];
    \$inserted = false;

    foreach (\$lines as \$i => \$line) {
        \$newLines[] = \$line;

        // Zoek de regel met de prefix group opening
        if (!inserted && strpos(\$line, \"Route::prefix('api/gymies')\") !== false && strpos(\$line, 'group(function') !== false) {
            // Voeg health routes toe als eerste routes in de groep
            \$newLines[] = \"\\n\";
            \$newLines[] = \"    // --- Health check (publiek, geen auth nodig — voor uptime monitoring) ---\\n\";
            \$newLines[] = \"    Route::get('health', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'ping'])->name('health');\\n\";
            \$newLines[] = \"\\n\";
            \$newLines[] = \"    // --- App versie check (publiek, geen auth nodig) ---\\n\";
            \$newLines[] = \"    Route::get('app-version', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'appVersion'])->name('app-version');\\n\";
            \$newLines[] = \"\\n\";
            \$inserted = true;
        }
    }

    if (\$inserted) {
        file_put_contents(\$file, implode('', \$newLines));
        echo \"  ✓ Health + app-version routes ingevoegd na prefix group opening\\n\";
    } else {
        echo \"  ✗ Kon prefix group niet vinden\\n\";
    }
"

echo ""
echo "═══ 3. Verificatie: juiste positie? ═══"
echo "--- Regels rond health route ---"
LINENUM=$(sudo grep -n "Route::get('health'" "$ROUTES" | head -1 | cut -d: -f1)
if [ -n "$LINENUM" ]; then
    START=$((LINENUM - 3))
    END=$((LINENUM + 8))
    sudo sed -n "${START},${END}p" "$ROUTES"
else
    echo "  ✗ Health route niet gevonden!"
fi

echo ""
echo "═══ 4. Cache opnieuw opbouwen ═══"
cd "$LP"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache ververst"

echo ""
echo "═══ 5. PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ PHP-FPM herstart"

echo ""
echo "═══ 6. Route cache check ═══"
sudo -u www-data php -r "
    \$cachePath = '$LP/bootstrap/cache/routes-v7.php';
    \$cached = file_get_contents(\$cachePath);
    echo (strpos(\$cached, 'api/gymies/health') !== false) ? '  ✓ api/gymies/health ZIT in route cache' : '  ✗ api/gymies/health NIET in route cache';
    echo PHP_EOL;
    echo (strpos(\$cached, 'app-version') !== false) ? '  ✓ app-version ZIT in route cache' : '  ✗ app-version NIET in route cache';
    echo PHP_EOL;
"

echo ""
echo "═══ 7. Route list check ═══"
sudo -u www-data php artisan route:list --path=api/gymies/health 2>&1 | head -10
echo ""
sudo -u www-data php artisan route:list --path=api/gymies/app-version 2>&1 | head -10

echo ""
echo "═══ 8. Health endpoint testen ═══"
HEALTH=$(curl -sk -H "Host: gymies.nl" https://127.0.0.1/api/gymies/health 2>/dev/null || echo '{"error":"curl failed"}')
echo "  Response: $HEALTH"

echo ""
echo "═══ Done ═══"
REMOTE

echo ""
echo "🚀 Final fix compleet!"
echo "   Test: curl https://gymies.nl/api/gymies/health"
