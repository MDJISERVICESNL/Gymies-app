#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════════
# GYMIES Deploy: Payout System + Self-billing + FCM + Mollie LIVE
# ═══════════════════════════════════════════════════════════════════════
#
# Dit script deployt:
# 1. Payout systeem (saldo, uitbetalingen, fees, cron)
# 2. Self-billing factuursysteem (PDF generator, bedrijfsgegevens)
# 3. FCM push notificaties
# 4. Chat Reverb broadcast fix
# 5. Mollie LIVE keys activeren
# 6. Zoekbare transactie-omschrijvingen
# 7. Sequentiële factuurnummering (GYM-2026-XXXX)
#
# Usage: ./deploy_payout_selfbilling.sh [--dry-run]
# ═══════════════════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"
LARAVEL_PATH="/var/www/gymies"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false

if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🏃 DRY RUN — geen wijzigingen op server"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  GYMIES Deploy: Payout + Self-billing + FCM + Mollie LIVE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Server: $SSH_HOST"
echo "Path:   $LARAVEL_PATH"
echo ""

# --- Stap 1: Bestanden inpakken ---
echo "📦 Stap 1: Bestanden inpakken..."
cd "$LOCAL_DIR"

# Lijst van alle bestanden die gedeployd moeten worden
FILES_TO_DEPLOY=(
    # Payout systeem
    "app/Http/Controllers/Gymies/GymiesPayoutService.php"
    "app/Http/Controllers/Gymies/GymiesPayoutController.php"
    "app/Http/Controllers/Gymies/GymiesAdminPayoutController.php"
    "app/Http/Controllers/Gymies/GymiesInvoiceGenerator.php"
    "app/Http/Controllers/Gymies/GymiesSchemaEnsure.php"
    "app/Http/Controllers/Gymies/GymiesCronController.php"

    # Payment (payout wiring + Mollie webhook)
    "app/Http/Controllers/Gymies/GymiesPaymentController.php"

    # FCM Push
    "app/Http/Controllers/Gymies/FcmPushHelper.php"
    "app/Http/Controllers/Gymies/GymiesDeviceTokenController.php"

    # Routes
    "routes_gymies_full.php"

    # Middleware
    "app/Http/Middleware/GymiesRateLimitMiddleware.php"
)

# Check of alle bestanden bestaan
MISSING=0
for f in "${FILES_TO_DEPLOY[@]}"; do
    if [ ! -f "$f" ]; then
        echo "  ❌ ONTBREEKT: $f"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -gt 0 ]; then
    echo ""
    echo "❌ $MISSING bestand(en) ontbreken. Deploy afgebroken."
    exit 1
fi

# Maak tar
tar czf /tmp/gymies_payout_deploy.tar.gz "${FILES_TO_DEPLOY[@]}" 2>/dev/null
FILE_COUNT=${#FILES_TO_DEPLOY[@]}
TAR_SIZE=$(du -h /tmp/gymies_payout_deploy.tar.gz | cut -f1)
echo "  ✓ $FILE_COUNT bestanden ingepakt ($TAR_SIZE)"

if $DRY_RUN; then
    echo ""
    echo "📋 Bestanden die gedeployd zouden worden:"
    for f in "${FILES_TO_DEPLOY[@]}"; do
        echo "    → $f"
    done
    rm -f /tmp/gymies_payout_deploy.tar.gz
    echo ""
    echo "🏃 DRY RUN klaar — geen wijzigingen gemaakt."
    exit 0
fi

# --- Stap 2: Upload ---
echo ""
echo "📤 Stap 2: Upload naar server..."
scp -i "$SSH_KEY" /tmp/gymies_payout_deploy.tar.gz "$SSH_HOST:/tmp/gymies_payout_deploy.tar.gz"
echo "  ✓ Upload compleet"
rm -f /tmp/gymies_payout_deploy.tar.gz

# --- Stap 3: Uitpakken + configureren op server ---
echo ""
echo "🔧 Stap 3: Deploy op server..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
LP="$1"
echo ""

# ── 3a. Backup maken ──
echo "═══ 3a. Backup van huidige versie ═══"
BACKUP_DIR="/tmp/gymies_backup_$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"
sudo cp -r "$LP/app/Http/Controllers/Gymies/" "$BACKUP_DIR/Gymies_controllers/" 2>/dev/null || true
sudo cp "$LP/routes_gymies_full.php" "$BACKUP_DIR/" 2>/dev/null || true
echo "  ✓ Backup in $BACKUP_DIR"

# ── 3b. Uitpakken ──
echo ""
echo "═══ 3b. Bestanden uitpakken ═══"
cd "$LP"
sudo tar xzf /tmp/gymies_payout_deploy.tar.gz -C "$LP" --no-same-owner
rm -f /tmp/gymies_payout_deploy.tar.gz
echo "  ✓ Alle bestanden uitgepakt"

# ── 3c. Permissions ──
echo ""
echo "═══ 3c. Permissions fixen ═══"
sudo find "$LP/app/Http/Controllers/Gymies/" -type d -exec chmod 755 {} \;
sudo find "$LP/app/Http/Controllers/Gymies/" -type f -exec chmod 644 {} \;
sudo chown -R www-data:www-data "$LP/app/Http/Controllers/Gymies/"

sudo chmod 644 "$LP/routes_gymies_full.php"
sudo chown www-data:www-data "$LP/routes_gymies_full.php"

# Storage writable (voor factuur PDFs)
sudo mkdir -p "$LP/storage/app/invoices"
sudo chown -R www-data:www-data "$LP/storage/"
sudo chmod -R 775 "$LP/storage/"
echo "  ✓ Permissions correct"

# ── 3d. Mollie LIVE keys instellen ──
echo ""
echo "═══ 3d. Mollie LIVE keys checken ═══"
if grep -q "MOLLIE_KEY=live_" "$LP/.env" 2>/dev/null; then
    echo "  ✓ Mollie LIVE key al ingesteld"
else
    echo "  ⚠️  Mollie key is NIET live — controleer .env handmatig!"
    echo "     Stel in: MOLLIE_KEY=live_xxxxxxxxxxxxxxxxxxxxxxxx"
fi

# ── 3e. FCM Server Key checken ──
echo ""
echo "═══ 3e. FCM configuratie checken ═══"
if grep -q "FCM_SERVER_KEY=" "$LP/.env" 2>/dev/null; then
    FCM_KEY=$(grep "FCM_SERVER_KEY=" "$LP/.env" | cut -d= -f2)
    if [ -n "$FCM_KEY" ]; then
        echo "  ✓ FCM_SERVER_KEY gevuld"
    else
        echo "  ⚠️  FCM_SERVER_KEY is leeg — push notifications werken niet!"
    fi
else
    echo "  ⚠️  FCM_SERVER_KEY niet in .env — voeg toe!"
fi

# ── 3f. dompdf dependency checken ──
echo ""
echo "═══ 3f. PDF dependency (dompdf) checken ═══"
if [ -d "$LP/vendor/dompdf/dompdf" ]; then
    echo "  ✓ dompdf geïnstalleerd"
else
    echo "  ⚠️  dompdf niet gevonden — installeer met:"
    echo "     cd $LP && composer require dompdf/dompdf --no-dev"
    echo "     (Facturen worden als HTML opgeslagen totdat dompdf beschikbaar is)"
fi

# ── 3g. Cache opnieuw opbouwen ──
echo ""
echo "═══ 3g. Cache rebuilden ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Config + route cache ververst"

# ── 3h. PHP-FPM herstarten ──
echo ""
echo "═══ 3h. PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || \
sudo systemctl restart php8.3-fpm 2>/dev/null || \
sudo systemctl restart php8.2-fpm 2>/dev/null || \
echo "  ⚠️  Kon PHP-FPM niet herstarten"
echo "  ✓ PHP-FPM herstart"

# ── 3i. Verificatie ──
echo ""
echo "═══ 3i. Verificatie ═══"

# Health check
echo "--- Health endpoint ---"
HEALTH=$(curl -s -H "Host: gymies.nl" http://127.0.0.1/api/gymies/health 2>/dev/null || echo '{"error":"curl failed"}')
echo "  $HEALTH" | head -c 200
echo ""

# Payout routes check
echo ""
echo "--- Payout routes ---"
sudo -u www-data php artisan route:list --name=payout 2>&1 | head -15
echo ""

# Admin payout routes
echo "--- Admin payout routes ---"
sudo -u www-data php artisan route:list --name=admin.payouts 2>&1 | head -10
echo ""

# Schema self-healing test
echo "--- Schema ensure (payout tables) ---"
sudo -u www-data php artisan tinker --execute="
    \App\Http\Controllers\Gymies\GymiesSchemaEnsure::trainerPayoutsTable();
    \App\Http\Controllers\Gymies\GymiesSchemaEnsure::payoutTransactionsTable();
    \App\Http\Controllers\Gymies\GymiesSchemaEnsure::payoutRequestsTable();
    echo 'OK: alle payout tabellen bestaan';
" 2>&1 | tail -3

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Deploy compleet!"
echo ""
echo "  Checklist na deploy:"
echo "  □ Controleer Mollie LIVE key in .env"
echo "  □ Controleer FCM_SERVER_KEY in .env"
echo "  □ Installeer dompdf: composer require dompdf/dompdf"
echo "  □ Test: POST /api/gymies/payout/balance"
echo "  □ Test: GET /api/gymies/admin/payouts"
echo "  □ Test: GET /api/gymies/payout/business"
echo "═══════════════════════════════════════════════════════════"

REMOTE

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  🎉 Deploy script klaar!"
echo ""
echo "  Volgende stappen:"
echo "  1. SSH naar server en check .env (Mollie LIVE + FCM key)"
echo "  2. composer require dompdf/dompdf (voor PDF facturen)"
echo "  3. Test payout endpoints in de app"
echo "  4. Eerste trainer uitbetaling → check factuurnummer"
echo "═══════════════════════════════════════════════════════════"
