<?php
/**
 * Voeg EnsureGymiesAuthPreempt toe aan het BEGIN van de api middleware group.
 * Zo draait onze auth vóór auth:sanctum en voorkomt "Unauthorized".
 *
 * Gebruik: php register_gymies_preempt.php [laravel_root]
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');

$middlewareClass = 'App\\Http\\Middleware\\EnsureGymiesAuthPreempt';
$newLine = "    \$middleware->api(prepend: [\\{$middlewareClass}::class]);\n";

$bootstrapPath = $base . '/bootstrap/app.php';
if (!file_exists($bootstrapPath)) {
    echo "bootstrap/app.php niet gevonden.\n";
    exit(1);
}

$content = file_get_contents($bootstrapPath);
if (strpos($content, 'EnsureGymiesAuthPreempt') !== false) {
    echo "EnsureGymiesAuthPreempt al geregistreerd.\n";
    exit(0);
}

// Voeg toe direct na "function (Middleware $middleware) {"
$content = preg_replace(
    '/(->withMiddleware\s*\(\s*function\s*\(\s*Middleware\s+\$middleware\s*\)\s*\{)/s',
    '$1' . "\n" . $newLine,
    $content,
    1
);

if (strpos($content, 'EnsureGymiesAuthPreempt') === false) {
    $content = preg_replace(
        '/(->withMiddleware\s*\(\s*function\s*\([^)]+\)\s*\{)/s',
        '$1' . "\n" . $newLine,
        $content,
        1
    );
}

if (strpos($content, 'EnsureGymiesAuthPreempt') === false) {
    echo "Kon preempt middleware niet toevoegen.\n";
    echo "Voeg handmatig toe in bootstrap/app.php binnen withMiddleware:\n";
    echo "  \$middleware->api(prepend: [\\{$middlewareClass}::class]);\n";
    exit(1);
}

file_put_contents($bootstrapPath, $content);
echo "EnsureGymiesAuthPreempt toegevoegd aan api middleware (prepend).\n";
