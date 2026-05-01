<?php
/**
 * Zorg dat routes_gymies_full.php wordt geladen in Laravel.
 * Run op server: sudo php scripts/register_gymies_routes.php [laravel_root]
 *
 * Probeert: routes/web.php, routes/api.php, bootstrap/app.php
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');
$routesFile = $base . '/routes/routes_gymies_full.php';

if (!is_file($routesFile)) {
    echo "FOUT: $routesFile niet gevonden. Run eerst sync_gymies_backend.sh.\n";
    exit(1);
}

$requireLine = "require __DIR__ . '/routes_gymies_full.php';";

// Optie 1: routes/web.php
$webPath = $base . '/routes/web.php';
if (is_file($webPath)) {
    $content = file_get_contents($webPath);
    if (strpos($content, 'routes_gymies_full') !== false) {
        echo "routes/web.php: gymies routes al geladen.\n";
        exit(0);
    }
    $content .= "\n// Gymies API (Flutter app)\n" . $requireLine . "\n";
    if (@file_put_contents($webPath, $content)) {
        echo "routes/web.php: gymies routes toegevoegd.\n";
        exit(0);
    }
}

// Optie 2: routes/api.php
$apiPath = $base . '/routes/api.php';
if (is_file($apiPath)) {
    $content = file_get_contents($apiPath);
    if (strpos($content, 'routes_gymies_full') !== false) {
        echo "routes/api.php: gymies routes al geladen.\n";
        exit(0);
    }
    $content .= "\n// Gymies API (Flutter app)\n" . $requireLine . "\n";
    if (@file_put_contents($apiPath, $content)) {
        echo "routes/api.php: gymies routes toegevoegd.\n";
        exit(0);
    }
}

echo "Kon gymies routes niet automatisch registreren.\n";
echo "Voeg handmatig toe aan routes/web.php (onderaan):\n";
echo "  $requireLine\n";
echo "\nOf aan bootstrap/app.php in withRouting(api: [...]).\n";
exit(1);
