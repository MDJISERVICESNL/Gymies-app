#!/usr/bin/env php
<?php
/**
 * Op de SERVER uitvoeren vanuit Laravel-root.
 * Verwijdert dummy-adminrechten en zet het opgegeven account als enige admin (met wachtwoord).
 *
 * Gebruik:
 *   scp scripts/set_admin_account_server.php gymies:/tmp/
 *   ssh gymies "cd /var/www/gymies && php /tmp/set_admin_account_server.php noreply@gymies.nl 'jouw-wachtwoord'"
 *
 * Dit zet is_admin=0 voor admin@trainmate.app en trainer.anne@example.com,
 * en maakt/werkt bij het opgegeven e-mailadres met is_admin=1 en het gegeven wachtwoord.
 */
declare(strict_types=1);

$email = $argv[1] ?? '';
$password = $argv[2] ?? '';

if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage: php set_admin_account_server.php <email> <password>\n");
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

$dummyAdmins = ['admin@trainmate.app', 'trainer.anne@example.com'];

// Dummy-admins: is_admin = 0
$stmt = $pdo->prepare("UPDATE gymies_users SET is_admin = 0 WHERE email = ?");
foreach ($dummyAdmins as $dummy) {
    $stmt->execute([$dummy]);
    if ($stmt->rowCount() > 0) {
        echo "Adminrechten verwijderd voor: {$dummy}\n";
    }
}

$passwordHash = password_hash($password, PASSWORD_BCRYPT);
if ($passwordHash === false) {
    fwrite(STDERR, "Kon wachtwoord niet hashen.\n");
    exit(1);
}

// Bestaande user ophalen
$stmt = $pdo->prepare("SELECT id, email FROM gymies_users WHERE email = ? LIMIT 1");
$stmt->execute([$email]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if ($row) {
    $stmt = $pdo->prepare("UPDATE gymies_users SET password_hash = ?, is_admin = 1, updated_at = NOW() WHERE id = ?");
    $stmt->execute([$passwordHash, (int) $row['id']]);
    echo "Account bijgewerkt en als admin ingesteld: {$email}\n";
} else {
    $stmt = $pdo->prepare("
        INSERT INTO gymies_users (email, password_hash, role, display_name, is_admin, created_at, updated_at)
        VALUES (?, ?, 'klant', ?, 1, NOW(), NOW())
    ");
    $displayName = explode('@', $email)[0];
    $stmt->execute([$email, $passwordHash, $displayName]);
    echo "Nieuw admin-account aangemaakt: {$email}\n";
}

echo "Klaar. Log in op de vault-console met dit account.\n";
