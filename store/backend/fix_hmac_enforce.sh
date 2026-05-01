#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix HMAC: enforce=false voor development   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Upload updated files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1/3 Bestanden uploaden ==="
scp "$SCRIPT_DIR/app/Http/Middleware/GymiesHmacMiddleware.php" "$SSH_HOST:/tmp/GymiesHmacMiddleware.php"
scp "$SCRIPT_DIR/config/gymies.php" "$SSH_HOST:/tmp/gymies_config.php"

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

# Copy files
sudo cp /tmp/GymiesHmacMiddleware.php "$LP/app/Http/Middleware/GymiesHmacMiddleware.php"
sudo cp /tmp/gymies_config.php "$LP/config/gymies.php"
sudo chown ubuntu:ubuntu "$LP/app/Http/Middleware/GymiesHmacMiddleware.php"
sudo chown ubuntu:ubuntu "$LP/config/gymies.php"
rm -f /tmp/GymiesHmacMiddleware.php /tmp/gymies_config.php
echo "  ✓ Bestanden gekopieerd"

echo ""
echo "=== 2/3 HMAC enforce=false instellen ==="
cd "$LP"

# Add GYMIES_HMAC_ENFORCE=false if not present
if grep -q "^GYMIES_HMAC_ENFORCE=" .env 2>/dev/null; then
    sudo sed -i "s|^GYMIES_HMAC_ENFORCE=.*|GYMIES_HMAC_ENFORCE=false|" .env
    echo "  ✓ GYMIES_HMAC_ENFORCE geüpdatet naar false"
else
    echo "GYMIES_HMAC_ENFORCE=false" | sudo tee -a .env > /dev/null
    echo "  ✓ GYMIES_HMAC_ENFORCE=false toegevoegd aan .env"
fi

echo ""
echo "=== 3/3 Cache rebuilden ==="
php artisan config:clear 2>&1 | tail -1
php artisan route:clear 2>&1 | tail -1
php artisan config:cache 2>&1 | tail -1
php artisan route:cache 2>&1 | tail -1

echo ""
echo "=== Verificatie: test endpoint ==="
STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -H "Accept: application/json" "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null)
echo "  GET trainers/27 → HTTP $STATUS"

if [ "$STATUS" = "200" ]; then
    echo "  ✓ API requests werken weer zonder HMAC headers"
else
    echo "  ✗ Endpoint geeft nog steeds $STATUS"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ HMAC enforce=false — development mode            ║"
echo "║                                                      ║"
echo "║  Requests zonder HMAC headers worden doorgelaten     ║"
echo "║  maar gelogd. Zet GYMIES_HMAC_ENFORCE=true voordat   ║"
echo "║  je naar productie gaat!                             ║"
echo "╚══════════════════════════════════════════════════════╝"
REMOTE
