#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Clear route cache + fix HTTPS              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
cd "$LP"

echo "=== 1. Current route cache ==="
ls -la "$LP/bootstrap/cache/routes"*.php 2>/dev/null || echo "No route cache files"

echo ""
echo "=== 2. Clear ALL caches ==="
sudo -u www-data php artisan route:clear 2>&1
echo "  ✓ Route cache cleared"
sudo -u www-data php artisan config:clear 2>&1
echo "  ✓ Config cache cleared"
sudo -u www-data php artisan cache:clear 2>&1
echo "  ✓ App cache cleared"
sudo -u www-data php artisan view:clear 2>&1
echo "  ✓ View cache cleared"

echo ""
echo "=== 3. Verify route cache is gone ==="
ls -la "$LP/bootstrap/cache/routes"*.php 2>/dev/null || echo "  ✓ No route cache files — good!"

echo ""
echo "=== 4. Remove debug logging from controllers ==="
# Remove debug lines we added
sudo -u www-data php -r "
\$files = [
    '$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php',
    '$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php',
];
foreach (\$files as \$f) {
    \$content = file_get_contents(\$f);
    // Remove our debug lines
    \$content = preg_replace('/\s*\\\\Log::info\(\"DEBUG_(?:AVAIL|SHOW)_ENTRY\".*?\);\s*\n/', \"\n\", \$content);
    file_put_contents(\$f, \$content);
    echo \"  Cleaned debug from \$f\n\";
}
"

echo ""
echo "=== 5. Restart PHP-FPM ==="
sudo systemctl restart php8.4-fpm
echo "  ✓ PHP-FPM restarted"

echo ""
echo "=== 6. Test HTTPS API ==="
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "Test A: HTTPS www.gymiesapp.nl trainer 27"
RESP=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "  Response (first 300):"
echo "  $(echo "$RESP" | head -c 300)"
echo ""
echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    settings = d.get('settings', {})
    print(f'  bookable_slots: {len(bs)}')
    if settings: print(f'  settings keys: {list(settings.keys())}')
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
echo "Test B: HTTPS www.gymiesapp.nl trainer 63"
RESP2=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/63/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP2" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
    if len(bs) > 0:
        print(f'    eerste: {bs[0][\"date\"]} {bs[0][\"start_time\"]}-{bs[0][\"end_time\"]}')
except Exception as e:
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "Test C: HTTPS www.gymies.nl trainer 27"
RESP3=$(curl -sk -H "Accept: application/json" \
  "https://www.gymies.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP3" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
except Exception as e:
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "=== 7. Rebuild route cache (for production performance) ==="
sudo -u www-data php artisan route:cache 2>&1
echo "  ✓ Route cache rebuilt with current routes"

echo ""
echo "=== 8. Final test after fresh cache ==="
echo "Test: HTTPS www.gymiesapp.nl trainer 27 (after cache rebuild)"
RESP_FINAL=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP_FINAL" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
    if len(bs) > 0:
        for s in bs[:2]:
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]}')
except Exception as e:
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "--- Done ---"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Route cache fix klaar                             ║"
echo "╚══════════════════════════════════════════════════════╝"
