#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES — App Version .env Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. Check huidige .env inhoud ═══"
sudo grep -n "GYMIES_MIN\|GYMIES_LATEST\|SENTRY" "$LP/.env" 2>/dev/null
echo ""

echo "═══ 2. Check config/gymies.php voor env keys ═══"
sudo grep -n "min_app_version\|latest_app_version" "$LP/config/gymies.php" 2>/dev/null || echo "  (niet gevonden in config/gymies.php)"
echo ""

echo "═══ 3. Force clear + rebuild ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
# Wacht even tot alles opgeruimd is
sleep 1
sudo -u www-data php artisan config:cache
echo "  ✓ Config cache"
echo ""

echo "═══ 4. Verify via PHP ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo 'min_app_version:    [' . config('gymies.min_app_version', 'FALLBACK') . ']' . PHP_EOL;
    echo 'latest_app_version: [' . config('gymies.latest_app_version', 'FALLBACK') . ']' . PHP_EOL;
    // Check of de env direct leesbaar is (buiten cache)
    echo 'Direct env MIN:     [' . env('GYMIES_MIN_APP_VERSION', 'NOT SET') . ']' . PHP_EOL;
    echo 'Direct env LATEST:  [' . env('GYMIES_LATEST_APP_VERSION', 'NOT SET') . ']' . PHP_EOL;
" 2>&1
echo ""

echo "═══ 5. Route cache rebuild ═══"
sudo -u www-data php artisan route:cache
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ Route cache + PHP-FPM"
echo ""

echo "═══ 6. app-version endpoint ═══"
curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/app-version?_=$(date +%s)" 2>/dev/null
echo ""

echo ""
echo "═══ Done ═══"
REMOTE
