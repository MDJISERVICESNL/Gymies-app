#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Ghosting-preventie: annuleer pending boekingen waar de trainer niet binnen X uur heeft gereageerd.
 * Stuur de klant een melding dat de aanvraag is verlopen.
 *
 * Gebruik: vanaf Laravel-root: php scripts/expire_pending_bookings_ghosting.php
 * Optioneel: php scripts/expire_pending_bookings_ghosting.php 24  (verval na 24 uur; default 48)
 *
 * Cron (elke uur): 0 * * * * cd /pad/naar/laravel && php scripts/expire_pending_bookings_ghosting.php 48
 */
$hours = isset($argv[1]) && ctype_digit($argv[1]) ? (int) $argv[1] : 48;
if ($hours < 1 || $hours > 168) {
    $hours = 48;
}

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

$envPath = getcwd() . '/.env';
$env = envMap($envPath);
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($env['DB_PORT'] ?? 3306);
$db = $env['DB_DATABASE'] ?? '';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';

if ($db === '' || $user === '') {
    fwrite(STDERR, "DB_DATABASE of DB_USERNAME ontbreekt in .env. Run vanuit Laravel-root.\n");
    exit(1);
}

$dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
try {
    $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Throwable $e) {
    fwrite(STDERR, "DB connect failed: " . $e->getMessage() . "\n");
    exit(1);
}

$cutoff = (new DateTimeImmutable())->modify("-{$hours} hours")->format('Y-m-d H:i:s');

$stmt = $pdo->prepare("
    SELECT id, client_user_id, trainer_user_id, scheduled_at, created_at
    FROM gymies_bookings
    WHERE status = 'pending' AND created_at < ?
");
$stmt->execute([$cutoff]);
$rows = $stmt->fetchAll(PDO::FETCH_OBJ);

if (count($rows) === 0) {
    fwrite(STDOUT, "Geen pending boekingen ouder dan {$hours}u. Cutoff: {$cutoff}\n");
    exit(0);
}

$pdo->beginTransaction();
try {
    $now = (new DateTimeImmutable())->format('Y-m-d H:i:s');
    $insNotif = $pdo->prepare("
        INSERT INTO gymies_notification_queue (user_id, channel, event_type, payload_json, scheduled_for, created_at)
        VALUES (?, 'in_app', ?, ?, ?, ?)
    ");

    foreach ($rows as $b) {
        $bookingId = (int) $b->id;
        $clientId = (int) $b->client_user_id;
        $trainerId = (int) $b->trainer_user_id;

        $pdo->prepare("
            UPDATE gymies_bookings
            SET status = 'cancelled', cancelled_at = ?, cancelled_by_user_id = NULL, updated_at = ?
            WHERE id = ?
        ")->execute([$now, $now, $bookingId]);

        $payload = json_encode([
            'booking_id' => (string) $bookingId,
            'event_type' => 'booking_expired_trainer_no_response',
        ], JSON_UNESCAPED_UNICODE);
        $insNotif->execute([
            $clientId,
            'booking_expired_trainer_no_response_for_client',
            $payload,
            $now,
            $now,
        ]);

        fwrite(STDOUT, "Expired booking {$bookingId} (client {$clientId}, trainer {$trainerId}, created {$b->created_at})\n");
    }

    $pdo->commit();
    fwrite(STDOUT, count($rows) . " pending boekingen geannuleerd en klant gemeld.\n");
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, "Error: " . $e->getMessage() . "\n");
    exit(1);
}
