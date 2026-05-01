<?php

declare(strict_types=1);

if ($argc < 2) {
    fwrite(STDERR, "Usage: php reset_admin_password_remote.php <new_password>\n");
    exit(1);
}

$newPassword = (string) $argv[1];
$email = 'admin@gymies.nl';

$dsn = 'mysql:host=127.0.0.1;port=3306;dbname=gymies;charset=utf8mb4';
$user = 'gymies_user';
$pass = 'M8cgIja8kH6OcyzQpBYJ';

$pdo = new PDO($dsn, $user, $pass, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);

$hash = password_hash($newPassword, PASSWORD_BCRYPT);

$stmt = $pdo->prepare('UPDATE gymies_users SET password_hash = :hash, updated_at = NOW() WHERE email = :email');
$stmt->execute([
    ':hash' => $hash,
    ':email' => $email,
]);

$verify = $pdo->prepare('SELECT id, email, password_hash, LENGTH(password_hash) AS hash_len FROM gymies_users WHERE email = :email LIMIT 1');
$verify->execute([':email' => $email]);
$row = $verify->fetch();

if (!is_array($row)) {
    fwrite(STDERR, "Admin user not found.\n");
    exit(2);
}

echo json_encode($row, JSON_UNESCAPED_SLASHES) . PHP_EOL;

