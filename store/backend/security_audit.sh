#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# GYMIES Security Audit — 7 checks
# ═══════════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  GYMIES Security Audit"
echo "═══════════════════════════════════════════════════════════"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1. RATE LIMITING — publieke endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
grep -rn 'throttle\|rate.limit\|RateLimiter\|GymiesRateLimit' /var/www/gymies/routes_gymies_full.php 2>/dev/null | head -20
echo ""
grep -rn 'throttle\|rate.limit\|RateLimiter' /var/www/gymies/app/Http/Middleware/GymiesRateLimit* 2>/dev/null | head -10
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  2. SQL INJECTION — raw queries check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
grep -rn 'DB::raw\|->whereRaw\|->orderByRaw\|->selectRaw\|->havingRaw' /var/www/gymies/app/Http/Controllers/Gymies/ --include='*.php' 2>/dev/null | grep -v 'vendor\|\.bak' | head -30
if [ $? -ne 0 ]; then
    echo "  ✓ Geen raw SQL queries gevonden"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  3. CORS — configuratie"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat /var/www/gymies/config/cors.php 2>/dev/null | grep -A2 'allowed_origins\|allowed_methods\|paths' | head -20
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  4. SANCTUM / TOKEN SECURITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
grep -n 'expiration\|token_expiration\|SANCTUM' /var/www/gymies/config/sanctum.php 2>/dev/null | head -10
echo ""
echo "--- HMAC check ---"
grep -rn 'hmac\|HMAC\|hash_hmac' /var/www/gymies/app/Http/Controllers/Gymies/ --include='*.php' 2>/dev/null | head -5
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  5. FILE UPLOAD — MIME validatie"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
grep -rn 'finfo_open\|mime_content_type\|getMimeType\|mimes:\|mimetypes:' /var/www/gymies/app/Http/Controllers/Gymies/ --include='*.php' 2>/dev/null | grep -v 'vendor\|\.bak' | head -10
if [ $? -ne 0 ]; then
    echo "  ⚠️  Geen MIME-type validatie gevonden in Gymies controllers"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  6. ENVIRONMENT VARIABLES — secrets audit"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sudo grep -E 'SECRET|KEY|PASSWORD|TOKEN|DSN' /var/www/gymies/.env 2>/dev/null | grep -v '^#' | sed 's/=.*/=***REDACTED***/'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  7. BACKUP ENCRYPTIE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [ -f /var/www/gymies/storage/scripts/backup_gymies.sh ]; then
    grep -n 'encrypt\|gpg\|openssl\|age\|gzip' /var/www/gymies/storage/scripts/backup_gymies.sh 2>/dev/null | head -10
    if [ $? -ne 0 ]; then
        echo "  ⚠️  Geen encryptie gevonden in backup script"
    fi
else
    ls /var/www/gymies/storage/scripts/backup* 2>/dev/null || echo "  ⚠️  Geen backup script gevonden in storage/scripts/"
    ls /var/www/gymies/backup* 2>/dev/null || true
    ls /root/backup* 2>/dev/null || true
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BONUS: Debug/dev endpoints exposed?"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
grep -rn 'debug\|telescope\|phpinfo\|tinker' /var/www/gymies/routes_gymies_full.php 2>/dev/null | head -10
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "  Audit compleet"
echo "═══════════════════════════════════════════════════════════"

REMOTE
