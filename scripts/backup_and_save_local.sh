#!/usr/bin/env bash
set -euo pipefail

# Maakt een backup op de server (DB dump + app tar) en kopieert die lokaal naar backups/.
# Gebruik:
#   bash scripts/backup_and_save_local.sh
#
# Optionele env vars (zelfde als sync_trainmate_web.sh):
#   SSH_TARGET=gymies
#   SSH_KEY=$HOME/.ssh/TrainMaat
#   REMOTE_LARAVEL=/var/www/mdjiservices.nl/laravel

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/TrainMaat}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/mdjiservices.nl/laravel}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_BACKUPS="${LOCAL_BACKUPS:-$ROOT_DIR/backups}"
STAMP="$(date +%Y%m%d_%H%M%S)"

SSH_OPTS=()
if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-i "$SSH_KEY")
fi

mkdir -p "$LOCAL_BACKUPS"
echo "=== Backup op server en ophalen naar $LOCAL_BACKUPS ==="

# PHP-script naar server kopiëren
scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/run_backup_server.php" "$SSH_TARGET:/tmp/run_backup_server.php"

# Backup op server draaien; laatste regel is het backup-pad
BACKUP_PATH="$(
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && php /tmp/run_backup_server.php" | tail -n1
)"
if [[ -z "$BACKUP_PATH" ]]; then
  echo "Fout: geen backup-pad ontvangen van server." >&2
  exit 1
fi

echo "Backup op server: $BACKUP_PATH"
LOCAL_DIR="$LOCAL_BACKUPS/trainmaat_backup_$STAMP"
mkdir -p "$LOCAL_DIR"

# Backup-map van server naar lokaal kopiëren
scp -r "${SSH_OPTS[@]}" "$SSH_TARGET:$BACKUP_PATH/"* "$LOCAL_DIR/"

# Opruimen op server
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "rm -rf $BACKUP_PATH /tmp/run_backup_server.php"

echo "Backup lokaal opgeslagen in: $LOCAL_DIR"
echo "  - db.sql"
echo "  - app.tar.gz"
