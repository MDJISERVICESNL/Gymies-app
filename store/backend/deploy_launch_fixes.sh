#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# GYMIES Launch Fixes Deploy
# Upload rate limit middleware, health route, insights controller
# ═══════════════════════════════════════════════════════════

# --- Configuratie ---
# SSH key + host (uit switch_to_aws.sh / ssh config)
SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

if [ ! -f "$SSH_KEY" ]; then
    echo "❌ SSH key niet gevonden: $SSH_KEY"
    echo "   Geef het pad op: export SSH_KEY=/pad/naar/Amazonekey.pem"
    exit 1
fi
LARAVEL_PATH="/var/www/gymies"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "═══ GYMIES Launch Fixes Deploy ═══"
echo "  Key:    $SSH_KEY"
echo "  Host:   $SSH_HOST"
echo "  Remote: $LARAVEL_PATH"
echo ""

# --- Stap 1: Upload bestanden naar /tmp/ (geen permission issues) ---
echo "📦 Uploading bestanden naar /tmp/..."

scp -i "$SSH_KEY" \
    "$LOCAL_DIR/app/Http/Middleware/GymiesRateLimitMiddleware.php" \
    "$SSH_HOST:/tmp/GymiesRateLimitMiddleware.php"
echo "  ✓ GymiesRateLimitMiddleware.php → /tmp/"

scp -i "$SSH_KEY" \
    "$LOCAL_DIR/scripts/register_gymies_rate_limit_middleware.php" \
    "$SSH_HOST:/tmp/register_gymies_rate_limit_middleware.php"
echo "  ✓ register_gymies_rate_limit_middleware.php → /tmp/"

scp -i "$SSH_KEY" \
    "$LOCAL_DIR/routes_gymies_full.php" \
    "$SSH_HOST:/tmp/routes_gymies_full.php"
echo "  ✓ routes_gymies_full.php → /tmp/"

scp -i "$SSH_KEY" \
    "$LOCAL_DIR/app/Http/Controllers/Gymies/GymiesInsightsController.php" \
    "$SSH_HOST:/tmp/GymiesInsightsController.php"
echo "  ✓ GymiesInsightsController.php → /tmp/"

echo ""

# --- Stap 2: Verplaats bestanden naar juiste locatie + registreer ---
echo "🔧 Bestanden verplaatsen en activeren op server..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
LP="$1"
cd "$LP"

echo ""
echo "═══ 0. Bestanden naar juiste plek (sudo) ═══"
sudo cp /tmp/GymiesRateLimitMiddleware.php "$LP/app/Http/Middleware/GymiesRateLimitMiddleware.php"
sudo chown www-data:www-data "$LP/app/Http/Middleware/GymiesRateLimitMiddleware.php"
echo "  ✓ GymiesRateLimitMiddleware.php"

sudo cp /tmp/register_gymies_rate_limit_middleware.php "$LP/scripts/register_gymies_rate_limit_middleware.php"
sudo chown www-data:www-data "$LP/scripts/register_gymies_rate_limit_middleware.php"
echo "  ✓ register_gymies_rate_limit_middleware.php"

sudo cp /tmp/routes_gymies_full.php "$LP/routes_gymies_full.php"
sudo chown www-data:www-data "$LP/routes_gymies_full.php"
echo "  ✓ routes_gymies_full.php"

sudo cp /tmp/GymiesInsightsController.php "$LP/app/Http/Controllers/Gymies/GymiesInsightsController.php"
sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/GymiesInsightsController.php"
echo "  ✓ GymiesInsightsController.php"

# Opruimen /tmp
rm -f /tmp/GymiesRateLimitMiddleware.php /tmp/register_gymies_rate_limit_middleware.php /tmp/routes_gymies_full.php /tmp/GymiesInsightsController.php
echo "  ✓ /tmp opgeruimd"

echo ""
echo "═══ 1. Rate limit middleware registreren ═══"
php scripts/register_gymies_rate_limit_middleware.php

echo ""
echo "═══ 2. Sentry DSN check ═══"
if grep -q "SENTRY_LARAVEL_DSN" .env 2>/dev/null; then
    DSN=$(grep "SENTRY_LARAVEL_DSN" .env | head -1)
    if [ -z "$(echo "$DSN" | cut -d= -f2)" ]; then
        echo "  ⚠️  SENTRY_LARAVEL_DSN is leeg in .env"
    else
        echo "  ✓ SENTRY_LARAVEL_DSN is gevuld"
    fi
else
    echo "  ⚠️  SENTRY_LARAVEL_DSN niet gevonden in .env"
    echo "     Voeg toe: SENTRY_LARAVEL_DSN=https://xxx@sentry.io/xxx"
fi

echo ""
echo "═══ 3. Min app version check ═══"
if grep -q "GYMIES_MIN_APP_VERSION" .env 2>/dev/null; then
    VER=$(grep "GYMIES_MIN_APP_VERSION" .env | head -1)
    echo "  ✓ $VER"
else
    echo "  ⚠️  GYMIES_MIN_APP_VERSION niet in .env (default 1.0.0)"
    echo "     Overweeg: echo 'GYMIES_MIN_APP_VERSION=1.2.1' >> .env"
fi

echo ""
echo "═══ 4. Config cache herladen ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache 2>/dev/null || php artisan config:cache
sudo -u www-data php artisan route:cache 2>/dev/null || php artisan route:cache 2>/dev/null || true
echo "  ✓ Config + route cache ververst"

echo ""
echo "═══ 5. PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null || echo "  ⚠️  Kon PHP-FPM niet herstarten (handmatig doen)"
echo "  ✓ PHP-FPM herstart"

echo ""
echo "═══ 6. Health endpoint testen ═══"
HEALTH=$(curl -s http://127.0.0.1/api/gymies/health 2>/dev/null || curl -s http://localhost/api/gymies/health 2>/dev/null || echo '{"error":"curl failed"}')
echo "  Response: $HEALTH"

echo ""
echo "═══ 7. Route check (rate limit middleware) ═══"
php artisan route:list --name=trainers.index 2>&1 | head -5 || echo "  ⚠️  Route list check gefaald"

echo ""
echo "═══ Done ═══"
echo "  Alles geüpload en geactiveerd."
echo "  Test extern: curl https://gymies.nl/api/gymies/health"
REMOTE

echo ""
echo "🚀 Deploy compleet!"
echo ""
echo "   Handmatige checks nog nodig:"
echo "   1. curl https://gymies.nl/api/gymies/health"
echo "   2. Sentry DSN vullen als die leeg was"
echo "   3. App Store metadata controleren"
