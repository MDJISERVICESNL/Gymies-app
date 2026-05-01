#!/bin/bash
# Deploy subscription features naar Gymies server
# 1. Maak DB backup en download naar Desktop
# 2. Kopieer bestanden en run migration

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP="${HOME}/Desktop"
BACKUP_NAME="gymies_db_backup_$(date +%Y%m%d_%H%M%S).sql"

# SSH config: Host gymies (zie ~/.ssh/config)
SSH_HOST="gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"

echo "=== 1) Database backup op server en download naar Desktop ==="
echo "SSH host: $SSH_HOST"
echo "Laravel path: $LARAVEL_PATH"
echo ""

ssh -i ~/.ssh/id_ed25519_gymies "$SSH_HOST" bash -s "$LARAVEL_PATH" "$BACKUP_NAME" << 'REMOTE'
set -e
LARAVEL_PATH="$1"
BACKUP_NAME="$2"
cd "$LARAVEL_PATH" || { echo "Laravel path niet gevonden: $LARAVEL_PATH"; exit 1; }

# Lees DB credentials uit .env
source .env 2>/dev/null || true
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_DATABASE="${DB_DATABASE:-gymies}"
DB_USERNAME="${DB_USERNAME:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"

echo "Backup maken: $DB_DATABASE -> /tmp/$BACKUP_NAME"
mysqldump -h "$DB_HOST" -u "$DB_USERNAME" ${DB_PASSWORD:+-p"$DB_PASSWORD"} "$DB_DATABASE" > "/tmp/$BACKUP_NAME"
echo "Backup klaar: /tmp/$BACKUP_NAME"
echo "/tmp/$BACKUP_NAME"
REMOTE

BACKUP_PATH=$(ssh -i ~/.ssh/id_ed25519_gymies "$SSH_HOST" "ls -t /tmp/gymies_db_backup_*.sql 2>/dev/null | head -1")
if [ -n "$BACKUP_PATH" ]; then
  echo ""
  echo "Downloaden naar $DESKTOP/..."
  scp -i ~/.ssh/id_ed25519_gymies "$SSH_HOST:$BACKUP_PATH" "$DESKTOP/"
  echo "Backup opgeslagen: $DESKTOP/$(basename $BACKUP_PATH)"
fi

echo ""
echo "=== 2) Deploy subscription features ==="
cd "$SCRIPT_DIR"
./deploy_subscription_features.sh "$LARAVEL_PATH" 2>/dev/null || true

echo ""
echo "=== 3) Bestanden naar server kopiëren + migrate ==="
scp -i ~/.ssh/id_ed25519_gymies \
  "$SCRIPT_DIR/app/Http/Controllers/Gymies/SubscriptionFeaturesAdminTrait.php" \
  "$SCRIPT_DIR/app/Http/Controllers/Gymies/SubscriptionEntitlementsTrait.php" \
  "$SCRIPT_DIR/app/Http/Controllers/Gymies/TrainerMediaValidationTrait.php" \
  "$SSH_HOST:$LARAVEL_PATH/app/Http/Controllers/Gymies/"

scp -i ~/.ssh/id_ed25519_gymies \
  "$SCRIPT_DIR/database/migrations/2025_03_12_000000_create_gymies_subscription_features_table.php" \
  "$SSH_HOST:$LARAVEL_PATH/database/migrations/"

echo ""
echo "Migration draaien op server..."
ssh -i ~/.ssh/id_ed25519_gymies "$SSH_HOST" "cd $LARAVEL_PATH && php artisan migrate --force"
ssh -i ~/.ssh/id_ed25519_gymies "$SSH_HOST" "cd $LARAVEL_PATH && php artisan optimize:clear && php artisan config:cache && php artisan route:cache"

echo ""
echo "=== 4) FFmpeg/ffprobe check (voor video-duur validatie) ==="
ssh -i ~/.ssh/id_ed25519_gymies "$SSH_HOST" "which ffprobe 2>/dev/null || echo 'FFprobe niet gevonden. Installeer ffmpeg voor video-validatie: apt install ffmpeg'"

echo ""
echo "Klaar. Vergeet niet:"
echo "  - use SubscriptionFeaturesAdminTrait / SubscriptionEntitlementsTrait in controllers"
echo "  - use TrainerMediaValidationTrait + validateVideoDuration(\$file) in storeMedia()"
