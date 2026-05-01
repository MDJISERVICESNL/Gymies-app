#!/bin/bash
# Post-deploy fixes v2 — lost de 3 resterende issues op
set -uo pipefail

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

# ── FIX 1: Sentry — composer met sudo ──
step "1/3 — Sentry (sudo composer)"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo COMPOSER_MEMORY_LIMIT=-1 composer require sentry/sentry-laravel --no-interaction --no-progress 2>&1 | tail -5"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && sudo chown -R www-data:www-data vendor/ 2>/dev/null"

if ssh -i "$SSH_KEY" "$SSH_HOST" "test -f $LP/vendor/sentry/sentry-laravel/src/Sentry/Laravel/ServiceProvider.php && echo YES" 2>/dev/null | grep -q "YES"; then
    ok "Sentry SDK geïnstalleerd"
else
    warn "Sentry nog steeds niet gevonden"
fi

# ── FIX 2: Reverb — kill bezette poort, herstart ──
step "2/3 — Reverb (poort 8080 vrijmaken)"

echo "  Proces op poort 8080 zoeken..."
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo lsof -ti:8080 2>/dev/null | head -5 | xargs -I{} echo '  PID: {}'"

echo "  Processen op poort 8080 killen..."
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo lsof -ti:8080 2>/dev/null | xargs -r sudo kill -9 2>/dev/null; sleep 1; echo '  Gedood'"

echo "  Supervisor herstarten..."
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl stop gymies-reverb 2>/dev/null; sleep 2; sudo supervisorctl start gymies-reverb 2>&1"

sleep 3
if ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl status gymies-reverb 2>/dev/null" | grep -q "RUNNING"; then
    ok "Reverb draait op poort 8080"
else
    echo ""
    ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl status gymies-reverb 2>/dev/null"
    ssh -i "$SSH_KEY" "$SSH_HOST" "tail -5 /var/log/gymies-reverb.log 2>/dev/null"
    warn "Reverb start niet — check logs hierboven"
fi

# ── FIX 3: Spatial kolommen — zonder after() ──
step "3/3 — Spatial kolommen toevoegen"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan tinker --execute=\"
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

if (!Schema::hasColumn('gymies_trainer_profiles', 'trainer_lat')) {
    Schema::table('gymies_trainer_profiles', function (Blueprint \\\$t) {
        \\\$t->decimal('trainer_lat', 10, 7)->nullable();
        \\\$t->decimal('trainer_lng', 10, 7)->nullable();
    });
    echo 'trainer_lat + trainer_lng kolommen toegevoegd';
} else {
    echo 'Kolommen bestaan al';
}
\" 2>&1 | grep -v '^>' | grep -v '^\$' | tail -3"

# Re-run spatial index
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan migrate --force 2>&1 | tail -3"

# Verify
if ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan tinker --execute=\"echo Schema::hasColumn('gymies_trainer_profiles', 'trainer_lat') ? 'YES' : 'NO';\" 2>/dev/null" | grep -q "YES"; then
    ok "trainer_lat + trainer_lng kolommen bestaan"
else
    warn "Kolommen nog niet gevonden — voeg handmatig toe op server:"
    echo "    ALTER TABLE gymies_trainer_profiles ADD trainer_lat DECIMAL(10,7) NULL, ADD trainer_lng DECIMAL(10,7) NULL;"
fi

# ── Cache + eindcontrole ──
step "Eindcontrole"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan optimize:clear 2>/dev/null && php artisan config:cache 2>/dev/null && php artisan route:cache 2>/dev/null"

echo ""
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl status gymies-reverb 2>/dev/null | head -1"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php -r \"echo class_exists('Sentry\Laravel\ServiceProvider') ? 'Sentry: OK' : 'Sentry: MISSING';\" 2>/dev/null || echo 'Sentry: check needed'"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan tinker --execute=\"echo Schema::hasColumn('gymies_trainer_profiles', 'trainer_lat') ? 'Spatial: OK' : 'Spatial: MISSING';\" 2>/dev/null"

echo ""
echo -e "${GREEN}Klaar.${NC}"
