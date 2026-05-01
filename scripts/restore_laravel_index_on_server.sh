#!/usr/bin/env bash
# Zet Laravel public/index.php terug op de server zodat /api/gymies (registreren, inloggen) weer werkt.
# Gebruik na een root-deploy of als "geen verbinding" bij registreren.
# SSH_TARGET=gymies ./scripts/restore_laravel_index_on_server.sh

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies.nl/laravel}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LARAVEL_INDEX="$PROJECT_DIR/deploy/laravel_public_index.php"

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET niet gezet. Bijv. export SSH_TARGET=gymies"
  exit 1
fi
if [[ ! -f "$LARAVEL_INDEX" ]]; then
  echo "ERROR: Niet gevonden: $LARAVEL_INDEX"
  exit 1
fi
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
else
  SSH_OPTS=()
fi

echo "Laravel index.php terugzetten op $SSH_TARGET..."
scp "${SSH_OPTS[@]}" "$LARAVEL_INDEX" "$SSH_TARGET:/tmp/laravel_index.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo cp /tmp/laravel_index.php $REMOTE_LARAVEL/public/index.php && sudo chown www-data:www-data $REMOTE_LARAVEL/public/index.php && rm -f /tmp/laravel_index.php"
echo "Klaar. Test: curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/api/gymies/trainers"
