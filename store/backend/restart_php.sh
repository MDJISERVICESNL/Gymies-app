#!/bin/bash
set -e
ssh gymies << 'REMOTE'
echo "=== PHP-FPM herstarten + OPcache resetten ==="

# Vind de juiste PHP-FPM service
PHP_FPM=$(systemctl list-units --type=service --state=running | grep -o 'php[0-9.]*-fpm' | head -1)
if [ -z "$PHP_FPM" ]; then
    echo "Geen draaiende PHP-FPM gevonden, probeer php8.3-fpm..."
    PHP_FPM="php8.3-fpm"
fi
echo "Service: $PHP_FPM"

sudo systemctl restart "$PHP_FPM"
echo "✓ $PHP_FPM herstart"

# Verify
sleep 1
sudo systemctl status "$PHP_FPM" --no-pager | head -5

# Clear OPcache via PHP
cd /var/www/gymies
php artisan cache:clear
php artisan config:cache
php artisan route:cache

echo ""
echo "✅ PHP-FPM herstart + caches herbouwd"
echo "   Test de boeking opnieuw in de app."
REMOTE
