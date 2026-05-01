#!/bin/bash
set -e
SSH_HOST="gymies"
LP="/var/www/gymies"
LOCAL_BACKEND="$(cd "$(dirname "$0")/../../backend" && pwd)"
LOCAL_STORE="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Deploy SlotEngine fix + Controller updates  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Create staging
STAGING="/tmp/gymies_slotfix_$$"
mkdir -p "$STAGING/Services" "$STAGING/Controllers/Gymies"

# Copy files
cp "$LOCAL_STORE/backend/app/Services/SlotEngine.php" "$STAGING/Services/"
echo "  ✓ SlotEngine.php (is_active fix)"

cp "$LOCAL_BACKEND/Controllers/GymiesAvailabilityController.php" "$STAGING/Controllers/Gymies/"
echo "  ✓ GymiesAvailabilityController.php (SlotEngine integration)"

cp "$LOCAL_BACKEND/Controllers/GymiesTrainerLocationController.php" "$STAGING/Controllers/Gymies/"
echo "  ✓ GymiesTrainerLocationController.php (stub)"

# Archive and upload
echo ""
echo "  Creating archive..."
tar -czf "/tmp/gymies_slotfix.tar.gz" -C "$STAGING" .
scp "/tmp/gymies_slotfix.tar.gz" "$SSH_HOST:/tmp/gymies_slotfix.tar.gz"
echo "  ✓ Uploaded"
rm -rf "$STAGING" "/tmp/gymies_slotfix.tar.gz"

# Deploy on server
echo ""
echo "=== Deploying on AWS ==="
ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

mkdir -p /tmp/gymies_slotfix
cd /tmp/gymies_slotfix
tar -xzf /tmp/gymies_slotfix.tar.gz 2>/dev/null

# Deploy files
sudo cp Services/SlotEngine.php "$LP/app/Services/SlotEngine.php"
echo "  ✓ Services/SlotEngine.php"

sudo cp Controllers/Gymies/GymiesAvailabilityController.php "$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php"
echo "  ✓ Controllers/GymiesAvailabilityController.php"

sudo cp Controllers/Gymies/GymiesTrainerLocationController.php "$LP/app/Http/Controllers/Gymies/GymiesTrainerLocationController.php"
echo "  ✓ Controllers/GymiesTrainerLocationController.php"

# Fix ownership
sudo chown -R ubuntu:ubuntu "$LP/app/"
echo "  ✓ Ownership fixed"

# Syntax check
echo ""
echo "=== PHP syntax check ==="
php -l "$LP/app/Services/SlotEngine.php" 2>&1
php -l "$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php" 2>&1
php -l "$LP/app/Http/Controllers/Gymies/GymiesTrainerLocationController.php" 2>&1

# Clear caches + restart
echo ""
echo "=== Clear caches + restart ==="
cd "$LP"
php artisan route:clear 2>&1
php artisan config:clear 2>&1
php artisan cache:clear 2>&1
php artisan view:clear 2>&1
sudo systemctl restart php8.4-fpm
echo "  ✓ PHP-FPM restarted"

# Rebuild route cache
echo ""
echo "=== Route cache ==="
php artisan route:cache 2>&1

# Test route:list
echo ""
echo "=== Route:list trainers ==="
php artisan route:list --path=trainers 2>&1 | head -25

# Test API
echo ""
echo "=== Test API ==="
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "--- Trainer 27 availability (should have bookable_slots) ---"
RESP=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    slots = data.get('slots', [])
    bookable = data.get('bookable_slots', [])
    tz = data.get('timezone', '?')
    dur = data.get('session_duration_minutes', '?')
    buf = data.get('buffer_minutes', '?')
    print(f'  raw slots: {len(slots)}')
    print(f'  bookable_slots: {len(bookable)}')
    print(f'  timezone: {tz}, session: {dur}min, buffer: {buf}min')
    if bookable:
        print(f'  First 5 bookable:')
        for s in bookable[:5]:
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]} available={s.get(\"available\", \"?\")}')
    else:
        msg = d.get('message', data.get('message', ''))
        if msg:
            print(f'  message: {msg}')
except Exception as e:
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "--- Trainer 200 availability ---"
RESP2=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/200/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP2" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    bookable = data.get('bookable_slots', [])
    print(f'  bookable_slots: {len(bookable)}')
    if bookable:
        for s in bookable[:3]:
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]} available={s.get(\"available\", \"?\")}')
except Exception as e:
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "--- Trainer 27 show endpoint ---"
RESP3=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null)
echo "$RESP3" | python3 -m json.tool 2>/dev/null | head -15 || echo "$RESP3" | head -c 300

# Cleanup
rm -rf /tmp/gymies_slotfix /tmp/gymies_slotfix.tar.gz

echo ""
echo "=== Done ==="
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ SlotEngine fix deployed and tested                ║"
echo "╚══════════════════════════════════════════════════════╝"
