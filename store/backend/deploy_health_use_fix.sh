#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health Controller — Use Statement Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
CTRL="$LP/app/Http/Controllers/Gymies/GymiesHealthController.php"
cd "$LP"

echo "═══ 1. Huidige use statements ═══"
sudo head -15 "$CTRL"
echo ""

echo "═══ 2. Fix: voeg use Controller toe ═══"
# Voeg 'use App\Http\Controllers\Controller;' toe na de namespace regel
# Check eerst of het al bestaat
if sudo grep -q "use App\\\\Http\\\\Controllers\\\\Controller;" "$CTRL"; then
    echo "  ✓ use statement bestaat al"
else
    sudo sed -i '/^namespace App\\Http\\Controllers\\Gymies;/a\\nuse App\\Http\\Controllers\\Controller;' "$CTRL"
    echo "  ✓ use App\\Http\\Controllers\\Controller; toegevoegd"
fi
echo ""

echo "═══ 3. Verify top van bestand ═══"
sudo head -15 "$CTRL"
echo ""

echo "═══ 4. Syntax check ═══"
sudo -u www-data php -l "$CTRL" 2>&1
echo ""

echo "═══ 5. Composer dump-autoload ═══"
sudo -u www-data composer dump-autoload --optimize 2>&1 | tail -3
echo ""

echo "═══ 6. Cache rebuild ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache"
echo ""

echo "═══ 7. PHP-FPM restart ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ PHP-FPM"
echo ""

echo "═══ 8. Route list check ═══"
sudo -u www-data php artisan route:list --path=api/gymies/health 2>&1 | head -10
echo ""

echo "═══ 9. Health endpoint test ═══"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)")
BODY=$(curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)" 2>/dev/null)
echo "  HTTP status: $HTTP_CODE"
echo "  Body: $BODY"
echo ""

echo "═══ Done ═══"
REMOTE

echo ""
echo "Test extern:"
echo "  curl 'https://gymies.nl/api/gymies/health?_=$(date +%s)'"
