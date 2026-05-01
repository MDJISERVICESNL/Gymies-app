#!/usr/bin/env php
<?php
/**
 * Verwijder Mollie Connect koppeling voor een trainer (bijv. om opnieuw te koppelen met nieuwe scopes).
 *
 * Gebruik:
 *   scp scripts/remove_mollie_connection_server.php gymies:/tmp/
 *   ssh gymies "cd /var/www/gymies && sudo -u www-data php /tmp/remove_mollie_connection_server.php trainer@example.com"
 *
 * Of met user_id:
 *   ssh gymies "cd /var/www/gymies && sudo -u www-data php /tmp/remove_mollie_connection_server.php --user-id=67"
 */
declare(strict_types=1);

$email = null;
$userId = null;

foreach ($argv as $i => $arg) {
    if ($i === 0) continue;
    if (str_starts_with($arg, '--user-id=')) {
        $userId = (int) substr($arg, 10);
    } elseif ($arg !== '' && $arg[0] !== '-') {
        $email = trim($arg);
    }
}

$checkOnly = in_array('--check', $argv, true);
if ($email === null && $userId === null) {
    fwrite(STDERR, "Usage: php remove_mollie_connection_server.php <email>\n");
    fwrite(STDERR, "   of: php remove_mollie_connection_server.php --user-id=67\n");
    fwrite(STDERR, "   of: php remove_mollie_connection_server.php <email> --check  (controleer status zonder te verwijderen)\n");
    exit(1);
}
if ($checkOnly && $email === null && $userId === null) {
    fwrite(STDERR, "Geef email of --user-id op voor --check.\n");
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
    if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) continue;
    [$k, $v] = explode('=', $line, 2);
    $map[trim($k)] = trim($v, "\"' \n\r\t");
}

$dsn = sprintf(
    'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
    $map['DB_HOST'] ?? '127.0.0.1',
    (int) ($map['DB_PORT'] ?? 3306),
    $map['DB_DATABASE'] ?? 'gymies'
);

try {
    $pdo = new PDO($dsn, $map['DB_USERNAME'] ?? 'root', $map['DB_PASSWORD'] ?? '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
} catch (Throwable $e) {
    fwrite(STDERR, "DB connect failed: " . $e->getMessage() . "\n");
    exit(1);
}

if ($userId !== null) {
    $stmt = $pdo->prepare("SELECT id, email, role FROM gymies_users WHERE id = ? AND role = 'trainer' LIMIT 1");
    $stmt->execute([$userId]);
} else {
    $stmt = $pdo->prepare("SELECT id, email, role FROM gymies_users WHERE email = ? AND role = 'trainer' LIMIT 1");
    $stmt->execute([$email]);
}

$user = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$user) {
    fwrite(STDERR, "Trainer niet gevonden.\n");
    exit(1);
}

$trainerId = (int) $user['id'];

// --check: toon alleen status, wijzig niets
if ($checkOnly) {
    $stmt = $pdo->prepare("SELECT mollie_profile_id, mollie_onboarding_status FROM gymies_trainer_profiles WHERE user_id = ? LIMIT 1");
    $stmt->execute([$trainerId]);
    $profile = $stmt->fetch(PDO::FETCH_ASSOC);
    echo "Trainer: {$user['email']} (user_id {$trainerId})\n";
    echo "mollie_profile_id: " . ($profile['mollie_profile_id'] ?? 'NULL') . "\n";
    echo "mollie_onboarding_status: " . ($profile['mollie_onboarding_status'] ?? 'onbekend') . "\n";
    exit(0);
}

$stmt = $pdo->prepare("UPDATE gymies_trainer_profiles SET mollie_profile_id = NULL, mollie_onboarding_status = 'not_started' WHERE user_id = ?");
$stmt->execute([$trainerId]);

echo "Mollie koppeling verwijderd voor {$user['email']} (user_id {$trainerId}).\n";
echo "De trainer kan nu opnieuw koppelen via de wizard.\n";
