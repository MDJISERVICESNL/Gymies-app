<?php
/**
 * Fix "Target class gymies.auth does not exist"
 * Run from Laravel root: php fix_gymies_auth.php
 * Or: php /path/to/Gymies/scripts/fix_gymies_auth.php /var/www/gymies.nl/laravel
 */
$laravelRoot = $argv[1] ?? getcwd();
$bootstrapApp = $laravelRoot . '/bootstrap/app.php';
$kernel = $laravelRoot . '/app/Http/Kernel.php';

if (!is_file($bootstrapApp) && !is_file($kernel)) {
    fwrite(STDERR, "Laravel niet gevonden. Run vanuit Laravel root of geef pad op: php fix_gymies_auth.php /pad/naar/laravel\n");
    exit(1);
}

// Laravel 11: bootstrap/app.php
if (is_file($bootstrapApp)) {
    $content = file_get_contents($bootstrapApp);
    if (strpos($content, 'gymies.auth') !== false) {
        echo "[OK] Middleware gymies.auth staat al in bootstrap/app.php.\n";
        exit(0);
    }
    $lines = explode("\n", $content);
    $inserted = false;
    foreach ($lines as $i => $line) {
        if (preg_match("/^\s*'auth'\s*=>/", $line)) {
            $indent = preg_match('/^(\s*)/', $line, $m) ? $m[1] : '        ';
            $newLine = $indent . "'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,";
            array_splice($lines, $i + 1, 0, [$newLine]);
            $inserted = true;
            break;
        }
    }
    if ($inserted) {
        copy($bootstrapApp, $bootstrapApp . '.bak_gymies_' . date('Ymd_His'));
        file_put_contents($bootstrapApp, implode("\n", $lines));
        echo "[OK] Middleware alias toegevoegd in bootstrap/app.php.\n";
    } else {
        fwrite(STDERR, "Kon geen 'auth' => regel vinden in bootstrap/app.php. Voeg handmatig toe:\n");
        fwrite(STDERR, "  'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,\n");
        fwrite(STDERR, "Binnen ->withMiddleware(function (Middleware \$middleware) { \$middleware->alias([ ... ]); })\n");
        exit(1);
    }
}
// Laravel 10: Kernel.php
elseif (is_file($kernel)) {
    $content = file_get_contents($kernel);
    if (strpos($content, 'gymies.auth') !== false) {
        echo "[OK] Middleware gymies.auth staat al in Kernel.php.\n";
        exit(0);
    }
    $lines = explode("\n", $content);
    $inserted = false;
    foreach ($lines as $i => $line) {
        if (preg_match("/^\s*'auth'\s*=>/", $line)) {
            $indent = preg_match('/^(\s*)/', $line, $m) ? $m[1] : '        ';
            $newLine = $indent . "'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,";
            array_splice($lines, $i + 1, 0, [$newLine]);
            $inserted = true;
            break;
        }
    }
    if ($inserted) {
        copy($kernel, $kernel . '.bak_gymies_' . date('Ymd_His'));
        file_put_contents($kernel, implode("\n", $lines));
        echo "[OK] Middleware alias toegevoegd in Kernel.php.\n";
    } else {
        fwrite(STDERR, "Voeg handmatig toe in app/Http/Kernel.php:\n  'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,\n");
        exit(1);
    }
}

// Clear caches
$artisan = $laravelRoot . '/artisan';
if (is_file($artisan)) {
    @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan route:clear 2>/dev/null');
    @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan config:clear 2>/dev/null');
    echo "[OK] Cache geleegd.\n";
}

echo "\nTest: GET " . (isset($_SERVER['HTTP_HOST']) ? 'https://' . $_SERVER['HTTP_HOST'] : 'https://gymies.nl') . "/api/gymies/trainers\n";
echo "Zorg dat app/Http/Middleware/GymiesAuthMiddleware.php bestaat (kopieer uit Gymies/backend/Middleware/).\n";
echo "Voor zoekpagina zonder inlog: zet GET trainers en GET trainers/{id} buiten de gymies.auth route-groep.\n";
