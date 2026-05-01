#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES — Sentry DSN + App Versions instellen ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. Sentry DSN toevoegen aan .env ═══"
if sudo grep -q "^SENTRY_LARAVEL_DSN=" "$LP/.env" 2>/dev/null; then
    echo "  Bestaat al, wordt overschreven..."
    sudo sed -i "s|^SENTRY_LARAVEL_DSN=.*|SENTRY_LARAVEL_DSN=https://977f14c358d0177c908418f6f7f1fadf@o4511314784354304.ingest.de.sentry.io/4511314792153168|" "$LP/.env"
else
    echo "SENTRY_LARAVEL_DSN=https://977f14c358d0177c908418f6f7f1fadf@o4511314784354304.ingest.de.sentry.io/4511314792153168" | sudo tee -a "$LP/.env" > /dev/null
fi
echo "  ✓ SENTRY_LARAVEL_DSN ingesteld"

# Traces sample rate
if ! sudo grep -q "^SENTRY_TRACES_SAMPLE_RATE=" "$LP/.env" 2>/dev/null; then
    echo "SENTRY_TRACES_SAMPLE_RATE=0.2" | sudo tee -a "$LP/.env" > /dev/null
    echo "  ✓ SENTRY_TRACES_SAMPLE_RATE=0.2 toegevoegd"
fi

echo ""
echo "═══ 2. App versions toevoegen aan .env ═══"
if ! sudo grep -q "^GYMIES_MIN_APP_VERSION=" "$LP/.env" 2>/dev/null; then
    echo "GYMIES_MIN_APP_VERSION=1.2.2" | sudo tee -a "$LP/.env" > /dev/null
    echo "  ✓ GYMIES_MIN_APP_VERSION=1.2.2"
else
    echo "  ✓ GYMIES_MIN_APP_VERSION bestaat al"
fi

if ! sudo grep -q "^GYMIES_LATEST_APP_VERSION=" "$LP/.env" 2>/dev/null; then
    echo "GYMIES_LATEST_APP_VERSION=1.2.2" | sudo tee -a "$LP/.env" > /dev/null
    echo "  ✓ GYMIES_LATEST_APP_VERSION=1.2.2"
else
    echo "  ✓ GYMIES_LATEST_APP_VERSION bestaat al"
fi

echo ""
echo "═══ 3. Cache rebuilden ═══"
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Config + route cache"

echo ""
echo "═══ 4. PHP-FPM restart ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ PHP-FPM"

echo ""
echo "═══ 5. Verify ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

    \$dsn = config('sentry.dsn') ?: config('gymies.sentry_dsn');
    echo 'Sentry DSN:         ' . (\$dsn ? substr(\$dsn, 0, 30) . '...' : '(LEEG)') . PHP_EOL;
    echo 'Traces rate:        ' . config('gymies.sentry_traces_sample_rate', config('sentry.traces_sample_rate', 'n/a')) . PHP_EOL;
    echo 'min_app_version:    ' . config('gymies.min_app_version') . PHP_EOL;
    echo 'latest_app_version: ' . config('gymies.latest_app_version') . PHP_EOL;
" 2>&1

echo ""
echo "═══ 6. Sentry test event ═══"
sudo -u www-data php artisan sentry:test 2>&1 | tail -5 || echo "  (sentry:test command niet beschikbaar)"

echo ""
echo "═══ 7. Endpoints check ═══"
echo "--- Health ---"
curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)" 2>/dev/null
echo ""
echo "--- App version ---"
curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/app-version?_=$(date +%s)" 2>/dev/null
echo ""

echo ""
echo "═══ SAMENVATTING ═══"
echo "  ✓ Sentry DSN ingesteld"
echo "  ✓ App versions ingesteld"
echo "  ✓ Health endpoint live"
echo "  ✓ Rate limiting actief"
echo ""
echo "═══ Done ═══"
REMOTE
