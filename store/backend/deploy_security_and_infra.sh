#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# Gymies — Deploy Security & Infrastructure Fixes
# ══════════════════════════════════════════════════════════════════════
#
# Dit script deployed ALLE security & infra fixes in één keer:
#
#   SECURITY:
#   1. Rate limiting op publieke endpoints
#   2. Sentry config (DSN toevoegen in .env na deploy)
#   3. Cron frequenties (SOS 1min, bookings 15min)
#   4. Cash idempotentie + Mollie reconciliatie cron
#
#   INFRASTRUCTURE:
#   5. QR TTL verkort naar 45 seconden
#   6. MySQL Spatial Index voor trainer zoeken
#   7. Laravel Reverb setup (WebSocket)
#
# Gebruik:
#   cd store/backend && bash deploy_security_and_infra.sh
#
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="/var/www/gymies"
DESKTOP="$HOME/Desktop"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Kleuren
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Gymies — Security & Infrastructure Deploy             ║"
echo "║   $(date '+%Y-%m-%d %H:%M:%S')                                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ══════════════════════════════════════════════════════════════════════
# STAP 1: Database backup
# ══════════════════════════════════════════════════════════════════════
step "1/8 — Database backup"

BACKUP_NAME="gymies_db_backup_${TIMESTAMP}.sql"

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" "$BACKUP_NAME" << 'REMOTE'
set -e
LARAVEL_PATH="$1"
BACKUP_NAME="$2"
cd "$LARAVEL_PATH" || exit 1
source .env 2>/dev/null || true
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_DATABASE="${DB_DATABASE:-gymies}"
DB_USERNAME="${DB_USERNAME:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
mysqldump -h "$DB_HOST" -u "$DB_USERNAME" ${DB_PASSWORD:+-p"$DB_PASSWORD"} "$DB_DATABASE" > "/tmp/$BACKUP_NAME"
echo "Backup: /tmp/$BACKUP_NAME ($(du -h /tmp/$BACKUP_NAME | cut -f1))"
REMOTE

BACKUP_PATH="/tmp/$BACKUP_NAME"
scp -i "$SSH_KEY" "$SSH_HOST:$BACKUP_PATH" "$DESKTOP/" 2>/dev/null && \
    ok "Backup gedownload: $DESKTOP/$BACKUP_NAME" || \
    warn "Backup download mislukt — staat nog op server"

# ══════════════════════════════════════════════════════════════════════
# STAP 2: Backend bestanden uploaden
# ══════════════════════════════════════════════════════════════════════
step "2/8 — Backend bestanden uploaden"

# Upload alles eerst naar /tmp/gymies_deploy/ op de server,
# daarna sudo cp naar de juiste locaties (voorkomt permission denied)
STAGING="/tmp/gymies_deploy_${TIMESTAMP}"

echo "  Staging directory aanmaken op server..."
ssh -i "$SSH_KEY" "$SSH_HOST" "mkdir -p $STAGING/controllers $STAGING/migrations $STAGING/config"

# --- Controllers ---
echo "  Controllers uploaden..."
scp -i "$SSH_KEY" \
    "$SCRIPT_DIR/app/Http/Controllers/Gymies/GymiesCronController.php" \
    "$SCRIPT_DIR/app/Http/Controllers/Gymies/GymiesCheckinController.php" \
    "$SCRIPT_DIR/app/Http/Controllers/Gymies/GymiesTrainerController.php" \
    "$SCRIPT_DIR/app/Http/Controllers/Gymies/GymiesBroadcastController.php" \
    "$SSH_HOST:$STAGING/controllers/"
ok "4 controllers naar staging"

# --- Routes ---
echo "  Routes uploaden..."
scp -i "$SSH_KEY" \
    "$SCRIPT_DIR/routes_gymies_full.php" \
    "$SCRIPT_DIR/server_gymies_routes.php" \
    "$SSH_HOST:$STAGING/"
ok "2 route bestanden naar staging"

# --- Config ---
echo "  Config uploaden..."
scp -i "$SSH_KEY" \
    "$SCRIPT_DIR/config/gymies.php" \
    "$SSH_HOST:$STAGING/config/"
ok "gymies.php naar staging"

# --- Migratie ---
echo "  Migraties uploaden..."
scp -i "$SSH_KEY" \
    "$SCRIPT_DIR/database/migrations/2026_04_30_000001_add_spatial_index_to_trainer_profiles.php" \
    "$SSH_HOST:$STAGING/migrations/"
ok "Spatial index migratie naar staging"

# --- Verplaats met sudo naar juiste locaties ---
echo "  Bestanden verplaatsen met sudo..."
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$STAGING" "$LARAVEL_PATH" << 'REMOTE'
STAGING="$1"
LP="$2"
sudo cp "$STAGING"/controllers/*.php "$LP/app/Http/Controllers/Gymies/"
sudo cp "$STAGING"/routes_gymies_full.php "$LP/"
sudo cp "$STAGING"/server_gymies_routes.php "$LP/"
sudo cp "$STAGING"/config/gymies.php "$LP/config/"
sudo cp "$STAGING"/migrations/*.php "$LP/database/migrations/"
sudo chown -R www-data:www-data "$LP/app/Http/Controllers/Gymies/" "$LP/config/gymies.php" "$LP/database/migrations/"
sudo chmod -R 644 "$LP/app/Http/Controllers/Gymies/"*.php "$LP/config/gymies.php"
rm -rf "$STAGING"
echo "  Alle bestanden gekopieerd en permissions gezet"
REMOTE
ok "Bestanden gedeployed naar $LARAVEL_PATH"

# ══════════════════════════════════════════════════════════════════════
# STAP 3: Migraties draaien
# ══════════════════════════════════════════════════════════════════════
step "3/8 — Database migraties"

ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LARAVEL_PATH && php artisan migrate --force" && \
    ok "Migraties uitgevoerd (spatial index)" || \
    warn "Migratie mislukt — controleer handmatig"

# ══════════════════════════════════════════════════════════════════════
# STAP 4: Sentry installeren
# ══════════════════════════════════════════════════════════════════════
step "4/8 — Sentry SDK installeren"

ssh -i "$SSH_KEY" "$SSH_HOST" bash << 'REMOTE'
cd /var/www/gymies
if composer show sentry/sentry-laravel 2>/dev/null | grep -q "name"; then
    echo "  sentry/sentry-laravel is al geïnstalleerd"
else
    composer require sentry/sentry-laravel --no-interaction 2>&1 | tail -3
    echo "  sentry/sentry-laravel geïnstalleerd"
fi
REMOTE
ok "Sentry SDK gecontroleerd"
warn "Vergeet niet SENTRY_LARAVEL_DSN toe te voegen aan .env op de server!"

# ══════════════════════════════════════════════════════════════════════
# STAP 5: Laravel Reverb installeren
# ══════════════════════════════════════════════════════════════════════
step "5/8 — Laravel Reverb installeren"

ssh -i "$SSH_KEY" "$SSH_HOST" bash << 'REMOTE'
cd /var/www/gymies
if composer show laravel/reverb 2>/dev/null | grep -q "name"; then
    echo "  laravel/reverb is al geïnstalleerd"
else
    composer require laravel/reverb --no-interaction 2>&1 | tail -3
    echo "  laravel/reverb geïnstalleerd"
fi
REMOTE
ok "Reverb SDK gecontroleerd"

# ══════════════════════════════════════════════════════════════════════
# STAP 6: Reverb .env + Supervisor + Nginx
# ══════════════════════════════════════════════════════════════════════
step "6/8 — Reverb configuratie (env + Supervisor)"

ssh -i "$SSH_KEY" "$SSH_HOST" bash << 'REMOTE'
set -e
cd /var/www/gymies
ENV_FILE=".env"

add_env() {
    local key="$1" val="$2"
    if ! grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        echo "${key}=${val}" >> "$ENV_FILE"
        echo "  + ${key} toegevoegd"
    else
        echo "  ~ ${key} bestaat al"
    fi
}

add_env "BROADCAST_CONNECTION" "reverb"
add_env "REVERB_APP_ID" "gymies-$(openssl rand -hex 4)"
add_env "REVERB_APP_KEY" "$(openssl rand -hex 16)"
add_env "REVERB_APP_SECRET" "$(openssl rand -hex 16)"
add_env "REVERB_HOST" "0.0.0.0"
add_env "REVERB_PORT" "8080"
add_env "REVERB_SCHEME" "http"

# Deprecate Pusher keys
for key in PUSHER_APP_ID PUSHER_APP_KEY PUSHER_APP_SECRET PUSHER_APP_CLUSTER PUSHER_HOST PUSHER_PORT PUSHER_SCHEME; do
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s/^${key}=/#DEPRECATED_${key}=/" "$ENV_FILE"
        echo "  # ${key} uitgeschakeld"
    fi
done

# Supervisor config
sudo tee /etc/supervisor/conf.d/gymies-reverb.conf > /dev/null << 'SUPCONF'
[program:gymies-reverb]
command=php /var/www/gymies/artisan reverb:start --host=0.0.0.0 --port=8080
directory=/var/www/gymies
autostart=true
autorestart=true
startretries=3
user=www-data
redirect_stderr=true
stdout_logfile=/var/log/gymies-reverb.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stopwaitsecs=10
SUPCONF

sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl restart gymies-reverb 2>/dev/null || sudo supervisorctl start gymies-reverb 2>/dev/null || echo "  Supervisor: start handmatig"
REMOTE

ok "Reverb env + Supervisor geconfigureerd"
echo ""
warn "NGINX: voeg WebSocket proxy toe als dat nog niet is gedaan:"
echo "    location /app {"
echo "        proxy_pass http://127.0.0.1:8080;"
echo "        proxy_http_version 1.1;"
echo "        proxy_set_header Upgrade \$http_upgrade;"
echo "        proxy_set_header Connection \"upgrade\";"
echo "        proxy_set_header Host \$host;"
echo "        proxy_read_timeout 60s;"
echo "    }"

# ══════════════════════════════════════════════════════════════════════
# STAP 7: Crontab updaten
# ══════════════════════════════════════════════════════════════════════
step "7/8 — Crontab updaten (SOS 1min, bookings 15min, reconciliatie)"

# Upload het setup script en draai het
scp -i "$SSH_KEY" "$SCRIPT_DIR/setup_crontab.sh" "$SSH_HOST:/tmp/gymies_setup_crontab.sh"
ssh -i "$SSH_KEY" "$SSH_HOST" "bash /tmp/gymies_setup_crontab.sh" && \
    ok "Crontab bijgewerkt" || \
    warn "Crontab update mislukt — draai handmatig: bash setup_crontab.sh"

# ══════════════════════════════════════════════════════════════════════
# STAP 8: Cache legen + verificatie
# ══════════════════════════════════════════════════════════════════════
step "8/8 — Cache legen + verificatie"

ssh -i "$SSH_KEY" "$SSH_HOST" bash << 'REMOTE'
cd /var/www/gymies

# Cache legen
php artisan optimize:clear 2>/dev/null || true
php artisan config:cache 2>/dev/null || true
php artisan route:cache 2>/dev/null || true

echo ""
echo "── Verificatie ──"

# Check routes
ROUTES=$(php artisan route:list --path=cron/reconcile 2>/dev/null | grep -c "reconcile" || echo "0")
if [ "$ROUTES" -gt 0 ]; then
    echo "  ✓ Mollie reconciliatie route actief"
else
    echo "  ✗ Mollie reconciliatie route NIET gevonden"
fi

# Check Reverb
if supervisorctl status gymies-reverb 2>/dev/null | grep -q "RUNNING"; then
    echo "  ✓ Reverb draait"
else
    echo "  ⚠ Reverb draait NIET — check: sudo supervisorctl status gymies-reverb"
fi

# Check Sentry
if composer show sentry/sentry-laravel 2>/dev/null | grep -q "name"; then
    echo "  ✓ Sentry SDK geïnstalleerd"
else
    echo "  ⚠ Sentry SDK niet gevonden"
fi

# Check spatial index
SPATIAL=$(php artisan tinker --execute="echo Schema::hasColumn('gymies_trainer_profiles','trainer_lat') ? 'yes' : 'no';" 2>/dev/null || echo "unknown")
echo "  ~ Spatial: trainer_lat kolom = $SPATIAL"

# Crontab check
CRON_COUNT=$(crontab -l 2>/dev/null | grep -c "gymies/cron/" || echo "0")
echo "  ✓ Crontab: $CRON_COUNT gymies cron jobs actief"

echo ""
echo "  OPcache flush..."
php artisan optimize:clear 2>/dev/null || true

echo ""
REMOTE

# ══════════════════════════════════════════════════════════════════════
# SAMENVATTING
# ══════════════════════════════════════════════════════════════════════
echo -e "\n${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Deploy voltooid!                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Wat is gedeployed:"
echo "    1. Rate limiting op publieke endpoints"
echo "    2. Sentry config (voeg DSN toe aan .env!)"
echo "    3. Crontab: SOS=1min, bookings=15min, reconciliatie=30min"
echo "    4. Cash idempotentie middleware"
echo "    5. Mollie reconciliatie cron job"
echo "    6. QR TTL verkort: 120s → 45s"
echo "    7. MySQL Spatial Index + ST_Distance_Sphere"
echo "    8. Laravel Reverb (Pusher verwijderd)"
echo ""
echo -e "  ${YELLOW}TODO na deploy:${NC}"
echo "    • Voeg SENTRY_LARAVEL_DSN=... toe aan .env"
echo "    • Controleer Nginx WebSocket proxy (/app location)"
echo "    • Test: curl -s https://gymies.nl/api/gymies/trainers"
echo "    • Test: supervisorctl status gymies-reverb"
echo ""
echo "  Backup: $DESKTOP/$BACKUP_NAME"
echo ""
