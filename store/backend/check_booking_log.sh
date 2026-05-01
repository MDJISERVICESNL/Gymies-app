#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Laravel log (laatste 50 regels) ==="
if [ -s storage/logs/laravel.log ]; then
    tail -50 storage/logs/laravel.log
else
    echo "(log is leeg — geen errors gelogd)"
fi

echo ""
echo "=== Nginx error log (vandaag) ==="
sudo tail -20 /var/log/nginx/error.log 2>/dev/null | grep "$(date -u +'%Y/%m/%d')" | tail -10

echo ""
echo "=== Nginx access: booking requests ==="
sudo tail -200 /var/log/nginx/access.log | grep -i "direct-book\|booking" | tail -10

echo ""
echo "=== PHP-FPM error log ==="
sudo tail -20 /var/log/php8.4-fpm.log 2>/dev/null | tail -10
REMOTE
