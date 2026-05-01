#!/bin/bash
# ============================================================
# GYMIES — Deploy controller + SlotEngine column detection fix
# Fix: Schema::hasColumn → getColumnListing (cache-safe)
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LOCAL_BACKEND="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Controller fix deploy + API test           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Upload both files
echo "  [1/4] Uploaden..."
cd "$LOCAL_BACKEND"
tar czf /tmp/gymies_fix.tar.gz \
  app/Http/Controllers/Gymies/GymiesAvailabilityController.php \
  app/Services/SlotEngine.php

scp -i "$SSH_KEY" /tmp/gymies_fix.tar.gz "$SSH_HOST:/tmp/"
rm -f /tmp/gymies_fix.tar.gz
echo "  ✓ Upload klaar"

# Install + restart FPM + test
echo ""
echo "  [2/4] Installeren..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s << 'REMOTE'
set -e
LP="/var/www/gymies"

cd /tmp
tar xzf gymies_fix.tar.gz 2>/dev/null

sudo cp app/Http/Controllers/Gymies/GymiesAvailabilityController.php "$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php"
sudo cp app/Services/SlotEngine.php "$LP/app/Services/SlotEngine.php"
sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php"
sudo chown www-data:www-data "$LP/app/Services/SlotEngine.php"
echo "  ✓ Bestanden geïnstalleerd"

# Restart PHP-FPM to clear opcache
PHP_FPM=$(systemctl list-units --type=service --state=running | grep -oP 'php[\d.]+-fpm' | head -1)
sudo systemctl restart "$PHP_FPM" 2>/dev/null && echo "  ✓ ${PHP_FPM} herstart"

# Clear all caches
cd "$LP"
sudo -u www-data php artisan cache:clear 2>/dev/null
sudo -u www-data php artisan config:clear 2>/dev/null
sudo -u www-data php artisan route:clear 2>/dev/null
sudo -u www-data php artisan route:cache 2>/dev/null
echo "  ✓ Caches gecleared + route:cache rebuilt"

# Cleanup
rm -f /tmp/gymies_fix.tar.gz
rm -rf /tmp/app

# Direct controller test
echo ""
echo "  [3/4] Direct controller test..."
sudo -u www-data php << 'PHP'
<?php
require_once '/var/www/gymies/vendor/autoload.php';
$app = require_once '/var/www/gymies/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$controller = new \App\Http\Controllers\Gymies\GymiesAvailabilityController();
$request = \Illuminate\Http\Request::create('/api/gymies/trainers/27/availability', 'GET', [
    'from' => date('Y-m-d'),
    'to' => date('Y-m-d', strtotime('+7 days')),
]);

try {
    $response = $controller->publicAvailability($request, '27');
    $data = json_decode($response->getContent(), true);
    echo "  Status: " . $response->getStatusCode() . "\n";
    echo "  bookable_slots: " . (isset($data['bookable_slots']) ? count($data['bookable_slots']) : 'MISSING') . "\n";
    echo "  settings: " . (isset($data['settings']) ? json_encode($data['settings']) : 'MISSING') . "\n";
    echo "  raw slots: " . (isset($data['slots']) ? count($data['slots']) : 'MISSING') . "\n";
    echo "  exceptions: " . (isset($data['exceptions']) ? count($data['exceptions']) : 'MISSING') . "\n";
    if (isset($data['bookable_slots']) && count($data['bookable_slots']) > 0) {
        echo "  Eerste 3 bookable slots:\n";
        $show = array_slice($data['bookable_slots'], 0, 3);
        foreach ($show as $s) {
            $avail = $s['available'] ? 'JA' : 'NEE';
            echo "    {$s['date']} {$s['start_time']}-{$s['end_time']} ({$avail})\n";
        }
    }
} catch (\Throwable $e) {
    echo "  ERROR: " . $e->getMessage() . "\n";
    echo "  File: " . $e->getFile() . ":" . $e->getLine() . "\n";
}
PHP

# API test via wget (curl might not be available)
echo ""
echo "  [4/4] API test via HTTP..."
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d)

for TID in 27 63; do
    URL="https://www.gymies.nl/api/gymies/trainers/${TID}/availability?from=${FROM}&to=${TO}"
    RESP=$(wget -qO- --header="Accept: application/json" "$URL" 2>/dev/null || echo '{"error":"wget failed"}')
    BOOKABLE=$(echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'bookable_slots={len(bs)}' + (f' message={msg}' if msg else ''))
except:
    print('PARSE_ERROR')
" 2>/dev/null || echo "FOUT")
    echo "  Trainer #${TID}: ${BOOKABLE}"
done
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Controller fix gedeployd                          ║"
echo "╚══════════════════════════════════════════════════════╝"
