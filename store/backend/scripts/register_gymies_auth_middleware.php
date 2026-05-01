<?php
/**
 * Registreer GymiesAuthMiddleware als gymies.auth middleware (zoekt tokens in gymies_sessions).
 * Gebruik: php register_gymies_auth_middleware.php [laravel_root]
 *
 * Ondersteunt Laravel 10 (Kernel.php) en Laravel 11+ (bootstrap/app.php).
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');

$middlewareClass = 'App\\Http\\Middleware\\GymiesAuthMiddleware';
$preemptClass = 'App\\Http\\Middleware\\EnsureGymiesAuthPreempt';
$newLine = "        'gymies.auth' => \\{$middlewareClass}::class,\n";
$preemptLine = "        'gymies.auth.preempt' => \\{$preemptClass}::class,\n";

// Laravel 10: app/Http/Kernel.php
$kernelPath = $base . '/app/Http/Kernel.php';
if (file_exists($kernelPath)) {
    $content = file_get_contents($kernelPath);
    if (strpos($content, 'gymies.auth') !== false) {
        $content = preg_replace(
            "/'gymies\.auth'\s*=>\s*[^\n]+/",
            "'gymies.auth' => \\{$middlewareClass}::class,",
            $content
        );
    } else {
        // Voeg toe voor de sluitende ]; van $middlewareAliases
        $content = preg_replace(
            '/(\$middlewareAliases\s*=\s*\[[^\]]*?)(\n\s*\];)/s',
            '$1' . "\n" . $newLine . '    $2',
            $content,
            1
        );
        if (strpos($content, 'gymies.auth') === false) {
            $content = preg_replace(
                '/(\$routeMiddleware\s*=\s*\[[^\]]*?)(\n\s*\];)/s',
                '$1' . "\n" . $newLine . '    $2',
                $content,
                1
            );
        }
    }
    if (strpos($content, 'gymies.auth') === false) {
        echo "Kernel.php: kon gymies.auth niet toevoegen. Voeg handmatig toe.\n";
        exit(1);
    }
    file_put_contents($kernelPath, $content);
    echo "Kernel.php: gymies.auth geregistreerd.\n";
    exit(0);
}

// Laravel 11+: bootstrap/app.php
$bootstrapPath = $base . '/bootstrap/app.php';
if (file_exists($bootstrapPath)) {
    $content = file_get_contents($bootstrapPath);
    if (strpos($content, 'gymies.auth') !== false) {
        $content = preg_replace(
            "/'gymies\.auth'\s*=>\s*[^\n]+/",
            "'gymies.auth' => \\{$middlewareClass}::class,",
            $content
        );
    } else {
        $content = preg_replace(
            '/(->alias\s*\(\s*\[)([^\]]*?)(\n\s*\]\s*\))/s',
            '$1$2' . "\n" . $newLine . $preemptLine . '    $3',
            $content,
            1
        );
    }
    if (strpos($content, 'gymies.auth.preempt') === false) {
        $content = preg_replace(
            '/(\'gymies\.auth\'\s*=>[^\n]+\n)/',
            '$1' . $preemptLine,
            $content,
            1
        );
    }
    if (strpos($content, 'gymies.auth') === false) {
        echo "bootstrap/app.php: kon gymies.auth niet toevoegen.\n";
        echo "Voeg handmatig toe in withMiddleware:\n";
        echo "  'gymies.auth' => \\{$middlewareClass}::class,\n";
        exit(1);
    }
    if (@file_put_contents($bootstrapPath, $content) === false) {
        echo "FOUT: Geen schrijfrechten op bootstrap/app.php. Run met sudo:\n";
        echo "  sudo php scripts/register_gymies_auth_middleware.php .\n";
        echo "\nOf voeg handmatig toe in ->alias([...]):\n";
        echo "  'gymies.auth' => \\{$middlewareClass}::class,\n";
        echo "  'gymies.auth.preempt' => \\{$preemptClass}::class,\n";
        exit(1);
    }
    echo "bootstrap/app.php: gymies.auth geregistreerd.\n";
    exit(0);
}

echo "Geen Kernel.php of bootstrap/app.php gevonden in {$base}\n";
exit(1);
