#!/usr/bin/env php
<?php
/**
 * Op de SERVER uitvoeren vanuit Laravel-root.
 * Wijzigt alleen het wachtwoord van een bestaand account; verandert GEEN rol of admin-rechten.
 *
 * Gebruik:
 *   scp scripts/set_user_password_server.php gymies:/tmp/
 *   ssh gymies "cd /var/www/gymies && sudo -u www-data php /tmp/set_user_password_server.php imcrz3147@gmail.com 'Demo123'"
 */
declare(strict_types=1);

$email = $argv[1] ?? '';
$password = $argv[2] ?? '';

if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage: php set_user_password_server.php <email> <password>\n");
    exit(1);
}
if ($password === '') {
    fwrite(STDERR, "Geef een wachtwoord op als tweede argument.\n");
    exit(1);
}

$envPath = getcwd() . '/.env';
if (!is_file($envPath)) {
    fwrite(STDERR, ".env niet gevonden. Run vanuit Laravel-root (bijv. /var/www/gymies).\n");
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

$passwordHash = password_hash($password, PASSWORD_BCRYPT);
if ($passwordHash === false) {
    fwrite(STDERR, "Kon wachtwoord niet hashen.\n");
    exit(1);
}

$stmt = $pdo->prepare("SELECT id, email, role FROM gymies_users WHERE email = ? LIMIT 1");
$stmt->execute([$email]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    fwrite(STDERR, "Account niet gevonden: {$email}\n");
    exit(1);
}

$stmt = $pdo->prepare("UPDATE gymies_users SET password_hash = ?, updated_at = NOW() WHERE id = ?");
$stmt->execute([$passwordHash, (int) $row['id']]);

echo "Wachtwoord gezet voor {$email} (role: {$row['role']}). Geen admin-rechten gewijzigd.\n";
