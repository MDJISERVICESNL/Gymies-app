#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Gymies Database Backup met Restore Verificatie
# ───────────────────────────────────────────────
# Maakt een MySQL dump, comprimeert, herstelt in een tijdelijke database
# om integriteit te verifiëren, en bewaart de laatste N backups.
#
# Gebruik:
#   chmod +x scripts/backup_met_verificatie.sh
#   ./scripts/backup_met_verificatie.sh
#
# Cron (dagelijks 03:00):
#   0 3 * * * /var/www/gymies/scripts/backup_met_verificatie.sh >> /var/log/gymies/backup.log 2>&1
#
# Vereist: mysql, mysqldump, gzip, gunzip
# Optioneel: AWS CLI (voor S3 offsite backup)
###############################################################################

# ── Configuratie (overschrijf via environment) ──────────────────────────────
BACKUP_DIR="${BACKUP_DIR:-/var/www/gymies/storage/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DB_HOST="${DB_HOST:-${RDS_HOST:-127.0.0.1}}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-gymies}"
DB_USER="${DB_USER:-gymies}"
DB_PASS="${DB_PASS:-}"
VERIFY_DB="${VERIFY_DB:-gymies_backup_verify}"
STATUS_FILE="${STATUS_FILE:-/var/www/gymies/storage/app/backup_status.json}"
S3_BUCKET="${S3_BUCKET:-}"           # Leeg = geen S3 upload
S3_PREFIX="${S3_PREFIX:-gymies-backups}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"   # Leeg = geen Slack notificatie

# ── Kleuren (als terminal) ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ── Helpers ─────────────────────────────────────────────────────────────────
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log()   { echo -e "[$(timestamp)] ${GREEN}INFO${NC}  $*"; }
warn()  { echo -e "[$(timestamp)] ${YELLOW}WARN${NC}  $*"; }
error() { echo -e "[$(timestamp)] ${RED}ERROR${NC} $*" >&2; }

mysql_cmd() {
    mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        ${DB_PASS:+--password="$DB_PASS"} "$@"
}

mysqldump_cmd() {
    mysqldump --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" \
        ${DB_PASS:+--password="$DB_PASS"} "$@"
}

cleanup_verify_db() {
    log "Opruimen verificatie-database '${VERIFY_DB}'..."
    mysql_cmd -e "DROP DATABASE IF EXISTS \`${VERIFY_DB}\`;" 2>/dev/null || true
}

write_status() {
    local status="$1" message="$2" backup_file="${3:-}" size_mb="${4:-0}" verified="${5:-false}"
    local rows_source="${6:-0}" rows_restored="${7:-0}"

    mkdir -p "$(dirname "$STATUS_FILE")"
    cat > "$STATUS_FILE" <<EOF
{
    "status": "${status}",
    "message": "${message}",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "backup_file": "${backup_file}",
    "size_mb": ${size_mb},
    "verified": ${verified},
    "rows_source": ${rows_source},
    "rows_restored": ${rows_restored},
    "retention_days": ${RETENTION_DAYS}
}
EOF
}

notify_slack() {
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        local color="$1" text="$2"
        curl -s -X POST "$SLACK_WEBHOOK" \
            -H 'Content-type: application/json' \
            -d "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${text}\"}]}" \
            > /dev/null 2>&1 || true
    fi
}

# ── Trap: opruimen bij fout ─────────────────────────────────────────────────
trap 'cleanup_verify_db; error "Backup mislukt!"; write_status "error" "Backup mislukt" "" 0 false; notify_slack "danger" "❌ Gymies backup MISLUKT op $(hostname) — $(timestamp)"' ERR

# ── Start ───────────────────────────────────────────────────────────────────
log "═══════════════════════════════════════════════"
log "Gymies Database Backup gestart"
log "═══════════════════════════════════════════════"

# Maak backup directory aan
mkdir -p "$BACKUP_DIR"

# Bestandsnaam met datum
DATE_STAMP=$(date '+%Y%m%d_%H%M%S')
DUMP_FILE="${BACKUP_DIR}/gymies_${DATE_STAMP}.sql"
GZ_FILE="${DUMP_FILE}.gz"

# ── Stap 1: Mysqldump ──────────────────────────────────────────────────────
log "Stap 1/5: Database dump maken van '${DB_NAME}'..."

mysqldump_cmd \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=OFF \
    --skip-lock-tables \
    --quick \
    "$DB_NAME" > "$DUMP_FILE"

DUMP_SIZE=$(stat -f%z "$DUMP_FILE" 2>/dev/null || stat --format=%s "$DUMP_FILE" 2>/dev/null || echo 0)
log "  Dump klaar: $(echo "scale=1; $DUMP_SIZE / 1048576" | bc)MB (ongecomprimeerd)"

# ── Stap 2: Comprimeren ────────────────────────────────────────────────────
log "Stap 2/5: Comprimeren..."
gzip -f "$DUMP_FILE"
GZ_SIZE=$(stat -f%z "$GZ_FILE" 2>/dev/null || stat --format=%s "$GZ_FILE" 2>/dev/null || echo 0)
GZ_SIZE_MB=$(echo "scale=1; $GZ_SIZE / 1048576" | bc)
log "  Gecomprimeerd: ${GZ_SIZE_MB}MB"

# ── Stap 3: Restore-verificatie ─────────────────────────────────────────────
log "Stap 3/5: Restore-verificatie starten..."

# Maak verificatie-database aan
cleanup_verify_db
mysql_cmd -e "CREATE DATABASE \`${VERIFY_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Herstel naar verificatie-database
gunzip -c "$GZ_FILE" | mysql_cmd "$VERIFY_DB"
log "  Restore naar '${VERIFY_DB}' voltooid."

# ── Stap 4: Row counts vergelijken ──────────────────────────────────────────
log "Stap 4/5: Rijen tellen en vergelijken..."

TABLES_TO_CHECK=(
    "gymies_users"
    "gymies_bookings"
    "gymies_trainers"
    "gymies_trainer_profiles"
    "gymies_payment_transactions"
    "gymies_chat_conversations"
    "gymies_chat_messages"
    "gymies_notifications"
)

TOTAL_SOURCE=0
TOTAL_RESTORED=0
MISMATCH=false

for TABLE in "${TABLES_TO_CHECK[@]}"; do
    # Controleer of tabel bestaat in bron
    SOURCE_EXISTS=$(mysql_cmd -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='${TABLE}';")
    if [[ "$SOURCE_EXISTS" -eq 0 ]]; then
        continue
    fi

    SOURCE_COUNT=$(mysql_cmd -N -e "SELECT COUNT(*) FROM \`${DB_NAME}\`.\`${TABLE}\`;")
    RESTORE_COUNT=$(mysql_cmd -N -e "SELECT COUNT(*) FROM \`${VERIFY_DB}\`.\`${TABLE}\`;")

    TOTAL_SOURCE=$((TOTAL_SOURCE + SOURCE_COUNT))
    TOTAL_RESTORED=$((TOTAL_RESTORED + RESTORE_COUNT))

    if [[ "$SOURCE_COUNT" -ne "$RESTORE_COUNT" ]]; then
        error "  MISMATCH ${TABLE}: bron=${SOURCE_COUNT}, restored=${RESTORE_COUNT}"
        MISMATCH=true
    else
        log "  ✓ ${TABLE}: ${SOURCE_COUNT} rijen OK"
    fi
done

# ── Stap 5: Opruimen ───────────────────────────────────────────────────────
log "Stap 5/5: Opruimen..."
cleanup_verify_db

if $MISMATCH; then
    error "VERIFICATIE MISLUKT — row counts komen niet overeen!"
    write_status "error" "Verificatie mislukt: row count mismatch" "$GZ_FILE" "$GZ_SIZE_MB" false "$TOTAL_SOURCE" "$TOTAL_RESTORED"
    notify_slack "danger" "⚠️ Gymies backup verificatie MISLUKT op $(hostname) — row count mismatch"
    exit 1
fi

log "Verificatie geslaagd: ${TOTAL_SOURCE} rijen correct hersteld."

# ── Oude backups opruimen ──────────────────────────────────────────────────
log "Oude backups opruimen (ouder dan ${RETENTION_DAYS} dagen)..."
DELETED=$(find "$BACKUP_DIR" -name "gymies_*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
if [[ "$DELETED" -gt 0 ]]; then
    log "  ${DELETED} oude backup(s) verwijderd."
fi

# Toon resterende backups
REMAINING=$(find "$BACKUP_DIR" -name "gymies_*.sql.gz" | wc -l)
log "  ${REMAINING} backup(s) bewaard."

# ── Optioneel: S3 upload ──────────────────────────────────────────────────
if [[ -n "$S3_BUCKET" ]]; then
    log "Uploaden naar S3: s3://${S3_BUCKET}/${S3_PREFIX}/..."
    if command -v aws &>/dev/null; then
        aws s3 cp "$GZ_FILE" "s3://${S3_BUCKET}/${S3_PREFIX}/$(basename "$GZ_FILE")" \
            --storage-class STANDARD_IA \
            --quiet
        log "  S3 upload voltooid."
    else
        warn "  AWS CLI niet geïnstalleerd — S3 upload overgeslagen."
    fi
fi

# ── Status schrijven ──────────────────────────────────────────────────────
write_status "ok" "Backup en verificatie geslaagd" "$GZ_FILE" "$GZ_SIZE_MB" true "$TOTAL_SOURCE" "$TOTAL_RESTORED"
notify_slack "good" "✅ Gymies backup OK op $(hostname) — ${GZ_SIZE_MB}MB, ${TOTAL_SOURCE} rijen geverifieerd"

log "═══════════════════════════════════════════════"
log "Backup compleet: ${GZ_FILE}"
log "═══════════════════════════════════════════════"
