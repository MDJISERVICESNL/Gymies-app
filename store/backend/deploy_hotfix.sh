#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════
# GYMIES Hotfix Deploy
# Fix: GymiesRefundController + routes namespace fix + log perms
# ═══════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"
LARAVEL_PATH="/var/www/gymies"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "═══ GYMIES Hotfix Deploy ═══"
echo ""

# --- Upload naar /tmp/ ---
echo "📦 Uploading naar /tmp/..."

scp -i "$SSH_KEY" \
    "$LOCAL_DIR/routes_gymies_full.php" \
    "$SSH_HOST:/tmp/routes_gymies_full.php"
echo "  ✓ routes_gymies_full.php (namespace fix)"

scp -i "$SSH_KEY" \
    "$LOCAL_DIR/app/Http/Controllers/Gymies/GymiesRefundController.php" \
    "$SSH_HOST:/tmp/GymiesRefundController.php"
echo "  ✓ GymiesRefundController.php (ontbrak op server)"

echo ""

# --- Fix op server ---
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
LP="$1"
cd "$LP"

echo "═══ 1. Bestanden plaatsen ═══"
sudo cp /tmp/routes_gymies_full.php "$LP/routes_gymies_full.php"
sudo chown www-data:www-data "$LP/routes_gymies_full.php"
echo "  ✓ routes_gymies_full.php"

sudo cp /tmp/GymiesRefundController.php "$LP/app/Http/Controllers/Gymies/GymiesRefundController.php"
sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/GymiesRefundController.php"
echo "  ✓ GymiesRefundController.php"

rm -f /tmp/routes_gymies_full.php /tmp/GymiesRefundController.php

echo ""
echo "═══ 2. Log permissions fixen ═══"
sudo chown -R www-data:www-data "$LP/storage/logs/"
sudo chmod -R 775 "$LP/storage/logs/"
echo "  ✓ storage/logs/ permissions gefixt"

echo ""
echo "═══ 3. Cache herladen ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache 2>/dev/null || php artisan config:cache
sudo -u www-data php artisan route:cache 2>/dev/null || php artisan route:cache 2>/dev/null || true
echo "  ✓ Config + route cache ververst"

echo ""
echo "═══ 4. PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null || echo "  ⚠️  Kon PHP-FPM niet herstarten"
echo "  ✓ PHP-FPM herstart"

echo ""
echo "═══ 5. Health endpoint testen ═══"
HEALTH=$(curl -s http://127.0.0.1/api/gymies/health 2>/dev/null || echo '{"error":"curl failed"}')
echo "  Response: $HEALTH"

echo ""
echo "═══ 6. Route check ═══"
php artisan route:list --name=trainers.index 2>&1 | head -5 || echo "  ⚠️  Route check gefaald"

echo ""
echo "═══ 7. Refund routes check ═══"
php artisan route:list --name=bookings.refund 2>&1 | head -5 || echo "  ⚠️  Refund route check gefaald"

echo ""
echo "═══ Done ═══"
REMOTE

echo ""
echo "🚀 Hotfix deploy compleet!"
echo "   Test: curl https://gymies.nl/api/gymies/health"
