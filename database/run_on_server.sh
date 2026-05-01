#!/usr/bin/env bash
# Op de server uitvoeren vanuit de map waar create_gymies_tables.sql staat.
# Gebruikt Laravel .env voor DB_* (zet eerst CD naar laravel root of export DB_* handmatig).
#
# Voorbeeld (op server):
#   cd /var/www/gymies.nl/laravel && bash -c 'export $(grep -E "^DB_|^APP_" .env | xargs) && /path/to/run_on_server.sh'
# Of: vul hieronder DB_NAME, DB_USER, DB_PASS in en run: bash run_on_server.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/create_gymies_tables.sql"

if [ ! -f "$SQL_FILE" ]; then
  echo "Niet gevonden: $SQL_FILE"
  exit 1
fi

# Als DB_DATABASE al gezet is (bijv. uit .env), gebruik die
DB_NAME="${DB_DATABASE:-}"
DB_USER="${DB_USERNAME:-}"
DB_PASS="${DB_PASSWORD:-}"

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then
  echo "Zet DB_DATABASE en DB_USERNAME (en optioneel DB_PASSWORD), of pas dit script aan."
  echo "Voorbeeld: export DB_DATABASE=mijn_db DB_USERNAME=mijn_user DB_PASSWORD=geheim"
  exit 1
fi

echo "Tabellen aanmaken in database: $DB_NAME"
mysql -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} "$DB_NAME" < "$SQL_FILE"
echo "Klaar. Tabellen:"
mysql -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} "$DB_NAME" -e "SHOW TABLES LIKE 'gymies_%';"
