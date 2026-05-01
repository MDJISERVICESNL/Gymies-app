#!/bin/bash
# ============================================================
# GYMIES — Flush OPcache + verify API bookable_slots
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — OPcache flush + API verificatie            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

# 1. Check which PHP-FPM is running
echo "  [1/4] PHP-FPM detecteren..."
PHP_FPM=$(systemctl list-units --type=service --state=running | grep -oP 'php[\d.]+-fpm' | head -1)
if [ -z "$PHP_FPM" ]; then
    echo "  ⚠ Geen actieve PHP-FPM gevonden, probeer php-fpm..."
    PHP_FPM="php-fpm"
fi
echo "  ✓ Gevonden: ${PHP_FPM}"

# 2. Create temporary opcache reset script
echo ""
echo "  [2/4] OPcache flushen..."
sudo bash -c "cat > $LP/public/opcache_reset.php << 'OPCACHE'
<?php
if (function_exists('opcache_reset')) {
    opcache_reset();
    echo json_encode(['status' => 'ok', 'message' => 'OPcache geflusht']);
} else {
    echo json_encode(['status' => 'ok', 'message' => 'OPcache niet actief']);
}
OPCACHE"
sudo chown www-data:www-data "$LP/public/opcache_reset.php"

# Flush via web request (hits FPM worker pool)
FLUSH=$(curl -s "https://www.gymies.nl/opcache_reset.php" 2>/dev/null || echo '{"status":"fallback"}')
echo "  OPcache flush: $FLUSH"

# Also restart PHP-FPM as belt-and-suspenders
sudo systemctl restart "$PHP_FPM" 2>/dev/null && echo "  ✓ ${PHP_FPM} herstart" || echo "  ⚠ FPM restart mislukt (niet erg als opcache_reset werkte)"

# Remove reset script
sudo rm -f "$LP/public/opcache_reset.php"

# 3. Clear Laravel caches
echo ""
echo "  [3/4] Laravel caches..."
cd "$LP"
sudo -u www-data php artisan cache:clear 2>/dev/null && echo "  ✓ cache:clear"
sudo -u www-data php artisan route:clear 2>/dev/null && echo "  ✓ route:clear"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "  ✓ route:cache"
sudo -u www-data php artisan config:clear 2>/dev/null && echo "  ✓ config:clear"

# 4. API test
echo ""
echo "  [4/4] API verificatie..."
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d)

TRAINER_IDS=$(sudo -u www-data php -r "
require_once '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
\$ids = DB::table('gymies_trainer_profiles')->pluck('user_id')->implode(',');
echo \$ids;
")

echo "  Trainer IDs: $TRAINER_IDS"
echo ""

IFS=',' read -ra IDS <<< "$TRAINER_IDS"
for TID in "${IDS[@]}"; do
    URL="https://www.gymies.nl/api/gymies/trainers/${TID}/availability?from=${FROM}&to=${TO}"
    echo "  GET $URL"
    AVAIL=$(curl -s "$URL" 2>/dev/null)

    # Parse response
    RESULT=$(echo "$AVAIL" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    slots = d.get('slots', [])
    settings = d.get('settings', {})
    print(f'  bookable_slots: {len(bs)}')
    print(f'  raw slots: {len(slots)}')
    print(f'  settings: {json.dumps(settings)}')
    if len(bs) > 0:
        for s in bs[:3]:
            avail = 'JA' if s.get('available') else 'NEE'
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]} ({avail})')
        if len(bs) > 3:
            print(f'    ... en {len(bs)-3} meer')
    elif 'error' in d or 'message' in d:
        print(f'  error/message: {d.get(\"error\", d.get(\"message\", \"\"))}')
except Exception as e:
    print(f'  PARSE ERROR: {e}')
    print(f'  Raw: {sys.stdin.read()[:200]}')
" 2>/dev/null || echo "  FOUT bij parsen")

    echo "$RESULT"
    echo ""
done
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ OPcache geflusht + API getest                    ║"
echo "╚══════════════════════════════════════════════════════╝"
