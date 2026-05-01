#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health Controller — Namespace Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
CTRL="$LP/app/Http/Controllers/Gymies/GymiesHealthController.php"
cd "$LP"

echo "═══ 1. Huidige namespace in controller ═══"
sudo grep -n "^namespace " "$CTRL" || echo "  (geen namespace gevonden)"
echo ""

echo "═══ 2. Check op duplicate controller bestanden ═══"
echo "--- In Controllers/ (root, FOUT) ---"
ls -la "$LP/app/Http/Controllers/GymiesHealthController.php" 2>/dev/null && echo "  ⚠️  DUPLICATE GEVONDEN!" || echo "  ✓ Geen duplicate in Controllers/"
echo "--- In Controllers/Gymies/ (correct) ---"
ls -la "$CTRL" 2>/dev/null || echo "  ✗ Controller niet gevonden!"
echo ""

echo "═══ 3. Fix namespace ═══"
# Backup
sudo cp "$CTRL" "$CTRL.bak_namespace_$(date +%Y%m%d_%H%M%S)"

# Fix: vervang foutieve namespace door correcte
sudo sed -i 's/^namespace App\\Http\\Controllers;/namespace App\\Http\\Controllers\\Gymies;/' "$CTRL"
echo "  ✓ Namespace gewijzigd"

# Verifieer
echo "--- Nieuwe namespace ---"
sudo grep -n "^namespace " "$CTRL"
echo ""

echo "═══ 4. Verwijder eventuele duplicate controller ═══"
if [ -f "$LP/app/Http/Controllers/GymiesHealthController.php" ]; then
    sudo rm "$LP/app/Http/Controllers/GymiesHealthController.php"
    echo "  ✓ Duplicate verwijderd uit Controllers/"
else
    echo "  ✓ Geen duplicate te verwijderen"
fi
echo ""

echo "═══ 5. Composer dump-autoload ═══"
cd "$LP"
sudo -u www-data composer dump-autoload --optimize 2>&1 | tail -5
echo "  ✓ Autoload"
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

echo "═══ 8. Syntax check controller ═══"
sudo -u www-data php -l "$CTRL" 2>&1
echo ""

echo "═══ 9. Route list check ═══"
sudo -u www-data php artisan route:list --path=api/gymies/health 2>&1 | head -10
echo ""

echo "═══ 10. Health endpoint test ═══"
echo "--- Via nginx (127.0.0.1) ---"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)")
BODY=$(curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)" 2>/dev/null)
echo "  HTTP status: $HTTP_CODE"
echo "  Body: $BODY"
echo ""

echo "--- Via artisan serve (bypass nginx) ---"
timeout 8 bash -c '
    sudo -u www-data php artisan serve --port=9999 &>/dev/null &
    PID=$!
    sleep 3
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9999/api/gymies/health 2>/dev/null)
    BODY=$(curl -s http://127.0.0.1:9999/api/gymies/health 2>/dev/null)
    echo "  HTTP status: $HTTP_CODE"
    echo "  Body: $BODY"
    kill $PID 2>/dev/null
' 2>/dev/null || echo "  (artisan serve timeout)"

echo ""
echo "═══ Done ═══"
REMOTE

echo ""
echo "Test extern:"
echo "  curl 'https://gymies.nl/api/gymies/health?_=$(date +%s)'"
