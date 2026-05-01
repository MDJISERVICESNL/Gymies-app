#!/usr/bin/env php
<?php
/**
 * Op de SERVER uitvoeren vanuit Laravel-root.
 * Maakt 4 dummy supporttickets aan voor testen in de Control Tower (vault-console).
 *
 * Gebruik:
 *   scp scripts/seed_dummy_tickets_server.php gymies:/tmp/
 *   ssh gymies "cd /var/www/gymies && php /tmp/seed_dummy_tickets_server.php"
 */
declare(strict_types=1);

$envPath = getcwd() . '/.env';
if (!is_file($envPath)) {
    fwrite(STDERR, ".env niet gevonden. Run vanuit Laravel-root (bijv. /var/www/gymies).\n");
    exit(1);
}

$map = [];
foreach (file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
    $line = trim($line);
    if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) {
        continue;
    }
    [$k, $v] = explode('=', $line, 2);
    $map[trim($k)] = trim($v, "\"' \n\r\t");
}

$host = $map['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($map['DB_PORT'] ?? 3306);
$db   = $map['DB_DATABASE'] ?? '';
$user = $map['DB_USERNAME'] ?? '';
$pass = $map['DB_PASSWORD'] ?? '';

if ($db === '' || $user === '') {
    fwrite(STDERR, "DB_DATABASE of DB_USERNAME ontbreekt in .env.\n");
    exit(1);
}

$dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
try {
    $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
} catch (Throwable $e) {
    fwrite(STDERR, "DB connect failed: " . $e->getMessage() . "\n");
    exit(1);
}

// Tabellen bestaan?
foreach (['gymies_support_tickets', 'gymies_support_ticket_messages'] as $t) {
    $stmt = $pdo->query("SHOW TABLES LIKE '{$t}'");
    if ($stmt->rowCount() === 0) {
        fwrite(STDERR, "Tabel {$t} ontbreekt. Run eerst admin_dashboard_schema of seed_gymies_admin_dummy.\n");
        exit(1);
    }
}

// Eerste user_id (klant of trainer) voor ticket-indiener
$stmt = $pdo->query("SELECT id FROM gymies_users ORDER BY id ASC LIMIT 1");
$row = $stmt->fetch(PDO::FETCH_ASSOC);
$userId = $row ? (int) $row['id'] : 0;
if ($userId === 0) {
    fwrite(STDERR, "Geen gebruikers in gymies_users. Maak eerst een user aan.\n");
    exit(1);
}

$tickets = [
    ['subject' => 'Probleem met betaling – transactie mislukt', 'category' => 'billing', 'priority' => 'high', 'status' => 'new', 'message' => 'Hallo, mijn betaling voor een sessie is mislukt. Ik kreeg een foutmelding in de app. Kunnen jullie helpen?'],
    ['subject' => 'Vraag over boeking – datum wijzigen', 'category' => 'booking', 'priority' => 'medium', 'status' => 'in_progress', 'message' => 'Ik wil mijn boeking van volgende week verzetten naar de week erna. Is dat mogelijk?'],
    ['subject' => 'Account wijziging – e-mailadres updaten', 'category' => 'account', 'priority' => 'low', 'status' => 'waiting_customer', 'message' => 'Ik heb een nieuw e-mailadres. Graag zou ik dit in mijn account willen wijzigen.'],
    ['subject' => 'Technisch probleem – inloggen lukt niet', 'category' => 'technical', 'priority' => 'medium', 'status' => 'new', 'message' => 'Sinds vanmorgen kan ik niet meer inloggen. Mijn wachtwoord klopt volgens mij. Kunnen jullie resetten?'],
];

$insertTicket = $pdo->prepare("
    INSERT INTO gymies_support_tickets (user_id, subject, category, priority, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, NOW(), NOW())
");
$insertMessage = $pdo->prepare("
    INSERT INTO gymies_support_ticket_messages (ticket_id, author_user_id, message, is_internal, created_at)
    VALUES (?, ?, ?, 0, NOW())
");

foreach ($tickets as $t) {
    $insertTicket->execute([$userId, $t['subject'], $t['category'], $t['priority'], $t['status']]);
    $ticketId = (int) $pdo->lastInsertId();
    $insertMessage->execute([$ticketId, $userId, $t['message']]);
    echo "Ticket #{$ticketId} aangemaakt: {$t['subject']} ({$t['status']}, {$t['priority']})\n";
}

echo "Klaar. 4 dummy tickets staan in de Control Tower (tab Tickets).\n";
