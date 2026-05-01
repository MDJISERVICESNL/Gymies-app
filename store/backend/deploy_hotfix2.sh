#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Hotfix 2 — Diagnose + Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"

echo "═══ 1. Diagnose: nginx config ═══"
echo "--- Enabled sites ---"
ls -la /etc/nginx/sites-enabled/ 2>/dev/null || echo "  geen sites-enabled"
echo ""
echo "--- Relevante nginx config (server block) ---"
sudo grep -r "gymies\|root\|location\|try_files\|fastcgi_pass\|index.php" /etc/nginx/sites-enabled/ 2>/dev/null | head -40
echo ""

echo "═══ 2. Diagnose: bestandspermissies ═══"
echo "--- RefundController ---"
ls -la "$LP/app/Http/Controllers/Gymies/GymiesRefundController.php" 2>/dev/null || echo "  NIET GEVONDEN"
echo "--- routes_gymies_full.php ---"
ls -la "$LP/routes_gymies_full.php" 2>/dev/null || echo "  NIET GEVONDEN"
echo "--- storage/logs ---"
ls -la "$LP/storage/logs/" 2>/dev/null | head -5
echo ""

echo "═══ 3. Fix: permissions breed zetten ═══"
# Alle bestanden in Controllers/Gymies leesbaar maken
sudo chmod -R 644 "$LP/app/Http/Controllers/Gymies/"*.php 2>/dev/null
sudo chmod 755 "$LP/app/Http/Controllers/Gymies/" 2>/dev/null
# routes file
sudo chmod 644 "$LP/routes_gymies_full.php" 2>/dev/null
# storage/logs writable voor iedereen
sudo chmod -R 775 "$LP/storage/logs/"
sudo chmod 775 "$LP/storage/logs"
# Zorg dat www-data eigenaar is
sudo chown -R www-data:www-data "$LP/storage/"
sudo chown www-data:www-data "$LP/routes_gymies_full.php"
sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/GymiesRefundController.php"
echo "  ✓ Permissions gefixt"
echo ""

echo "═══ 4. Fix: laravel.log opnieuw aanmaken ═══"
sudo rm -f "$LP/storage/logs/laravel.log"
sudo -u www-data touch "$LP/storage/logs/laravel.log"
sudo chmod 664 "$LP/storage/logs/laravel.log"
echo "  ✓ laravel.log hergemaakt als www-data"
echo ""

echo "═══ 5. Cache opnieuw opbouwen (als www-data) ═══"
cd "$LP"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache ververst"
echo ""

echo "═══ 6. PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ PHP-FPM herstart"
echo ""

echo "═══ 7. Nginx herstarten ═══"
sudo nginx -t 2>&1
sudo systemctl restart nginx
echo "  ✓ Nginx herstart"
echo ""

echo "═══ 8. Route list check (als www-data) ═══"
sudo -u www-data php artisan route:list --name=health 2>&1 | head -10
echo ""
sudo -u www-data php artisan route:list --name=bookings.refund 2>&1 | head -5
echo ""

echo "═══ 9. Health endpoint testen ═══"
echo "--- Via 127.0.0.1 ---"
curl -sv http://127.0.0.1/api/gymies/health 2>&1 | tail -20
echo ""
echo "--- Via localhost ---"
curl -s http://localhost/api/gymies/health 2>&1
echo ""

echo "═══ 10. Laravel log check (laatste errors) ═══"
tail -5 "$LP/storage/logs/laravel.log" 2>/dev/null || echo "  (log leeg of onbereikbaar)"
echo ""

echo "═══ Done ═══"
REMOTE

echo ""
echo "🔍 Bekijk de output hierboven."
echo "   De nginx config laat zien of /api/gymies/ correct gerouteerd wordt."
