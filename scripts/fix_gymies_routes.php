<?php
/**
 * Zorg dat Laravel web.php de Gymies API-routes laadt (o.a. api/gymies/support/tickets).
 * Run op de server vanuit Laravel root: php gymies_deploy/fix_gymies_routes.php
 * Of: php fix_gymies_routes.php /var/www/gymies.nl/laravel
 */
$laravelRoot = isset($argv[1]) && $argv[1] !== '' ? $argv[1] : getcwd();
$webPath = $laravelRoot . '/routes/web.php';
$gymiesFullPath = $laravelRoot . '/gymies_deploy/routes_gymies_full.php';

if (!is_file($webPath)) {
    fwrite(STDERR, "routes/web.php niet gevonden. Run vanuit Laravel root of geef pad op.\n");
    exit(1);
}

if (!is_file($gymiesFullPath)) {
    fwrite(STDERR, "gymies_deploy/routes_gymies_full.php niet gevonden. Run eerst upload_backend.sh.\n");
    exit(1);
}

$content = file_get_contents($webPath);
$needle = 'gymies_deploy/routes_gymies_full';
$needle2 = "require __DIR__ . '/gymies_deploy/routes_gymies_snippet";
$hasTrainmaat = (strpos($content, $needle) !== false) || (strpos($content, $needle2) !== false)
    || (preg_match('/require\s+.*routes_gymies_full\.php/', $content));

if ($hasTrainmaat) {
    if (strpos($content, "/../gymies_deploy/routes_gymies_full.php") === false) {
        fwrite(STDERR, "Let op: web.php laadt gymies mogelijk met verkeerd pad (geen ../gymies_deploy).\n");
        fwrite(STDERR, "  Run: php gymies_deploy/fix_gymies_web_routes_force.php\n");
    }
    echo "[OK] Gymies routes staan al in web.php.\n";
    doClear($laravelRoot);
    exit(0);
}

// Vanuit routes/web.php is __DIR__ = routes/ , dus één niveau omhoog naar Laravel root
$line = "\n// Gymies API (api/gymies, support/tickets, etc.)\nrequire __DIR__ . '/../gymies_deploy/routes_gymies_full.php';\n";
$backup = $webPath . '.bak_gymies_' . date('Ymd_His');

if (!@copy($webPath, $backup) || @file_put_contents($webPath, $content . $line) === false) {
    fwrite(STDERR, "Geen schrijfrechten op routes/web.php. Run met sudo:\n");
    fwrite(STDERR, "  sudo php gymies_deploy/fix_gymies_routes.php\n\n");
    fwrite(STDERR, "Of voeg handmatig onderaan routes/web.php toe:\n");
    fwrite(STDERR, "  require __DIR__ . '/../gymies_deploy/routes_gymies_full.php';\n");
    exit(1);
}

echo "[OK] Gymies routes toegevoegd aan routes/web.php (backup: $backup).\n";

doClear($laravelRoot);
echo "Klaar. Test: https://jouw-domein.nl/api/gymies/me (na inloggen) of support/tickets.\n";

function doClear(string $laravelRoot): void
{
    $artisan = $laravelRoot . '/artisan';
    if (is_file($artisan)) {
        @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan route:clear 2>/dev/null');
        @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan config:clear 2>/dev/null');
        echo "[OK] Route en config cache geleegd.\n";
    }
}
