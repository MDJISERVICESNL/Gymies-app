<?php
/**
 * Pas de 401-response aan voor api/gymies: gebruik NL-melding i.p.v. "Unauthorized".
 * Voorkomt dat de app "Unauthorized" toont; toont "Je sessie is verlopen. Log opnieuw in."
 *
 * Gebruik: php patch_401_exception_handler.php [laravel_root]
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');

$bootstrapPath = $base . '/bootstrap/app.php';
if (!file_exists($bootstrapPath)) {
    echo "bootstrap/app.php niet gevonden.\n";
    exit(1);
}

$content = file_get_contents($bootstrapPath);
if (strpos($content, 'Je sessie is verlopen. Log opnieuw in.') !== false && strpos($content, 'api/gymies') !== false) {
    echo "401-handler al gepatcht.\n";
    exit(0);
}

$handler = "
    // Gymies: vriendelijke 401 voor api/gymies
    \$exceptions->render(function (\\Illuminate\\Auth\\AuthenticationException \$e, \\Illuminate\\Http\\Request \$request) {
        if (\$request->is('api/gymies*') && \$request->expectsJson()) {
            return response()->json(['message' => 'Je sessie is verlopen. Log opnieuw in.'], 401);
        }
        return null;
    });
";

// Zoek ->withExceptions( en voeg onze handler toe
if (!preg_match('/->withExceptions\s*\(/s', $content)) {
    echo "Geen withExceptions gevonden in bootstrap. Laravel 11+ vereist dit.\n";
    exit(0);
}
if (preg_match('/->withExceptions\s*\(\s*function\s*\([^)]+\)\s*\{/s', $content)) {
    $content = preg_replace(
        '/(->withExceptions\s*\(\s*function\s*\([^)]+\)\s*\{)/s',
        '$1' . $handler,
        $content,
        1
    );
}

if (strpos($content, 'Je sessie is verlopen') === false) {
    echo "Kon 401-handler niet toevoegen. Voeg handmatig toe in bootstrap/app.php ->withExceptions().\n";
    exit(1);
}

file_put_contents($bootstrapPath, $content);
echo "401-exception handler toegevoegd.\n";
