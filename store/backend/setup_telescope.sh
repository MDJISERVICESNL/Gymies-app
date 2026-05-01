#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# Gymies — Laravel Telescope Setup (alleen dev/staging)
# ══════════════════════════════════════════════════════════════════════
# Installeert en configureert Laravel Telescope voor debugging.
# NIET voor productie — alleen op dev/staging servers draaien.
# ══════════════════════════════════════════════════════════════════════

set -uo pipefail

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }

step "1/4 — Telescope installeren"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo COMPOSER_MEMORY_LIMIT=-1 composer require laravel/telescope --dev --no-interaction 2>&1 | tail -5"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo chown -R www-data:www-data $LP/vendor/ 2>/dev/null"
ok "Telescope package geïnstalleerd"

step "2/4 — Telescope publiceren"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan telescope:install 2>&1 | tail -3"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan migrate --force 2>&1 | tail -3"
ok "Telescope migraties gedraaid"

step "3/4 — Telescope configuratie"
# Zorg dat Telescope alleen op non-productie draait
ssh -i "$SSH_KEY" "$SSH_HOST" "
    if ! grep -q 'TELESCOPE_ENABLED' $LP/.env; then
        echo '' >> $LP/.env
        echo '# Laravel Telescope (alleen dev/staging)' >> $LP/.env
        echo 'TELESCOPE_ENABLED=true' >> $LP/.env
    fi
"
ok "TELESCOPE_ENABLED=true in .env"

step "4/4 — Cache herstellen"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan optimize:clear 2>/dev/null && sudo -u www-data php artisan config:cache 2>/dev/null"
ok "Cache hersteld"

echo ""
echo -e "${GREEN}Telescope beschikbaar op: https://gymies.nl/telescope${NC}"
echo "  Let op: beveilig het pad met IP-restrictie of auth gate in TelescopeServiceProvider."
echo ""
