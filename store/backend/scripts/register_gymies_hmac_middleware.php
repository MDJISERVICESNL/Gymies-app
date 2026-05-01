<?php
/**
 * Registreer GymiesHmacMiddleware als gymies.hmac middleware.
 *
 * Ondersteunt:
 * - Laravel 11+ (bootstrap/app.php → withMiddleware)
 * - Laravel 10  (app/Http/Kernel.php → $middlewareAliases)
 *
 * Draai: php scripts/register_gymies_hmac_middleware.php
 */

$middlewareClass = 'App\\Http\\Middleware\\GymiesHmacMiddleware';
$newLine = "        'gymies.hmac' => \\{$middlewareClass}::class,\n";
$basePath = dirname(__DIR__);

// ── Laravel 11+ (bootstrap/app.php) ─────────────────────────────
$appFile = $basePath . '/bootstrap/app.php';
if (file_exists($appFile)) {
    $content = file_get_contents($appFile);
    if (strpos($content, 'gymies.hmac') !== false) {
        echo "bootstrap/app.php: gymies.hmac al geregistreerd — overgeslagen.\n";
    } elseif (strpos($content, 'gymies.auth') !== false) {
        // Voeg toe direct na gymies.auth registratie
        $content = str_replace(
            "'gymies.auth' => \\{$middlewareClass}::class,",
            "'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,\n{$newLine}",
            $content
        );

        // Alternatief: voeg toe na de laatst bekende gymies middleware
        if (strpos($content, 'gymies.hmac') === false) {
            // Zoek het patroon: 'gymies.xxx' => \...,  en voeg erna toe
            $pattern = "/([\t ]*'gymies\.[^']+'\s*=>\s*\\\\[^,]+,)/";
            if (preg_match_all($pattern, $content, $matches, PREG_OFFSET_CAPTURE)) {
                $lastMatch = end($matches[0]);
                $insertPos = $lastMatch[1] + strlen($lastMatch[0]);
                $content = substr_replace($content, "\n{$newLine}", $insertPos, 0);
            }
        }

        if (strpos($content, 'gymies.hmac') !== false) {
            file_put_contents($appFile, $content);
            echo "bootstrap/app.php: gymies.hmac geregistreerd.\n";
        } else {
            echo "bootstrap/app.php: kon gymies.hmac niet automatisch toevoegen.\n";
            echo "Voeg handmatig toe in withMiddleware(aliases: [...]):\n";
            echo "  'gymies.hmac' => \\{$middlewareClass}::class,\n";
        }
    } else {
        echo "bootstrap/app.php: geen bestaande gymies middleware gevonden.\n";
        echo "Voeg handmatig toe in withMiddleware(aliases: [...]):\n";
        echo "  'gymies.hmac' => \\{$middlewareClass}::class,\n";
    }
}

// ── Laravel 10 (Kernel.php) ────────────────────────────────────
$kernelFile = $basePath . '/app/Http/Kernel.php';
if (file_exists($kernelFile)) {
    $content = file_get_contents($kernelFile);
    if (strpos($content, 'gymies.hmac') !== false) {
        echo "Kernel.php: gymies.hmac al geregistreerd — overgeslagen.\n";
    } elseif (strpos($content, '$middlewareAliases') !== false || strpos($content, '$routeMiddleware') !== false) {
        // Voeg toe na gymies.auth als die bestaat
        if (strpos($content, 'gymies.auth') !== false) {
            $pattern = "/([\t ]*'gymies\.auth'\s*=>\s*\\\\[^,]+,)/";
            if (preg_match($pattern, $content, $matches, PREG_OFFSET_CAPTURE)) {
                $insertPos = $matches[0][1] + strlen($matches[0][0]);
                $content = substr_replace($content, "\n{$newLine}", $insertPos, 0);
            }
        } else {
            // Voeg toe aan het einde van de array
            $content = preg_replace(
                '/(\$middlewareAliases\s*=\s*\[)(.*?)(\];)/s',
                "$1$2{$newLine}$3",
                $content
            );
        }

        if (strpos($content, 'gymies.hmac') !== false) {
            file_put_contents($kernelFile, $content);
            echo "Kernel.php: gymies.hmac geregistreerd.\n";
        } else {
            echo "Kernel.php: kon gymies.hmac niet toevoegen. Voeg handmatig toe:\n";
            echo "  'gymies.hmac' => \\{$middlewareClass}::class,\n";
        }
    }
}

echo "\nKlaar. Vergeet niet:\n";
echo "  1. GYMIES_HMAC_SECRET=<jouw-secret> in .env\n";
echo "  2. php artisan config:cache\n";
echo "  3. Zelfde secret als Flutter --dart-define=GYMIES_HMAC_SECRET=<secret>\n";
