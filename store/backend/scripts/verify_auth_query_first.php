#!/usr/bin/env php
<?php
/**
 * Controleer of de server de "query-first" auth middleware heeft.
 * Run OP DE SERVER: php scripts/verify_auth_query_first.php
 *
 * Als dit faalt: sync_gymies_backend.sh niet gedraaid, of PHP opcache serveert oude code.
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');

$file = $base . '/app/Http/Middleware/EnsureGymiesUserFromToken.php';
if (!is_file($file)) {
    echo "FOUT: EnsureGymiesUserFromToken.php niet gevonden op $file\n";
    exit(1);
}

$content = file_get_contents($file);

// Check 1: getToken() moet access_token query EERST gebruiken
$hasQueryFirst = (
    strpos($content, "request->filled('access_token')") !== false
    && (preg_match('/if\s*\(\s*\$request->filled\s*\(\s*[\'"]access_token[\'"]\s*\)\s*\)\s*\{/s', $content)
       || strpos($content, 'access_token') !== false && strpos($content, "input('access_token')") !== false)
);

// Check 2: moet vóór Authorization header kijken
$queryBeforeHeader = false;
$queryPos = strpos($content, "access_token");
$authPos = strpos($content, "header('Authorization')");
if ($queryPos !== false && $authPos !== false && $queryPos < $authPos) {
    $queryBeforeHeader = true;
}

if ($hasQueryFirst) {
    echo "OK: EnsureGymiesUserFromToken controleert access_token query.\n";
} else {
    echo "FOUT: Middleware heeft GEEN query-first logica. Draai sync_gymies_backend.sh opnieuw!\n";
    exit(1);
}

echo "Na sync: herstart PHP-FPM om opcache te legen: sudo systemctl restart php*-fpm\n";
exit(0);
