#!/usr/bin/env php
<?php
/**
 * Forceer dat api/gymies/* (auth/verify-email, login, register, …) altijd uit
 * gymies_deploy/routes_gymies_full.php komt. Lost "could not be found" op als
 * web.php een verkeerde require heeft of routes/gymies.php ontbreekt op de server.
 *
 * Run op server vanuit Laravel-root:
 *   cd /var/www/gymies
 *   php gymies_deploy/fix_gymies_web_routes_force.php
 *   php artisan route:clear
 *
 * Bij Permission denied op routes/:
 *   Het script schrijft dan naar ~/gymies_web_ROUTES_PATCH.php — daarna:
 *   sudo cp ~/gymies_web_ROUTES_PATCH.php routes/web.php && sudo chown www-data:www-data routes/web.php
 *   Of: sudo php gymies_deploy/fix_gymies_web_routes_force.php
 */
declare(strict_types=1);

$laravelRoot = isset($argv[1]) && $argv[1] !== '' ? rtrim($argv[1], '/') : getcwd();
$webPath = $laravelRoot . '/routes/web.php';
$fullFile = $laravelRoot . '/gymies_deploy/routes_gymies_full.php';

if (!is_file($webPath)) {
    fwrite(STDERR, "Niet gevonden: $webPath\n");
    exit(1);
}
if (!is_file($fullFile)) {
    fwrite(STDERR, "Niet gevonden: $fullFile — eerst ./scripts/upload_backend.sh\n");
    exit(1);
}

// Vanuit routes/web.php moet het pad ÉÉN niveau omhoog naar gymies_deploy/
$requireLine = "require __DIR__ . '/../gymies_deploy/routes_gymies_full.php';";
$marker = '// Gymies API — geladen via gymies_deploy (fix_gymies_web_routes_force)';

$content = file_get_contents($webPath);
if ($content === false) {
    fwrite(STDERR, "Kan web.php niet lezen.\n");
    exit(1);
}

// Al correct aanwezig?
if (strpos($content, "gymies_deploy/routes_gymies_full.php") !== false &&
    strpos($content, "/../gymies_deploy/routes_gymies_full.php") !== false) {
    echo "[OK] web.php bevat al require naar ../gymies_deploy/routes_gymies_full.php\n";
    doClear($laravelRoot);
    exit(0);
}

$lines = preg_split('/\r\n|\r|\n/', $content);
$out = [];
$skipUntilSemicolon = false;
foreach ($lines as $line) {
    $trim = trim($line);
    // Verwijder oude/broken gymies requires (voorkomt dubbele prefix of verkeerd pad)
    if (preg_match('/require\s+__DIR__\s*\.\s*[\'\"].*gymies/i', $line) ||
        preg_match('/require\s+.*routes_gymies/i', $line) ||
        preg_match('/require\s+.*gymies\.php/i', $line)) {
        continue;
    }
    if ($trim === $marker) {
        continue;
    }
    $out[] = $line;
}

// Geen dubbele lege regels aan het eind
while (count($out) > 0 && trim($out[count($out) - 1]) === '') {
    array_pop($out);
}

$out[] = '';
$out[] = $marker;
$out[] = $requireLine;
$out[] = '';

$newContent = implode("\n", $out);
$backup = $webPath . '.bak_force_' . date('Ymd_His');
$home = getenv('HOME') ?: '/tmp';
$backupHome = $home . '/gymies_web_backup_' . date('Ymd_His') . '.php';
$patchFile = $home . '/gymies_web_ROUTES_PATCH.php';

// Backup: eerst naast web.php; bij Permission denied naar home
if (!@copy($webPath, $backup)) {
    if (@file_put_contents($backupHome, $content) !== false) {
        echo "[INFO] Backup in routes/ mislukt (Permission denied) — backup staat in: $backupHome\n";
    } else {
        fwrite(STDERR, "Backup mislukt (geen rechten op routes/ en niet naar $backupHome te schrijven).\n");
    }
}

if (@file_put_contents($webPath, $newContent) !== false) {
    if (is_file($backup)) {
        echo "[OK] routes/web.php bijgewerkt (backup: $backup)\n";
    } else {
        echo "[OK] routes/web.php bijgewerkt (backup was naar home geschreven indien nodig)\n";
    }
} else {
    // Geen schrijfrecht op routes/web.php → patch naar home + instructies
    if (file_put_contents($patchFile, $newContent) === false) {
        fwrite(STDERR, "Kan ook niet naar $patchFile schrijven.\n");
        exit(1);
    }
    echo "\n--- Geen schrijfrecht op routes/web.php ---\n";
    echo "Patch geschreven naar:\n  $patchFile\n\n";
    echo "Voer uit (vanuit $laravelRoot):\n";
    echo "  sudo cp $patchFile routes/web.php\n";
    echo "  sudo chown www-data:www-data routes/web.php\n";
    echo "  php artisan route:clear\n\n";
    exit(2);
}
echo "     Toegevoegd: $requireLine\n";
doClear($laravelRoot);
echo "Test: curl -s -o /dev/null -w '%{http_code}' -X POST $laravelRoot/../  # of curl naar https://gymies.nl/api/gymies/auth/verify-email\n";
exit(0);

function doClear(string $laravelRoot): void
{
    $artisan = $laravelRoot . '/artisan';
    if (is_file($artisan)) {
        @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan route:clear 2>/dev/null');
        @exec('cd ' . escapeshellarg($laravelRoot) . ' && php artisan config:clear 2>/dev/null');
        echo "[OK] route:clear + config:clear\n";
    }
}
