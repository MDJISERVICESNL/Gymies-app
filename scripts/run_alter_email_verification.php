#!/usr/bin/env php
<?php
declare(strict_types=1);
$envPath = $argv[1] ?? getcwd() . '/.env';
if (!is_file($envPath)) {
    fwrite(STDERR, "Usage: php run_alter_email_verification.php [path-to-.env]\n");
    exit(1);
}
$env = [];
foreach (file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
    $line = trim($line);
    if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) continue;
    [$k, $v] = explode('=', $line, 2);
    $env[trim($k)] = trim($v, " \t\n\r\"'");
}
$dsn = 'mysql:host=' . ($env['DB_HOST'] ?? '127.0.0.1') . ';dbname=' . ($env['DB_DATABASE'] ?? '') . ';charset=utf8mb4';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';
if ($user === '' || ($env['DB_DATABASE'] ?? '') === '') {
    fwrite(STDERR, "DB_DATABASE and DB_USERNAME required in .env\n");
    exit(1);
}
try {
    $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}
$sql = "CREATE TABLE IF NOT EXISTS gymies_email_verification_codes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    code VARCHAR(10) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY gymies_email_verification_user (user_id),
    KEY gymies_email_verification_expires (expires_at),
    CONSTRAINT gymies_email_verification_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
$pdo->exec($sql);
echo "OK: gymies_email_verification_codes table created or exists.\n";
exit(0);
