#!/usr/bin/env bash
# Optioneel na deploy: sluitreden tickets + admin gebruikersnotities + Fee Switcher-kolom (DB-migraties).
# Gebruik:
#   ./scripts/run_optional_gymies_sql.sh
#   SSH_TARGET=gymies REMOTE_LARAVEL=/var/www/gymies ./scripts/run_optional_gymies_sql.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

echo "=== Optionele Gymies SQL op server ==="
echo "Target: $SSH_TARGET"
echo "Laravel: $REMOTE_LARAVEL"
echo ""

ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$SSH_TARGET" bash -s <<EOF
set -e
cd "$REMOTE_LARAVEL"
php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_ticket_close_reason.sql
php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_admin_user_notes.sql
# Fee Switcher (client_pays_service_fee op bank_accounts) — zie Cursor assets/sh-fee-switcher-eigen-baas.md
php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_trainer_bank_accounts_client_pays_fee.sql || true
echo "Klaar."
EOF

echo ""
echo "Klaar."
