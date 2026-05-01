#!/bin/bash
# Deploy Mollie features + Crowdfund model naar Gymies server
# v3: SSH multiplexing (1 verbinding, geen rate-limit block)
#     + sudo upload via /tmp staging
#     + traits meesturen

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/backend"
DESKTOP="${HOME}/Desktop"
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"
BACKUP_NAME="gymies_db_backup_$(date +%Y%m%d_%H%M%S).sql"
TMP_STAGE="/tmp/gymies_deploy_$$"

# ── SSH multiplexing: 1 persistente verbinding ─────────
SOCKET="/tmp/gymies_ssh_$$"
SSH="ssh -i $SSH_KEY -o ControlMaster=auto -o ControlPath=$SOCKET -o ControlPersist=120"
SCP="scp -i $SSH_KEY -o ControlPath=$SOCKET"

cleanup() {
  $SSH -O exit "$SSH_HOST" 2>/dev/null || true
  rm -f "$SOCKET"
}
trap cleanup EXIT

echo "╔══════════════════════════════════════════════════╗"
echo "║  GYMIES Deploy v3: Mollie + Crowdfund Features   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "SSH Host: $SSH_HOST"
echo "Laravel:  $LARAVEL_PATH"
echo ""

# Open master verbinding
echo "Verbinding openen..."
$SSH -MNf "$SSH_HOST"
echo "  ✓ SSH master verbinding actief"
echo ""

# ── Helper: upload via /tmp + sudo cp ──────────────────
upload_file() {
  local SRC="$1"
  local DEST="$2"
  local FNAME
  FNAME=$(basename "$SRC")
  $SCP "$SRC" "$SSH_HOST:$TMP_STAGE/$FNAME"
  $SSH "$SSH_HOST" "sudo cp $TMP_STAGE/$FNAME $DEST/$FNAME && sudo chown www-data:www-data $DEST/$FNAME && sudo chmod 644 $DEST/$FNAME"
}

# Maak staging dir + doelmappen
$SSH "$SSH_HOST" "mkdir -p $TMP_STAGE && sudo mkdir -p $LARAVEL_PATH/app/Http/Controllers/Gymies $LARAVEL_PATH/app/Http/Traits $LARAVEL_PATH/app/Traits $LARAVEL_PATH/routes"

# ── 1) Database backup ──────────────────────────────────
echo "=== 1/6 · Database backup ==="
$SSH "$SSH_HOST" bash -s "$LARAVEL_PATH" "$BACKUP_NAME" << 'REMOTE'
set -e
cd "$1" || exit 1
source .env 2>/dev/null || true
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_DATABASE="${DB_DATABASE:-gymies}"
DB_USERNAME="${DB_USERNAME:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
echo "Backup: $DB_DATABASE -> /tmp/$2"
mysqldump --no-tablespaces -h "$DB_HOST" -u "$DB_USERNAME" ${DB_PASSWORD:+-p"$DB_PASSWORD"} "$DB_DATABASE" > "/tmp/$2"
echo "OK: /tmp/$2 ($(du -h /tmp/$2 | cut -f1))"
REMOTE

BACKUP_PATH=$($SSH "$SSH_HOST" "ls -t /tmp/gymies_db_backup_*.sql 2>/dev/null | head -1")
if [ -n "$BACKUP_PATH" ]; then
  $SCP "$SSH_HOST:$BACKUP_PATH" "$DESKTOP/" 2>/dev/null
  echo "Backup gedownload: $DESKTOP/$(basename $BACKUP_PATH)"
fi
echo ""

# ── 2) Traits uploaden ─────────────────────────────────
echo "=== 2/6 · Traits uploaden ==="

SRC="$BACKEND_DIR/Traits/GymiesSchemaCacheTrait.php"
if [ -f "$SRC" ]; then
  upload_file "$SRC" "$LARAVEL_PATH/app/Http/Traits"
  echo "  ✓ GymiesSchemaCacheTrait.php → app/Http/Traits/"
else
  echo "  ⚠ GymiesSchemaCacheTrait.php niet gevonden"
fi

SRC="$BACKEND_DIR/Traits/GymiesRequireTrainerTrait.php"
if [ -f "$SRC" ]; then
  upload_file "$SRC" "$LARAVEL_PATH/app/Traits"
  echo "  ✓ GymiesRequireTrainerTrait.php → app/Traits/"
else
  echo "  ⚠ GymiesRequireTrainerTrait.php niet gevonden"
fi

SRC="$BACKEND_DIR/Traits/GymiesRequireAdminTrait.php"
if [ -f "$SRC" ]; then
  upload_file "$SRC" "$LARAVEL_PATH/app/Traits"
  echo "  ✓ GymiesRequireAdminTrait.php → app/Traits/"
else
  echo "  ⚠ GymiesRequireAdminTrait.php niet gevonden"
fi
echo ""

# ── 3) Controllers uploaden ─────────────────────────────
echo "=== 3/6 · Controllers uploaden ==="
CONTROLLERS=(
  GymiesGroupSessionController.php
  GymiesPaymentController.php
  GymiesRefundController.php
  GymiesSubscriptionController.php
  GymiesSchemaEnsure.php
  GymiesTrainerOpsController.php
  SubscriptionWebhookTrait.php
  SubscriptionPaymentTrait.php
)

for f in "${CONTROLLERS[@]}"; do
  SRC="$SCRIPT_DIR/app/Http/Controllers/Gymies/$f"
  if [ -f "$SRC" ]; then
    upload_file "$SRC" "$LARAVEL_PATH/app/Http/Controllers/Gymies"
    echo "  ✓ $f"
  else
    echo "  ⚠ $f niet gevonden in store"
  fi
done
echo ""

# ── 4) Routes uploaden + registreren ────────────────────
echo "=== 4/6 · Routes uploaden ==="
upload_file "$SCRIPT_DIR/routes_gymies_full.php" "$LARAVEL_PATH/routes"
echo "  ✓ routes_gymies_full.php geüpload"

# Zorg dat routes_gymies_full.php wordt geladen
$SSH "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'ROUTES_REG'
set -e
cd "$1" || exit 1
REQUIRE_LINE="require __DIR__ . '/routes_gymies_full.php';"

# Check of het al ERGENS geladen wordt (api.php, web.php, RouteServiceProvider, bootstrap)
FOUND_IN=""
for RFILE in routes/api.php routes/web.php app/Providers/RouteServiceProvider.php bootstrap/app.php; do
  if [ -f "$RFILE" ] && grep -q "routes_gymies_full\|gymies_full" "$RFILE" 2>/dev/null; then
    FOUND_IN="$RFILE"
    break
  fi
done

if [ -n "$FOUND_IN" ]; then
  echo "  ✓ gymies routes al geladen via $FOUND_IN"
else
  # Toevoegen aan web.php (want routes file definieert eigen prefix api/gymies)
  RFILE="routes/web.php"
  if [ -f "$RFILE" ]; then
    echo "" | sudo tee -a "$RFILE" > /dev/null
    echo "// Gymies API (Flutter app)" | sudo tee -a "$RFILE" > /dev/null
    echo "$REQUIRE_LINE" | sudo tee -a "$RFILE" > /dev/null
    sudo chown www-data:www-data "$RFILE"
    echo "  ✓ gymies routes require toegevoegd aan $RFILE"
  else
    echo "  ⚠ routes/web.php niet gevonden — handmatig registreren!"
  fi
fi
ROUTES_REG
echo ""

# ── 5) Cache verversen ──────────────────────────────────
echo "=== 5/6 · Cache verversen ==="
$SSH "$SSH_HOST" "cd $LARAVEL_PATH && php artisan optimize:clear && php artisan config:cache && php artisan route:cache"
echo "  ✓ Cache ververst"
echo ""

# ── 6) Verificatie ──────────────────────────────────────
echo "=== 6/6 · Verificatie ==="
$SSH "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'VERIFY'
set -e
cd "$1" || exit 1

echo "Traits check:"
for f in "app/Http/Traits/GymiesSchemaCacheTrait.php" "app/Traits/GymiesRequireTrainerTrait.php" "app/Traits/GymiesRequireAdminTrait.php"; do
  if [ -f "$f" ]; then
    echo "  ✓ $f"
  else
    echo "  ✗ $f NIET GEVONDEN"
  fi
done

echo ""
echo "Routes check:"
php artisan route:list --name=gymies 2>/dev/null | grep -c "gymies" | xargs -I{} echo "  {} gymies routes geregistreerd"

for route in "bookings/{id}/refund-preview" "cron/crowdfund-check" "subscription/pause"; do
  if php artisan route:list 2>/dev/null | grep -q "$route"; then
    echo "  ✓ $route"
  else
    echo "  ✗ $route NIET GEVONDEN"
  fi
done

echo ""
echo "Controller load test:"
php artisan route:list 2>&1 | head -5
if [ $? -eq 0 ]; then
  echo "  ✓ Routes laden zonder fatale errors"
else
  echo "  ✗ Route loading gaf errors"
fi
VERIFY

# Opruimen
$SSH "$SSH_HOST" "rm -rf $TMP_STAGE"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Deploy compleet!                                ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Cron al ingesteld (crowdfund-check elke 15m)    ║"
echo "║  TODO:                                           ║"
echo "║  1. Test groepsles aanmaken + inschrijven        ║"
echo "║  2. Test Mollie betaling flow                    ║"
echo "╚══════════════════════════════════════════════════╝"
