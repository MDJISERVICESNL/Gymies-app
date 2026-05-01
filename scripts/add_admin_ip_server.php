#!/usr/bin/env php
<?php
/**
 * Voer uit op de SERVER vanuit Laravel-root. Voegt één IP toe aan gymies_admin_ip_allowlist.
 * Gebruik: scp scripts/add_admin_ip_server.php gymies:/tmp/ && ssh gymies "cd /var/www/gymies && php /tmp/add_admin_ip_server.php <IP>"
 */
declare(strict_types=1);

$ip = $argv[1] ?? '';
if ($ip === '' || !filter_var($ip, FILTER_VALIDATE_IP)) {
    fwrite(STDERR, "Usage: php add_admin_ip_server.php <IPv4>\n");
    exit(1);
}

$envPath = getcwd() . '/.env';
if (!is_file($envPath)) {
    fwrite(STDERR, ".env niet gevonden. Run vanuit Laravel-root (bijv. /var/www/gymies.nl/laravel).\n");
    exit(1);
}

$map = [];
foreach (file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
    $line = trim($line);
    if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) {
        continue;
    }
    [$k, $v] = explode('=', $line, 2);
    $map[trim($k)] = trim($v, "\"' \n\r\t");
}

$host = $map['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($map['DB_PORT'] ?? 3306);
$db   = $map['DB_DATABASE'] ?? '';
$user = $map['DB_USERNAME'] ?? '';
$pass = $map['DB_PASSWORD'] ?? '';

if ($db === '' || $user === '') {
    fwrite(STDERR, "DB_DATABASE of DB_USERNAME ontbreekt in .env.\n");
    exit(1);
}

$dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
try {
    $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Throwable $e) {
    fwrite(STDERR, "DB connect failed: " . $e->getMessage() . "\n");
    exit(1);
}

$stmt = $pdo->prepare("INSERT INTO gymies_admin_ip_allowlist (ip_pattern, status, created_at, updated_at) VALUES (?, 'active', NOW(), NOW())");
$stmt->execute([$ip]);

echo "IP {$ip} toegevoegd aan gymies_admin_ip_allowlist.\n";
