#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Deep HTTPS debug                           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

# ── 1. What does GymiesTrainerController@show do at lines 30-55? ─────────
echo "============================================"
echo "  1. GymiesTrainerController@show (the source of 'Trainer niet gevonden')"
echo "============================================"
sudo sed -n '1,70p' "$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php"

echo ""
echo "============================================"
echo "  2. GymiesAvailabilityController — first 80 lines"
echo "============================================"
sudo sed -n '1,80p' "$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php"

echo ""
echo "============================================"
echo "  3. Routes file — trainer routes section"
echo "============================================"
sudo cat -n "$LP/routes/gymies.php" | grep -A3 -B3 'trainer'

echo ""
echo "============================================"
echo "  4. Place debug PHP to check REQUEST_URI via HTTPS"
echo "============================================"
sudo bash -c "cat > $LP/public/debug_env.php << 'DBGPHP'
<?php
header('Content-Type: application/json');
echo json_encode([
    'REQUEST_URI' => \$_SERVER['REQUEST_URI'] ?? 'N/A',
    'SCRIPT_NAME' => \$_SERVER['SCRIPT_NAME'] ?? 'N/A',
    'SCRIPT_FILENAME' => \$_SERVER['SCRIPT_FILENAME'] ?? 'N/A',
    'PHP_SELF' => \$_SERVER['PHP_SELF'] ?? 'N/A',
    'QUERY_STRING' => \$_SERVER['QUERY_STRING'] ?? 'N/A',
    'SERVER_NAME' => \$_SERVER['SERVER_NAME'] ?? 'N/A',
    'HTTP_HOST' => \$_SERVER['HTTP_HOST'] ?? 'N/A',
    'SERVER_PORT' => \$_SERVER['SERVER_PORT'] ?? 'N/A',
    'HTTPS' => \$_SERVER['HTTPS'] ?? 'N/A',
    'REMOTE_ADDR' => \$_SERVER['REMOTE_ADDR'] ?? 'N/A',
], JSON_PRETTY_PRINT);
DBGPHP"
sudo chown www-data:www-data "$LP/public/debug_env.php"

echo "  Testing debug_env.php via HTTPS..."
curl -sk "https://www.gymiesapp.nl/debug_env.php" 2>/dev/null
echo ""

echo ""
echo "============================================"
echo "  5. Test: does /api/ route reach PHP correctly?"
echo "============================================"
# Create an API debug endpoint inside Laravel's index.php wrapper
sudo bash -c "cat > $LP/public/api_debug.php << 'APIDBG'
<?php
header('Content-Type: application/json');
echo json_encode([
    'reached' => 'api_debug.php',
    'REQUEST_URI' => \$_SERVER['REQUEST_URI'] ?? 'N/A',
    'SCRIPT_NAME' => \$_SERVER['SCRIPT_NAME'] ?? 'N/A',
]);
APIDBG"
sudo chown www-data:www-data "$LP/public/api_debug.php"

echo "  Testing /api_debug.php via HTTPS..."
curl -sk "https://www.gymiesapp.nl/api_debug.php" 2>/dev/null
echo ""
echo ""

echo "============================================"
echo "  6. Route cache check"
echo "============================================"
if [ -f "$LP/bootstrap/cache/routes-v7.php" ]; then
    echo "  ⚠️  Route cache EXISTS — checking..."
    ls -la "$LP/bootstrap/cache/routes-v7.php"
    echo "  Searching for availability in route cache..."
    sudo grep -c 'availability' "$LP/bootstrap/cache/routes-v7.php" 2>/dev/null || echo "  Not found in route cache!"
else
    echo "  ✓ No route cache file (routes-v7)"
fi
if [ -f "$LP/bootstrap/cache/routes.php" ]; then
    echo "  ⚠️  Route cache EXISTS (routes.php)"
    ls -la "$LP/bootstrap/cache/routes.php"
    sudo grep -c 'availability' "$LP/bootstrap/cache/routes.php" 2>/dev/null || echo "  Not found!"
else
    echo "  ✓ No route cache file (routes.php)"
fi

echo ""
echo "============================================"
echo "  7. Check what APP_URL is set to"
echo "============================================"
sudo grep 'APP_URL\|APP_ENV\|APP_DEBUG' "$LP/.env" 2>/dev/null

echo ""
echo "============================================"
echo "  8. Add temporary debug logging to availability route"
echo "============================================"
# Add a debug log line at the START of publicAvailability
sudo -u www-data php -r "
\$file = '$LP/app/Http/Controllers/Gymies/GymiesAvailabilityController.php';
\$content = file_get_contents(\$file);

// Check if debug log already exists
if (strpos(\$content, 'DEBUG_AVAIL_ENTRY') === false) {
    // Find publicAvailability method and add logging after the opening brace
    \$pattern = '/(public function publicAvailability\s*\([^)]*\)\s*(?::\s*\w+\s*)?\{)/';
    \$replacement = '\$1' . \"\\n\" . '        \\Log::info(\"DEBUG_AVAIL_ENTRY\", [\"id\" => \$id ?? \$request->route(\"id\") ?? \"NO_ID\", \"uri\" => \$request->getRequestUri(), \"method\" => \$request->method()]);';
    \$newContent = preg_replace(\$pattern, \$replacement, \$content, 1, \$count);
    if (\$count > 0) {
        file_put_contents(\$file, \$newContent);
        echo \"Debug logging added to publicAvailability\\n\";
    } else {
        echo \"Could not find publicAvailability method signature\\n\";
        // Show what we're looking for
        preg_match('/public function publicAvailability[^{]*\{/', \$content, \$m);
        echo \"Found: \" . (\$m[0] ?? 'NOT FOUND') . \"\\n\";
    }
} else {
    echo \"Debug logging already present\\n\";
}
"

# Also add debug to GymiesTrainerController@show
sudo -u www-data php -r "
\$file = '$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php';
\$content = file_get_contents(\$file);

if (strpos(\$content, 'DEBUG_SHOW_ENTRY') === false) {
    \$pattern = '/(public function show\s*\([^)]*\)\s*(?::\s*\w+\s*)?\{)/';
    \$replacement = '\$1' . \"\\n\" . '        \\Log::info(\"DEBUG_SHOW_ENTRY\", [\"id\" => \$id ?? \$request->route(\"id\") ?? \"NO_ID\", \"uri\" => request()->getRequestUri()]);';
    \$newContent = preg_replace(\$pattern, \$replacement, \$content, 1, \$count);
    if (\$count > 0) {
        file_put_contents(\$file, \$newContent);
        echo \"Debug logging added to TrainerController@show\\n\";
    } else {
        echo \"Could not find show method\\n\";
    }
} else {
    echo \"Debug logging already present in show\\n\";
}
"

# Restart FPM to pick up changes
sudo systemctl restart php8.4-fpm
echo "  PHP-FPM restarted"

echo ""
echo "============================================"
echo "  9. Clear Laravel log and test"
echo "============================================"
sudo truncate -s 0 "$LP/storage/logs/laravel.log"
echo "  Log cleared"

echo ""
echo "  Making HTTPS request..."
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)
curl -sk -H "Accept: application/json" "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null
echo ""

echo ""
echo "  Making HTTP localhost request..."
curl -s -H "Accept: application/json" -H "Host: www.gymiesapp.nl" "http://127.0.0.1/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null
echo ""

echo ""
echo "============================================"
echo "  10. Check Laravel log for debug entries"
echo "============================================"
echo "  Full log:"
sudo cat "$LP/storage/logs/laravel.log" | head -100

# Cleanup debug files
sudo rm -f "$LP/public/debug_env.php" "$LP/public/api_debug.php"

echo ""
echo "--- Done ---"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Deep debug klaar                                  ║"
echo "╚══════════════════════════════════════════════════════╝"
