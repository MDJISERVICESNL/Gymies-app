#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health Route Inject ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
ROUTES="$LP/routes/gymies.php"

echo "═══ 1. Check of health route al bestaat ═══"
if sudo grep -q "Route::get('health'" "$ROUTES" 2>/dev/null; then
    echo "  ✓ Health route bestaat al in routes/gymies.php — niets te doen"
else
    echo "  ✗ Health route ontbreekt — wordt nu toegevoegd"

    # Zoek een ankerpunt: de auth/reset-password route of de eerste Route::get na de auth groep
    # We voegen de health + app-version routes toe NA de auth sectie

    # Maak een backup
    sudo cp "$ROUTES" "$ROUTES.bak_$(date +%Y%m%d_%H%M%S)"
    echo "  ✓ Backup gemaakt"

    # Gebruik PHP om de route veilig in te voegen
    sudo -u www-data php -r "
        \$file = '$ROUTES';
        \$content = file_get_contents(\$file);

        // Zoek een ankerpunt: auth/reset-password closing bracket
        // We voegen toe na de laatste auth rate-limit groep
        \$anchor = \"Route::post('auth/reset-password'\";
        \$pos = strpos(\$content, \$anchor);

        if (\$pos === false) {
            echo \"  ⚠️  Ankerpunt niet gevonden. Probeer alternatief...\\n\";
            // Alternatief: zoek na auth/forgot-password
            \$anchor = \"Route::post('auth/forgot-password'\";
            \$pos = strpos(\$content, \$anchor);
        }

        if (\$pos !== false) {
            // Zoek het einde van de rate-limit groep (de }); na het ankerpunt)
            \$searchFrom = \$pos;
            // Zoek de volgende 2x }); om uit de Route + middleware groep te komen
            \$endPos = strpos(\$content, '});', \$searchFrom);
            if (\$endPos !== false) {
                \$endPos = strpos(\$content, '});', \$endPos + 3);
            }

            if (\$endPos !== false) {
                \$insertAt = \$endPos + 3; // Na de });
                \$newRoutes = \"\\n\\n    // --- App versie check (publiek, geen auth nodig) ---\\n    Route::get('app-version', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'appVersion'])->name('app-version');\\n\\n    // --- Health check (publiek, geen auth nodig — voor uptime monitoring / load balancers) ---\\n    Route::get('health', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'ping'])->name('health');\\n\";

                \$newContent = substr(\$content, 0, \$insertAt) . \$newRoutes . substr(\$content, \$insertAt);
                file_put_contents(\$file, \$newContent);
                echo \"  ✓ Health + app-version routes toegevoegd\\n\";
            } else {
                echo \"  ✗ Kon einde van auth groep niet vinden\\n\";
            }
        } else {
            echo \"  ✗ Geen ankerpunt gevonden — voeg handmatig toe\\n\";
        }
    "
fi

echo ""
echo "═══ 2. Verificatie: health route in bestand? ═══"
if sudo grep -q "Route::get('health'" "$ROUTES"; then
    echo "  ✓ Health route gevonden in routes/gymies.php"
    sudo grep -n "health\|app-version" "$ROUTES" | head -10
else
    echo "  ✗ Health route NIET gevonden — handmatige actie nodig"
fi

echo ""
echo "═══ 3. Cache herladen ═══"
cd "$LP"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache ververst"

echo ""
echo "═══ 4. PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ PHP-FPM herstart"

echo ""
echo "═══ 5. Route list check ═══"
sudo -u www-data php artisan route:list --path=api/gymies/health 2>&1 | head -10
echo ""
sudo -u www-data php artisan route:list --path=api/gymies/app-version 2>&1 | head -10

echo ""
echo "═══ 6. Health endpoint testen ═══"
HEALTH=$(curl -sk -H "Host: gymies.nl" https://127.0.0.1/api/gymies/health 2>/dev/null || curl -s -H "Host: gymies.nl" http://127.0.0.1/api/gymies/health 2>/dev/null || echo '{"error":"curl failed"}')
echo "  Response: $HEALTH"

echo ""
echo "═══ Done ═══"
REMOTE

echo ""
echo "🚀 Health route inject compleet!"
echo "   Test: curl https://gymies.nl/api/gymies/health"
