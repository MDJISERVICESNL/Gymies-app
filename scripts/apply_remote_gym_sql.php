<?php

declare(strict_types=1);

function envMap(string $path): array
{
    $map = [];
    if (!is_file($path)) {
        return $map;
    }
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) {
            continue;
        }
        [$k, $v] = explode('=', $line, 2);
        $map[$k] = trim($v, "\"' ");
    }

    return $map;
}

$env = envMap(getcwd() . '/.env');
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($env['DB_PORT'] ?? 3306);
$db = $env['DB_DATABASE'] ?? '';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';
$sqlPath = __DIR__ . '/database/alter_trainmaat_gym_organisations.sql';
if (!is_file($sqlPath)) {
    $sqlPath = getenv('GYMIES_PROJECT_DIR') ? (getenv('GYMIES_PROJECT_DIR') . '/database/alter_trainmaat_gym_organisations.sql') : __DIR__ . '/../database/alter_trainmaat_gym_organisations.sql';
}

if (!is_file($sqlPath) || $db === '' || $user === '') {
    fwrite(STDOUT, "SKIP DB alter (missing sql file or DB vars).\n");
    exit(0);
}

try {
    $pdo = new PDO(
        "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4",
        $user,
        $pass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $sql = file_get_contents($sqlPath) ?: '';
    foreach (array_filter(array_map('trim', explode(';', $sql))) as $stmt) {
        if ($stmt === '' || str_starts_with($stmt, '--')) {
            continue;
        }
        try {
            $pdo->exec($stmt);
        } catch (Throwable $e) {
            // Intentionally idempotent.
        }
    }
    fwrite(STDOUT, "DB alter attempted.\n");
} catch (Throwable $e) {
    fwrite(STDOUT, "DB alter skipped: {$e->getMessage()}\n");
}
