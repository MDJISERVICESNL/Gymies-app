#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix permissions + diagnose + test AWS       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

echo "=== 1. Fix permissions ==="
# storage/ and bootstrap/cache/ need to be writable by both ubuntu and www-data
sudo chown -R ubuntu:ubuntu "$LP/storage"
sudo chown -R ubuntu:ubuntu "$LP/bootstrap/cache"
sudo chmod -R 775 "$LP/storage"
sudo chmod -R 775 "$LP/bootstrap/cache"
echo "  ✓ storage/ and bootstrap/cache/ fixed"

# Also fix app/ ownership (some files were www-data from old deploy)
sudo chown -R ubuntu:ubuntu "$LP/app/"
echo "  ✓ app/ ownership fixed"

echo ""
echo "=== 2. Check PHP syntax on deployed files ==="
for f in \
  "$LP/app/Services/SlotEngine.php" \
  "$LP/app/Services/CancellationPolicyService.php" \
  "$LP/app/Services/WaitlistService.php" \
  "$LP/app/Services/RecurringBookingService.php" \
  "$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php" \
  "$LP/app/Http/Controllers/Gymies/GymiesBookingController.php" \
  "$LP/app/Http/Controllers/Gymies/GymiesWaitlistController.php" \
  "$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php" \
  "$LP/routes/gymies.php"; do
  RESULT=$(php -l "$f" 2>&1)
  if echo "$RESULT" | grep -q "No syntax errors"; then
    echo "  ✓ $(basename $f)"
  else
    echo "  ✗ $(basename $f): $RESULT"
  fi
done

echo ""
echo "=== 3. Check ALL controllers for syntax ==="
find "$LP/app/Http/Controllers/Gymies/" -name "*.php" -exec php -l {} \; 2>&1 | grep -v "No syntax errors" || echo "  ✓ All controllers OK"

echo ""
echo "=== 4. Clear all caches ==="
cd "$LP"
php artisan route:clear 2>&1
php artisan config:clear 2>&1
php artisan cache:clear 2>&1
php artisan view:clear 2>&1
php artisan optimize:clear 2>&1 || true
echo "  ✓ All caches cleared"

echo ""
echo "=== 5. Restart PHP-FPM ==="
sudo systemctl restart php8.4-fpm
echo "  ✓ PHP-FPM restarted"

echo ""
echo "=== 6. Test route:list ==="
php artisan route:list --path=trainers 2>&1 | head -25

echo ""
echo "=== 7. Check database: trainer profiles ==="
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// What columns exist in gymies_trainer_profiles?
echo 'Columns in gymies_trainer_profiles:' . PHP_EOL;
\$cols = DB::select('SHOW COLUMNS FROM gymies_trainer_profiles');
foreach (\$cols as \$c) {
    echo '  ' . \$c->Field . ' (' . \$c->Type . ')' . PHP_EOL;
}

echo PHP_EOL;

// What trainers exist?
echo 'Trainers in gymies_users (role=trainer):' . PHP_EOL;
\$trainers = DB::table('gymies_users')->where('role', 'trainer')->get(['id', 'display_name', 'email']);
foreach (\$trainers as \$t) {
    echo '  id=' . \$t->id . ' name=' . (\$t->display_name ?? 'null') . ' email=' . (\$t->email ?? 'null') . PHP_EOL;
}
echo 'Total: ' . count(\$trainers) . PHP_EOL;

echo PHP_EOL;

// What trainer_profiles exist?
echo 'Trainer profiles:' . PHP_EOL;
\$profiles = DB::table('gymies_trainer_profiles')->get();
foreach (\$profiles as \$p) {
    echo '  profile_id=' . \$p->id . ' user_id=' . \$p->user_id . PHP_EOL;
}
echo 'Total: ' . count(\$profiles) . PHP_EOL;

echo PHP_EOL;

// Check availability slots
echo 'Availability slots:' . PHP_EOL;
\$slots = DB::table('gymies_availability_slots')->get();
echo 'Total slots: ' . count(\$slots) . PHP_EOL;
foreach (\$slots as \$s) {
    echo '  slot_id=' . \$s->id . ' trainer=' . \$s->trainer_user_id . ' day=' . \$s->day_of_week . ' ' . \$s->start_time . '-' . \$s->end_time . PHP_EOL;
}
" 2>&1

echo ""
echo "=== 8. Test API ==="
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "--- Test trainer/27/availability via HTTPS ---"
RESP=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP" | python3 -m json.tool 2>/dev/null | head -30 || echo "$RESP" | head -c 300

echo ""
echo "--- Test trainer/27 show endpoint ---"
RESP2=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null)
echo "$RESP2" | python3 -m json.tool 2>/dev/null | head -20 || echo "$RESP2" | head -c 300

echo ""
echo "=== Done ==="
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Fix and test complete                             ║"
echo "╚══════════════════════════════════════════════════════╝"
