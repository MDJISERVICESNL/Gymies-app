#!/usr/bin/env php
<?php
/**
 * Op de SERVER draaien vanuit de Laravel-root (waar .env staat).
 * Controleert of gymies_users.trainer_balance_cents bestaat.
 * Gebruik: ssh gymies "cd /var/www/gymies && php /tmp/check_trainer_balance_column_server.php"
 * Of na upload: cd /var/www/gymies && php scripts/check_trainer_balance_column_server.php
 */
declare(strict_types=1);

function envMap(string $path): array
{
    $map = [];
    if (!is_file($path)) {
        return $map;
    }
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) {
            continue;
        }
        [$k, $v] = explode('=', $line, 2);
        $map[trim($k)] = trim($v, "\"' \n\r\t");
    }
    return $map;
}

$envPath = getcwd() . '/.env';
$env = envMap($envPath);
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($env['DB_PORT'] ?? 3306);
$db = $env['DB_DATABASE'] ?? '';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';

if ($db === '' || $user === '') {
    fwrite(STDERR, "DB_DATABASE of DB_USERNAME ontbreekt in .env. Run vanuit Laravel-root (bijv. /var/www/gymies).\n");
    exit(1);
}

$dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
try {
    $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Throwable $e) {
    fwrite(STDERR, "DB connect failed: " . $e->getMessage() . "\n");
    exit(1);
}

$stmt = $pdo->query("SHOW COLUMNS FROM gymies_users LIKE 'trainer_balance_cents'");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

if ($rows === []) {
    echo "Kolom trainer_balance_cents bestaat NIET in gymies_users.\n";
    exit(1);
}

echo "Kolom trainer_balance_cents bestaat:\n";
print_r($rows);
exit(0);
