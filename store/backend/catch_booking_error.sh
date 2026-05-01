#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

# 1. Log permissions opnieuw fixen
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 666 storage/logs/laravel.log

# 2. Leeg de log zodat we alleen verse errors zien
sudo truncate -s 0 storage/logs/laravel.log
echo "✓ laravel.log geleegd"

# 3. Restart PHP-FPM zodat nieuwe workers de juiste file handle krijgen
sudo systemctl restart php8.4-fpm
echo "✓ php8.4-fpm herstart"
sleep 1

echo ""
echo "=== Wachten op booking-poging... ==="
echo "    Probeer NU te boeken in de app!"
echo "    (wacht 30 seconden op errors...)"
sleep 30

echo ""
echo "=== Laravel log na 30 sec ==="
if [ -s storage/logs/laravel.log ]; then
    echo "--- ERRORS GEVONDEN ---"
    cat storage/logs/laravel.log | head -80
else
    echo "(log is leeg — geen errors gelogd)"
fi

echo ""
echo "=== Nginx errors laatste minuut ==="
sudo tail -20 /var/log/nginx/error.log | grep "$(date -u +'%Y/%m/%d %H:')" | tail -10

echo ""
echo "=== Nginx access log: booking requests ==="
sudo tail -100 /var/log/nginx/access.log | grep -i "direct-book\|booking" | tail -10
REMOTE
