<?php
/**
 * Registreer GymiesRateLimitMiddleware als gymies.rate.limit middleware.
 *
 * Ondersteunt:
 * - Laravel 11+ (bootstrap/app.php → withMiddleware)
 * - Laravel 10  (app/Http/Kernel.php → $middlewareAliases)
 *
 * Gebruik:
 *   php scripts/register_gymies_rate_limit_middleware.php
 */

$middlewareClass = 'App\\Http\\Middleware\\GymiesRateLimitMiddleware';
$alias = 'gymies.rate.limit';
$newLine = "        '{$alias}' => \\{$middlewareClass}::class,\n";

// --- Poging 1: bootstrap/app.php (Laravel 11+) ---
$bootstrapPath = __DIR__ . '/../bootstrap/app.php';
if (file_exists($bootstrapPath)) {
    $content = file_get_contents($bootstrapPath);

    if (strpos($content, $alias) !== false) {
        echo "bootstrap/app.php: {$alias} al geregistreerd — overgeslagen.\n";
    } elseif (strpos($content, 'gymies.auth') !== false) {
        // Voeg toe direct na gymies.auth registratie
        $content = str_replace(
            "'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,",
            "'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,\n{$newLine}",
            $content
        );
        file_put_contents($bootstrapPath, $content);

        if (strpos($content, $alias) !== false) {
            echo "bootstrap/app.php: {$alias} geregistreerd.\n";
        } else {
            echo "bootstrap/app.php: kon {$alias} niet automatisch toevoegen.\n";
            echo "Voeg handmatig toe in withMiddleware(aliases: [...]):\n";
            echo "  '{$alias}' => \\{$middlewareClass}::class,\n";
        }
    } else {
        echo "bootstrap/app.php: gymies.auth niet gevonden als ankerpunt.\n";
        echo "Voeg handmatig toe in withMiddleware(aliases: [...]):\n";
        echo "  '{$alias}' => \\{$middlewareClass}::class,\n";
    }
}

// --- Poging 2: Kernel.php (Laravel 10) ---
$kernelPath = __DIR__ . '/../app/Http/Kernel.php';
if (file_exists($kernelPath)) {
    $content = file_get_contents($kernelPath);

    if (strpos($content, $alias) !== false) {
        echo "Kernel.php: {$alias} al geregistreerd — overgeslagen.\n";
    } elseif (strpos($content, '$middlewareAliases') !== false || strpos($content, '$routeMiddleware') !== false) {
        if (strpos($content, 'gymies.auth') !== false) {
            $content = str_replace(
                "'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,",
                "'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,\n{$newLine}",
                $content
            );
        } else {
            // Probeer na laatste entry in $middlewareAliases
            $content = preg_replace(
                '/(\$middlewareAliases\s*=\s*\[.*?)(\n\s*\];)/s',
                "$1\n{$newLine}$2",
                $content,
                1
            );
        }
        file_put_contents($kernelPath, $content);

        if (strpos(file_get_contents($kernelPath), $alias) !== false) {
            echo "Kernel.php: {$alias} geregistreerd.\n";
        } else {
            echo "Kernel.php: kon {$alias} niet toevoegen. Voeg handmatig toe:\n";
            echo "  '{$alias}' => \\{$middlewareClass}::class,\n";
        }
    } else {
        echo "Kernel.php: geen \$middlewareAliases of \$routeMiddleware gevonden.\n";
        echo "Voeg handmatig toe:\n";
        echo "  '{$alias}' => \\{$middlewareClass}::class,\n";
    }
}

if (!file_exists($bootstrapPath) && !file_exists($kernelPath)) {
    echo "Geen bootstrap/app.php of Kernel.php gevonden.\n";
    echo "Registreer handmatig:\n";
    echo "  '{$alias}' => \\{$middlewareClass}::class,\n";
}

echo "\nDone. Test met: php artisan route:list --name=trainers.index\n";
