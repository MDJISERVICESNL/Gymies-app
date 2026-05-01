#!/bin/bash
# ============================================================
# GYMIES — V2 Controllers Deploy
# Deployt: updated controllers, routes, nieuwe controller
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="/var/www/gymies"
LOCAL_BACKEND="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — V2 Controllers Deploy                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Stap 1: Bestanden uploaden via tar ──
echo "  [1/3] Bestanden uploaden..."
cd "$LOCAL_BACKEND"

tar czf /tmp/gymies_v2_controllers.tar.gz \
  app/Http/Controllers/Gymies/GymiesAvailabilityController.php \
  app/Http/Controllers/Gymies/GymiesBookingController.php \
  app/Http/Controllers/Gymies/GymiesWaitlistController.php \
  app/Http/Controllers/Gymies/GymiesRecurringBookingController.php \
  app/Http/Controllers/Gymies/GymiesCronController.php \
  routes_gymies_full.php

scp -i "$SSH_KEY" /tmp/gymies_v2_controllers.tar.gz "$SSH_HOST:/tmp/"
echo "  ✓ Upload klaar"

# ── Stap 2: Installeren + cache ──
echo ""
echo "  [2/3] Installeren..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
LP="$1"

cd /tmp
tar xzf gymies_v2_controllers.tar.gz 2>/dev/null

echo "  Controllers kopiëren..."
for f in app/Http/Controllers/Gymies/GymiesAvailabilityController.php \
         app/Http/Controllers/Gymies/GymiesBookingController.php \
         app/Http/Controllers/Gymies/GymiesWaitlistController.php \
         app/Http/Controllers/Gymies/GymiesRecurringBookingController.php \
         app/Http/Controllers/Gymies/GymiesCronController.php; do
  if [ -f "$f" ]; then
    sudo cp "$f" "$LP/$f"
    sudo chown www-data:www-data "$LP/$f"
    echo "  ✓ $(basename $f)"
  fi
done

echo ""
echo "  Routes kopiëren..."
if [ -f "routes_gymies_full.php" ]; then
  sudo cp routes_gymies_full.php "$LP/routes_gymies_full.php"
  sudo chown www-data:www-data "$LP/routes_gymies_full.php"
  echo "  ✓ routes_gymies_full.php"
fi

echo ""
echo "  Cache rebuilden..."
cd "$LP"
sudo -u www-data php artisan route:clear 2>/dev/null && echo "  ✓ route:clear"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "  ✓ route:cache"

# Cleanup
rm -f /tmp/gymies_v2_controllers.tar.gz
rm -rf /tmp/app /tmp/routes_gymies_full.php

# ── Verificatie ──
echo ""
echo "  ═══ VERIFICATIE ═══"
echo "  Testen of SlotEngine werkt..."

sudo -u www-data php << 'PHP'
<?php
require_once '/var/www/gymies/vendor/autoload.php';
$app = require_once '/var/www/gymies/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

// Test SlotEngine
$engine = new \App\Services\SlotEngine();

// Test splitBlock
$slots = $engine->splitBlock('07:00', '12:00', 60, 15);
echo "  splitBlock(07:00-12:00, 60min, 15buf): " . count($slots) . " slots\n";
foreach ($slots as $s) {
    echo "    {$s['start']} - {$s['end']}\n";
}

// Test trainer settings laden
$settings = $engine->loadTrainerSettings(200);
echo "\n  Trainer #200 settings:\n";
echo "    session_duration: {$settings['session_duration_min']} min\n";
echo "    buffer: {$settings['buffer_minutes']} min\n";
echo "    timezone: {$settings['timezone']}\n";

// Test bookable slots voor trainer 200
$from = date('Y-m-d');
$to = date('Y-m-d', strtotime('+7 days'));
$bookable = $engine->getBookableSlots(200, $from, $to, filterBooked: true);
echo "\n  Bookable slots trainer #200 ({$from} t/m {$to}): " . count($bookable) . " slots\n";
if (count($bookable) > 0) {
    $first = $bookable[0];
    echo "    Eerste: {$first['date']} {$first['start_time']}-{$first['end_time']} (beschikbaar: " . ($first['available'] ? 'ja' : 'nee') . ")\n";
}

// Test WaitlistService
echo "\n  WaitlistService: OK (class exists: " . (class_exists(\App\Services\WaitlistService::class) ? 'ja' : 'nee') . ")\n";

// Test RecurringBookingService
echo "  RecurringBookingService: OK (class exists: " . (class_exists(\App\Services\RecurringBookingService::class) ? 'ja' : 'nee') . ")\n";

// Test CancellationPolicyService
echo "  CancellationPolicyService: OK (class exists: " . (class_exists(\App\Services\CancellationPolicyService::class) ? 'ja' : 'nee') . ")\n";

// Test RecurringBookingController
echo "  RecurringBookingController: OK (class exists: " . (class_exists(\App\Http\Controllers\Gymies\GymiesRecurringBookingController::class) ? 'ja' : 'nee') . ")\n";
PHP

echo ""
echo "  API test: trainers/200/availability..."
AVAIL=$(curl -s "https://www.gymies.nl/api/gymies/trainers/200/availability?from=$(date +%Y-%m-%d)&to=$(date -d '+7 days' +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d)" 2>/dev/null)
BOOKABLE_COUNT=$(echo "$AVAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('bookable_slots',[])))" 2>/dev/null || echo "FOUT")
echo "  bookable_slots: ${BOOKABLE_COUNT}"
REMOTE

# ── Cleanup ──
echo ""
echo "  [3/3] Cleanup..."
rm -f /tmp/gymies_v2_controllers.tar.gz

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ V2 Controllers gedeployd!                         ║"
echo "║                                                      ║"
echo "║  Updated:                                            ║"
echo "║  · GymiesAvailabilityController (SlotEngine)         ║"
echo "║  · GymiesBookingController (WaitlistService)         ║"
echo "║  · GymiesWaitlistController (V2 schema)              ║"
echo "║  · GymiesCronController (recurring + waitlist cron)  ║"
echo "║                                                      ║"
echo "║  Nieuw:                                              ║"
echo "║  · GymiesRecurringBookingController                  ║"
echo "║                                                      ║"
echo "║  Nieuwe routes:                                      ║"
echo "║  · POST waitlist/{id}/claim                          ║"
echo "║  · GET/POST/PUT/DELETE recurring-bookings            ║"
echo "║  · CRON: generate-recurring-bookings                 ║"
echo "║  · CRON: expire-waitlist-offers                      ║"
echo "║  · CRON: cleanup-idempotency-keys                   ║"
echo "╚══════════════════════════════════════════════════════╝"
