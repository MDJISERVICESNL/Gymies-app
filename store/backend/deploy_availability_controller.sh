#!/bin/bash
# ============================================================
# Deploy controllers + routes naar GYMIES server
# Gebruikt 1x scp (batch) + 1x ssh om rate limiting te voorkomen
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL_DIR="$SCRIPT_DIR/app/Http/Controllers/Gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Controllers Deployen                       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 1/2 Alle bestanden uploaden in ÉÉN scp-call ──
echo "=== 1/2 Bestanden uploaden (batch) ==="
scp -i "$SSH_KEY" \
  "$CTRL_DIR/GymiesAvailabilityController.php" \
  "$CTRL_DIR/GymiesBookingController.php" \
  "$CTRL_DIR/GymiesSpoedInvalController.php" \
  "$CTRL_DIR/GymiesTrainerController.php" \
  "$CTRL_DIR/GymiesSpecialtyController.php" \
  "$SCRIPT_DIR/routes_gymies_full.php" \
  "$SSH_HOST:/tmp/"
echo "  ✓ 6 bestanden geüpload"

# ── 2/2 Installeren + cache rebuilden in ÉÉN ssh-call ──
echo ""
echo "=== 2/2 Installeren + cache ==="
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
LP="$1"
DEST="$LP/app/Http/Controllers/Gymies"

echo "  Kopiëren..."
sudo cp /tmp/GymiesAvailabilityController.php "$DEST/"
sudo cp /tmp/GymiesBookingController.php "$DEST/"
sudo cp /tmp/GymiesSpoedInvalController.php "$DEST/"
sudo cp /tmp/GymiesTrainerController.php "$DEST/"
sudo cp /tmp/GymiesSpecialtyController.php "$DEST/"
sudo cp /tmp/routes_gymies_full.php "$LP/routes/routes_gymies_full.php"

echo "  Permissions..."
sudo chown www-data:www-data \
  "$DEST/GymiesAvailabilityController.php" \
  "$DEST/GymiesBookingController.php" \
  "$DEST/GymiesSpoedInvalController.php" \
  "$DEST/GymiesTrainerController.php" \
  "$DEST/GymiesSpecialtyController.php" \
  "$LP/routes/routes_gymies_full.php"

echo "  Opruimen..."
rm -f /tmp/GymiesAvailabilityController.php \
  /tmp/GymiesBookingController.php \
  /tmp/GymiesSpoedInvalController.php \
  /tmp/GymiesTrainerController.php \
  /tmp/GymiesSpecialtyController.php \
  /tmp/routes_gymies_full.php

echo "  ✓ Controllers geïnstalleerd"

echo ""
echo "  Cache rebuilden..."
cd "$LP"
sudo -u www-data php artisan config:clear 2>/dev/null && echo "    config:clear OK"
sudo -u www-data php artisan route:clear 2>/dev/null && echo "    route:clear OK"
sudo -u www-data php artisan config:cache 2>/dev/null && echo "    config:cache OK"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "    route:cache OK"
echo "  ✓ Cache rebuilden klaar"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Controllers GEDEPLOYED                              ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  ✓ GymiesAvailabilityController (slot_date)          ║"
echo "║  ✓ GymiesBookingController (slot validatie)          ║"
echo "║  ✓ GymiesSpoedInvalController (slot_date fallback)  ║"
echo "║  ✓ GymiesTrainerController (dynamic columns)        ║"
echo "║  ✓ GymiesSpecialtyController (aanvraag-systeem)     ║"
echo "║  ✓ routes_gymies_full.php (alle routes)             ║"
echo "╚══════════════════════════════════════════════════════╝"
