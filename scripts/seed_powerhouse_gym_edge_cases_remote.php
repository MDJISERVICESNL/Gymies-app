<?php

declare(strict_types=1);

if ($argc < 2) {
    fwrite(STDERR, "Usage: php seed_powerhouse_gym_edge_cases_remote.php <gym_name>\n");
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

function getUserIdByEmail(PDO $pdo, string $email): ?int
{
    $stmt = $pdo->prepare('SELECT id FROM TrainMaat_users WHERE email = ? LIMIT 1');
    $stmt->execute([$email]);
    $id = $stmt->fetchColumn();
    return $id ? (int) $id : null;
}

function ensureUser(PDO $pdo, string $email, string $role, string $displayName, string $passwordHash, string $now): int
{
    $existing = getUserIdByEmail($pdo, $email);
    if ($existing !== null) {
        $upd = $pdo->prepare('UPDATE TrainMaat_users SET role = ?, display_name = ?, updated_at = ? WHERE id = ?');
        $upd->execute([$role, $displayName, $now, $existing]);
        return $existing;
    }

    $ins = $pdo->prepare(
        "INSERT INTO TrainMaat_users
            (email, password_hash, role, display_name, email_verified_at, preferred_language, country, created_at, updated_at)
         VALUES
            (?, ?, ?, ?, ?, 'nl', 'NL', ?, ?)"
    );
    $ins->execute([$email, $passwordHash, $role, $displayName, $now, $now, $now]);
    return (int) $pdo->lastInsertId();
}

function ensureInactiveTrainer(PDO $pdo, int $orgId, int $trainerUserId, string $now): void
{
    $profileExists = $pdo->prepare('SELECT id FROM TrainMaat_trainer_profiles WHERE user_id = ? LIMIT 1');
    $profileExists->execute([$trainerUserId]);
    $profileId = $profileExists->fetchColumn();
    if ($profileId) {
        $upd = $pdo->prepare(
            "UPDATE TrainMaat_trainer_profiles
             SET specialty = 'Hersteltraining', region = 'Eindhoven', hourly_rate_cents = 6200, is_available = 0, updated_at = ?
             WHERE id = ?"
        );
        $upd->execute([$now, (int) $profileId]);
    } else {
        $ins = $pdo->prepare(
            "INSERT INTO TrainMaat_trainer_profiles
                (user_id, bio, specialty, region, hourly_rate_cents, is_available, created_at, updated_at)
             VALUES
                (?, 'Tijdelijk niet inzetbaar (edge-case).', 'Hersteltraining', 'Eindhoven', 6200, 0, ?, ?)"
        );
        $ins->execute([$trainerUserId, $now, $now]);
    }

    $rel = $pdo->prepare(
        'SELECT id FROM TrainMaat_organisation_trainers WHERE organisation_id = ? AND trainer_user_id = ? LIMIT 1'
    );
    $rel->execute([$orgId, $trainerUserId]);
    $relId = $rel->fetchColumn();
    if ($relId) {
        $upd = $pdo->prepare(
            "UPDATE TrainMaat_organisation_trainers
             SET status = 'inactive', is_primary = 0, payout_route = 'via_organisation', employment_type = 'employee', updated_at = ?
             WHERE id = ?"
        );
        $upd->execute([$now, (int) $relId]);
    } else {
        $ins = $pdo->prepare(
            "INSERT INTO TrainMaat_organisation_trainers
                (organisation_id, trainer_user_id, employment_type, payout_route, is_primary, status, active_from, active_until, created_at, updated_at)
             VALUES
                (?, ?, 'employee', 'via_organisation', 0, 'inactive', CURDATE(), CURDATE(), ?, ?)"
        );
        $ins->execute([$orgId, $trainerUserId, $now, $now]);
    }
}

function ensureNoShowBooking(PDO $pdo, int $orgId, int $clientId, int $trainerId, string $scheduledAt, string $now): void
{
    $marker = 'Powerhouse no-show edge-case seed';
    $exists = $pdo->prepare(
        'SELECT id FROM TrainMaat_bookings WHERE organisation_id = ? AND location_notes = ? LIMIT 1'
    );
    $exists->execute([$orgId, $marker]);
    if ($exists->fetchColumn()) {
        return;
    }

    $ins = $pdo->prepare(
        "INSERT INTO TrainMaat_bookings
            (client_user_id, trainer_user_id, organisation_id, payout_route, scheduled_at, duration_minutes, status, amount_cents, paid_at, location_type, location_notes, client_notes, created_at, updated_at)
         VALUES
            (?, ?, ?, 'via_organisation', ?, 60, 'no_show', 6800, ?, 'gym', ?, 'No-show test booking', ?, ?)"
    );
    $ins->execute([$clientId, $trainerId, $orgId, $scheduledAt, $now, $marker, $now, $now]);
}

function ensureSettlement(
    PDO $pdo,
    int $orgId,
    int $createdByUserId,
    string $periodStart,
    string $periodEnd,
    string $status,
    int $gross,
    int $fee,
    int $adjustments,
    string $now
): void {
    $exists = $pdo->prepare(
        'SELECT id FROM TrainMaat_organisation_settlements WHERE organisation_id = ? AND period_start = ? AND period_end = ? LIMIT 1'
    );
    $exists->execute([$orgId, $periodStart, $periodEnd]);
    if ($exists->fetchColumn()) {
        return;
    }

    $net = max($gross - $fee + $adjustments, 0);
    $approvedAt = in_array($status, ['approved', 'paid', 'reconciled'], true) ? $now : null;
    $paidAt = in_array($status, ['paid', 'reconciled'], true) ? $now : null;
    $reconciledAt = $status === 'reconciled' ? $now : null;
    $payoutRef = in_array($status, ['paid', 'reconciled'], true) ? 'SEED-' . strtoupper($status) : null;

    $ins = $pdo->prepare(
        "INSERT INTO TrainMaat_organisation_settlements
            (organisation_id, period_start, period_end, gross_cents, fee_cents, adjustments_cents, net_cents, status, approved_at, paid_at, reconciled_at, created_by_user_id, payout_reference, created_at, updated_at)
         VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );
    $ins->execute([
        $orgId,
        $periodStart,
        $periodEnd,
        $gross,
        $fee,
        $adjustments,
        $net,
        $status,
        $approvedAt,
        $paidAt,
        $reconciledAt,
        $createdByUserId,
        $payoutRef,
        $now,
        $now,
    ]);
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

$orgStmt = $pdo->prepare('SELECT id FROM TrainMaat_organisations WHERE LOWER(name) = LOWER(?) LIMIT 1');
$orgStmt->execute([$gymName]);
$orgId = (int) ($orgStmt->fetchColumn() ?: 0);
if ($orgId <= 0) {
    fwrite(STDERR, "Organisation not found: {$gymName}\n");
    exit(1);
}

$ownerStmt = $pdo->prepare(
    "SELECT user_id FROM TrainMaat_organisation_members
     WHERE organisation_id = ? AND role = 'owner' AND status = 'active'
     ORDER BY id ASC LIMIT 1"
);
$ownerStmt->execute([$orgId]);
$ownerUserId = (int) ($ownerStmt->fetchColumn() ?: 0);

$settlementsTableExists = (int) $pdo->query(
    "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'TrainMaat_organisation_settlements'"
)->fetchColumn() > 0;

$now = date('Y-m-d H:i:s');
$seedPasswordHash = password_hash('TrainMateSeed123!', PASSWORD_BCRYPT);

$pdo->beginTransaction();
try {
    $inactiveTrainerId = ensureUser(
        $pdo,
        'powerhouse.inactive.trainer@trainmate.app',
        'trainer',
        'Ruben Inactive',
        $seedPasswordHash,
        $now
    );
    ensureInactiveTrainer($pdo, $orgId, $inactiveTrainerId, $now);

    $clientId = ensureUser(
        $pdo,
        'powerhouse.noshow.client@trainmate.app',
        'klant',
        'NoShow Client',
        $seedPasswordHash,
        $now
    );

    $activeTrainerId = getUserIdByEmail($pdo, 'powerhouse.trainer1@trainmate.app');
    if ($activeTrainerId === null) {
        $activeTrainerId = $inactiveTrainerId;
    }
    ensureNoShowBooking(
        $pdo,
        $orgId,
        $clientId,
        $activeTrainerId,
        (new DateTimeImmutable('now'))->modify('-5 days')->format('Y-m-d 12:00:00'),
        $now
    );

    if ($settlementsTableExists) {
        $seedBy = $ownerUserId > 0 ? $ownerUserId : $clientId;
        ensureSettlement($pdo, $orgId, $seedBy, '2026-01-01', '2026-01-31', 'approved', 38000, 4560, 0, $now);
        ensureSettlement($pdo, $orgId, $seedBy, '2025-12-01', '2025-12-31', 'paid', 41200, 4944, 1200, $now);
        ensureSettlement($pdo, $orgId, $seedBy, '2025-11-01', '2025-11-30', 'reconciled', 36500, 4380, -500, $now);
    }

    $pdo->commit();
    echo json_encode([
        'ok' => true,
        'organisation_id' => $orgId,
        'inactive_trainer_email' => 'powerhouse.inactive.trainer@trainmate.app',
        'no_show_client_email' => 'powerhouse.noshow.client@trainmate.app',
        'settlements_seeded' => $settlementsTableExists ? 3 : 0,
    ], JSON_UNESCAPED_SLASHES) . PHP_EOL;
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}

