#!/bin/bash
# ============================================================
# Deploy Mollie Test Configuratie naar Gymies Server
# ============================================================
# Dit script:
# 1. Maakt een DB backup (veiligheid)
# 2. Upload config/gymies.php (nieuwe config file)
# 3. Voegt Mollie test variabelen toe aan .env
# 4. Cleared alle caches
# 5. Verifieert de configuratie
# ============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP="${HOME}/Desktop"

# ── SSH Config ──────────────────────────────────────────────
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"

# ── Mollie Test Key ─────────────────────────────────────────
MOLLIE_TEST_KEY="test_JaKE2emRwW4GGfPFsvCerAJGP7QpGs"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Mollie Test Configuratie Deploy            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Server:  $SSH_HOST"
echo "Path:    $LARAVEL_PATH"
echo "Mode:    TEST (Mollie sandbox)"
echo ""

# ── Stap 1: Database Backup ────────────────────────────────
echo "=== 1/5 Database backup ==="
BACKUP_NAME="gymies_db_backup_pre_mollie_test_$(date +%Y%m%d_%H%M%S).sql"

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" "$BACKUP_NAME" << 'REMOTE'
set -e
LARAVEL_PATH="$1"
BACKUP_NAME="$2"
cd "$LARAVEL_PATH" || { echo "FOUT: $LARAVEL_PATH niet gevonden"; exit 1; }

# Lees DB credentials uit .env
export $(grep -E '^DB_(HOST|DATABASE|USERNAME|PASSWORD)=' .env | xargs) 2>/dev/null || true
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_DATABASE="${DB_DATABASE:-gymies}"
DB_USERNAME="${DB_USERNAME:-root}"

echo "  Backup: $DB_DATABASE -> /tmp/$BACKUP_NAME"
mysqldump -h "$DB_HOST" -u "$DB_USERNAME" ${DB_PASSWORD:+-p"$DB_PASSWORD"} "$DB_DATABASE" > "/tmp/$BACKUP_NAME" 2>/dev/null
echo "  OK: /tmp/$BACKUP_NAME ($(du -h /tmp/$BACKUP_NAME | cut -f1))"
REMOTE

# Download backup
BACKUP_PATH=$(ssh -i "$SSH_KEY" "$SSH_HOST" "ls -t /tmp/gymies_db_backup_pre_mollie_test_*.sql 2>/dev/null | head -1")
if [ -n "$BACKUP_PATH" ]; then
  scp -i "$SSH_KEY" "$SSH_HOST:$BACKUP_PATH" "$DESKTOP/" 2>/dev/null
  echo "  Backup gedownload: $DESKTOP/$(basename $BACKUP_PATH)"
fi
echo ""

# ── Stap 2: Upload config/gymies.php ───────────────────────
echo "=== 2/5 Upload config/gymies.php ==="
scp -i "$SSH_KEY" \
  "$SCRIPT_DIR/config/gymies.php" \
  "$SSH_HOST:/tmp/gymies_config.php"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo cp /tmp/gymies_config.php $LARAVEL_PATH/config/gymies.php && sudo chown www-data:www-data $LARAVEL_PATH/config/gymies.php && rm /tmp/gymies_config.php"
echo "  OK: config/gymies.php geüpload"
echo ""

# ── Stap 3: .env updaten met Mollie test variabelen ────────
echo "=== 3/5 .env updaten met Mollie test configuratie ==="
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" "$MOLLIE_TEST_KEY" << 'REMOTE'
set -e
LARAVEL_PATH="$1"
MOLLIE_TEST_KEY="$2"
cd "$LARAVEL_PATH"

# Backup van huidige .env
sudo cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
echo "  .env backup gemaakt"

# Functie: voeg toe of update een .env variabele (via sudo)
update_env() {
  local key="$1"
  local value="$2"
  if sudo grep -q "^${key}=" .env; then
    OLD_VAL=$(sudo grep "^${key}=" .env | head -1)
    sudo sed -i "s|^${key}=.*|${key}=${value}|" .env
    echo "  UPDATE: $key (was: ${OLD_VAL#*=})"
  else
    echo "${key}=${value}" | sudo tee -a .env > /dev/null
    echo "  NIEUW:  $key=${value}"
  fi
}

# Mollie test variabelen
update_env "MOLLIE_API_KEY" "$MOLLIE_TEST_KEY"
update_env "MOLLIE_TESTMODE" "true"

# Check of deze al bestaan, zo niet: voeg toe met lege waarde
for KEY in MOLLIE_PROFILE_ID MOLLIE_CLIENT_ID MOLLIE_CLIENT_SECRET MOLLIE_WEBHOOK_SECRET; do
  if ! sudo grep -q "^${KEY}=" .env; then
    echo "${KEY}=" | sudo tee -a .env > /dev/null
    echo "  NIEUW:  $KEY= (leeg — vul later in indien nodig)"
  else
    echo "  BESTAAT: $KEY (niet gewijzigd)"
  fi
done

echo ""
echo "  Huidige Mollie config in .env:"
sudo grep -E "^MOLLIE_" .env | sed 's/^/    /'
REMOTE
echo ""

# ── Stap 4: Cache clearen ──────────────────────────────────
echo "=== 4/5 Cache clearen + opnieuw opbouwen ==="
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
cd "$1"
sudo -u www-data php artisan config:clear 2>/dev/null && echo "  config:clear OK"
sudo -u www-data php artisan route:clear 2>/dev/null && echo "  route:clear OK"
sudo -u www-data php artisan cache:clear 2>/dev/null && echo "  cache:clear OK"
sudo -u www-data php artisan config:cache 2>/dev/null && echo "  config:cache OK"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "  route:cache OK"
REMOTE
echo ""

# ── Stap 5: Verificatie ────────────────────────────────────
echo "=== 5/5 Verificatie ==="
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
cd "$1"

echo "  Mollie config check via artisan tinker:"
CONFIG_KEY=$(sudo -u www-data php artisan tinker --execute="echo config('gymies.mollie_api_key');" 2>/dev/null | tail -1)
CONFIG_TEST=$(sudo -u www-data php artisan tinker --execute="echo config('gymies.mollie_testmode') ? 'true' : 'false';" 2>/dev/null | tail -1)

if [[ "$CONFIG_KEY" == test_* ]]; then
  echo "  ✓ mollie_api_key: ${CONFIG_KEY:0:10}... (test key)"
else
  echo "  ✗ mollie_api_key: onverwacht — '$CONFIG_KEY'"
fi

if [[ "$CONFIG_TEST" == "true" || "$CONFIG_TEST" == "1" ]]; then
  echo "  ✓ mollie_testmode: aan"
else
  echo "  ✗ mollie_testmode: uit — check .env"
fi

# Check webhook URL
APP_URL=$(sudo -u www-data php artisan tinker --execute="echo config('app.url');" 2>/dev/null | tail -1)
echo "  Webhook URL: ${APP_URL}/api/gymies/webhooks/mollie"

# Check of config/gymies.php bestaat
if [ -f config/gymies.php ]; then
  echo "  ✓ config/gymies.php bestaat"
else
  echo "  ✗ config/gymies.php NIET GEVONDEN"
fi
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  DEPLOY KLAAR — Mollie staat in TESTMODE            ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  Test in de app:                                     ║"
echo "║  • Boek een sessie → betaal via iDEAL               ║"
echo "║  • Kies 'TBM Bank' → kies Paid/Failed/Cancelled     ║"
echo "║                                                      ║"
echo "║  Terug naar LIVE:                                    ║"
echo "║  • Draai: ./deploy_mollie_live_config.sh             ║"
echo "║  • Of handmatig: MOLLIE_API_KEY=live_xxx             ║"
echo "║    + MOLLIE_TESTMODE=false + config:cache            ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
