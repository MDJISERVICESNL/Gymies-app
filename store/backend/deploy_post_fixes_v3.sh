#!/bin/bash
set -uo pipefail
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }

# ── FIX 1: Sentry — autoload regeneren + permissions ──
step "1/2 — Sentry autoload + permissions"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo composer dump-autoload --no-interaction 2>&1 | tail -3"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo chown -R www-data:www-data $LP/vendor/ $LP/bootstrap/cache/ 2>/dev/null"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo chmod -R 755 $LP/vendor/ 2>/dev/null"

echo "  Sentry check:"
ssh -i "$SSH_KEY" "$SSH_HOST" "ls -la $LP/vendor/sentry/sentry-laravel/src/Sentry/Laravel/ServiceProvider.php 2>/dev/null && echo '  Bestand bestaat' || echo '  Bestand NIET gevonden'"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan package:discover 2>&1 | grep -i sentry || echo '  Sentry niet in package:discover'"

# ── FIX 2: Reverb — volledige error log bekijken ──
step "2/2 — Reverb diagnose"

echo "  Volledige error:"
ssh -i "$SSH_KEY" "$SSH_HOST" "tail -30 /var/log/gymies-reverb.log 2>/dev/null"

echo ""
echo "  Handmatige test (5 sec):"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && timeout 5 php artisan reverb:start --host=0.0.0.0 --port=8080 2>&1 || true"

echo ""
echo "  Reverb config in .env:"
ssh -i "$SSH_KEY" "$SSH_HOST" "grep -E '^REVERB_|^BROADCAST' $LP/.env 2>/dev/null"

echo ""
echo "  PHP versie + reverb package:"
ssh -i "$SSH_KEY" "$SSH_HOST" "php -v | head -1"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && composer show laravel/reverb 2>/dev/null | grep -E 'name|version' | head -2"

# ── Cache ──
step "Cache"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan optimize:clear 2>/dev/null && php artisan config:cache 2>/dev/null"

echo ""
echo -e "${GREEN}Klaar — plak de output zodat ik de errors kan analyseren.${NC}"
