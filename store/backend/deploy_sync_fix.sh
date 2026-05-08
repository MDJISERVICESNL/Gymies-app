#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════
# GYMIES Deploy: Bidirectionele sync + dompdf
# ═══════════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"
LARAVEL_PATH="/var/www/gymies"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  GYMIES Deploy: Sync fix + dompdf"
echo "═══════════════════════════════════════════════════════════"
echo ""

cd "$LOCAL_DIR"

FILES=(
    "app/Http/Controllers/Gymies/GymiesTrainerDocumentsController.php"
    "app/Http/Controllers/Gymies/GymiesPayoutController.php"
)

# Check bestanden
for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "❌ ONTBREEKT: $f"
        exit 1
    fi
    echo "  ✓ $f"
done

# Upload
echo ""
echo "📤 Uploaden..."
tar czf /tmp/gymies_sync_deploy.tar.gz "${FILES[@]}"
scp -i "$SSH_KEY" /tmp/gymies_sync_deploy.tar.gz "$SSH_HOST:/tmp/gymies_sync_deploy.tar.gz"
rm -f /tmp/gymies_sync_deploy.tar.gz
echo "  ✓ Upload compleet"

# Installeren op server
echo ""
echo "🔧 Installeren op server..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
LP="$1"

# Backup
sudo cp "$LP/app/Http/Controllers/Gymies/GymiesPayoutController.php" "/tmp/GymiesPayoutController_backup.php" 2>/dev/null || true
sudo cp "$LP/app/Http/Controllers/Gymies/GymiesTrainerDocumentsController.php" "/tmp/GymiesTrainerDocumentsController_backup.php" 2>/dev/null || true

# Uitpakken
sudo tar xzf /tmp/gymies_sync_deploy.tar.gz -C "$LP" --no-same-owner
rm -f /tmp/gymies_sync_deploy.tar.gz

# Permissions
sudo chmod 644 "$LP/app/Http/Controllers/Gymies/GymiesPayoutController.php"
sudo chmod 644 "$LP/app/Http/Controllers/Gymies/GymiesTrainerDocumentsController.php"
sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/GymiesPayoutController.php"
sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/GymiesTrainerDocumentsController.php"
echo "  ✓ Controllers geïnstalleerd"

# dompdf installeren
echo ""
echo "═══ dompdf installeren ═══"
cd "$LP"
if [ -d "vendor/dompdf/dompdf" ]; then
    echo "  ✓ dompdf al geïnstalleerd"
else
    sudo -u www-data composer require dompdf/dompdf --no-dev --no-interaction 2>&1 | tail -5
    if [ -d "vendor/dompdf/dompdf" ]; then
        echo "  ✓ dompdf geïnstalleerd"
    else
        echo "  ⚠️  dompdf installatie mislukt — probeer handmatig"
    fi
fi

# Cache rebuilden
echo ""
echo "═══ Cache rebuilden ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache ververst"

# PHP-FPM restart
sudo systemctl restart php8.4-fpm 2>/dev/null || \
sudo systemctl restart php8.3-fpm 2>/dev/null || \
sudo systemctl restart php8.2-fpm 2>/dev/null || true
echo "  ✓ PHP-FPM herstart"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Deploy compleet!"
echo ""
echo "  Gedeployd:"
echo "  ✓ GymiesPayoutController.php (+ sync naar profiles)"
echo "  ✓ GymiesTrainerDocumentsController.php (+ sync naar payouts)"
echo "  ✓ dompdf (PDF factuur generatie)"
echo "═══════════════════════════════════════════════════════════"

REMOTE

echo ""
echo "🎉 Klaar! Alles gedeployd."
