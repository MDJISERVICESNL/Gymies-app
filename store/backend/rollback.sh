#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# Gymies — Deployment Rollback Script
# ══════════════════════════════════════════════════════════════════════
# Draait de laatste deployment terug naar de vorige backup.
#
# Gebruik: bash rollback.sh [backup_dir]
#   Zonder argument: toont beschikbare backups en laat je kiezen.
#   Met argument:    gebruikt die specifieke backup map.
#
# Wat het doet:
#   1. Stopt queue workers en Reverb
#   2. Kopieert backup bestanden terug
#   3. Draait de laatste migratie batch terug (optioneel)
#   4. Herstelt cache
#   5. Herstart services
# ══════════════════════════════════════════════════════════════════════

set -uo pipefail

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"
BACKUP_BASE="/var/www/gymies_backups"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Gymies — Deployment Rollback                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Stap 0: Backup selecteren ──────────────────────────────────────

if [ -n "${1:-}" ]; then
    BACKUP_DIR="$1"
else
    step "Beschikbare backups"
    BACKUPS=$(ssh -i "$SSH_KEY" "$SSH_HOST" "ls -dt ${BACKUP_BASE}/*/  2>/dev/null | head -10" 2>/dev/null)

    if [ -z "$BACKUPS" ]; then
        fail "Geen backups gevonden in ${BACKUP_BASE}/"
        echo "  Maak eerst een backup met: sudo cp -r $LP ${BACKUP_BASE}/\$(date +%Y%m%d_%H%M%S)"
        exit 1
    fi

    echo "  Recente backups:"
    echo "$BACKUPS" | nl -ba
    echo ""
    read -p "  Kies een nummer (of plak het volledige pad): " CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
        BACKUP_DIR=$(echo "$BACKUPS" | sed -n "${CHOICE}p" | tr -d '[:space:]')
    else
        BACKUP_DIR="$CHOICE"
    fi
fi

if [ -z "$BACKUP_DIR" ]; then
    fail "Geen backup geselecteerd."
    exit 1
fi

echo "  Geselecteerde backup: $BACKUP_DIR"

# Controleer of backup bestaat
if ! ssh -i "$SSH_KEY" "$SSH_HOST" "test -d '$BACKUP_DIR'"; then
    fail "Backup map niet gevonden: $BACKUP_DIR"
    exit 1
fi

# ── Bevestiging ────────────────────────────────────────────────────

echo ""
echo -e "  ${YELLOW}WAARSCHUWING: Dit overschrijft de huidige deployment!${NC}"
read -p "  Doorgaan? (ja/nee): " CONFIRM
if [ "$CONFIRM" != "ja" ]; then
    echo "  Rollback geannuleerd."
    exit 0
fi

# ── Stap 1: Services stoppen ─────────────────────────────────────

step "1/5 — Services stoppen"

ssh -i "$SSH_KEY" "$SSH_HOST" "
    # Queue workers stoppen (als ze draaien)
    cd $LP && sudo -u www-data php artisan queue:restart 2>/dev/null || true
    echo '  Queue workers gestopt'
"
ok "Services gestopt"

# ── Stap 2: Huidige staat backuppen ─────────────────────────────

step "2/5 — Huidige staat backuppen (rollback van rollback)"

ROLLBACK_BACKUP="${BACKUP_BASE}/pre_rollback_$(date +%Y%m%d_%H%M%S)"
ssh -i "$SSH_KEY" "$SSH_HOST" "
    sudo mkdir -p '$ROLLBACK_BACKUP'
    sudo cp -r $LP/app $LP/config $LP/routes* $LP/database '$ROLLBACK_BACKUP/' 2>/dev/null
    sudo cp $LP/.env '$ROLLBACK_BACKUP/.env' 2>/dev/null
    echo '  Pre-rollback backup: $ROLLBACK_BACKUP'
"
ok "Huidige staat bewaard in: $ROLLBACK_BACKUP"

# ── Stap 3: Backup terugzetten ───────────────────────────────────

step "3/5 — Backup bestanden herstellen"

ssh -i "$SSH_KEY" "$SSH_HOST" "
    # App code herstellen
    for dir in app config routes database; do
        if [ -d '${BACKUP_DIR}/\$dir' ]; then
            sudo cp -r '${BACKUP_DIR}/\$dir' $LP/
            echo \"  \$dir/ hersteld\"
        fi
    done

    # Routes bestanden op root level
    for f in ${BACKUP_DIR}/routes_gymies*.php ${BACKUP_DIR}/server_gymies_routes.php; do
        if [ -f \"\$f\" ]; then
            sudo cp \"\$f\" $LP/
            echo \"  \$(basename \$f) hersteld\"
        fi
    done

    # .env NIET terugzetten (kan nieuwe env vars bevatten die nodig zijn)
    # Tenzij expliciet gevraagd

    # Permissions herstellen
    sudo chown -R www-data:www-data $LP/app/ $LP/config/ $LP/database/ 2>/dev/null
    sudo chown -R www-data:www-data $LP/bootstrap/cache/ $LP/storage/ 2>/dev/null
"
ok "Backup bestanden hersteld"

# ── Stap 4: Migratie rollback (optioneel) ────────────────────────

step "4/5 — Migratie rollback"

echo "  Laatste migratie batch controleren..."
LAST_BATCH=$(ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan migrate:status 2>/dev/null | tail -5" 2>/dev/null)
echo "$LAST_BATCH"
echo ""
read -p "  Wil je de laatste migratie batch terugdraaien? (ja/nee): " MIGRATE_ROLLBACK

if [ "$MIGRATE_ROLLBACK" = "ja" ]; then
    ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan migrate:rollback --force 2>&1 | tail -5"
    ok "Laatste migratie batch teruggedraaid"
else
    echo "  Migraties niet aangepast."
fi

# ── Stap 5: Cache herstellen + services herstart ────────────────

step "5/5 — Cache herstellen + services herstart"

ssh -i "$SSH_KEY" "$SSH_HOST" "
    cd $LP
    sudo -u www-data php artisan optimize:clear 2>&1 | tail -1
    sudo -u www-data php artisan config:cache 2>&1 | tail -1
    sudo -u www-data php artisan route:cache 2>&1 | tail -1
    sudo -u www-data php artisan view:cache 2>&1 | tail -1
    echo '  Cache hersteld'
"
ok "Cache hersteld en services herstart"

# ── Eindcontrole ─────────────────────────────────────────────────

step "Eindcontrole"

echo "  Health check:"
HEALTH=$(ssh -i "$SSH_KEY" "$SSH_HOST" "curl -sf http://127.0.0.1/api/gymies/health 2>/dev/null" || echo '{"status":"unreachable"}')
echo "  $HEALTH"

echo ""
echo -e "${GREEN}Rollback voltooid.${NC}"
echo "  Backup gebruikt: $BACKUP_DIR"
echo "  Pre-rollback bewaard: $ROLLBACK_BACKUP"
echo ""
