#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# GYMIES Database Backup — dagelijks geautomatiseerd
# ═══════════════════════════════════════════════════════════════
#
# Wat het doet:
# 1. MySQL dump van gymies database
# 2. Comprimeert met gzip
# 3. Encrypt met openssl (AES-256)
# 4. Upload naar S3 (optioneel)
# 5. Verwijdert backups ouder dan 30 dagen
#
# Installatie:
#   1. Kopieer naar server: /var/www/gymies/storage/scripts/backup_database.sh
#   2. chmod +x /var/www/gymies/storage/scripts/backup_database.sh
#   3. Voeg toe aan crontab:
#      sudo crontab -e
#      0 3 * * * /var/www/gymies/storage/scripts/backup_database.sh >> /var/log/gymies_backup.log 2>&1
#
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ── Configuratie ──
LARAVEL_PATH="/var/www/gymies"
BACKUP_DIR="/var/www/gymies/storage/backups"
RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="gymies_db_${DATE}"

# Encryptie wachtwoord (lees uit .env of stel hier in)
ENCRYPT_PASS="${BACKUP_ENCRYPT_KEY:-$(grep '^APP_KEY=' "$LARAVEL_PATH/.env" 2>/dev/null | cut -d= -f2)}"

# Database credentials uit Laravel .env
DB_HOST=$(grep '^DB_HOST=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_PORT=$(grep '^DB_PORT=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_DATABASE=$(grep '^DB_DATABASE=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_USERNAME=$(grep '^DB_USERNAME=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_PASSWORD=$(grep '^DB_PASSWORD=' "$LARAVEL_PATH/.env" | cut -d= -f2)

# Defaults
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

# ── Start ──
echo ""
echo "═══ GYMIES Database Backup ═══"
echo "Datum:    $(date)"
echo "Database: $DB_DATABASE"
echo ""

# Maak backup directory
mkdir -p "$BACKUP_DIR"

# ── Stap 1: MySQL Dump ──
echo "1. MySQL dump starten..."
mysqldump \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --user="$DB_USERNAME" \
    --password="$DB_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --quick \
    --lock-tables=false \
    "$DB_DATABASE" > "$BACKUP_DIR/${BACKUP_NAME}.sql"

DUMP_SIZE=$(du -h "$BACKUP_DIR/${BACKUP_NAME}.sql" | cut -f1)
echo "   ✓ Dump compleet: ${DUMP_SIZE}"

# ── Stap 2: Comprimeren ──
echo "2. Comprimeren..."
gzip "$BACKUP_DIR/${BACKUP_NAME}.sql"
GZ_SIZE=$(du -h "$BACKUP_DIR/${BACKUP_NAME}.sql.gz" | cut -f1)
echo "   ✓ Gecomprimeerd: ${GZ_SIZE}"

# ── Stap 3: Encrypten ──
echo "3. Encrypten (AES-256-CBC)..."
openssl enc -aes-256-cbc -salt -pbkdf2 \
    -in "$BACKUP_DIR/${BACKUP_NAME}.sql.gz" \
    -out "$BACKUP_DIR/${BACKUP_NAME}.sql.gz.enc" \
    -pass "pass:${ENCRYPT_PASS}"

rm -f "$BACKUP_DIR/${BACKUP_NAME}.sql.gz"
ENC_SIZE=$(du -h "$BACKUP_DIR/${BACKUP_NAME}.sql.gz.enc" | cut -f1)
echo "   ✓ Encrypted: ${ENC_SIZE}"

# ── Stap 4: Upload naar S3 (optioneel) ──
if command -v aws &> /dev/null; then
    S3_BUCKET=$(grep '^AWS_BUCKET=' "$LARAVEL_PATH/.env" 2>/dev/null | cut -d= -f2)
    if [ -n "$S3_BUCKET" ]; then
        echo "4. Upload naar S3..."
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.sql.gz.enc" \
            "s3://${S3_BUCKET}/backups/database/${BACKUP_NAME}.sql.gz.enc" \
            --storage-class STANDARD_IA \
            --quiet
        echo "   ✓ Geüpload naar s3://${S3_BUCKET}/backups/database/"
    else
        echo "4. S3 overgeslagen (geen AWS_BUCKET in .env)"
    fi
else
    echo "4. S3 overgeslagen (aws CLI niet geïnstalleerd)"
fi

# ── Stap 5: Oude backups opruimen ──
echo "5. Oude backups verwijderen (ouder dan ${RETENTION_DAYS} dagen)..."
DELETED=$(find "$BACKUP_DIR" -name "gymies_db_*.enc" -mtime +$RETENTION_DAYS -delete -print | wc -l)
echo "   ✓ ${DELETED} oude backup(s) verwijderd"

# ── Stap 6: Verificatie ──
echo ""
echo "═══ Resultaat ═══"
echo "Bestand: $BACKUP_DIR/${BACKUP_NAME}.sql.gz.enc"
echo "Grootte: $ENC_SIZE"
echo "Backups in folder: $(ls "$BACKUP_DIR"/gymies_db_*.enc 2>/dev/null | wc -l)"
echo ""

# Lijst laatste 5 backups
echo "Laatste backups:"
ls -lht "$BACKUP_DIR"/gymies_db_*.enc 2>/dev/null | head -5
echo ""

echo "═══ Backup compleet ═══"
echo ""

# ── Restore instructies (voor referentie) ──
# Decrypt:
#   openssl enc -aes-256-cbc -d -pbkdf2 -in FILE.sql.gz.enc -out FILE.sql.gz -pass "pass:YOUR_KEY"
# Decompress:
#   gunzip FILE.sql.gz
# Restore:
#   mysql -u root -p gymies < FILE.sql
