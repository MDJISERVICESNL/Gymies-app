#!/usr/bin/env bash
# 1. Upload de SQL naar de server
# 2. Voer de SQL uit op de server (tabellen aanmaken)
# Credentials staan in database/credentials.env (staat in .gitignore)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SQL_FILE="$PROJECT_DIR/database/create_gymies_tables.sql"
CREDENTIALS="$PROJECT_DIR/database/credentials.env"
REMOTE="niyyahpath"

if [ ! -f "$SQL_FILE" ]; then
  echo "Bestand niet gevonden: $SQL_FILE"
  exit 1
fi

if [ ! -f "$CREDENTIALS" ]; then
  echo "Maak database/credentials.env aan met: DB_NAME, DB_USER, DB_PASS, DB_HOST, DB_PORT"
  exit 1
fi

# shellcheck source=/dev/null
source "$CREDENTIALS"

echo "Uploaden SQL naar de server ..."
scp "$SQL_FILE" "$REMOTE:~/create_gymies_tables.sql"

echo "Tabellen aanmaken in database $DB_NAME ..."
ssh "$REMOTE" "mysql -h ${DB_HOST:-127.0.0.1} -P ${DB_PORT:-3306} -u $DB_USER -p'$DB_PASS' $DB_NAME < ~/create_gymies_tables.sql"

echo "Klaar. Tabellen:"
ssh "$REMOTE" "mysql -h ${DB_HOST:-127.0.0.1} -P ${DB_PORT:-3306} -u $DB_USER -p'$DB_PASS' $DB_NAME -e \"SHOW TABLES LIKE 'gymies_%';\""
