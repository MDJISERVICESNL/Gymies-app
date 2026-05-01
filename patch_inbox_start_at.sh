#!/usr/bin/env bash
set -euo pipefail

# Patch GymiesAdminController: fix "unknown column start_at" in inbox.
# Gebruik: bash patch_inbox_start_at.sh

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

SSH_OPTS=()
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_SCRIPT="$SCRIPT_DIR/store/backend/scripts/patch_inbox_start_at.php"

if [[ ! -f "$PATCH_SCRIPT" ]]; then
  echo "ERROR: $PATCH_SCRIPT niet gevonden"
  exit 1
fi

echo "=== Patch start_at fix voor Control Tower inbox ==="
scp "${SSH_OPTS[@]}" "$PATCH_SCRIPT" "$SSH_TARGET:/tmp/patch_inbox_start_at.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo php /tmp/patch_inbox_start_at.php $REMOTE_LARAVEL && rm -f /tmp/patch_inbox_start_at.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan optimize:clear 2>/dev/null || true"
echo "Patch klaar."
