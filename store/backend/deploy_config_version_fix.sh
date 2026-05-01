#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES — Config + Controller Version Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. Waar komen de huidige waarden vandaan? ═══"
echo "--- Zoek 1.0.0 en 1.2.1 in controller ---"
sudo grep -rn "1\.0\.0\|1\.2\.1\|min_version\|latest_version\|min_app_version\|latest_app_version" "$LP/app/Http/Controllers/Gymies/GymiesHealthController.php" | head -20
echo ""

echo "--- config/gymies.php bestaan? ---"
if [ -f "$LP/config/gymies.php" ]; then
    echo "  ✓ Bestaat"
    echo "--- Inhoud (zoek version) ---"
    sudo grep -n "version\|app_version" "$LP/config/gymies.php" || echo "  (geen version keys)"
else
    echo "  ✗ config/gymies.php bestaat NIET"
fi
echo ""

echo "═══ 2. Fix: voeg version config toe aan config/gymies.php ═══"
if [ -f "$LP/config/gymies.php" ]; then
    # Check of de keys al bestaan
    if sudo grep -q "min_app_version" "$LP/config/gymies.php"; then
        echo "  ✓ min_app_version bestaat al in config"
    else
        # Voeg toe voor de laatste ]; van het config bestand
        sudo -u www-data php -r "
            \$file = '$LP/config/gymies.php';
            \$content = file_get_contents(\$file);

            // Zoek de laatste ];
            \$pos = strrpos(\$content, '];');
            if (\$pos !== false) {
                \$insert = \"
    // --- App versie beheer ---
    'min_app_version' => env('GYMIES_MIN_APP_VERSION', '1.0.0'),
    'latest_app_version' => env('GYMIES_LATEST_APP_VERSION', '1.0.0'),
    'api_version' => env('GYMIES_API_VERSION', '1.0'),

    // --- Sentry ---
    'sentry_dsn' => env('SENTRY_LARAVEL_DSN', ''),
    'sentry_traces_sample_rate' => (float) env('SENTRY_TRACES_SAMPLE_RATE', 0.2),

\";
                \$newContent = substr(\$content, 0, \$pos) . \$insert . substr(\$content, \$pos);
                file_put_contents(\$file, \$newContent);
                echo '  ✓ Version + Sentry config keys toegevoegd aan config/gymies.php' . PHP_EOL;
            } else {
                echo '  ✗ Kon einde van config array niet vinden' . PHP_EOL;
            }
        " 2>&1
    fi
else
    echo "  ✗ config/gymies.php bestaat niet — wordt aangemaakt"
    sudo -u www-data tee "$LP/config/gymies.php" > /dev/null << 'PHPEOF'
<?php

return [
    // --- App versie beheer ---
    'min_app_version' => env('GYMIES_MIN_APP_VERSION', '1.0.0'),
    'latest_app_version' => env('GYMIES_LATEST_APP_VERSION', '1.0.0'),
    'api_version' => env('GYMIES_API_VERSION', '1.0'),

    // --- Sentry ---
    'sentry_dsn' => env('SENTRY_LARAVEL_DSN', ''),
    'sentry_traces_sample_rate' => (float) env('SENTRY_TRACES_SAMPLE_RATE', 0.2),
];
PHPEOF
    echo "  ✓ config/gymies.php aangemaakt"
fi
echo ""

echo "═══ 3. Fix controller: gebruik config() i.p.v. hardcoded waarden ═══"
CTRL="$LP/app/Http/Controllers/Gymies/GymiesHealthController.php"
# Zoek de appVersion methode
echo "--- Huidige appVersion methode ---"
sudo grep -A 30 "function appVersion" "$CTRL" | head -35
echo ""

# Fix hardcoded waarden in de controller
sudo -u www-data php -r "
    \$file = '$CTRL';
    \$content = file_get_contents(\$file);
    \$changed = false;

    // Vervang hardcoded '1.0.0' bij min_version met config('gymies.min_app_version')
    // Zoek patronen als: 'min_version' => '1.0.0' of \"min_version\" => \"1.0.0\"
    \$patterns = [
        \"/'min_version'\s*=>\s*'[^']*'/\" => \"'min_version' => config('gymies.min_app_version', '1.0.0')\",
        \"/\\\"min_version\\\"\s*=>\s*\\\"[^\\\"]*\\\"/\" => \"'min_version' => config('gymies.min_app_version', '1.0.0')\",
        \"/'latest_version'\s*=>\s*'[^']*'/\" => \"'latest_version' => config('gymies.latest_app_version', '1.0.0')\",
        \"/\\\"latest_version\\\"\s*=>\s*\\\"[^\\\"]*\\\"/\" => \"'latest_version' => config('gymies.latest_app_version', '1.0.0')\",
    ];

    foreach (\$patterns as \$pattern => \$replacement) {
        \$newContent = preg_replace(\$pattern, \$replacement, \$content);
        if (\$newContent !== \$content) {
            \$content = \$newContent;
            \$changed = true;
        }
    }

    // Ook config('gymies.api_version') waarden fixen als die hardcoded zijn
    // Vervang hardcoded versie strings in config() calls die al bestaan

    if (\$changed) {
        file_put_contents(\$file, \$content);
        echo '  ✓ Controller bijgewerkt naar config() calls' . PHP_EOL;
    } else {
        echo '  ℹ️  Geen hardcoded versies gevonden om te vervangen' . PHP_EOL;
        echo '  Mogelijk gebruikt controller al config() of andere bron' . PHP_EOL;
    }
" 2>&1

echo ""
echo "--- Na fix: appVersion methode ---"
sudo grep -A 30 "function appVersion" "$CTRL" | head -35
echo ""

echo "═══ 4. Syntax check ═══"
sudo -u www-data php -l "$CTRL" 2>&1
sudo -u www-data php -l "$LP/config/gymies.php" 2>&1
echo ""

echo "═══ 5. Cache + restart ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sleep 1
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ Cache + PHP-FPM"
echo ""

echo "═══ 6. Verify ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo 'min_app_version:    ' . config('gymies.min_app_version', 'LEEG') . PHP_EOL;
    echo 'latest_app_version: ' . config('gymies.latest_app_version', 'LEEG') . PHP_EOL;
" 2>&1
echo ""

echo "═══ 7. Endpoint test ═══"
curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/app-version?_=$(date +%s)" 2>/dev/null
echo ""

echo ""
echo "═══ Done ═══"
REMOTE
