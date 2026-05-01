#!/bin/bash
# ============================================================
# Zet Mollie terug naar LIVE modus
# ============================================================
# Draai dit NA het testen om terug te schakelen naar echte betalingen.
# ============================================================

set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Mollie terugzetten naar LIVE               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Check: heeft de gebruiker een live key?
read -p "Voer je Mollie LIVE API key in (live_...): " LIVE_KEY

if [[ ! "$LIVE_KEY" == live_* ]]; then
  echo ""
  echo "FOUT: Key moet beginnen met 'live_'"
  echo "Vind je live key op: https://my.mollie.com → Developers → API keys"
  exit 1
fi

echo ""
echo "Mollie terugzetten naar LIVE met key: ${LIVE_KEY:0:10}..."
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" "$LIVE_KEY" << 'REMOTE'
set -e
cd "$1"
LIVE_KEY="$2"

# Backup
cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

# Update
sed -i "s|^MOLLIE_API_KEY=.*|MOLLIE_API_KEY=${LIVE_KEY}|" .env
sed -i "s|^MOLLIE_TESTMODE=.*|MOLLIE_TESTMODE=false|" .env

echo "  .env geüpdatet:"
grep -E "^MOLLIE_(API_KEY|TESTMODE)=" .env | sed 's/^/    /'

# Cache rebuild
php artisan config:clear 2>/dev/null
php artisan config:cache 2>/dev/null
echo ""
echo "  ✓ Config cache opnieuw opgebouwd"

# Verify
CONFIG_KEY=$(php artisan tinker --execute="echo config('gymies.mollie_api_key');" 2>/dev/null | tail -1)
CONFIG_TEST=$(php artisan tinker --execute="echo config('gymies.mollie_testmode') ? 'true' : 'false';" 2>/dev/null | tail -1)
echo "  Verificatie: key=${CONFIG_KEY:0:10}... testmode=$CONFIG_TEST"
REMOTE

echo ""
echo "✓ Mollie staat weer op LIVE. Echte betalingen zijn actief."
