#!/usr/bin/env bash
#
# Gymies database-migratie via SSH met key Gymies.
# Voer uit vanaf de Gymies-projectmap (niet op de server).
#
# Vereisten: SSH-key "Gymies", toegang tot de server, Laravel .env op de server.
#
# Gebruik:
#   ./scripts/migrate_gymies_db_ssh.sh              # Volledige migratie (hoofd + admin)
#   ./scripts/migrate_gymies_db_ssh.sh admin-only   # Alleen admin/support-tabellen (laatste update)
#
# Of met eigen variabelen:
#   SSH_KEY=~/.ssh/Gymies SSH_USER=user SSH_HOST=gymies-server REMOTE_LARAVEL=/var/www/gymies.nl/laravel ./scripts/migrate_gymies_db_ssh.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# SSH-key en server: pas aan voor jouw Gymies-server
SSH_KEY="${SSH_KEY:-$HOME/.ssh/Gymies}"
SSH_USER="${SSH_USER:-}"
SSH_HOST="${SSH_HOST:-}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies.nl/laravel}"

SSH_TARGET="${SSH_TARGET:-${SSH_USER}@${SSH_HOST}}"
if [[ -z "$SSH_TARGET" || "$SSH_TARGET" == "@" ]]; then
  echo "ERROR: Stel SSH_TARGET in of SSH_USER en SSH_HOST (bijv. SSH_USER=user SSH_HOST=gymies-server)"
  exit 1
fi

# Alleen admin/support-update uitvoeren (geen hoofdtabellen opnieuw)?
ADMIN_ONLY=false
if [ "${1:-}" = "admin-only" ] || [ "${1:-}" = "--admin-only" ]; then
  ADMIN_ONLY=true
fi

echo "== Gymies database-migratie via SSH =="
if [ "$ADMIN_ONLY" = true ]; then
  echo "Modus: alleen admin/support-update (geen hoofdtabellen)"
fi
echo "Key: ${SSH_KEY}"
echo "Target: ${SSH_TARGET}"
echo "Laravel (op server): ${REMOTE_LARAVEL}"
echo ""

if [ ! -f "$SSH_KEY" ]; then
  echo "ERROR: SSH-key niet gevonden: $SSH_KEY"
  echo "Zet de key op die locatie of export SSH_KEY=/pad/naar/Gymies"
  exit 1
fi

SQL_MAIN="$PROJECT_DIR/database/create_gymies_tables.sql"
SQL_ADMIN="$PROJECT_DIR/database/admin_dashboard_schema.sql"
RUNNER="$SCRIPT_DIR/run_migrate_gymies_sql_server.php"

if [ "$ADMIN_ONLY" = false ] && [ ! -f "$SQL_MAIN" ]; then
  echo "ERROR: SQL-bestand niet gevonden: $SQL_MAIN"
  exit 1
fi
if [ ! -f "$RUNNER" ]; then
  echo "ERROR: Runner niet gevonden: $RUNNER"
  exit 1
fi
if [ ! -f "$SQL_ADMIN" ]; then
  echo "ERROR: Admin SQL niet gevonden: $SQL_ADMIN"
  exit 1
fi

echo "1) SQL en runner naar server kopiëren..."
if [ "$ADMIN_ONLY" = false ]; then
  scp -i "$SSH_KEY" "$SQL_MAIN" "$SSH_TARGET:/tmp/create_gymies_tables.sql"
fi
scp -i "$SSH_KEY" "$RUNNER" "$SSH_TARGET:/tmp/run_migrate_gymies_sql_server.php"
scp -i "$SSH_KEY" "$SQL_ADMIN" "$SSH_TARGET:/tmp/admin_dashboard_schema.sql"

if [ "$ADMIN_ONLY" = true ]; then
  echo "2) Alleen admin/support-update uitvoeren..."
  ssh -i "$SSH_KEY" "$SSH_TARGET" "cd '$REMOTE_LARAVEL' && php /tmp/run_migrate_gymies_sql_server.php /tmp/admin_dashboard_schema.sql"
else
  echo "2) Migratie uitvoeren op server (hoofdtabellen)..."
  ssh -i "$SSH_KEY" "$SSH_TARGET" "cd '$REMOTE_LARAVEL' && php /tmp/run_migrate_gymies_sql_server.php /tmp/create_gymies_tables.sql"

  echo "3) Migratie uitvoeren (admin/support-tabellen)..."
  ssh -i "$SSH_KEY" "$SSH_TARGET" "cd '$REMOTE_LARAVEL' && php /tmp/run_migrate_gymies_sql_server.php /tmp/admin_dashboard_schema.sql"
fi

echo "4) Opruimen op server..."
if [ "$ADMIN_ONLY" = true ]; then
  ssh -i "$SSH_KEY" "$SSH_TARGET" "rm -f /tmp/admin_dashboard_schema.sql /tmp/run_migrate_gymies_sql_server.php"
else
  ssh -i "$SSH_KEY" "$SSH_TARGET" "rm -f /tmp/create_gymies_tables.sql /tmp/admin_dashboard_schema.sql /tmp/run_migrate_gymies_sql_server.php"
fi

echo ""
echo "Klaar. Gymies-database-migratie is uitgevoerd."
