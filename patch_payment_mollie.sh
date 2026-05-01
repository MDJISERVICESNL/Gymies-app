#!/usr/bin/env bash
set -euo pipefail

# Patch GymiesPaymentController op de server voor Mollie Connect (betalingen naar trainer).
# Gebruik: bash patch_payment_mollie.sh
#
# Optionele env vars:
#   SSH_TARGET=gymies
#   SSH_KEY=$HOME/.ssh/id_ed25519_gymies
#   REMOTE_LARAVEL=/var/www/gymies

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

SSH_OPTS=()
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_SCRIPT="$SCRIPT_DIR/store/backend/scripts/patch_payment_mollie_connect.php"

if [[ ! -f "$PATCH_SCRIPT" ]]; then
  echo "ERROR: patch script niet gevonden: $PATCH_SCRIPT"
  exit 1
fi

echo "=== Patch GymiesPaymentController voor Mollie Connect ==="
echo "Server: $SSH_TARGET"
echo ""

scp "${SSH_OPTS[@]}" "$PATCH_SCRIPT" "$SSH_TARGET:/tmp/patch_payment_mollie_connect.php"

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo php /tmp/patch_payment_mollie_connect.php $REMOTE_LARAVEL && rm -f /tmp/patch_payment_mollie_connect.php" || {
  echo ""
  echo "Patch mislukt. Zie MOLLIE_CONNECT_PAYMENT_DEPLOY.md voor handmatige stappen."
  exit 1
}

echo ""
echo "Cache legen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan optimize:clear 2>/dev/null || true"

echo ""
echo "GymiesPaymentController gepatcht. Sessiebetalingen gaan nu naar het Mollie-account van de trainer."
