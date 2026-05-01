<?php

declare(strict_types=1);

if ($argc < 2) {
    fwrite(STDERR, "Usage: php create_gym_account_remote.php <gym_name>\n");
    exit(1);
}

$gymName = trim((string) $argv[1]);
if ($gymName === '') {
    fwrite(STDERR, "Gym name is required.\n");
    exit(1);
}

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

$tables = $pdo->query("SHOW TABLES")->fetchAll(PDO::FETCH_COLUMN);
if (!in_array('TrainMaat_organisations', $tables, true) || !in_array('TrainMaat_organisation_members', $tables, true)) {
    fwrite(STDERR, "Gym tables are missing. Apply migration first.\n");
    exit(1);
}

$slug = strtolower(preg_replace('/[^a-z0-9]+/', '', $gymName) ?: 'gym');
$baseEmail = $slug . '@trainmate.app';
$tempPassword = bin2hex(random_bytes(6)) . 'A!';
$passwordHash = password_hash($tempPassword, PASSWORD_BCRYPT);
$now = date('Y-m-d H:i:s');

$pdo->beginTransaction();
try {
    $orgStmt = $pdo->prepare("SELECT id FROM TrainMaat_organisations WHERE LOWER(name)=LOWER(?) LIMIT 1");
    $orgStmt->execute([$gymName]);
    $existingOrgId = $orgStmt->fetchColumn();

    $orgCreated = false;
    if ($existingOrgId) {
        $orgId = (int) $existingOrgId;
    } else {
        $insertOrg = $pdo->prepare("
            INSERT INTO TrainMaat_organisations
                (name, type, status, contact_email, payout_frequency, payout_minimum_cents, created_at, updated_at)
            VALUES
                (?, 'gym', 'active', ?, 'weekly', 0, ?, ?)
        ");
        $insertOrg->execute([$gymName, $baseEmail, $now, $now]);
        $orgId = (int) $pdo->lastInsertId();
        $orgCreated = true;
    }

    $email = $baseEmail;
    $counter = 1;
    while (true) {
        $checkUser = $pdo->prepare("SELECT id FROM TrainMaat_users WHERE email = ? LIMIT 1");
        $checkUser->execute([$email]);
        if (!$checkUser->fetchColumn()) {
            break;
        }
        $counter++;
        $email = $slug . '+' . $counter . '@trainmate.app';
    }

    $insertUser = $pdo->prepare("
        INSERT INTO TrainMaat_users
            (email, password_hash, role, display_name, email_verified_at, created_at, updated_at)
        VALUES
            (?, ?, 'klant', ?, ?, ?, ?)
    ");
    $insertUser->execute([$email, $passwordHash, $gymName . ' admin', $now, $now, $now]);
    $userId = (int) $pdo->lastInsertId();

    $insertMember = $pdo->prepare("
        INSERT INTO TrainMaat_organisation_members
            (organisation_id, user_id, role, status, invited_at, joined_at, created_at, updated_at)
        VALUES
            (?, ?, 'owner', 'active', ?, ?, ?, ?)
    ");
    $insertMember->execute([$orgId, $userId, $now, $now, $now, $now]);

    $pdo->commit();

    echo json_encode([
        'ok' => true,
        'organisation_id' => $orgId,
        'organisation_created' => $orgCreated,
        'owner_user_id' => $userId,
        'owner_email' => $email,
        'temporary_password' => $tempPassword,
    ], JSON_UNESCAPED_SLASHES) . PHP_EOL;
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}
