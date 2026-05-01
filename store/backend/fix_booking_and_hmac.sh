#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix booking validation + HMAC enforce      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. Check what's on server ──────────────────────────────
echo "=== 1/5 Server FormRequest checken ==="
ssh "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
echo "--- Huidige GymiesDirectBookingRequest op server ---"
if [ -f "$LP/app/Http/Requests/GymiesDirectBookingRequest.php" ]; then
    grep -n "amount_cents" "$LP/app/Http/Requests/GymiesDirectBookingRequest.php" 2>/dev/null || echo "  (geen amount_cents rule gevonden)"
    echo ""
    echo "  Volledige rules():"
    sed -n '/function rules/,/^    }/p' "$LP/app/Http/Requests/GymiesDirectBookingRequest.php" 2>/dev/null
else
    echo "  Bestand bestaat NIET op server"
fi
REMOTE

# ── 2. Upload fixed FormRequest ────────────────────────────
echo ""
echo "=== 2/5 FormRequest uploaden ==="
scp "$SCRIPT_DIR/app/Http/Requests/GymiesDirectBookingRequest.php" "$SSH_HOST:/tmp/GymiesDirectBookingRequest.php"

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
sudo mkdir -p "$LP/app/Http/Requests"
sudo cp /tmp/GymiesDirectBookingRequest.php "$LP/app/Http/Requests/GymiesDirectBookingRequest.php"
sudo chown ubuntu:ubuntu "$LP/app/Http/Requests/GymiesDirectBookingRequest.php"
rm -f /tmp/GymiesDirectBookingRequest.php
echo "  ✓ GymiesDirectBookingRequest geüpload"
REMOTE

# ── 3. Upload HMAC middleware + config ─────────────────────
echo ""
echo "=== 3/5 HMAC middleware + config uploaden ==="
scp "$SCRIPT_DIR/app/Http/Middleware/GymiesHmacMiddleware.php" "$SSH_HOST:/tmp/GymiesHmacMiddleware.php"
scp "$SCRIPT_DIR/config/gymies.php" "$SSH_HOST:/tmp/gymies_config.php"

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
sudo cp /tmp/GymiesHmacMiddleware.php "$LP/app/Http/Middleware/GymiesHmacMiddleware.php"
sudo cp /tmp/gymies_config.php "$LP/config/gymies.php"
sudo chown ubuntu:ubuntu "$LP/app/Http/Middleware/GymiesHmacMiddleware.php"
sudo chown ubuntu:ubuntu "$LP/config/gymies.php"
rm -f /tmp/GymiesHmacMiddleware.php /tmp/gymies_config.php
echo "  ✓ HMAC middleware + config geüpload"
REMOTE

# ── 4. HMAC enforce=false instellen ────────────────────────
echo ""
echo "=== 4/5 HMAC enforce=false + cache rebuild ==="
ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
cd "$LP"

# HMAC enforce=false voor development
if grep -q "^GYMIES_HMAC_ENFORCE=" .env 2>/dev/null; then
    sudo sed -i "s|^GYMIES_HMAC_ENFORCE=.*|GYMIES_HMAC_ENFORCE=false|" .env
    echo "  ✓ GYMIES_HMAC_ENFORCE geüpdatet naar false"
else
    echo "GYMIES_HMAC_ENFORCE=false" | sudo tee -a .env > /dev/null
    echo "  ✓ GYMIES_HMAC_ENFORCE=false toegevoegd"
fi

# Rebuild caches
php artisan config:clear 2>&1 | tail -1
php artisan route:clear 2>&1 | tail -1
php artisan config:cache 2>&1 | tail -1
php artisan route:cache 2>&1 | tail -1
REMOTE

# ── 5. Test endpoints ──────────────────────────────────────
echo ""
echo "=== 5/5 Verificatie ==="
ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
cd "$LP"

echo "--- PHP syntax check ---"
php -l "$LP/app/Http/Requests/GymiesDirectBookingRequest.php" 2>&1 | tail -1
php -l "$LP/app/Http/Middleware/GymiesHmacMiddleware.php" 2>&1 | tail -1

echo ""
echo "--- Route check ---"
php artisan route:list --path=direct-book 2>&1 | head -5

echo ""
echo "--- Test trainer endpoint (HMAC bypass) ---"
STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -H "Accept: application/json" "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null)
echo "  GET trainers/27 → HTTP $STATUS"
[ "$STATUS" = "200" ] && echo "  ✓ API werkt zonder HMAC headers" || echo "  ✗ Nog steeds geblokkeerd"

echo ""
echo "--- FormRequest validation rules ---"
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Http\Kernel::class);
\$kernel->bootstrap();

\$req = new App\Http\Requests\GymiesDirectBookingRequest();
\$rules = \$req->rules();
echo 'amount_cents rule: ' . (\$rules['amount_cents'] ?? '(niet gedefinieerd)') . PHP_EOL;
echo 'trainer_user_id rule: ' . (\$rules['trainer_user_id'] ?? '(niet gedefinieerd)') . PHP_EOL;
" 2>&1
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Booking validation + HMAC enforce gefixed         ║"
echo "║                                                      ║"
echo "║  - amount_cents is nu nullable (server berekent)     ║"
echo "║  - HMAC enforce=false (dev mode)                     ║"
echo "║  - Zet GYMIES_HMAC_ENFORCE=true voor productie!      ║"
echo "╚══════════════════════════════════════════════════════╝"
