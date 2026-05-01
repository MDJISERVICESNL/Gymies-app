#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Fix log permissions voor www-data ==="
# PHP-FPM draait als www-data, niet ubuntu
sudo chown www-data:www-data storage/logs/laravel.log
sudo chmod 664 storage/logs/laravel.log
# Hele storage map writable voor www-data
sudo chown -R www-data:ubuntu storage
sudo chmod -R 775 storage
sudo chown -R www-data:ubuntu bootstrap/cache
sudo chmod -R 775 bootstrap/cache
echo "✓ Log permissions gefixed voor www-data"

echo ""
echo "=== PHP-FPM user check ==="
ps aux | grep php-fpm | grep -v grep | head -3

echo ""
echo "=== Direct booking endpoint testen ==="
# Login als testklant om een token te krijgen
echo ">> Login als testklant..."
LOGIN_RESP=$(curl -s -X POST http://localhost/api/gymies/login \
    -H "Content-Type: application/json" \
    -d '{"email":"testklant@gymies.nl","password":"TestKlant2026!"}')
echo "Login response (eerste 200 chars): ${LOGIN_RESP:0:200}"

TOKEN=$(echo "$LOGIN_RESP" | php -r "echo json_decode(file_get_contents('php://stdin'), true)['token'] ?? 'GEEN_TOKEN';")
echo "Token: ${TOKEN:0:20}..."

if [ "$TOKEN" = "GEEN_TOKEN" ] || [ -z "$TOKEN" ]; then
    echo "FOUT: Kan niet inloggen als testklant!"
    echo "Volledige response: $LOGIN_RESP"
    exit 1
fi

echo ""
echo ">> Booking test: POST bookings/direct-book..."
BOOK_RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost/api/gymies/bookings/direct-book \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
        "trainer_user_id": 27,
        "scheduled_at": "2026-05-02T10:00:00",
        "payment_method": "cash"
    }')
HTTP_CODE=$(echo "$BOOK_RESP" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$BOOK_RESP" | grep -v "HTTP_CODE:")
echo "HTTP Status: $HTTP_CODE"
echo "Response: ${BODY:0:500}"

echo ""
echo "=== Verse Laravel errors na test ==="
sleep 1
tail -50 storage/logs/laravel.log | grep -A 20 "$(date -u +'%Y-%m-%d')" | grep -i "error\|exception\|SQLSTATE" | tail -10

echo ""
echo "=== Verse Nginx errors ==="
sudo tail -10 /var/log/nginx/error.log | grep "$(date -u +'%Y/%m/%d')" | tail -5
REMOTE
