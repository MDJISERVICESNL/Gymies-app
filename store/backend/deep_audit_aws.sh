#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Deep Audit: controllers, models, routes    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

# ═══════════════════════════════════════════════════════════
# 1. PHP SYNTAX CHECK — ALL FILES
# ═══════════════════════════════════════════════════════════
echo "=== 1. PHP Syntax Check (all Gymies PHP files) ==="
ERRORS=0
TOTAL=0
for f in $(find "$LP/app/Http/Controllers/Gymies/" "$LP/app/Services/" "$LP/app/Http/Middleware/" -name "*.php" 2>/dev/null); do
    TOTAL=$((TOTAL+1))
    RESULT=$(php -l "$f" 2>&1)
    if ! echo "$RESULT" | grep -q "No syntax errors"; then
        echo "  ✗ $(basename $f): $RESULT"
        ERRORS=$((ERRORS+1))
    fi
done
echo "  Checked $TOTAL files, $ERRORS errors"
[ $ERRORS -eq 0 ] && echo "  ✓ All PHP files syntax OK"

# ═══════════════════════════════════════════════════════════
# 2. LIST ALL FILES ON SERVER
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 2. Files on server ==="
echo "--- Controllers ---"
ls -la "$LP/app/Http/Controllers/Gymies/"*.php 2>/dev/null | awk '{print "  " $NF}' | sed "s|$LP/app/Http/Controllers/Gymies/||"
echo "--- Traits ---"
ls -la "$LP/app/Http/Controllers/Gymies/Traits/"*.php 2>/dev/null | awk '{print "  " $NF}' | sed "s|$LP/app/Http/Controllers/Gymies/Traits/||"
echo "--- Services ---"
ls -la "$LP/app/Services/"*.php 2>/dev/null | awk '{print "  " $NF}' | sed "s|$LP/app/Services/||"
echo "--- Middleware ---"
ls -la "$LP/app/Http/Middleware/"*.php "$LP/app/Http/Middleware/Gymies/"*.php 2>/dev/null | awk '{print "  " $NF}' | sed "s|$LP/app/Http/Middleware/||"

# ═══════════════════════════════════════════════════════════
# 3. ROUTE COMPILATION TEST
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 3. Route compilation ==="
cd "$LP"
php artisan route:clear 2>&1 | tail -1
ROUTE_RESULT=$(php artisan route:cache 2>&1)
echo "$ROUTE_RESULT" | tail -1
if echo "$ROUTE_RESULT" | grep -qi "error\|fatal\|exception"; then
    echo "  ✗ Route cache FAILED"
    echo "$ROUTE_RESULT"
else
    echo "  ✓ Route cache OK"
fi

# ═══════════════════════════════════════════════════════════
# 4. FULL ROUTE LIST (gymies only)
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 4. All gymies routes ==="
php artisan route:list --path=gymies 2>&1 | head -80

# ═══════════════════════════════════════════════════════════
# 5. DATABASE TABLES CHECK
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 5. Database tables ==="
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$tables = DB::select('SHOW TABLES');
\$gymiesTables = [];
foreach (\$tables as \$t) {
    \$name = array_values((array)\$t)[0];
    if (str_starts_with(\$name, 'gymies_')) {
        \$gymiesTables[] = \$name;
    }
}
sort(\$gymiesTables);
echo 'Gymies tables: ' . count(\$gymiesTables) . PHP_EOL;
foreach (\$gymiesTables as \$t) {
    \$count = DB::table(\$t)->count();
    echo '  ' . str_pad(\$t, 45) . ' ' . \$count . ' rows' . PHP_EOL;
}
" 2>&1

# ═══════════════════════════════════════════════════════════
# 6. API ENDPOINT TESTS — key flows
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 6. API Endpoint Tests ==="
BASE="https://www.gymiesapp.nl/api/gymies"
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

test_endpoint() {
    local DESC="$1"
    local URL="$2"
    local EXPECT="$3"
    RESP=$(curl -sk -H "Accept: application/json" "$URL" 2>/dev/null)
    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -H "Accept: application/json" "$URL" 2>/dev/null)

    if [ "$EXPECT" = "200" ] && [ "$STATUS" = "200" ]; then
        echo "  ✓ $DESC (HTTP $STATUS)"
    elif [ "$EXPECT" = "401" ] && [ "$STATUS" = "401" ]; then
        echo "  ✓ $DESC (HTTP $STATUS — auth required, correct)"
    elif [ "$EXPECT" = "any" ]; then
        echo "  ✓ $DESC (HTTP $STATUS)"
    else
        echo "  ✗ $DESC (HTTP $STATUS, expected $EXPECT)"
        echo "    $(echo "$RESP" | head -c 150)"
    fi
}

echo "--- Public endpoints (should return 200) ---"
test_endpoint "GET trainers (listing)" "$BASE/trainers" "200"
test_endpoint "GET trainers/27 (show)" "$BASE/trainers/27" "200"
test_endpoint "GET trainers/200 (show)" "$BASE/trainers/200" "200"
test_endpoint "GET trainers/27/availability" "$BASE/trainers/27/availability?from=${FROM}&to=${TO}" "200"
test_endpoint "GET trainers/200/availability" "$BASE/trainers/200/availability?from=${FROM}&to=${TO}" "200"
test_endpoint "GET trainers/27/blocked-slots" "$BASE/trainers/27/blocked-slots?from=${FROM}&to=${TO}" "200"
test_endpoint "GET trainers/27/reviews" "$BASE/trainers/27/reviews" "200"
test_endpoint "GET trainers/27/packages" "$BASE/trainers/27/packages" "200"
test_endpoint "GET trainers/27/media" "$BASE/trainers/27/media" "200"
test_endpoint "GET trainers/27/latest-review" "$BASE/trainers/27/latest-review" "200"

echo ""
echo "--- Auth-required endpoints (should return 401) ---"
test_endpoint "GET me" "$BASE/me" "401"
test_endpoint "GET bookings" "$BASE/bookings" "401"
test_endpoint "GET favorites" "$BASE/favorites" "401"
test_endpoint "GET notifications" "$BASE/notifications" "401"
test_endpoint "GET conversations" "$BASE/conversations" "401"
test_endpoint "GET availability (trainer)" "$BASE/availability" "401"
test_endpoint "GET wallet/balance" "$BASE/wallet/balance" "401"
test_endpoint "GET trainer/dashboard" "$BASE/trainer/dashboard" "401"
test_endpoint "GET trainer/clients" "$BASE/trainer/clients" "401"
test_endpoint "GET trainer/sessions" "$BASE/trainer/sessions" "401"
test_endpoint "GET trainer/revenue" "$BASE/trainer/revenue" "401"

echo ""
echo "--- Admin endpoints (should return 401/403) ---"
test_endpoint "GET vault-console/stats" "$BASE/vault-console/stats" "401"
test_endpoint "GET vault-console/users" "$BASE/vault-console/users" "401"

echo ""
echo "--- Non-existent (should return 404) ---"
test_endpoint "GET trainers/999999" "$BASE/trainers/999999" "any"

# ═══════════════════════════════════════════════════════════
# 7. CHECK .env PRODUCTION VALUES
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 7. Production .env check ==="
cd "$LP"
APP_ENV=$(grep "^APP_ENV=" .env 2>/dev/null | cut -d= -f2)
APP_DEBUG=$(grep "^APP_DEBUG=" .env 2>/dev/null | cut -d= -f2)
HMAC=$(grep "^GYMIES_HMAC_SECRET=" .env 2>/dev/null | cut -d= -f2)
CRON=$(grep "^GYMIES_CRON_KEY=" .env 2>/dev/null | cut -d= -f2)
DEBUG_AUTH=$(grep "^GYMIES_DEBUG_AUTH=" .env 2>/dev/null | cut -d= -f2)

echo "  APP_ENV=$APP_ENV"
[ "$APP_ENV" = "production" ] && echo "    ✓ OK" || echo "    ✗ Should be 'production'"
echo "  APP_DEBUG=$APP_DEBUG"
[ "$APP_DEBUG" = "false" ] && echo "    ✓ OK" || echo "    ✗ Should be 'false'"
echo "  GYMIES_HMAC_SECRET=$([ -n "$HMAC" ] && echo "${HMAC:0:8}..." || echo "(not set)")"
[ -n "$HMAC" ] && [ "$HMAC" != "" ] && echo "    ✓ Set" || echo "    ✗ Not configured!"
echo "  GYMIES_CRON_KEY=$([ -n "$CRON" ] && echo "${CRON:0:8}..." || echo "(not set)")"
[ -n "$CRON" ] && echo "    ✓ Set" || echo "    ✗ Not configured!"
echo "  GYMIES_DEBUG_AUTH=$DEBUG_AUTH"
[ "$DEBUG_AUTH" = "false" ] || [ -z "$DEBUG_AUTH" ] && echo "    ✓ OK (disabled)" || echo "    ✗ Should be 'false'"

# ═══════════════════════════════════════════════════════════
# 8. STORAGE & PERMISSIONS
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 8. Storage & permissions ==="
echo "  storage/logs writable:"
touch "$LP/storage/logs/test_write" 2>/dev/null && rm "$LP/storage/logs/test_write" && echo "    ✓ OK" || echo "    ✗ NOT writable"
echo "  bootstrap/cache writable:"
touch "$LP/bootstrap/cache/test_write" 2>/dev/null && rm "$LP/bootstrap/cache/test_write" && echo "    ✓ OK" || echo "    ✗ NOT writable"
echo "  storage/framework/sessions:"
ls -ld "$LP/storage/framework/sessions" 2>/dev/null | awk '{print "    " $1 " " $3 ":" $4}'
echo "  storage/framework/cache:"
ls -ld "$LP/storage/framework/cache" 2>/dev/null | awk '{print "    " $1 " " $3 ":" $4}'

# ═══════════════════════════════════════════════════════════
# 9. NGINX & SSL CHECK
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== 9. Nginx & SSL ==="
echo "  Nginx status:"
sudo systemctl status nginx 2>/dev/null | head -3 | tail -1
echo "  SSL cert expiry (gymiesapp.nl):"
echo | openssl s_client -servername www.gymiesapp.nl -connect 127.0.0.1:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null || echo "    Could not check"
echo "  Sites enabled:"
ls /etc/nginx/sites-enabled/ 2>/dev/null | sed 's/^/    /'

echo ""
echo "=== AUDIT COMPLETE ==="
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Deep audit complete                               ║"
echo "╚══════════════════════════════════════════════════════╝"
