#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health — Trainers Table Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
CTRL="$LP/app/Http/Controllers/Gymies/GymiesHealthController.php"
cd "$LP"

echo "═══ 1. Fix: gymies_trainers → gymies_trainer_profiles ═══"
sudo sed -i "s/'gymies_trainers'/'gymies_trainer_profiles'/g" "$CTRL"
echo "  ✓ Tabelnaam gewijzigd"

echo ""
echo "═══ 2. Verify ═══"
sudo grep -n "gymies_trainer" "$CTRL" | grep -i "tables\|hasTable\|kerntabel" | head -5
sudo grep -A 3 "tables = \[" "$CTRL" | head -5
echo ""

echo "═══ 3. Cache + restart ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ Cache + PHP-FPM"
echo ""

echo "═══ 4. Health endpoint test ═══"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)")
BODY=$(curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)" 2>/dev/null)
echo "  HTTP status: $HTTP_CODE"
echo "  Body: $BODY"
echo ""

echo "═══ 5. Extern test ═══"
EXT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://gymies.nl/api/gymies/health?_=$(date +%s)" 2>/dev/null)
EXT_BODY=$(curl -s "https://gymies.nl/api/gymies/health?_=$(date +%s)" 2>/dev/null)
echo "  Extern HTTP: $EXT_CODE"
echo "  Extern Body: $EXT_BODY"

echo ""
echo "═══ Done ═══"
REMOTE
