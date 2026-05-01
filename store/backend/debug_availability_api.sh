#!/bin/bash
# ============================================================
# GYMIES — Debug: waarom geeft de availability API 404?
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Debug availability API                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
cd "$LP"

sudo -u www-data php << 'PHP'
<?php
require_once '/var/www/gymies/vendor/autoload.php';
$app = require_once '/var/www/gymies/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

echo "=== 1. Route check ===\n";
// Zoek de route die matcht op trainers/{id}/availability
$routes = Route::getRoutes();
foreach ($routes as $route) {
    $uri = $route->uri();
    if (strpos($uri, 'trainers') !== false && strpos($uri, 'availability') !== false) {
        $action = $route->getActionName();
        $methods = implode('|', $route->methods());
        echo "  {$methods} {$uri} → {$action}\n";
        echo "  Middleware: " . implode(', ', $route->gatherMiddleware()) . "\n";
    }
}

echo "\n=== 2. Controller file check ===\n";
$controllerFile = '/var/www/gymies/app/Http/Controllers/Gymies/GymiesAvailabilityController.php';
if (file_exists($controllerFile)) {
    echo "  ✓ File exists\n";
    echo "  Size: " . filesize($controllerFile) . " bytes\n";
    echo "  Modified: " . date('Y-m-d H:i:s', filemtime($controllerFile)) . "\n";

    // Check if it contains SlotEngine import
    $content = file_get_contents($controllerFile);
    echo "  Contains 'SlotEngine': " . (strpos($content, 'SlotEngine') !== false ? 'JA' : 'NEE') . "\n";
    echo "  Contains 'bookable_slots': " . (strpos($content, 'bookable_slots') !== false ? 'JA' : 'NEE') . "\n";
    echo "  Contains 'Trainer niet gevonden': " . (strpos($content, 'Trainer niet gevonden') !== false ? 'JA' : 'NEE') . "\n";

    // Show first 30 lines
    $lines = explode("\n", $content);
    echo "\n  --- First 10 lines ---\n";
    for ($i = 0; $i < min(10, count($lines)); $i++) {
        echo "  " . ($i+1) . ": " . $lines[$i] . "\n";
    }
} else {
    echo "  ✗ FILE NOT FOUND!\n";
}

echo "\n=== 3. Routes file check ===\n";
$routesFile = '/var/www/gymies/routes_gymies_full.php';
if (file_exists($routesFile)) {
    echo "  ✓ routes_gymies_full.php exists\n";
    echo "  Size: " . filesize($routesFile) . " bytes\n";
    echo "  Modified: " . date('Y-m-d H:i:s', filemtime($routesFile)) . "\n";
} else {
    echo "  ✗ routes_gymies_full.php NOT FOUND!\n";
}

// Check routes/web.php for how routes are loaded
echo "\n  --- routes/web.php (last 20 lines) ---\n";
$webRoutes = file_get_contents('/var/www/gymies/routes/web.php');
$webLines = explode("\n", $webRoutes);
$start = max(0, count($webLines) - 20);
for ($i = $start; $i < count($webLines); $i++) {
    echo "  " . ($i+1) . ": " . $webLines[$i] . "\n";
}

echo "\n=== 4. Direct controller test ===\n";
// Direct call publicAvailability without HTTP
$controller = new \App\Http\Controllers\Gymies\GymiesAvailabilityController();
$request = \Illuminate\Http\Request::create('/api/gymies/trainers/27/availability', 'GET', [
    'from' => date('Y-m-d'),
    'to' => date('Y-m-d', strtotime('+7 days')),
]);

try {
    $response = $controller->publicAvailability($request, '27');
    $data = json_decode($response->getContent(), true);
    echo "  Status: " . $response->getStatusCode() . "\n";
    echo "  Has bookable_slots: " . (isset($data['bookable_slots']) ? 'JA (' . count($data['bookable_slots']) . ')' : 'NEE') . "\n";
    echo "  Has settings: " . (isset($data['settings']) ? 'JA' : 'NEE') . "\n";
    echo "  Has slots: " . (isset($data['slots']) ? 'JA (' . count($data['slots']) . ')' : 'NEE') . "\n";
    if (isset($data['message'])) {
        echo "  Message: " . $data['message'] . "\n";
    }
    if (isset($data['bookable_slots']) && count($data['bookable_slots']) > 0) {
        $first = $data['bookable_slots'][0];
        echo "  First slot: {$first['date']} {$first['start_time']}-{$first['end_time']}\n";
    }
} catch (\Throwable $e) {
    echo "  ERROR: " . $e->getMessage() . "\n";
    echo "  File: " . $e->getFile() . ":" . $e->getLine() . "\n";
}

echo "\n=== 5. HMAC middleware check ===\n";
$secret = env('GYMIES_HMAC_SECRET', 'NOT SET');
echo "  GYMIES_HMAC_SECRET: " . (strlen($secret) > 10 ? substr($secret, 0, 8) . '...' : $secret) . "\n";

echo "\n=== 6. Actual curl test from localhost ===\n";
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, "https://www.gymies.nl/api/gymies/trainers/27/availability?from=" . date('Y-m-d') . "&to=" . date('Y-m-d', strtotime('+7 days')));
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Accept: application/json']);
$result = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
echo "  HTTP {$httpCode}\n";
$decoded = json_decode($result, true);
if ($decoded) {
    echo "  Keys: " . implode(', ', array_keys($decoded)) . "\n";
    if (isset($decoded['message'])) echo "  Message: " . $decoded['message'] . "\n";
    if (isset($decoded['bookable_slots'])) echo "  bookable_slots: " . count($decoded['bookable_slots']) . "\n";
} else {
    echo "  Not JSON. First 200 chars: " . substr($result, 0, 200) . "\n";
}

echo "\nDone.\n";
PHP
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Debug klaar                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
