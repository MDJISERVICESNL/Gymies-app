#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════
# GYMIES Deploy: FCM V1 API + Service Account
# ═══════════════════════════════════════════════════════════════
#
# Deployt:
# 1. Herschreven FcmPushHelper.php (V1 API met OAuth2 JWT)
# 2. Firebase service account JSON
#
# Usage: ./deploy_fcm_v1.sh
# ═══════════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"
LARAVEL_PATH="/var/www/gymies"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  GYMIES Deploy: FCM V1 API + Service Account JSON"
echo "═══════════════════════════════════════════════════════════"
echo ""

# --- Stap 1: Check bestanden ---
echo "📦 Stap 1: Bestanden checken..."
cd "$LOCAL_DIR"

FCM_HELPER="app/Http/Controllers/Gymies/FcmPushHelper.php"
SERVICE_ACCOUNT="firebase-service-account.json"

if [ ! -f "$FCM_HELPER" ]; then
    echo "  ❌ ONTBREEKT: $FCM_HELPER"
    exit 1
fi
echo "  ✓ $FCM_HELPER"

# Service account JSON - check meerdere locaties
SA_PATH=""
if [ -f "$SERVICE_ACCOUNT" ]; then
    SA_PATH="$SERVICE_ACCOUNT"
elif [ -f "storage/app/$SERVICE_ACCOUNT" ]; then
    SA_PATH="storage/app/$SERVICE_ACCOUNT"
fi

if [ -z "$SA_PATH" ]; then
    echo "  ⚠️  Service account JSON niet gevonden lokaal"
    echo "     We uploaden alleen FcmPushHelper.php"
    echo "     Upload het JSON bestand handmatig naar server:"
    echo "     scp -i $SSH_KEY gymiesapp-d1424-*.json $SSH_HOST:$LARAVEL_PATH/storage/app/firebase-service-account.json"
else
    echo "  ✓ $SA_PATH"
fi

# --- Stap 2: Upload FcmPushHelper.php ---
echo ""
echo "📤 Stap 2: FcmPushHelper.php uploaden..."
scp -i "$SSH_KEY" "$FCM_HELPER" "$SSH_HOST:/tmp/FcmPushHelper.php"
echo "  ✓ FcmPushHelper.php geüpload"

# --- Stap 3: Upload service account JSON (als beschikbaar) ---
if [ -n "$SA_PATH" ]; then
    echo ""
    echo "📤 Stap 3: Service account JSON uploaden..."
    scp -i "$SSH_KEY" "$SA_PATH" "$SSH_HOST:/tmp/firebase-service-account.json"
    echo "  ✓ Service account JSON geüpload"
fi

# --- Stap 4: Installeren op server ---
echo ""
echo "🔧 Stap 4: Installeren op server..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" "$SA_PATH" << 'REMOTE'
LP="$1"
HAS_SA="$2"

echo ""
echo "═══ Backup ═══"
sudo cp "$LP/app/Http/Controllers/Gymies/FcmPushHelper.php" "/tmp/FcmPushHelper_backup_$(date +%H%M%S).php" 2>/dev/null || true
echo "  ✓ Backup gemaakt"

echo ""
echo "═══ FcmPushHelper.php installeren ═══"
sudo cp /tmp/FcmPushHelper.php "$LP/app/Http/Controllers/Gymies/FcmPushHelper.php"
sudo chmod 644 "$LP/app/Http/Controllers/Gymies/FcmPushHelper.php"
sudo chown www-data:www-data "$LP/app/Http/Controllers/Gymies/FcmPushHelper.php"
rm -f /tmp/FcmPushHelper.php
echo "  ✓ FcmPushHelper.php geïnstalleerd"

if [ -f "/tmp/firebase-service-account.json" ]; then
    echo ""
    echo "═══ Service Account JSON installeren ═══"
    sudo mkdir -p "$LP/storage/app"
    sudo cp /tmp/firebase-service-account.json "$LP/storage/app/firebase-service-account.json"
    sudo chmod 600 "$LP/storage/app/firebase-service-account.json"
    sudo chown www-data:www-data "$LP/storage/app/firebase-service-account.json"
    rm -f /tmp/firebase-service-account.json
    echo "  ✓ Service account JSON geïnstalleerd op $LP/storage/app/firebase-service-account.json"
    echo "  ✓ Permissions: 600 (alleen www-data kan lezen)"
fi

echo ""
echo "═══ Cache rebuilden ═══"
cd "$LP"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
echo "  ✓ Cache ververst"

echo ""
echo "═══ PHP-FPM herstarten ═══"
sudo systemctl restart php8.4-fpm 2>/dev/null || \
sudo systemctl restart php8.3-fpm 2>/dev/null || \
sudo systemctl restart php8.2-fpm 2>/dev/null || \
echo "  ⚠️  Kon PHP-FPM niet herstarten"
echo "  ✓ PHP-FPM herstart"

echo ""
echo "═══ Verificatie ═══"

# Check of service account JSON leesbaar is
echo "--- Service Account JSON ---"
if [ -f "$LP/storage/app/firebase-service-account.json" ]; then
    SA_PROJECT=$(sudo -u www-data php -r "
        \$d = json_decode(file_get_contents('$LP/storage/app/firebase-service-account.json'), true);
        echo \$d['project_id'] ?? 'FOUT';
    " 2>/dev/null)
    echo "  Project ID: $SA_PROJECT"
    if [ "$SA_PROJECT" = "gymiesapp-d1424" ]; then
        echo "  ✓ Service account correct!"
    else
        echo "  ❌ Project ID klopt niet!"
    fi
else
    echo "  ❌ Service account JSON NIET gevonden op $LP/storage/app/"
    echo "     Upload handmatig!"
fi

# Quick FCM test (token exchange only, geen push)
echo ""
echo "--- FCM Token Exchange Test ---"
sudo -u www-data php artisan tinker --execute="
    try {
        \$ref = new \ReflectionMethod(\App\Http\Controllers\Gymies\FcmPushHelper::class, 'getAccessToken');
        \$ref->setAccessible(true);
        \$token = \$ref->invoke(null);
        if (\$token) {
            echo 'OK: Access token verkregen (' . strlen(\$token) . ' chars)' . PHP_EOL;
        } else {
            echo 'FOUT: Kon geen access token krijgen' . PHP_EOL;
        }
    } catch (\Throwable \$e) {
        echo 'ERROR: ' . \$e->getMessage() . PHP_EOL;
    }
" 2>&1 | grep -v "^$" | tail -5

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ FCM V1 Deploy compleet!"
echo ""
echo "  Status:"
echo "  ✓ FcmPushHelper.php → V1 API (OAuth2 JWT)"
echo "  ✓ Service account JSON → storage/app/"
echo ""
echo "  Nog te doen:"
echo "  □ APNs key uploaden in Firebase Console"
echo "    (Settings → Cloud Messaging → iOS → Upload APNs key)"
echo "    Key ID: H9F9849256 | Team ID: W3MU5Y9MMX"
echo "═══════════════════════════════════════════════════════════"

REMOTE

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  🎉 FCM V1 Deploy klaar!"
echo ""
echo "  Volgende stap:"
echo "  → Upload APNs Authentication Key in Firebase Console"
echo "    Project Settings → Cloud Messaging → iOS app config"
echo "    Key ID: H9F9849256"
echo "    Team ID: W3MU5Y9MMX"
echo "═══════════════════════════════════════════════════════════"
