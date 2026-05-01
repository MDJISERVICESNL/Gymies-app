#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Launch Verificatie ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══════════════════════════════════════"
echo "  1. SENTRY DSN CHECK"
echo "═══════════════════════════════════════"
echo ""
echo "--- .env waarde ---"
sudo grep "SENTRY" "$LP/.env" 2>/dev/null || echo "  ⚠️  Geen SENTRY variabelen in .env"
echo ""
echo "--- Config cache waarde ---"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    \$dsn = config('gymies.sentry_dsn');
    echo 'gymies.sentry_dsn: ' . (\$dsn ?: '(LEEG)') . PHP_EOL;
    \$rate = config('gymies.sentry_traces_sample_rate');
    echo 'sentry_traces_sample_rate: ' . \$rate . PHP_EOL;
    // Check ook de sentry package config
    \$pkgDsn = config('sentry.dsn');
    echo 'sentry.dsn (package): ' . (\$pkgDsn ?: '(LEEG)') . PHP_EOL;
" 2>&1
echo ""

echo "═══════════════════════════════════════"
echo "  2. MIN APP VERSION CHECK"
echo "═══════════════════════════════════════"
echo ""
echo "--- .env waarde ---"
sudo grep "GYMIES_MIN_APP_VERSION\|GYMIES_LATEST_APP_VERSION" "$LP/.env" 2>/dev/null || echo "  ⚠️  Geen GYMIES_*_APP_VERSION in .env"
echo ""
echo "--- Config cache waarde ---"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo 'min_app_version:    ' . config('gymies.min_app_version', '(NIET GEZET)') . PHP_EOL;
    echo 'latest_app_version: ' . config('gymies.latest_app_version', '(NIET GEZET)') . PHP_EOL;
" 2>&1
echo ""

echo "--- app-version endpoint ---"
APPVER=$(curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/app-version?_=$(date +%s)" 2>/dev/null)
echo "  Response: $APPVER"
echo ""

echo "═══════════════════════════════════════"
echo "  3. RATE LIMITING MIDDLEWARE CHECK"
echo "═══════════════════════════════════════"
echo ""
echo "--- Middleware alias geregistreerd? ---"
sudo grep -n "gymies.rate.limit\|GymiesRateLimitMiddleware" "$LP/bootstrap/app.php" 2>/dev/null || echo "  ⚠️  Middleware NIET in bootstrap/app.php"
echo ""
echo "--- Middleware bestand bestaat? ---"
ls -la "$LP/app/Http/Middleware/GymiesRateLimitMiddleware.php" 2>/dev/null || echo "  ⚠️  Middleware bestand ontbreekt!"
echo ""
echo "--- Routes met throttle/rate-limit middleware ---"
sudo -u www-data php artisan route:list 2>&1 | grep -iE "throttle|rate.limit|gymies.rate" | head -15 || echo "  (geen routes met rate limit middleware)"
echo ""
echo "--- Routes met gymies.rate.limit middleware (via tinker alternatief) ---"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    \$count = 0;
    foreach (app('router')->getRoutes() as \$route) {
        \$mw = implode(',', \$route->middleware());
        if (str_contains(\$mw, 'throttle') || str_contains(\$mw, 'rate')) {
            echo '  ' . implode('|', \$route->methods()) . ' ' . \$route->uri() . ' [' . \$mw . ']' . PHP_EOL;
            \$count++;
            if (\$count >= 15) { echo '  ... (meer routes)' . PHP_EOL; break; }
        }
    }
    if (\$count === 0) echo '  Geen routes met throttle/rate middleware gevonden' . PHP_EOL;
" 2>&1
echo ""

echo "═══════════════════════════════════════"
echo "  4. HEALTH ENDPOINT (bevestiging)"
echo "═══════════════════════════════════════"
echo ""
HEALTH=$(curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)" 2>/dev/null)
echo "  $HEALTH"
echo ""

echo "═══════════════════════════════════════"
echo "  5. SAMENVATTING"
echo "═══════════════════════════════════════"
echo ""

# Sentry check
SENTRY_DSN=$(sudo grep "^SENTRY_LARAVEL_DSN=" "$LP/.env" 2>/dev/null | cut -d= -f2-)
if [ -n "$SENTRY_DSN" ] && [ "$SENTRY_DSN" != "" ]; then
    echo "  ✓ Sentry DSN: ingesteld"
else
    echo "  ⚠️  Sentry DSN: NIET ingesteld — voeg SENTRY_LARAVEL_DSN toe aan .env"
fi

# Min version check
MIN_VER=$(sudo grep "^GYMIES_MIN_APP_VERSION=" "$LP/.env" 2>/dev/null | cut -d= -f2-)
if [ -n "$MIN_VER" ]; then
    echo "  ✓ Min app version: $MIN_VER"
else
    echo "  ⚠️  Min app version: niet in .env (default 1.0.0 uit config)"
fi

# Rate limiting
if sudo grep -q "gymies.rate.limit\|GymiesRateLimitMiddleware" "$LP/bootstrap/app.php" 2>/dev/null; then
    echo "  ✓ Rate limiting: middleware geregistreerd"
else
    echo "  ⚠️  Rate limiting: middleware NIET geregistreerd in bootstrap/app.php"
fi

# Health
if echo "$HEALTH" | grep -q '"status":"ok"'; then
    echo "  ✓ Health endpoint: OK (200)"
else
    echo "  ⚠️  Health endpoint: niet OK"
fi

echo ""
echo "═══ Done ═══"
REMOTE
