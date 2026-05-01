#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"
TRAITS_LOCAL="$(cd "$(dirname "$0")/../../backend/Controllers/Traits" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Deploy missing Traits (single connection)  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 1. Upload ALL trait files in one scp call ────────────────────────────
echo "=== Uploading all trait files ==="
scp -i "$SSH_KEY" \
  "$TRAITS_LOCAL/TrainerRevenueTrait.php" \
  "$TRAITS_LOCAL/TrainerMessagingTrait.php" \
  "$TRAITS_LOCAL/TrainerClientsTrait.php" \
  "$TRAITS_LOCAL/TrainerSessionsTrait.php" \
  "$SSH_HOST:/tmp/"

echo "  ✓ All 4 traits uploaded to /tmp/"
echo ""

# ── 2. Single SSH session for everything else ────────────────────────────
echo "=== Deploying + testing (single SSH session) ==="
ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

echo "--- Creating Traits directory ---"
sudo mkdir -p "$LP/app/Http/Controllers/Gymies/Traits"

echo "--- Moving trait files ---"
for TRAIT in TrainerRevenueTrait.php TrainerMessagingTrait.php TrainerClientsTrait.php TrainerSessionsTrait.php; do
    if [ -f "/tmp/$TRAIT" ]; then
        sudo cp "/tmp/$TRAIT" "$LP/app/Http/Controllers/Gymies/Traits/$TRAIT"
        sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/Traits/$TRAIT"
        rm "/tmp/$TRAIT"
        echo "  ✓ $TRAIT deployed"
    else
        echo "  ✗ $TRAIT not in /tmp — skipping"
    fi
done

echo ""
echo "--- Verify traits on disk ---"
ls -la "$LP/app/Http/Controllers/Gymies/Traits/"

echo ""
echo "--- Restarting PHP-FPM ---"
sudo systemctl restart php8.4-fpm
echo "  ✓ PHP-FPM restarted"

echo ""
echo "--- Testing route:list ---"
cd "$LP"
sudo -u www-data php artisan route:list --path=trainers 2>&1 | head -30

echo ""
echo "--- Testing API via HTTPS ---"
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "Test: HTTPS www.gymiesapp.nl trainer 27"
RESP=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null || echo "CURL_FAILED")
echo "  Response (first 400):"
echo "  $RESP" | head -c 400
echo ""

echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    settings = d.get('settings', {})
    print(f'  bookable_slots: {len(bs)}')
    if settings: print(f'  settings: {json.dumps(settings)}')
    if msg: print(f'  message: {msg}')
    if len(bs) > 0:
        for s in bs[:3]:
            avail = 'JA' if s.get('available') else 'NEE'
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]} ({avail})')
        if len(bs) > 3:
            print(f'    ... en {len(bs)-3} meer')
except Exception as e:
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "Test: HTTPS www.gymiesapp.nl trainer 63"
RESP2=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/63/availability?from=${FROM}&to=${TO}" 2>/dev/null || echo "CURL_FAILED")
echo "$RESP2" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
except:
    print('  Not JSON')
" 2>/dev/null

echo ""
echo "--- Done ---"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Trait deploy + API test klaar                     ║"
echo "╚══════════════════════════════════════════════════════╝"
