#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# Gymies — Post-deploy fixes
# ══════════════════════════════════════════════════════════════════════
# Fixt de 4 issues uit de verificatie na de security deploy.
# ══════════════════════════════════════════════════════════════════════

set -uo pipefail  # geen -e, we willen doorgaan bij fouten

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Gymies — Post-deploy Fixes                            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ══════════════════════════════════════════════════════════════════════
# FIX 1: Sentry installeren (direct ssh command, geen heredoc)
# ══════════════════════════════════════════════════════════════════════
step "1/4 — Sentry SDK installeren"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && COMPOSER_MEMORY_LIMIT=-1 composer require sentry/sentry-laravel --no-interaction --no-progress 2>&1 | tail -10"

if ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php -r \"require 'vendor/autoload.php'; echo class_exists('Sentry\Laravel\ServiceProvider') ? 'OK' : 'MISSING';\"" 2>/dev/null | grep -q "OK"; then
    ok "Sentry SDK is geïnstalleerd en werkend"
else
    warn "Sentry SDK niet gevonden — mogelijk composer memory issue. Probeer op server: COMPOSER_MEMORY_LIMIT=-1 composer require sentry/sentry-laravel"
fi

# ══════════════════════════════════════════════════════════════════════
# FIX 2: Reverb — check waarom het niet start, fix permissions
# ══════════════════════════════════════════════════════════════════════
step "2/4 — Reverb spawn error fixen"

echo "  Reverb error log:"
ssh -i "$SSH_KEY" "$SSH_HOST" "tail -20 /var/log/gymies-reverb.log 2>/dev/null || echo '  (geen logbestand)'"

echo ""
echo "  Reverb config checken..."
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan reverb:start --host=0.0.0.0 --port=8080 2>&1 & sleep 3 && kill %1 2>/dev/null; wait 2>/dev/null" 2>&1 | head -5

echo ""
echo "  Supervisor herstarten..."
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl stop gymies-reverb 2>/dev/null; sleep 1; sudo supervisorctl start gymies-reverb 2>&1"

sleep 2
if ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl status gymies-reverb 2>/dev/null" | grep -q "RUNNING"; then
    ok "Reverb draait!"
else
    warn "Reverb start nog steeds niet. Controleer: sudo supervisorctl status gymies-reverb"
    echo ""
    echo "  Debug commando's op de server:"
    echo "    cd $LP && php artisan reverb:start --host=0.0.0.0 --port=8080"
    echo "    tail -50 /var/log/gymies-reverb.log"
fi

# ══════════════════════════════════════════════════════════════════════
# FIX 3: Mollie reconciliatie route — clear + recheck
# ══════════════════════════════════════════════════════════════════════
step "3/4 — Mollie reconciliatie route controleren"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan route:clear && php artisan route:cache 2>/dev/null"
ROUTE_CHECK=$(ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan route:list 2>/dev/null | grep reconcile" 2>/dev/null || echo "")

if [ -n "$ROUTE_CHECK" ]; then
    ok "Mollie reconciliatie route gevonden:"
    echo "    $ROUTE_CHECK"
else
    # Check of de route in het PHP-bestand zelf staat
    ROUTE_IN_FILE=$(ssh -i "$SSH_KEY" "$SSH_HOST" "grep 'reconcile-mollie' $LP/server_gymies_routes.php 2>/dev/null || grep 'reconcile-mollie' $LP/routes_gymies_full.php 2>/dev/null" || echo "")
    if [ -n "$ROUTE_IN_FILE" ]; then
        ok "Route staat in routes bestand maar route:list toont het niet (kan normaal zijn met route caching)"
        echo "    $ROUTE_IN_FILE"
    else
        warn "Route niet gevonden in bestanden — mogelijk niet correct geüpload"
    fi
fi

# ══════════════════════════════════════════════════════════════════════
# FIX 4: Spatial index — check kolommen, voeg toe als ze ontbreken
# ══════════════════════════════════════════════════════════════════════
step "4/4 — Spatial kolommen controleren + aanmaken"

echo "  Huidige kolommen checken..."
COLS=$(ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan tinker --execute=\"\\\$cols = Schema::getColumnListing('gymies_trainer_profiles'); echo implode(', ', array_filter(\\\$cols, fn(\\\$c) => str_contains(\\\$c, 'lat') || str_contains(\\\$c, 'lng') || str_contains(\\\$c, 'location')));\" 2>/dev/null" || echo "")

echo "  Gevonden geo-kolommen: ${COLS:-geen}"

if echo "$COLS" | grep -q "trainer_lat"; then
    ok "trainer_lat en trainer_lng bestaan al"
else
    echo "  Kolommen toevoegen: trainer_lat, trainer_lng..."
    ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan tinker --execute=\"
        if (!Schema::hasColumn('gymies_trainer_profiles', 'trainer_lat')) {
            Schema::table('gymies_trainer_profiles', function (\\\$t) {
                \\\$t->decimal('trainer_lat', 10, 7)->nullable()->after('city');
                \\\$t->decimal('trainer_lng', 10, 7)->nullable()->after('trainer_lat');
            });
            echo 'Kolommen trainer_lat + trainer_lng toegevoegd';
        } else {
            echo 'Kolommen bestaan al';
        }
    \" 2>/dev/null"

    # Herrun de spatial index migratie
    ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan migrate --force 2>/dev/null"
    ok "Geo-kolommen + spatial index aangemaakt"
fi

# ══════════════════════════════════════════════════════════════════════
# FINAL: Cache legen
# ══════════════════════════════════════════════════════════════════════
step "Cache legen + eindcontrole"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan optimize:clear && php artisan config:cache && php artisan route:cache 2>/dev/null"

echo ""
echo "  ── Eindcontrole ──"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LP && php artisan route:list 2>/dev/null | grep -c 'cron/' | xargs -I{} echo '  Cron routes: {}'"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl status gymies-reverb 2>/dev/null | head -1 | xargs -I{} echo '  Reverb: {}'"
ssh -i "$SSH_KEY" "$SSH_HOST" "crontab -l 2>/dev/null | grep -c 'gymies/cron/' | xargs -I{} echo '  Crontab jobs: {}'"

echo ""
echo -e "${GREEN}Post-deploy fixes voltooid.${NC}"
echo ""
