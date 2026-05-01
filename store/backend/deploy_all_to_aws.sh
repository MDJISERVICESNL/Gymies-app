#!/bin/bash
set -e
SSH_HOST="gymies"
# Note: after switch_to_aws.sh, "gymies" points to AWS (ubuntu@18.159.130.187)
LP="/var/www/gymies"
LOCAL_BACKEND="$(cd "$(dirname "$0")/../../backend" && pwd)"
LOCAL_STORE="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Deploy ALL fixes to AWS server              ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 0. Verify we're connecting to AWS ────────────────────────────────────
echo "=== 0. Verify connection ==="
SERVER_IP=$(ssh "$SSH_HOST" "hostname -I | awk '{print \$1}'")
echo "  Connected to: $SERVER_IP"
if [[ "$SERVER_IP" != 172.26.* ]]; then
    echo "  WARNING: Expected AWS private IP (172.26.*), got $SERVER_IP"
    echo "  Continuing anyway..."
fi

# ── 1. Check current state on AWS =──────────────────────────────────────
echo ""
echo "=== 1. Check current state on AWS ==="
ssh "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
echo "Owner of /var/www/gymies:"
ls -ld "$LP" 2>/dev/null
echo ""
echo "SlotEngine exists?"
ls -la "$LP/app/Services/SlotEngine.php" 2>/dev/null || echo "  ✗ NOT FOUND"
echo ""
echo "Traits directory?"
ls -la "$LP/app/Http/Controllers/Gymies/Traits/" 2>/dev/null || echo "  ✗ NOT FOUND"
echo ""
echo "AvailabilityController has SlotEngine?"
grep -c "SlotEngine" "$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php" 2>/dev/null || echo "  0 (no SlotEngine)"
echo ""
echo "Routes file:"
ls -la "$LP/routes/gymies.php" 2>/dev/null
echo ""
echo "Route: trainers/{id}/availability?"
grep 'publicAvailability' "$LP/routes/gymies.php" 2>/dev/null || echo "  ✗ NOT FOUND in routes"
echo ""
echo "PHP-FPM status:"
sudo systemctl status php8.4-fpm 2>/dev/null | head -3
REMOTE

# ── 2. Upload files ─────────────────────────────────────────────────────
echo ""
echo "=== 2. Upload files to /tmp/ ==="

# Create a staging directory with all files
STAGING="/tmp/gymies_deploy_$$"
mkdir -p "$STAGING/Services"
mkdir -p "$STAGING/Controllers/Gymies/Traits"
mkdir -p "$STAGING/Middleware/Gymies"

# SlotEngine
if [ -f "$LOCAL_STORE/backend/app/Services/SlotEngine.php" ]; then
    cp "$LOCAL_STORE/backend/app/Services/SlotEngine.php" "$STAGING/Services/"
    echo "  ✓ SlotEngine.php"
fi

# AvailabilityController
if [ -f "$LOCAL_BACKEND/Controllers/GymiesAvailabilityController.php" ]; then
    cp "$LOCAL_BACKEND/Controllers/GymiesAvailabilityController.php" "$STAGING/Controllers/Gymies/"
    echo "  ✓ GymiesAvailabilityController.php"
fi

# BookingController
if [ -f "$LOCAL_BACKEND/Controllers/GymiesBookingController.php" ]; then
    cp "$LOCAL_BACKEND/Controllers/GymiesBookingController.php" "$STAGING/Controllers/Gymies/"
    echo "  ✓ GymiesBookingController.php"
fi

# WaitlistController
if [ -f "$LOCAL_BACKEND/Controllers/GymiesWaitlistController.php" ]; then
    cp "$LOCAL_BACKEND/Controllers/GymiesWaitlistController.php" "$STAGING/Controllers/Gymies/"
    echo "  ✓ GymiesWaitlistController.php"
fi

# RecurringBookingController
if [ -f "$LOCAL_BACKEND/Controllers/GymiesRecurringBookingController.php" ]; then
    cp "$LOCAL_BACKEND/Controllers/GymiesRecurringBookingController.php" "$STAGING/Controllers/Gymies/"
    echo "  ✓ GymiesRecurringBookingController.php"
fi

# Traits
for TRAIT in TrainerRevenueTrait.php TrainerMessagingTrait.php TrainerClientsTrait.php TrainerSessionsTrait.php; do
    if [ -f "$LOCAL_BACKEND/Controllers/Traits/$TRAIT" ]; then
        cp "$LOCAL_BACKEND/Controllers/Traits/$TRAIT" "$STAGING/Controllers/Gymies/Traits/"
        echo "  ✓ $TRAIT"
    fi
done

# CancellationPolicyService, WaitlistService, RecurringBookingService
for SVC in CancellationPolicyService.php WaitlistService.php RecurringBookingService.php; do
    if [ -f "$LOCAL_STORE/backend/app/Services/$SVC" ]; then
        cp "$LOCAL_STORE/backend/app/Services/$SVC" "$STAGING/Services/"
        echo "  ✓ $SVC"
    fi
done

# IdempotencyMiddleware
if [ -f "$LOCAL_STORE/backend/app/Http/Middleware/Gymies/IdempotencyMiddleware.php" ]; then
    cp "$LOCAL_STORE/backend/app/Http/Middleware/Gymies/IdempotencyMiddleware.php" "$STAGING/Middleware/Gymies/"
    echo "  ✓ IdempotencyMiddleware.php"
fi

# Tar and upload
echo ""
echo "  Creating archive..."
tar -czf "/tmp/gymies_deploy.tar.gz" -C "$STAGING" .
scp "/tmp/gymies_deploy.tar.gz" "$SSH_HOST:/tmp/gymies_deploy.tar.gz"
echo "  ✓ Archive uploaded"

# Clean up local staging
rm -rf "$STAGING" "/tmp/gymies_deploy.tar.gz"

# ── 3. Deploy on AWS server ─────────────────────────────────────────────
echo ""
echo "=== 3. Deploy files on AWS server ==="
ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

echo "--- Extracting archive ---"
mkdir -p /tmp/gymies_deploy
cd /tmp/gymies_deploy
tar -xzf /tmp/gymies_deploy.tar.gz

echo "--- Creating directories ---"
sudo mkdir -p "$LP/app/Services"
sudo mkdir -p "$LP/app/Http/Controllers/Gymies/Traits"
sudo mkdir -p "$LP/app/Http/Middleware/Gymies"

echo "--- Deploying Services ---"
for f in Services/*.php; do
    [ -f "$f" ] || continue
    FNAME=$(basename "$f")
    sudo cp "$f" "$LP/app/Services/$FNAME"
    echo "  ✓ Services/$FNAME"
done

echo "--- Deploying Controllers ---"
for f in Controllers/Gymies/*.php; do
    [ -f "$f" ] || continue
    FNAME=$(basename "$f")
    sudo cp "$f" "$LP/app/Http/Controllers/Gymies/$FNAME"
    echo "  ✓ Controllers/$FNAME"
done

echo "--- Deploying Traits ---"
for f in Controllers/Gymies/Traits/*.php; do
    [ -f "$f" ] || continue
    FNAME=$(basename "$f")
    sudo cp "$f" "$LP/app/Http/Controllers/Gymies/Traits/$FNAME"
    echo "  ✓ Traits/$FNAME"
done

echo "--- Deploying Middleware ---"
for f in Middleware/Gymies/*.php; do
    [ -f "$f" ] || continue
    FNAME=$(basename "$f")
    sudo cp "$f" "$LP/app/Http/Middleware/Gymies/$FNAME"
    echo "  ✓ Middleware/$FNAME"
done

echo "--- Fix ownership ---"
sudo chown -R ubuntu:ubuntu "$LP/app/"

echo "--- Clean up ---"
rm -rf /tmp/gymies_deploy /tmp/gymies_deploy.tar.gz

echo ""
echo "--- Clear all caches ---"
cd "$LP"
sudo -u ubuntu php artisan route:clear 2>&1 || true
sudo -u ubuntu php artisan config:clear 2>&1 || true
sudo -u ubuntu php artisan cache:clear 2>&1 || true
sudo -u ubuntu php artisan view:clear 2>&1 || true

echo ""
echo "--- Restart PHP-FPM ---"
sudo systemctl restart php8.4-fpm
echo "  ✓ PHP-FPM restarted"

echo ""
echo "--- Test route:list ---"
sudo -u ubuntu php artisan route:list --path=trainers 2>&1 | head -20

echo ""
echo "--- Rebuild route cache ---"
sudo -u ubuntu php artisan route:cache 2>&1 || echo "Route cache failed (non-fatal)"

echo ""
echo "--- Seed availability data ---"
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "Checking trainer IDs..."
sudo -u ubuntu php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$trainers = DB::table('gymies_trainer_profiles')->select('id','user_id','display_name')->get();
echo 'Trainers found: ' . count(\$trainers) . PHP_EOL;
foreach (\$trainers as \$t) {
    echo \"  profile_id={\$t->id} user_id={\$t->user_id} name={\$t->display_name}\" . PHP_EOL;
}

// Check if availability data exists
\$slots = DB::table('gymies_availability_slots')->count();
echo PHP_EOL . \"Availability slots in DB: \$slots\" . PHP_EOL;
" 2>/dev/null || echo "PHP bootstrap failed"

echo ""
echo "--- Test API via localhost ---"
RESP=$(curl -s -H "Accept: application/json" -H "Host: www.gymiesapp.nl" \
  "http://127.0.0.1/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "HTTP localhost response (first 200):"
echo "$RESP" | head -c 200
echo ""
echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
except Exception as e:
    print(f'  Parse: {e}')
" 2>/dev/null

echo ""
echo "--- Test API via HTTPS (--resolve to localhost) ---"
RESP2=$(curl -sk --resolve "www.gymiesapp.nl:443:127.0.0.1" -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "HTTPS --resolve response (first 200):"
echo "$RESP2" | head -c 200
echo ""
echo "$RESP2" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
except Exception as e:
    print(f'  Parse: {e}')
" 2>/dev/null

echo ""
echo "--- Test API via HTTPS (real DNS) ---"
RESP3=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "HTTPS real DNS response (first 200):"
echo "$RESP3" | head -c 200
echo ""
echo "$RESP3" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
except Exception as e:
    print(f'  Parse: {e}')
" 2>/dev/null

echo ""
echo "--- Done ---"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Deploy to AWS complete                            ║"
echo "╚══════════════════════════════════════════════════════╝"
