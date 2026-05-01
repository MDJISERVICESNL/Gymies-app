#!/usr/bin/env bash
set -euo pipefail

# Patch GymiesAdminController::updateTicket om bij afgehandeld (resolved) een notificatie
# te sturen naar de klant/trainer.
#
# Gebruik: bash patch_ticket_notification.sh
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
PATCH_SCRIPT="$SCRIPT_DIR/store/backend/scripts/patch_ticket_closed_notification.php"

if [[ ! -f "$PATCH_SCRIPT" ]]; then
  echo "ERROR: patch script niet gevonden: $PATCH_SCRIPT"
  exit 1
fi

echo "=== Patch GymiesAdminController voor ticket-closed notificatie ==="
echo "Server: $SSH_TARGET"
echo ""

# Upload patch script
scp "${SSH_OPTS[@]}" "$PATCH_SCRIPT" "$SSH_TARGET:/tmp/patch_ticket_closed_notification.php"

# Run patch op server (sudo voor schrijven naar app/Http/Controllers)
echo "Patch uitvoeren..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo php /tmp/patch_ticket_closed_notification.php $REMOTE_LARAVEL && rm -f /tmp/patch_ticket_closed_notification.php" || {
  echo ""
  echo "Patch mislukt. Controleer of TicketClosedNotificationHelper.php op de server staat."
  exit 1
}

echo ""
echo "Cache legen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan optimize:clear 2>/dev/null || true"

echo ""
echo "Ticket-closed notificatie patch klaar."
