#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Diagnose auth 500s + configure secrets      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

# ═══════════════════════════════════════════════════════════
# 1. Check recent laravel.log for 500 errors
# ═══════════════════════════════════════════════════════════
echo "=== 1. Recent errors in laravel.log ==="
tail -100 "$LP/storage/logs/laravel.log" 2>/dev/null | grep -A3 "Server Error\|500\|Exception\|Error\|Fatal" | head -60 || echo "  No errors found"

echo ""
echo "=== 2. Test /me endpoint — see actual error ==="
cd "$LP"
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Http\Kernel::class);

\$request = Illuminate\Http\Request::create('/api/gymies/me', 'GET');
\$request->headers->set('Accept', 'application/json');

try {
    \$response = \$kernel->handle(\$request);
    echo 'Status: ' . \$response->getStatusCode() . PHP_EOL;
    echo 'Body: ' . substr(\$response->getContent(), 0, 500) . PHP_EOL;
} catch (\Throwable \$e) {
    echo 'Exception: ' . get_class(\$e) . PHP_EOL;
    echo 'Message: ' . \$e->getMessage() . PHP_EOL;
    echo 'File: ' . \$e->getFile() . ':' . \$e->getLine() . PHP_EOL;
    echo 'Trace: ' . PHP_EOL;
    \$trace = \$e->getTraceAsString();
    echo substr(\$trace, 0, 1000) . PHP_EOL;
}
" 2>&1

echo ""
echo "=== 3. Check auth middleware ==="
echo "--- EnsureGymiesUserFromToken ---"
head -60 "$LP/app/Http/Middleware/EnsureGymiesUserFromToken.php" 2>/dev/null

echo ""
echo "--- GymiesAuthMiddleware ---"
head -60 "$LP/app/Http/Middleware/GymiesAuthMiddleware.php" 2>/dev/null

echo ""
echo "=== 4. Check latest-review endpoint error ==="
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Http\Kernel::class);

\$request = Illuminate\Http\Request::create('/api/gymies/trainers/27/latest-review', 'GET');
\$request->headers->set('Accept', 'application/json');

try {
    \$response = \$kernel->handle(\$request);
    echo 'Status: ' . \$response->getStatusCode() . PHP_EOL;
    echo 'Body: ' . substr(\$response->getContent(), 0, 500) . PHP_EOL;
} catch (\Throwable \$e) {
    echo 'Exception: ' . get_class(\$e) . PHP_EOL;
    echo 'Message: ' . \$e->getMessage() . PHP_EOL;
    echo 'File: ' . \$e->getFile() . ':' . \$e->getLine() . PHP_EOL;
}
" 2>&1

echo ""
echo "=== 5. Check correct route paths ==="
php artisan route:list 2>&1 | grep -i "favorite\|wallet\|dashboard\|trainer/session\|vault.*stats" | head -15

echo ""
echo "=== 6. Configure HMAC secret + cron key ==="
cd "$LP"

# Generate and set HMAC secret if not set
EXISTING_HMAC=$(grep "^GYMIES_HMAC_SECRET=" .env 2>/dev/null | cut -d= -f2)
if [ -z "$EXISTING_HMAC" ]; then
    NEW_HMAC=$(openssl rand -hex 32)
    echo "GYMIES_HMAC_SECRET=$NEW_HMAC" | sudo tee -a .env > /dev/null
    echo "  ✓ HMAC secret generated and added: ${NEW_HMAC:0:8}..."
else
    echo "  ✓ HMAC secret already set: ${EXISTING_HMAC:0:8}..."
fi

# Generate and set cron key if not set
EXISTING_CRON=$(grep "^GYMIES_CRON_KEY=" .env 2>/dev/null | cut -d= -f2)
if [ -z "$EXISTING_CRON" ]; then
    NEW_CRON=$(openssl rand -hex 16)
    echo "GYMIES_CRON_KEY=$NEW_CRON" | sudo tee -a .env > /dev/null
    echo "  ✓ Cron key generated and added: ${NEW_CRON:0:8}..."
else
    echo "  ✓ Cron key already set: ${EXISTING_CRON:0:8}..."
fi

# Clear config cache so new values take effect
php artisan config:clear 2>&1 | tail -1
php artisan config:cache 2>&1 | tail -1

echo ""
echo "=== Done ==="
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Diagnostics + secrets configured                  ║"
echo "╚══════════════════════════════════════════════════════╝"
