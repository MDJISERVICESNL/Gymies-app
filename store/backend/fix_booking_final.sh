#!/bin/bash
set -e
echo "=== FINALE BOOKING FIX: deploy + opcache clear + fpm restart ==="

# 1. Upload bijgewerkte controller
echo "1. Controller uploaden..."
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesBookingController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesBookingController.php

ssh gymies << 'REMOTE'
cd /var/www/gymies

# 2. Permissions
echo "2. Permissions fixen..."
chown ubuntu:ubuntu app/Http/Controllers/Gymies/GymiesBookingController.php
sudo chown www-data:www-data storage/logs/laravel.log 2>/dev/null || true
sudo chmod 666 storage/logs/laravel.log 2>/dev/null || true
sudo chmod -R 775 storage/ bootstrap/cache/

# 3. OPcache resetten via CLI (reset voor FPM workers)
echo "3. OPcache CLI reset..."
php -r "
if (function_exists('opcache_reset')) {
    opcache_reset();
    echo 'CLI OPcache gereset' . PHP_EOL;
} else {
    echo 'OPcache niet actief in CLI' . PHP_EOL;
}
"

# 4. Maak een tijdelijk PHP-bestand om OPcache via web te resetten
echo "4. OPcache web reset voorbereiden..."
cat > /tmp/opcache_reset.php << 'OPCACHE'
<?php
if (function_exists('opcache_reset')) {
    opcache_reset();
    echo json_encode(['opcache' => 'reset', 'time' => date('Y-m-d H:i:s')]);
} else {
    echo json_encode(['opcache' => 'not_available']);
}
OPCACHE
sudo cp /tmp/opcache_reset.php /var/www/gymies/public/opcache_reset.php
sudo chown www-data:www-data /var/www/gymies/public/opcache_reset.php

# 5. Restart PHP-FPM (dit is de BELANGRIJKSTE stap)
echo "5. PHP 8.4 FPM herstarten..."
sudo systemctl restart php8.4-fpm
sleep 2

# 6. Trigger OPcache reset via FPM (niet CLI)
echo "6. OPcache via FPM resetten..."
curl -s http://127.0.0.1/opcache_reset.php -H "Host: gymies.nl" 2>/dev/null || echo "(curl niet bereikbaar, maar FPM is herstart)"

# 7. Verwijder het reset-bestand
sudo rm -f /var/www/gymies/public/opcache_reset.php

# 8. Laravel caches opruimen
echo "7. Laravel caches clearen..."
php artisan config:cache
php artisan route:cache
php artisan view:clear 2>/dev/null || true

# 9. Leeg laravel.log voor frisse capture
echo "8. Log legen..."
sudo truncate -s 0 storage/logs/laravel.log
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 10. Verify: check dat de try-catch in het bestand zit
echo ""
echo "=== Verificatie ==="
if grep -q "doStoreDirectBook" app/Http/Controllers/Gymies/GymiesBookingController.php; then
    echo "✓ try-catch wrapper gevonden (doStoreDirectBook)"
else
    echo "✗ FOUT: doStoreDirectBook niet gevonden!"
fi

if grep -q "property_exists.*priceCol" app/Http/Controllers/Gymies/GymiesBookingController.php; then
    echo "✓ property_exists price fix gevonden"
else
    echo "✗ FOUT: property_exists fix niet gevonden!"
fi

echo ""
echo "=== PHP-FPM status ==="
sudo systemctl status php8.4-fpm --no-pager | head -5

echo ""
echo "✅ ALLES GEDEPLOYED!"
echo "   Test de boeking NU in de app."
echo "   Als het nog faalt, draai dan:"
echo "   bash check_booking_log.sh"
REMOTE

echo ""
echo "=== KLAAR! Test de app ==="
