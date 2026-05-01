#!/usr/bin/env php
<?php
/**
 * Maakt een backup (DB dump + app tar) op de server in /tmp (voor lokaal ophalen).
 * Voer uit IN de Laravel-root:
 *   cd /var/www/mdjiservices.nl/laravel && php /path/to/run_backup_server.php
 * Output: één regel met het pad naar de backup-map (bijv. /tmp/trainmaat_backup_20250228_123456).
 */
declare(strict_types=1);

$laravelRoot = getenv('LARAVEL_ROOT');
if (!$laravelRoot) {
    if (is_file(getcwd() . '/vendor/autoload.php')) {
        $laravelRoot = getcwd();
    } elseif (is_dir(__DIR__ . '/../vendor') && is_file(__DIR__ . '/../vendor/autoload.php')) {
        $laravelRoot = realpath(__DIR__ . '/..');
    } else {
        $laravelRoot = '/var/www/mdjiservices.nl/laravel';
    }
}
if (!is_file($laravelRoot . '/vendor/autoload.php')) {
    fwrite(STDERR, "Laravel root niet gevonden. Zet LARAVEL_ROOT of run vanuit Laravel-root.\n");
    exit(1);
}

require $laravelRoot . '/vendor/autoload.php';
$app = require_once $laravelRoot . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$stamp = date('Ymd_His');
$backupDir = '/tmp/trainmaat_backup_' . $stamp;
if (!mkdir($backupDir, 0755, true) && !is_dir($backupDir)) {
    fwrite(STDERR, "Kon map niet aanmaken: {$backupDir}\n");
    exit(1);
}

$db = config('database.connections.mysql');
$dbHost = $db['host'] ?? '127.0.0.1';
$dbPort = $db['port'] ?? 3306;
$dbUser = $db['username'] ?? '';
$dbPass = $db['password'] ?? '';
$dbName = $db['database'] ?? '';

$dbFile = $backupDir . '/db.sql';
$mysqldump = 'mysqldump';
$cmd = [
    $mysqldump,
    '-h', $dbHost,
    '-P', (string) $dbPort,
    '-u', $dbUser,
    '--single-transaction',
    '--quick',
    '--lock-tables=false',
    $dbName,
];
$proc = proc_open(
    $cmd,
    [
        0 => ['pipe', 'r'],
        1 => ['file', $dbFile, 'w'],
        2 => ['pipe', 'w'],
    ],
    $pipes,
    null,
    ['MYSQL_PWD' => $dbPass]
);
if (!is_resource($proc)) {
    fwrite(STDERR, "mysqldump kon niet gestart worden.\n");
    exit(1);
}
fclose($pipes[0]);
$stderr = stream_get_contents($pipes[2]);
fclose($pipes[2]);
$code = proc_close($proc);
if ($code !== 0) {
    fwrite(STDERR, "mysqldump mislukt (code {$code}): {$stderr}\n");
    @unlink($dbFile);
    @rmdir($backupDir);
    exit(1);
}

$appTar = $backupDir . '/app.tar.gz';
$laravelParent = dirname($laravelRoot);
$laravelDirName = basename($laravelRoot);
$tarCmd = sprintf(
    'tar -czf %s -C %s %s',
    escapeshellarg($appTar),
    escapeshellarg($laravelParent),
    escapeshellarg($laravelDirName)
);
exec($tarCmd . ' 2>&1', $tarOut, $tarCode);
if ($tarCode !== 0) {
    fwrite(STDERR, "tar mislukt: " . implode("\n", $tarOut) . "\n");
    @unlink($dbFile);
    @unlink($appTar);
    @rmdir($backupDir);
    exit(1);
}

echo $backupDir . "\n";
