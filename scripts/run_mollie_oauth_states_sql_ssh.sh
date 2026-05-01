#!/usr/bin/env bash
# Upload alter_gymies_mollie_oauth_states.sql en voer uit via SSH key — geen sudo.
# Het migrate-script leest het SQL-bestand vanaf elk pad; DB-credentials komen uit .env.
# Gebruik: ./scripts/run_mollie_oauth_states_sql_ssh.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
# Bestand in home van Gymiesagent — geen sudo nodig om naar /var/www te kopiëren.
REMOTE_SQL_NAME="alter_gymies_mollie_oauth_states.sql"

SQL_FILE="$PROJECT_DIR/database/alter_gymies_mollie_oauth_states.sql"
if [[ ! -f "$SQL_FILE" ]]; then
  echo "ERROR: $SQL_FILE niet gevonden."
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

echo "Uploaden en uitvoeren (geen sudo)..."
# scp naar host:bestandsnaam = in login-home op de server
scp -i "$SSH_KEY" -o IdentitiesOnly=yes "$SQL_FILE" "$SSH_TARGET:$REMOTE_SQL_NAME"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "$SSH_TARGET" \
  "cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php \$HOME/$REMOTE_SQL_NAME"
echo "Klaar."
