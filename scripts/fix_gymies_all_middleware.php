<?php
/**
 * Registreer alle Gymies middleware (nodig o.a. voor login – anders 500 "class does not exist").
 * Run op de server vanuit Laravel root: php fix_gymies_all_middleware.php
 * Of: php fix_gymies_all_middleware.php /var/www/gymies.nl/laravel
 */
$laravelRoot = $argv[1] ?? getcwd();
$bootstrapApp = $laravelRoot . '/bootstrap/app.php';
$kernel = $laravelRoot . '/app/Http/Kernel.php';

$aliases = [
    'gymies.auth' => '\\App\\Http\\Middleware\\GymiesAuthMiddleware::class',
    'gymies.rate.limit' => '\\App\\Http\\Middleware\\GymiesRateLimitMiddleware::class',
    'gymies.error_log' => '\\App\\Http\\Middleware\\GymiesApiErrorLoggingMiddleware::class',
    'gymies.idempotency' => '\\App\\Http\\Middleware\\GymiesIdempotencyMiddleware::class',
    'gymies.admin.ip' => '\\App\\Http\\Middleware\\GymiesAdminIpAllowlistMiddleware::class',
    'gymies.admin.capability' => '\\App\\Http\\Middleware\\GymiesAdminCapabilityMiddleware::class',
    'gymies.debug.auth' => '\\App\\Http\\Middleware\\GymiesDebugAuthMiddleware::class',
];

if (!is_file($bootstrapApp) && !is_file($kernel)) {
    fwrite(STDERR, "Laravel niet gevonden. Run vanuit Laravel root of geef pad op: php fix_gymies_all_middleware.php /pad/naar/laravel\n");
    exit(1);
}

$missing = [];
foreach (array_keys($aliases) as $name) {
    $class = trim($aliases[$name], '\\');
    $shortName = substr($class, strrpos($class, '\\') + 1);
    $shortName = str_replace('::class', '', $shortName); // bestandsnaam is GymiesAuthMiddleware.php, niet GymiesAuthMiddleware::class.php
    $path = $laravelRoot . '/app/Http/Middleware/' . $shortName . '.php';
    if (!is_file($path)) {
        $missing[] = $shortName . '.php (kopieer uit Gymies/backend/Middleware/)';
    }
}
if (!empty($missing)) {
    fwrite(STDERR, "Ontbrekende middleware-bestanden op server:\n  - " . implode("\n  - ", $missing) . "\n");
    fwrite(STDERR, "Upload eerst alle bestanden uit backend/Middleware/ naar app/Http/Middleware/ op de server.\n");
    exit(1);
}

// Laravel 11: bootstrap/app.php
if (is_file($bootstrapApp)) {
    $content = file_get_contents($bootstrapApp);
    $already = [];
    foreach (array_keys($aliases) as $name) {
        if (strpos($content, "'$name'") !== false || strpos($content, "\"$name\"") !== false) {
            $already[] = $name;
        }
    }
    if (count($already) === count($aliases)) {
        echo "[OK] Alle Gymies middleware staan al in bootstrap/app.php.\n";
        doClear($laravelRoot);
        exit(0);
    }
    $toAdd = [];
    foreach ($aliases as $name => $class) {
        if (strpos($content, "'$name'") === false && strpos($content, "\"$name\"") === false) {
            $toAdd[] = "'$name' => $class,";
        }
    }
    if (empty($toAdd)) {
        echo "[OK] Alle Gymies middleware staan al in bootstrap/app.php.\n";
        doClear($laravelRoot);
        exit(0);
    }
    $lines = explode("\n", $content);
    $inserted = 0;
    // Zoek plek: na 'auth' =>, na gymies.* alias, of na ->alias([
    $anchorPatterns = [
        "/^\s*'auth'\s*=>/",
        "/^\s*'gymies\./",
        "/^\s*'verified'\s*=>/",
    ];
    foreach ($anchorPatterns as $pattern) {
        foreach ($lines as $i => $line) {
            if (preg_match($pattern, $line)) {
                $indent = preg_match('/^(\s*)/', $line, $m) ? $m[1] : '        ';
                $formatted = array_map(fn ($a) => $indent . $a, $toAdd);
                array_splice($lines, $i + 1, 0, $formatted);
                $inserted = count($formatted);
                break 2;
            }
        }
    }
    // Fallback: zoek ->alias([ en voeg toe na die regel
    if ($inserted === 0 && preg_match('/->alias\s*\(\s*\[/', $content)) {
        foreach ($lines as $i => $line) {
            if (preg_match('/->alias\s*\(\s*\[/', $line)) {
                $indent = preg_match('/^(\s*)/', $line, $m) ? $m[1] : '        ';
                $extraIndent = (strlen($indent) >= 4) ? $indent . '    ' : '        ';
                $formatted = array_map(fn ($a) => $extraIndent . $a, $toAdd);
                array_splice($lines, $i + 1, 0, $formatted);
                $inserted = count($formatted);
                break;
            }
        }
    }
    if ($inserted > 0) {
        copy($bootstrapApp, $bootstrapApp . '.bak_gymies_' . date('Ymd_His'));
        file_put_contents($bootstrapApp, implode("\n", $lines));
        echo "[OK] $inserted Gymies middleware alias(sen) toegevoegd in bootstrap/app.php.\n";
    } else {
        fwrite(STDERR, "Kon geen plek vinden om aliases toe te voegen. Voeg handmatig toe in bootstrap/app.php ->withMiddleware()->alias([ ... ]):\n");
        foreach ($aliases as $name => $class) {
            if (strpos($content, $name) === false) {
                fwrite(STDERR, "  '$name' => $class,\n");
            }
        }
        exit(1);
    }
}
// Laravel 10: Kernel.php
elseif (is_file($kernel)) {
    $content = file_get_contents($kernel);
    $allThere = true;
    foreach (array_keys($aliases) as $name) {
        if (strpos($content, "'$name'") === false && strpos($content, "\"$name\"") === false) {
            $allThere = false;
            break;
        }
    }
    if ($allThere) {
        echo "[OK] Alle Gymies middleware staan al in Kernel.php.\n";
        doClear($laravelRoot);
        exit(0);
    }
    $lines = explode("\n", $content);
    $inserted = 0;
    foreach ($lines as $i => $line) {
        if (preg_match("/^\s*'auth'\s*=>/", $line)) {
            $indent = preg_match('/^(\s*)/', $line, $m) ? $m[1] : '        ';
            $toAdd = [];
            foreach ($aliases as $name => $class) {
                if (strpos($content, "'$name'") === false && strpos($content, "\"$name\"") === false) {
                    $toAdd[] = $indent . "'$name' => $class,";
                }
            }
            if (!empty($toAdd)) {
                array_splice($lines, $i + 1, 0, $toAdd);
                $inserted = count($toAdd);
            }
            break;
        }
    }
    if ($inserted > 0) {
        copy($kernel, $kernel . '.bak_gymies_' . date('Ymd_His'));
        file_put_contents($kernel, implode("\n", $lines));
        echo "[OK] $inserted Gymies middleware alias(sen) toegevoegd in Kernel.php.\n";
    } else {
        fwrite(STDERR, "Voeg handmatig toe in app/Http/Kernel.php \$middlewareAliases:\n");
        foreach ($aliases as $name => $class) {
            fwrite(STDERR, "  '$name' => $class,\n");
        }
        exit(1);
    }
}

doClear($laravelRoot);
echo "\nKlaar. Test inloggen op de site. Bij nog 500: kijk in storage/logs/laravel.log op de server.\n";

function doClear(string $laravelRoot): void
{
    $artisan = $laravelRoot . '/artisan';
    if (is_file($artisan)) {
        @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan route:clear 2>/dev/null');
        @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan config:clear 2>/dev/null');
        echo "[OK] Cache geleegd.\n";
    }
}
