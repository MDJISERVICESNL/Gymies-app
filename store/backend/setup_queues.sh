#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# Gymies — Laravel Queue Setup
# ══════════════════════════════════════════════════════════════════════
# Configureert database queue driver + PM2 queue worker.
# Verplaatst emails en notificaties naar async queue.
# ══════════════════════════════════════════════════════════════════════

set -uo pipefail

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }

step "1/4 — Queue tabellen aanmaken"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan queue:table 2>&1 | tail -3 || echo '  Queue migration al aanwezig'"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan queue:failed-table 2>&1 | tail -3 || echo '  Failed jobs migration al aanwezig'"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan migrate --force 2>&1 | tail -5"
ok "Queue tabellen bestaan"

step "2/4 — .env queue driver instellen"

ssh -i "$SSH_KEY" "$SSH_HOST" "
    if grep -q '^QUEUE_CONNECTION=' $LP/.env; then
        sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=database/' $LP/.env
    else
        echo '' >> $LP/.env
        echo '# Queue Configuration' >> $LP/.env
        echo 'QUEUE_CONNECTION=database' >> $LP/.env
    fi
    echo '  QUEUE_CONNECTION=database'
"
ok "Queue driver ingesteld op database"

step "3/4 — PM2 queue worker configureren"

# PM2 wordt al gebruikt voor Reverb, voeg queue worker toe
ssh -i "$SSH_KEY" "$SSH_HOST" "
    # Controleer of pm2 beschikbaar is
    if ! command -v pm2 &>/dev/null; then
        echo '  PM2 niet gevonden — installeer eerst: npm install -g pm2'
        exit 1
    fi

    # Stop eventueel bestaande worker
    pm2 delete gymies-queue 2>/dev/null || true

    # Start queue worker via PM2
    pm2 start --name gymies-queue \
        --interpreter php \
        $LP/artisan -- queue:work database \
        --sleep=3 \
        --tries=3 \
        --max-time=3600 \
        --memory=256

    pm2 save
    echo '  PM2 queue worker gestart'
"
ok "Queue worker draait via PM2"

step "4/4 — Cache herstellen"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan optimize:clear 2>/dev/null && sudo -u www-data php artisan config:cache 2>/dev/null"
ok "Cache hersteld"

echo ""
echo -e "${GREEN}Queue systeem actief.${NC}"
echo "  Queue worker: pm2 status gymies-queue"
echo "  Failed jobs:  php artisan queue:failed"
echo "  Retry failed: php artisan queue:retry all"
echo ""
