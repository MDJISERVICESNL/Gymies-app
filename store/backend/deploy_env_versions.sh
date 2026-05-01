#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES .env — App Versions instellen ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. App version variabelen toevoegen aan .env ═══"

# GYMIES_MIN_APP_VERSION
if sudo grep -q "^GYMIES_MIN_APP_VERSION=" "$LP/.env" 2>/dev/null; then
    echo "  GYMIES_MIN_APP_VERSION bestaat al:"
    sudo grep "^GYMIES_MIN_APP_VERSION=" "$LP/.env"
else
    echo "GYMIES_MIN_APP_VERSION=1.0.0" | sudo tee -a "$LP/.env" > /dev/null
    echo "  ✓ GYMIES_MIN_APP_VERSION=1.0.0 toegevoegd"
fi

# GYMIES_LATEST_APP_VERSION
if sudo grep -q "^GYMIES_LATEST_APP_VERSION=" "$LP/.env" 2>/dev/null; then
    echo "  GYMIES_LATEST_APP_VERSION bestaat al:"
    sudo grep "^GYMIES_LATEST_APP_VERSION=" "$LP/.env"
else
    echo "GYMIES_LATEST_APP_VERSION=1.0.0" | sudo tee -a "$LP/.env" > /dev/null
    echo "  ✓ GYMIES_LATEST_APP_VERSION=1.0.0 toegevoegd"
fi

echo ""
echo "═══ 2. Cache rebuilden ═══"
sudo -u www-data php artisan config:cache
echo "  ✓ Config cache"
echo ""

echo "═══ 3. Verify via config ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo 'min_app_version:    ' . config('gymies.min_app_version') . PHP_EOL;
    echo 'latest_app_version: ' . config('gymies.latest_app_version') . PHP_EOL;
" 2>&1
echo ""

echo "═══ 4. app-version endpoint test ═══"
APPVER=$(curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/app-version?_=$(date +%s)" 2>/dev/null)
echo "  $APPVER"
echo ""

echo "═══ Done ═══"
REMOTE
