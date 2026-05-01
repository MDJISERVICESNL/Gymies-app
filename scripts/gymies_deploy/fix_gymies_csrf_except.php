#!/usr/bin/env php
<?php
/**
 * Zorg dat POST naar api/gymies/* niet door CSRF blokkeert (419 Page Expired).
 * Flutter web stuurt geen X-CSRF-TOKEN mee — uitzondering is nodig.
 *
 * Run op server vanuit Laravel-root:
 *   php gymies_deploy/fix_gymies_csrf_except.php
 * Of met sudo als bestand eigenaar www-data is.
 */
declare(strict_types=1);

$root = isset($argv[1]) && $argv[1] !== '' ? $argv[1] : getcwd();
$candidates = [
    $root . '/app/Http/Middleware/VerifyCsrfToken.php',
    $root . '/app/Http/Middleware/ValidateCsrfToken.php',
];

$file = null;
foreach ($candidates as $c) {
    if (is_file($c)) {
        $file = $c;
        break;
    }
}

if ($file === null) {
    fwrite(STDERR, "Geen VerifyCsrfToken/ValidateCsrfToken gevonden. Voeg handmatig toe aan \$except:\n");
    fwrite(STDERR, "  'api/gymies/*'\n");
    exit(1);
}

$content = file_get_contents($file);
if ($content === false) {
    fwrite(STDERR, "Kan bestand niet lezen: $file\n");
    exit(1);
}

if (preg_match("/['\"]api\\/gymies\\/\\*['\"]/", $content) ||
    strpos($content, 'api/gymies/*') !== false) {
    echo "[OK] api/gymies/* staat al in CSRF-uitzondering ($file).\n";
    exit(0);
}

// Zoek protected $except = [ ... ];
if (!preg_match('/protected\s+\$except\s*=\s*\[/', $content, $m, PREG_OFFSET_CAPTURE)) {
    fwrite(STDERR, "Kon \$except-array niet vinden in $file. Voeg handmatig toe: 'api/gymies/*'\n");
    exit(1);
}

$insert = "\n        'api/gymies/*',";
// Voeg toe direct na de openingshaak van $except
$newContent = preg_replace(
    '/(protected\s+\$except\s*=\s*\[)/',
    '$1' . $insert,
    $content,
    1
);

if ($newContent === $content) {
    fwrite(STDERR, "Patch mislukt. Voeg handmatig toe aan \$except in $file\n");
    exit(1);
}

$bak = $file . '.bak_gymies_csrf_' . date('Ymd_His');
if (!copy($file, $bak)) {
    fwrite(STDERR, "Backup mislukt. Abort.\n");
    exit(1);
}

if (file_put_contents($file, $newContent) === false) {
    fwrite(STDERR, "Schrijven mislukt. Herstel van $bak indien nodig.\n");
    exit(1);
}

echo "[OK] api/gymies/* toegevoegd aan CSRF-uitzondering.\n";
echo "     Bestand: $file (backup: $bak)\n";
echo "     Daarna: php artisan config:clear && php artisan route:clear\n";
exit(0);
