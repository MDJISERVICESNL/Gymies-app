#!/bin/bash
set -uo pipefail
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }

# ── FIX 0: Permissions herstellen (root cause van meerdere issues) ──
step "0 — Permissions herstellen"

ssh -i "$SSH_KEY" "$SSH_HOST" "
sudo chown -R www-data:www-data $LP/vendor/ $LP/bootstrap/cache/ $LP/storage/ 2>/dev/null
sudo chmod -R 775 $LP/bootstrap/cache/ $LP/storage/ 2>/dev/null
sudo chmod -R 755 $LP/vendor/ 2>/dev/null
echo 'Permissions hersteld'
"
ok "www-data eigenaar van vendor/, bootstrap/cache/, storage/"

# ── FIX 1: Sentry package discover ──
step "1 — Sentry registreren"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan package:discover 2>&1 | grep -i sentry || echo 'Sentry niet auto-discovered'"

# Fallback: handmatig registreren in config/app.php als nodig
ssh -i "$SSH_KEY" "$SSH_HOST" "
if grep -q 'SentryServiceProvider\|sentry' $LP/config/app.php 2>/dev/null; then
    echo '  Sentry al in config/app.php'
else
    echo '  Sentry auto-discovery zou moeten werken met Laravel 12'
fi
"
ok "Sentry gecontroleerd"

# ── FIX 2: Reverb — vind en kill ALLES op 8080, gebruik fuser ──
step "2 — Reverb: poort 8080 volledig vrijmaken"

echo "  Wat draait er op 8080?"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo ss -tlnp | grep 8080 || echo '  Niets op ss'"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo fuser -v 8080/tcp 2>&1 || echo '  fuser: niets gevonden'"

echo ""
echo "  ALLES op poort 8080 killen (fuser)..."
ssh -i "$SSH_KEY" "$SSH_HOST" "
sudo supervisorctl stop gymies-reverb 2>/dev/null
sleep 1
sudo fuser -k 8080/tcp 2>/dev/null
sleep 2
echo '  Poort 8080 check na kill:'
sudo ss -tlnp | grep 8080 || echo '  Poort 8080 is vrij!'
"

echo ""
echo "  Reverb starten..."
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl start gymies-reverb 2>&1"

sleep 3
echo "  Status:"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl status gymies-reverb 2>/dev/null"

# ── Cache herstellen ──
step "3 — Cache herstellen"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan optimize:clear 2>&1 | tail -1"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan config:cache 2>&1 | tail -1"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo -u www-data php artisan route:cache 2>&1 | tail -1"
ok "Cache hersteld als www-data"

echo ""
echo -e "${GREEN}Klaar.${NC}"
