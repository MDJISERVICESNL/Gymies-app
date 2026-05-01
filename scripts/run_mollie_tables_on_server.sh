#!/usr/bin/env bash
# Upload alter_gymies_mollie_payment_tables.sql naar de server en voer het uit.
# Gebruik: ./scripts/run_mollie_tables_on_server.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
REMOTE_STAGING="${REMOTE_STAGING:-~/gymies_upload}"

SQL_FILE="$PROJECT_DIR/database/alter_gymies_mollie_payment_tables.sql"
if [[ ! -f "$SQL_FILE" ]]; then
  echo "ERROR: $SQL_FILE niet gevonden."
  exit 1
fi

echo "Uploaden van alter_gymies_mollie_payment_tables.sql en uitvoeren op de server..."
ssh -i "$SSH_KEY" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING"
scp -i "$SSH_KEY" -o ConnectTimeout=10 "$SQL_FILE" "$SSH_TARGET:$REMOTE_STAGING/alter_gymies_mollie_payment_tables.sql"
ssh -i "$SSH_KEY" "$SSH_TARGET" "cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php $REMOTE_STAGING/alter_gymies_mollie_payment_tables.sql"
echo "Klaar."
echo "Bij 'Duplicate column name paid_at' is de kolom er al; verder niets doen."
