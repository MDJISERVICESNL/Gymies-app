#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# GYMIES Full Sync Deploy
# Upload ALLE controllers + routes + middleware naar server
# ═══════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"
LARAVEL_PATH="/var/www/gymies"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "═══ GYMIES Full Sync Deploy ═══"
echo ""

# --- Stap 1: Upload ALLE Gymies controllers als tar naar /tmp ---
echo "📦 Stap 1: Alle controllers + bestanden inpakken..."

# Maak een tijdelijke tar van alle bestanden die we nodig hebben
cd "$LOCAL_DIR"
tar czf /tmp/gymies_deploy.tar.gz \
    app/Http/Controllers/Gymies/ \
    app/Http/Middleware/GymiesRateLimitMiddleware.php \
    routes_gymies_full.php \
    scripts/register_gymies_rate_limit_middleware.php

FILE_COUNT=$(tar tzf /tmp/gymies_deploy.tar.gz | wc -l | tr -d ' ')
echo "  ✓ $FILE_COUNT bestanden ingepakt"

echo ""
echo "📤 Stap 2: Uploading tar naar server..."
scp -i "$SSH_KEY" /tmp/gymies_deploy.tar.gz "$SSH_HOST:/tmp/gymies_deploy.tar.gz"
echo "  ✓ Upload compleet"
rm -f /tmp/gymies_deploy.tar.gz

echo ""
echo "🔧 Stap 3: Uitpakken + permissions + cache op server..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
LP="$1"

echo ""
echo "═══ 1. Bestanden uitpakken naar $LP ═══"
cd "$LP"
sudo tar xzf /tmp/gymies_deploy.tar.gz -C "$LP" --no-same-owner
rm -f /tmp/gymies_deploy.tar.gz
echo "  ✓ Alle bestanden uitgepakt"

echo ""
echo "═══ 2. Permissions fixen (ALLES) ═══"
# Directories: 755, Files: 644, eigenaar: www-data
sudo find "$LP/app/Http/Controllers/Gymies/" -type d -exec chmod 755 {} \;
sudo find "$LP/app/Http/Controllers/Gymies/" -type f -exec chmod 644 {} \;
sudo chown -R www-data:www-data "$LP/app/Http/Controllers/Gymies/"

sudo chmod 644 "$LP/routes_gymies_full.php"
sudo chown www-data:www-data "$LP/routes_gymies_full.php"

sudo chmod 644 "$LP/app/Http/Middleware/GymiesRateLimitMiddleware.php"
sudo chown www-data:www-data "$LP/app/Http/Middleware/GymiesRateLimitMiddleware.php"

sudo mkdir -p "$LP/scripts"
sudo chmod 644 "$LP/scripts/register_gymies_rate_limit_middleware.php"
sudo chown www-data:www-data "$LP/scripts/register_gymies_rate_limit_middleware.php"

# Storage/logs altijd writable
sudo chown -R www-data:www-data "$LP/storage/"
sudo chmod -R 775 "$LP/storage/"
echo "  ✓ Alle permissions correct"

echo ""
echo "═══ 3. Cache opnieuw opbouwen (als www-data) ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Config + route cache ververst"

echo ""
echo "═══ 4. PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || \
sudo systemctl restart php8.3-fpm 2>/dev/null || \
sudo systemctl restart php8.2-fpm 2>/dev/null || \
echo "  ⚠️  Kon PHP-FPM niet herstarten"
echo "  ✓ PHP-FPM herstart"

echo ""
echo "═══ 5. Route list check (als www-data) ═══"
echo "--- Health route ---"
sudo -u www-data php artisan route:list --name=health 2>&1 | head -10
echo ""
echo "--- Refund routes ---"
sudo -u www-data php artisan route:list --name=refund 2>&1 | head -5
echo ""
echo "--- Trainer routes ---"
sudo -u www-data php artisan route:list --name=trainers.index 2>&1 | head -5

echo ""
echo "═══ 6. Health endpoint testen ═══"
# Test met juiste Host header (nginx luistert op gymies.nl, niet 127.0.0.1)
HEALTH=$(curl -s -H "Host: gymies.nl" http://127.0.0.1/api/gymies/health 2>/dev/null || echo '{"error":"curl failed"}')
echo "  Response: $HEALTH"

echo ""
echo "═══ 7. Nginx config check ═══"
echo "--- gymies.nl config (root + location) ---"
sudo cat /etc/nginx/sites-available/gymies.nl 2>/dev/null | grep -E "root|location|try_files|fastcgi|server_name|index" | head -20
echo ""

echo "═══ 8. Sentry + min version check ═══"
if grep -q "SENTRY_LARAVEL_DSN" "$LP/.env" 2>/dev/null; then
    DSN=$(grep "SENTRY_LARAVEL_DSN" "$LP/.env" | head -1)
    if [ -z "$(echo "$DSN" | cut -d= -f2)" ]; then
        echo "  ⚠️  SENTRY_LARAVEL_DSN is leeg"
    else
        echo "  ✓ SENTRY_LARAVEL_DSN gevuld"
    fi
else
    echo "  ⚠️  SENTRY_LARAVEL_DSN niet in .env"
fi

if grep -q "GYMIES_MIN_APP_VERSION" "$LP/.env" 2>/dev/null; then
    echo "  ✓ $(grep 'GYMIES_MIN_APP_VERSION' "$LP/.env" | head -1)"
else
    echo "  ⚠️  GYMIES_MIN_APP_VERSION niet in .env"
fi

echo ""
echo "═══ Done ═══"
REMOTE

echo ""
echo "🚀 Full sync deploy compleet!"
echo "   Test extern: curl https://gymies.nl/api/gymies/health"
