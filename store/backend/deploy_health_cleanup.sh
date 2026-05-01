#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health Cleanup + Test ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
ROUTES="$LP/routes/gymies.php"
cd "$LP"

echo "═══ 1. Verwijder duplicate health routes ═══"
# Verwijder ALLE health/app-version injecties, dan voeg 1x opnieuw toe
sudo sed -i "/\/\/ --- Health check (publiek, geen auth nodig)/d" "$ROUTES"
sudo sed -i "/\/\/ --- App versie check (publiek, geen auth nodig)/d" "$ROUTES"
sudo sed -i "/Route::get('health',.*GymiesHealthController.*'ping'.*'health'/d" "$ROUTES"
sudo sed -i "/Route::get('app-version',.*GymiesHealthController.*'appVersion'.*'app-version'/d" "$ROUTES"
# Verwijder lege regels die overblijven (max 2 achter elkaar)
sudo sed -i '/^$/N;/^\n$/d' "$ROUTES"
echo "  ✓ Alle health/app-version regels verwijderd"

# Voeg 1x toe op juiste plek
sudo sed -i "/Route::prefix('api\/gymies')->name('api.gymies.')->group(function/a\\
\\
    \/\/ --- Health + app-version (publiek) ---\\
    Route::get('health', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'ping'])->name('health');\\
    Route::get('app-version', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesHealthController::class, 'appVersion'])->name('app-version');" "$ROUTES"
echo "  ✓ Health + app-version 1x toegevoegd"

echo ""
echo "═══ 2. Verify: precies 1 health route ═══"
COUNT=$(grep -c "Route::get('health'" "$ROUTES")
echo "  Health route count: $COUNT (moet 1 zijn)"
grep -n "Route::get('health'" "$ROUTES"

echo ""
echo "═══ 3. Rebuild cache ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache"

echo ""
echo "═══ 4. PHP-FPM restart ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ PHP-FPM"

echo ""
echo "═══ 5. Route list (health) ═══"
sudo -u www-data php artisan route:list --path=api/gymies/health 2>&1 | head -10
echo ""
sudo -u www-data php artisan route:list --name=health 2>&1 | head -10

echo ""
echo "═══ 6. Endpoint tests ═══"
echo "--- Test 1: curl met Host header + cache bust ---"
curl -sk -H "Host: gymies.nl" -H "Cache-Control: no-cache" "https://127.0.0.1/api/gymies/health?_=$(date +%s)" 2>/dev/null | head -3
echo ""

echo "--- Test 2: php artisan serve test ---"
# Start een tijdelijke server en test direct via PHP (bypass nginx)
timeout 5 bash -c 'sudo -u www-data php artisan serve --port=9999 &>/dev/null &
sleep 2
RESULT=$(curl -s http://127.0.0.1:9999/api/gymies/health 2>/dev/null)
echo "  PHP direct: $RESULT"
kill %1 2>/dev/null' 2>/dev/null || echo "  (artisan serve test timeout)"

echo ""
echo "--- Test 3: Cloudflare/proxy check ---"
curl -sI https://gymies.nl/api/gymies/health 2>/dev/null | grep -iE "server:|cf-|x-cache|via:|age:" || echo "  (geen proxy headers)"

echo ""
echo "═══ Done ═══"
REMOTE

echo ""
echo "Test extern met cache bust:"
echo "  curl 'https://gymies.nl/api/gymies/health?_=$(date +%s)'"
