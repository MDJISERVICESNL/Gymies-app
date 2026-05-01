#!/bin/bash
# ============================================================
# Deploy GymiesHmacMiddleware naar Gymies Server
# ============================================================
# Dit script:
# 1. Upload de HMAC middleware + updated config
# 2. Genereert een veilig HMAC secret (als er nog geen is)
# 3. Registreert de middleware
# 4. Toont het secret — bewaar dit voor Flutter --dart-define
# ============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SSH_HOST="gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — HMAC Middleware Deploy                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Stap 1: Upload bestanden ───────────────────────────────
echo "=== 1/4 Bestanden uploaden ==="

# Upload naar /tmp/ eerst (permission issues met /var/www)
scp \
  "$SCRIPT_DIR/app/Http/Middleware/GymiesHmacMiddleware.php" \
  "$SSH_HOST:/tmp/GymiesHmacMiddleware.php"

scp \
  "$SCRIPT_DIR/config/gymies.php" \
  "$SSH_HOST:/tmp/gymies_config.php"

scp \
  "$SCRIPT_DIR/scripts/register_gymies_hmac_middleware.php" \
  "$SSH_HOST:/tmp/register_gymies_hmac_middleware.php"

# Kopieer naar juiste plek met sudo
ssh "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
LP="$1"
sudo cp /tmp/GymiesHmacMiddleware.php "$LP/app/Http/Middleware/GymiesHmacMiddleware.php"
sudo cp /tmp/gymies_config.php "$LP/config/gymies.php"
sudo cp /tmp/register_gymies_hmac_middleware.php "$LP/scripts/register_gymies_hmac_middleware.php"
sudo chown ubuntu:ubuntu "$LP/app/Http/Middleware/GymiesHmacMiddleware.php"
sudo chown ubuntu:ubuntu "$LP/config/gymies.php"
rm -f /tmp/GymiesHmacMiddleware.php /tmp/gymies_config.php /tmp/register_gymies_hmac_middleware.php
echo "  ✓ Bestanden gekopieerd"
REMOTE

# ── Stap 2: HMAC Secret genereren ──────────────────────────
echo ""
echo "=== 2/4 HMAC Secret ==="
ssh "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
cd "$1"

# Check of er al een HMAC secret is
EXISTING=$(sudo grep "^GYMIES_HMAC_SECRET=" .env 2>/dev/null | cut -d= -f2)

if [ -n "$EXISTING" ] && [ "$EXISTING" != "" ]; then
  echo "  ✓ HMAC secret al geconfigureerd: ${EXISTING:0:8}..."
  echo "  (niet gewijzigd)"
else
  # Genereer een veilig 64-karakter hex secret
  NEW_SECRET=$(openssl rand -hex 32)

  if sudo grep -q "^GYMIES_HMAC_SECRET=" .env; then
    sudo sed -i "s|^GYMIES_HMAC_SECRET=.*|GYMIES_HMAC_SECRET=${NEW_SECRET}|" .env
    echo "  ✓ HMAC secret GEÜPDATET (was dev-default)"
  else
    echo "GYMIES_HMAC_SECRET=${NEW_SECRET}" | sudo tee -a .env > /dev/null
    echo "  ✓ HMAC secret GEGENEREERD en toegevoegd aan .env"
  fi

  echo ""
  echo "  ┌──────────────────────────────────────────────────────────┐"
  echo "  │  BEWAAR DIT SECRET — je hebt het nodig voor Flutter:    │"
  echo "  │                                                          │"
  echo "  │  $NEW_SECRET  │"
  echo "  │                                                          │"
  echo "  │  Flutter build commando:                                 │"
  echo "  │  flutter run --dart-define=GYMIES_HMAC_SECRET=$NEW_SECRET │"
  echo "  └──────────────────────────────────────────────────────────┘"
fi
REMOTE

# ── Stap 3: Middleware registreren ──────────────────────────
echo ""
echo "=== 3/4 Middleware registreren ==="
ssh "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
cd "$1"
php scripts/register_gymies_hmac_middleware.php 2>/dev/null || {
  echo "  ⚠ Auto-registratie mislukt — voeg handmatig toe:"
  echo "    'gymies.hmac' => \App\Http\Middleware\GymiesHmacMiddleware::class,"
}
REMOTE

# ── Stap 4: Cache opnieuw opbouwen ─────────────────────────
echo ""
echo "=== 4/4 Cache rebuilden ==="
ssh "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
cd "$1"
php artisan config:clear 2>/dev/null && echo "  config:clear OK"
php artisan route:clear 2>/dev/null && echo "  route:clear OK"
php artisan config:cache 2>/dev/null && echo "  config:cache OK"
php artisan route:cache 2>/dev/null && echo "  route:cache OK"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  HMAC Middleware GEDEPLOYED                          ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  De server valideert nu HMAC signatures op alle      ║"
echo "║  API requests (behalve webhooks en cron).            ║"
echo "║                                                      ║"
echo "║  Vergeet niet de Flutter app te builden met:         ║"
echo "║  --dart-define=GYMIES_HMAC_SECRET=<het-secret>       ║"
echo "║                                                      ║"
echo "║  Zonder het juiste secret worden alle app-requests   ║"
echo "║  geblokkeerd met 403 Forbidden.                      ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
