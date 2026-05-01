#!/usr/bin/env bash
# Voert create_client_progress_table.php uit op de server via SSH key (geen mysql -p typen).
# Gebruik: ./scripts/run_client_progress_table_ssh.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

# Upload naar home (geen schrijfrecht op /var/www), daarna sudo cp + php
REMOTE_FILE="create_client_progress_table.php"
scp -o IdentitiesOnly=yes -i "$SSH_KEY" \
  "$SCRIPT_DIR/gymies_deploy/create_client_progress_table.php" \
  "$SSH_TARGET:~/$REMOTE_FILE"

echo "Kopiëren naar gymies_deploy en uitvoeren (sudo kan wachtwoord vragen)..."
ssh -t -o IdentitiesOnly=yes -i "$SSH_KEY" "$SSH_TARGET" \
  "sudo cp ~/$REMOTE_FILE $REMOTE_LARAVEL/gymies_deploy/ && cd $REMOTE_LARAVEL && php gymies_deploy/create_client_progress_table.php && rm -f ~/$REMOTE_FILE"

echo "Klaar."
