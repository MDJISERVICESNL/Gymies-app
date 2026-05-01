<?php
/**
 * Controleer of Gymies auth correct is geconfigureerd.
 * Gebruik: php verify_gymies_auth.php [laravel_root]
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');

echo "=== Gymies auth verificatie ===\n";
echo "Laravel root: $base\n\n";

$ok = true;

// 1. Middleware bestanden
$middlewareDir = $base . '/app/Http/Middleware';
$preempt = $middlewareDir . '/EnsureGymiesAuthPreempt.php';
$token = $middlewareDir . '/EnsureGymiesUserFromToken.php';
if (!is_file($preempt)) {
    echo "FOUT: EnsureGymiesAuthPreempt.php niet gevonden in app/Http/Middleware/\n";
    $ok = false;
} else {
    echo "OK: EnsureGymiesAuthPreempt.php aanwezig\n";
}
if (!is_file($token)) {
    echo "FOUT: EnsureGymiesUserFromToken.php niet gevonden in app/Http/Middleware/\n";
    $ok = false;
} else {
    echo "OK: EnsureGymiesUserFromToken.php aanwezig\n";
}

// 2. Tabellen
require $base . '/vendor/autoload.php';
$app = require_once $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

if (\Illuminate\Support\Facades\Schema::hasTable('gymies_users')) {
    echo "OK: gymies_users tabel bestaat\n";
} else {
    echo "WAARSCHUWING: gymies_users niet gevonden (fallback naar users)\n";
}

if (\Illuminate\Support\Facades\Schema::hasTable('gymies_personal_access_tokens')) {
    $count = \Illuminate\Support\Facades\DB::table('gymies_personal_access_tokens')->count();
    echo "OK: gymies_personal_access_tokens bestaat ($count tokens)\n";
} elseif (\Illuminate\Support\Facades\Schema::hasTable('personal_access_tokens')) {
    echo "OK: personal_access_tokens bestaat (gymies_personal_access_tokens niet)\n";
} else {
    echo "FOUT: Geen token-tabel. Run: php artisan migrate\n";
    $ok = false;
}

// 3. Authorization header (.htaccess)
$htaccess = $base . '/public/.htaccess';
if (is_file($htaccess)) {
    $content = file_get_contents($htaccess);
    if (strpos($content, 'HTTP_AUTHORIZATION') !== false) {
        echo "OK: Authorization-header in .htaccess\n";
    } else {
        echo "WAARSCHUWING: Authorization-header ontbreekt in .htaccess\n";
        echo "  Run: php scripts/patch_apache_authorization_header.php .\n";
    }
}

echo "\n";
if ($ok) {
    echo "=== Configuratie OK. Test login in de app.\n";
} else {
    echo "=== Los de bovenstaande fouten op.\n";
    exit(1);
}
