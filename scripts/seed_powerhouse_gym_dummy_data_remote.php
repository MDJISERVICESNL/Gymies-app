<?php

declare(strict_types=1);

if ($argc < 2) {
    fwrite(STDERR, "Usage: php seed_powerhouse_gym_dummy_data_remote.php <gym_name>\n");
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
    $existingId = getUserIdByEmail($pdo, $email);
    if ($existingId !== null) {
        $update = $pdo->prepare(
            'UPDATE TrainMaat_users
             SET role = ?, display_name = ?, updated_at = ?
             WHERE id = ?'
        );
        $update->execute([$role, $displayName, $now, $existingId]);
        return $existingId;
    }

    $insert = $pdo->prepare(
        "INSERT INTO TrainMaat_users
            (email, password_hash, role, display_name, email_verified_at, preferred_language, country, created_at, updated_at)
         VALUES
            (?, ?, ?, ?, ?, 'nl', 'NL', ?, ?)"
    );
    $insert->execute([$email, $passwordHash, $role, $displayName, $now, $now, $now]);
    return (int) $pdo->lastInsertId();
}

function ensureOrgMember(PDO $pdo, int $orgId, int $userId, string $role, string $now): void
{
    $exists = $pdo->prepare(
        'SELECT id FROM TrainMaat_organisation_members WHERE organisation_id = ? AND user_id = ? LIMIT 1'
    );
    $exists->execute([$orgId, $userId]);
    $id = $exists->fetchColumn();
    if ($id) {
        $update = $pdo->prepare(
            "UPDATE TrainMaat_organisation_members
             SET role = ?, status = 'active', updated_at = ?
             WHERE id = ?"
        );
        $update->execute([$role, $now, (int) $id]);
        return;
    }

    $insert = $pdo->prepare(
        "INSERT INTO TrainMaat_organisation_members
            (organisation_id, user_id, role, status, invited_at, joined_at, created_at, updated_at)
         VALUES
            (?, ?, ?, 'active', ?, ?, ?, ?)"
    );
    $insert->execute([$orgId, $userId, $role, $now, $now, $now, $now]);
}

function ensureTrainerProfile(
    PDO $pdo,
    int $userId,
    string $bio,
    string $specialty,
    string $region,
    int $hourlyRateCents,
    int $primaryOrgId,
    string $now
): void {
    $hasPrimaryOrgColumn = false;
    $colCheck = $pdo->query(
        "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = 'TrainMaat_trainer_profiles'
           AND COLUMN_NAME = 'primary_organisation_id'"
    );
    if ((int) $colCheck->fetchColumn() > 0) {
        $hasPrimaryOrgColumn = true;
    }

    $exists = $pdo->prepare('SELECT id FROM TrainMaat_trainer_profiles WHERE user_id = ? LIMIT 1');
    $exists->execute([$userId]);
    $id = $exists->fetchColumn();

    if ($id) {
        if ($hasPrimaryOrgColumn) {
            $update = $pdo->prepare(
                "UPDATE TrainMaat_trainer_profiles
                 SET bio = ?, specialty = ?, region = ?, hourly_rate_cents = ?, is_available = 1,
                     trainer_verified_at = COALESCE(trainer_verified_at, ?),
                     primary_organisation_id = ?, updated_at = ?
                 WHERE id = ?"
            );
            $update->execute([$bio, $specialty, $region, $hourlyRateCents, $now, $primaryOrgId, $now, (int) $id]);
        } else {
            $update = $pdo->prepare(
                "UPDATE TrainMaat_trainer_profiles
                 SET bio = ?, specialty = ?, region = ?, hourly_rate_cents = ?, is_available = 1,
                     trainer_verified_at = COALESCE(trainer_verified_at, ?), updated_at = ?
                 WHERE id = ?"
            );
            $update->execute([$bio, $specialty, $region, $hourlyRateCents, $now, $now, (int) $id]);
        }
        return;
    }

    if ($hasPrimaryOrgColumn) {
        $insert = $pdo->prepare(
            "INSERT INTO TrainMaat_trainer_profiles
                (user_id, bio, specialty, region, hourly_rate_cents, is_available, trainer_verified_at, primary_organisation_id, created_at, updated_at)
             VALUES
                (?, ?, ?, ?, ?, 1, ?, ?, ?, ?)"
        );
        $insert->execute([$userId, $bio, $specialty, $region, $hourlyRateCents, $now, $primaryOrgId, $now, $now]);
    } else {
        $insert = $pdo->prepare(
            "INSERT INTO TrainMaat_trainer_profiles
                (user_id, bio, specialty, region, hourly_rate_cents, is_available, trainer_verified_at, created_at, updated_at)
             VALUES
                (?, ?, ?, ?, ?, 1, ?, ?, ?)"
        );
        $insert->execute([$userId, $bio, $specialty, $region, $hourlyRateCents, $now, $now, $now]);
    }
}

function ensureOrgTrainer(PDO $pdo, int $orgId, int $trainerUserId, bool $isPrimary, string $now): void
{
    $exists = $pdo->prepare(
        'SELECT id FROM TrainMaat_organisation_trainers WHERE organisation_id = ? AND trainer_user_id = ? LIMIT 1'
    );
    $exists->execute([$orgId, $trainerUserId]);
    $id = $exists->fetchColumn();
    if ($id) {
        $update = $pdo->prepare(
            "UPDATE TrainMaat_organisation_trainers
             SET status = 'active', is_primary = ?, payout_route = 'via_organisation',
                 employment_type = 'employee', updated_at = ?
             WHERE id = ?"
        );
        $update->execute([$isPrimary ? 1 : 0, $now, (int) $id]);
        return;
    }

    $insert = $pdo->prepare(
        "INSERT INTO TrainMaat_organisation_trainers
            (organisation_id, trainer_user_id, employment_type, payout_route, is_primary, status, active_from, created_at, updated_at)
         VALUES
            (?, ?, 'employee', 'via_organisation', ?, 'active', CURDATE(), ?, ?)"
    );
    $insert->execute([$orgId, $trainerUserId, $isPrimary ? 1 : 0, $now, $now]);
}

function ensureBooking(
    PDO $pdo,
    int $clientUserId,
    int $trainerUserId,
    int $orgId,
    string $scheduledAt,
    int $durationMinutes,
    string $status,
    int $amountCents,
    string $locationType,
    string $locationNotes,
    string $now
): void {
    $exists = $pdo->prepare(
        "SELECT id FROM TrainMaat_bookings
         WHERE client_user_id = ?
           AND trainer_user_id = ?
           AND scheduled_at = ?
           AND location_notes = ?
         LIMIT 1"
    );
    $exists->execute([$clientUserId, $trainerUserId, $scheduledAt, $locationNotes]);
    if ($exists->fetchColumn()) {
        return;
    }

    $paidAt = in_array($status, ['confirmed', 'completed'], true) ? $now : null;
    $insert = $pdo->prepare(
        "INSERT INTO TrainMaat_bookings
            (client_user_id, trainer_user_id, organisation_id, payout_route, scheduled_at, duration_minutes, status, amount_cents, paid_at, location_type, location_notes, client_notes, created_at, updated_at)
         VALUES
            (?, ?, ?, 'via_organisation', ?, ?, ?, ?, ?, ?, ?, 'seed booking powerhousegym', ?, ?)"
    );
    $insert->execute([
        $clientUserId,
        $trainerUserId,
        $orgId,
        $scheduledAt,
        $durationMinutes,
        $status,
        $amountCents,
        $paidAt,
        $locationType,
        $locationNotes,
        $now,
        $now,
    ]);
}

function ensureSettlementDraft(PDO $pdo, int $orgId, int $createdByUserId, string $periodStart, string $periodEnd, string $now): void
{
    $hasSettlements = (int) $pdo->query(
        "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'TrainMaat_organisation_settlements'"
    )->fetchColumn() > 0;
    $hasLines = (int) $pdo->query(
        "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'TrainMaat_organisation_settlement_lines'"
    )->fetchColumn() > 0;
    if (!$hasSettlements || !$hasLines) {
        return;
    }

    $existing = $pdo->prepare(
        'SELECT id FROM TrainMaat_organisation_settlements WHERE organisation_id = ? AND period_start = ? AND period_end = ? LIMIT 1'
    );
    $existing->execute([$orgId, $periodStart, $periodEnd]);
    if ($existing->fetchColumn()) {
        return;
    }

    $bookingsStmt = $pdo->prepare(
        "SELECT id, trainer_user_id, amount_cents
         FROM TrainMaat_bookings
         WHERE organisation_id = ?
           AND scheduled_at BETWEEN ? AND ?
           AND status IN ('confirmed', 'completed')"
    );
    $bookingsStmt->execute([$orgId, $periodStart . ' 00:00:00', $periodEnd . ' 23:59:59']);
    $bookings = $bookingsStmt->fetchAll(PDO::FETCH_ASSOC);

    $gross = 0;
    foreach ($bookings as $booking) {
        $gross += (int) ($booking['amount_cents'] ?? 0);
    }
    $fee = (int) round($gross * 0.12);
    $net = max($gross - $fee, 0);

    $insertSettlement = $pdo->prepare(
        "INSERT INTO TrainMaat_organisation_settlements
            (organisation_id, period_start, period_end, gross_cents, fee_cents, adjustments_cents, net_cents, status, created_by_user_id, created_at, updated_at)
         VALUES
            (?, ?, ?, ?, ?, 0, ?, 'draft', ?, ?, ?)"
    );
    $insertSettlement->execute([$orgId, $periodStart, $periodEnd, $gross, $fee, $net, $createdByUserId, $now, $now]);
    $settlementId = (int) $pdo->lastInsertId();

    if (empty($bookings)) {
        return;
    }

    $insertLine = $pdo->prepare(
        "INSERT INTO TrainMaat_organisation_settlement_lines
            (settlement_id, booking_id, trainer_user_id, line_type, gross_cents, platform_fee_cents, adjustment_cents, net_cents, metadata_json, created_at)
         VALUES
            (?, ?, ?, 'booking', ?, ?, 0, ?, ?, ?)"
    );
    foreach ($bookings as $booking) {
        $lineGross = (int) ($booking['amount_cents'] ?? 0);
        $lineFee = (int) round($lineGross * 0.12);
        $lineNet = max($lineGross - $lineFee, 0);
        $insertLine->execute([
            $settlementId,
            (int) $booking['id'],
            (int) $booking['trainer_user_id'],
            $lineGross,
            $lineFee,
            $lineNet,
            json_encode(['source' => 'seed_powerhouse'], JSON_UNESCAPED_UNICODE),
            $now,
        ]);
    }
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

$now = date('Y-m-d H:i:s');
$defaultPasswordHash = password_hash('TrainMateSeed123!', PASSWORD_BCRYPT);

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

$pdo->beginTransaction();
try {
    $trainerSeeds = [
        [
            'email' => 'powerhouse.trainer1@trainmate.app',
            'name' => 'Amina Powerhouse',
            'bio' => 'Kracht- en conditietrainer voor beginner en gevorderd.',
            'specialty' => 'Krachttraining, Conditie',
            'region' => 'Rotterdam',
            'rate' => 6500,
            'primary' => true,
        ],
        [
            'email' => 'powerhouse.trainer2@trainmate.app',
            'name' => 'Youssef Mobility',
            'bio' => 'Focus op mobiliteit, core en blessurepreventie.',
            'specialty' => 'Mobiliteit, Core',
            'region' => 'Den Haag',
            'rate' => 7000,
            'primary' => false,
        ],
        [
            'email' => 'powerhouse.trainer3@trainmate.app',
            'name' => 'Sofia HIIT',
            'bio' => 'High intensity coaching en vetverlies trajecten.',
            'specialty' => 'HIIT, Vetverlies',
            'region' => 'Utrecht',
            'rate' => 7500,
            'primary' => false,
        ],
    ];

    $trainerUserIds = [];
    foreach ($trainerSeeds as $trainer) {
        $trainerUserId = ensureUser(
            $pdo,
            $trainer['email'],
            'trainer',
            $trainer['name'],
            $defaultPasswordHash,
            $now
        );
        ensureTrainerProfile(
            $pdo,
            $trainerUserId,
            $trainer['bio'],
            $trainer['specialty'],
            $trainer['region'],
            $trainer['rate'],
            $orgId,
            $now
        );
        ensureOrgTrainer($pdo, $orgId, $trainerUserId, $trainer['primary'], $now);
        $trainerUserIds[] = $trainerUserId;
    }

    $managerId = ensureUser(
        $pdo,
        'powerhouse.manager@trainmate.app',
        'klant',
        'Powerhouse Manager',
        $defaultPasswordHash,
        $now
    );
    ensureOrgMember($pdo, $orgId, $managerId, 'manager', $now);

    $viewerId = ensureUser(
        $pdo,
        'powerhouse.viewer@trainmate.app',
        'klant',
        'Powerhouse Viewer',
        $defaultPasswordHash,
        $now
    );
    ensureOrgMember($pdo, $orgId, $viewerId, 'viewer', $now);

    $clientIds = [];
    foreach ([
        ['email' => 'powerhouse.client1@trainmate.app', 'name' => 'Nora Client'],
        ['email' => 'powerhouse.client2@trainmate.app', 'name' => 'Milan Client'],
        ['email' => 'powerhouse.client3@trainmate.app', 'name' => 'Daan Client'],
        ['email' => 'powerhouse.client4@trainmate.app', 'name' => 'Lina Client'],
    ] as $client) {
        $clientIds[] = ensureUser(
            $pdo,
            $client['email'],
            'klant',
            $client['name'],
            $defaultPasswordHash,
            $now
        );
    }

    $base = new DateTimeImmutable('now');
    ensureBooking(
        $pdo,
        $clientIds[0],
        $trainerUserIds[0],
        $orgId,
        $base->modify('-2 days')->format('Y-m-d 10:00:00'),
        60,
        'completed',
        6500,
        'gym',
        'Powerhouse Gym zaal A [seed-powerhouse]',
        $now
    );
    ensureBooking(
        $pdo,
        $clientIds[1],
        $trainerUserIds[1],
        $orgId,
        $base->modify('-1 day')->format('Y-m-d 13:30:00'),
        60,
        'confirmed',
        7000,
        'gym',
        'Powerhouse Gym zaal B [seed-powerhouse]',
        $now
    );
    ensureBooking(
        $pdo,
        $clientIds[2],
        $trainerUserIds[2],
        $orgId,
        $base->modify('+1 day')->format('Y-m-d 17:00:00'),
        45,
        'pending',
        5500,
        'gym',
        'Powerhouse Gym zone cardio [seed-powerhouse]',
        $now
    );
    ensureBooking(
        $pdo,
        $clientIds[3],
        $trainerUserIds[0],
        $orgId,
        $base->modify('+3 days')->format('Y-m-d 09:00:00'),
        60,
        'cancelled',
        6500,
        'gym',
        'Powerhouse Gym zaal A [seed-powerhouse]',
        $now
    );

    $periodStart = $base->modify('first day of this month')->format('Y-m-d');
    $periodEnd = $base->format('Y-m-d');
    ensureSettlementDraft($pdo, $orgId, $ownerUserId > 0 ? $ownerUserId : $managerId, $periodStart, $periodEnd, $now);

    $pdo->commit();
    echo json_encode([
        'ok' => true,
        'organisation_id' => $orgId,
        'trainers_seeded' => 3,
        'team_members_seeded' => 2,
        'clients_seeded' => 4,
        'bookings_seeded' => 4,
        'period_start' => $periodStart,
        'period_end' => $periodEnd,
    ], JSON_UNESCAPED_SLASHES) . PHP_EOL;
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}

