#!/usr/bin/env bash
# Draait op de server: laadt credentials uit ~/.gymies_db.env en voert de SQL uit.
# Eenmalig op de server aanmaken: ~/.gymies_db.env met DB_NAME, DB_USER, DB_PASS, DB_HOST (zie database/credentials.env.example).

set -e
ENV_FILE="$HOME/.gymies_db.env"
SQL_FILE="$HOME/create_gymies_tables.sql"

if [ ! -f "$ENV_FILE" ]; then
  echo "Maak eerst $ENV_FILE aan (zie database/credentials.env.example)."
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

for var in DB_NAME DB_USER DB_PASS; do
  if [ -z "${!var}" ]; then
    echo "Zet $var in $ENV_FILE"
    exit 1
  fi
done

if [ ! -f "$SQL_FILE" ]; then
  echo "Bestand niet gevonden: $SQL_FILE. Eerst uploaden met ./scripts/upload_gymies_db.sh"
  exit 1
fi

echo "Tabellen aanmaken in $DB_NAME ..."
mysql -h "${DB_HOST:-127.0.0.1}" -P "${DB_PORT:-3306}" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_FILE"
echo "Klaar."
mysql -h "${DB_HOST:-127.0.0.1}" -P "${DB_PORT:-3306}" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'gymies_%';"
