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

function hasColumn(PDO $pdo, string $db, string $table, string $column): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?'
    );
    $stmt->execute([$db, $table, $column]);
    return ((int) $stmt->fetchColumn()) > 0;
}

function hasIndex(PDO $pdo, string $db, string $table, string $index): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND INDEX_NAME = ?'
    );
    $stmt->execute([$db, $table, $index]);
    return ((int) $stmt->fetchColumn()) > 0;
}

function hasConstraint(PDO $pdo, string $db, string $table, string $constraint): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND CONSTRAINT_NAME = ?'
    );
    $stmt->execute([$db, $table, $constraint]);
    return ((int) $stmt->fetchColumn()) > 0;
}

$env = envMap(getcwd() . '/.env');
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($env['DB_PORT'] ?? 3306);
$db = $env['DB_DATABASE'] ?? '';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';

if ($db === '' || $user === '') {
    fwrite(STDERR, "DB vars missing in .env\n");
    exit(1);
}

$pdo = new PDO(
    "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4",
    $user,
    $pass,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$changes = [];

if (!hasColumn($pdo, $db, 'TrainMaat_bookings', 'organisation_id')) {
    $pdo->exec(
        "ALTER TABLE TrainMaat_bookings ADD COLUMN organisation_id BIGINT UNSIGNED NULL COMMENT 'Gym/organisatie voor payout flow'"
    );
    $changes[] = 'added TrainMaat_bookings.organisation_id';
}

if (!hasColumn($pdo, $db, 'TrainMaat_bookings', 'payout_route')) {
    $pdo->exec(
        "ALTER TABLE TrainMaat_bookings ADD COLUMN payout_route ENUM('direct_trainer','via_organisation') NOT NULL DEFAULT 'direct_trainer'"
    );
    $changes[] = 'added TrainMaat_bookings.payout_route';
}

if (!hasIndex($pdo, $db, 'TrainMaat_bookings', 'TrainMaat_bookings_organisation')) {
    $pdo->exec('ALTER TABLE TrainMaat_bookings ADD KEY TrainMaat_bookings_organisation (organisation_id)');
    $changes[] = 'added index TrainMaat_bookings_organisation';
}

if (hasColumn($pdo, $db, 'TrainMaat_bookings', 'organisation_id') &&
    !hasConstraint($pdo, $db, 'TrainMaat_bookings', 'TrainMaat_bookings_organisation_fk')
) {
    try {
        $pdo->exec(
            'ALTER TABLE TrainMaat_bookings ADD CONSTRAINT TrainMaat_bookings_organisation_fk FOREIGN KEY (organisation_id) REFERENCES TrainMaat_organisations (id) ON DELETE SET NULL'
        );
        $changes[] = 'added fk TrainMaat_bookings_organisation_fk';
    } catch (Throwable $e) {
        $changes[] = 'fk skipped: ' . $e->getMessage();
    }
}

echo json_encode([
    'ok' => true,
    'changes' => $changes,
], JSON_UNESCAPED_SLASHES) . PHP_EOL;

