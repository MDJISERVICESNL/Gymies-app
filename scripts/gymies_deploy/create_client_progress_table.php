#!/usr/bin/env php
<?php
/**
 * Maakt gymies_client_progress aan via .env (geen mysql-cli wachtwoord nodig).
 * Server: cd /var/www/gymies && php gymies_deploy/create_client_progress_table.php
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

$root = getcwd();
$envPath = $root . '/.env';
if (!is_file($envPath)) {
    fwrite(STDERR, "Geen .env in $root — run vanuit Laravel-root.\n");
    exit(1);
}
$env = envMap($envPath);
$db = $env['DB_DATABASE'] ?? '';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($env['DB_PORT'] ?? 3306);
if ($db === '' || $user === '') {
    fwrite(STDERR, "DB_DATABASE/DB_USERNAME ontbreekt in .env\n");
    exit(1);
}

$sql = <<<'SQL'
CREATE TABLE IF NOT EXISTS gymies_client_progress (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  type VARCHAR(32) NOT NULL,
  value TEXT NOT NULL,
  note VARCHAR(500) DEFAULT NULL,
  is_private TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_client_progress_client_trainer (client_user_id, trainer_user_id),
  KEY gymies_client_progress_trainer_created (trainer_user_id, created_at),
  CONSTRAINT gymies_client_progress_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_progress_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
SQL;

$dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
try {
    $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Throwable $e) {
    fwrite(STDERR, "DB connect: " . $e->getMessage() . "\n");
    exit(1);
}

try {
    $pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
    $pdo->exec($sql);
    $pdo->exec('SET FOREIGN_KEY_CHECKS = 1');
    fwrite(STDOUT, "OK: gymies_client_progress aangemaakt of bestond al.\n");
} catch (Throwable $e) {
    fwrite(STDERR, "Fout: " . $e->getMessage() . "\n");
    exit(1);
}
