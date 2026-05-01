#!/usr/bin/env php
<?php
/**
 * Gymies API-testscript voor op de server (of lokaal tegen de server).
 * Test: login → support/tickets (lijst, aanmaken, ophalen, bericht toevoegen).
 *
 * Gebruik op de server (vanuit Laravel-root):
 *   cd /var/www/gymies.nl/laravel
 *   php /path/to/Gymies/scripts/test_gymies_api_server.php
 *
 * Of met expliciete URL en inloggegevens:
 *   GYMIES_BASE_URL=https://gymies.nl GYMIES_EMAIL=klant@example.com GYMIES_PASSWORD=wachtwoord php test_gymies_api_server.php
 *
 * Of met argumenten (base_url email password):
 *   php test_gymies_api_server.php https://gymies.nl klant@example.com wachtwoord
 *
 * Op de server (vanuit Laravel-root, APP_URL komt uit .env):
 *   cd /var/www/gymies.nl/laravel && GYMIES_EMAIL=... GYMIES_PASSWORD=... php /pad/naar/scripts/test_gymies_api_server.php
 */
declare(strict_types=1);

$baseUrl = $argv[1] ?? getenv('GYMIES_BASE_URL') ?: '';
$email   = $argv[2] ?? getenv('GYMIES_EMAIL') ?: '';
$password = $argv[3] ?? getenv('GYMIES_PASSWORD') ?: '';

// Als we in een Laravel-root draaien, base URL uit .env
if ($baseUrl === '' && is_file(getcwd() . '/.env')) {
    foreach (file(getcwd() . '/.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (strpos($line, '=') !== false && str_starts_with(trim($line), 'APP_URL=')) {
            $baseUrl = trim(explode('=', $line, 2)[1], " \t\"'");
            break;
        }
    }
}
$baseUrl = rtrim($baseUrl, '/');
$apiBase = $baseUrl . '/api/gymies';

if ($baseUrl === '') {
    fwrite(STDERR, "Usage: GYMIES_BASE_URL=https://... GYMIES_EMAIL=... GYMIES_PASSWORD=... php test_gymies_api_server.php\n");
    fwrite(STDERR, "   or: php test_gymies_api_server.php <base_url> <email> <password>\n");
    exit(1);
}
if ($email === '' || $password === '') {
    fwrite(STDERR, "Email en wachtwoord zijn verplicht (env GYMIES_EMAIL, GYMIES_PASSWORD of argumenten 2 en 3).\n");
    exit(1);
}

$passed = 0;
$failed = 0;

function request(string $method, string $url, ?string $body = null, ?string $token = null): array
{
    $ctx = stream_context_create([
        'http' => [
            'method' => $method,
            'header' => array_filter([
                'Content-Type: application/json',
                'Accept: application/json',
                $token !== null ? 'Authorization: Bearer ' . $token : null,
            ]),
            'content' => $body,
            'ignore_errors' => true,
            'timeout' => 15,
        ],
    ]);
    $response = @file_get_contents($url, false, $ctx);
    $code = 0;
    if (isset($http_response_header[0]) && preg_match('/ (\d{3}) /', $http_response_header[0], $m)) {
        $code = (int) $m[1];
    }
    $json = $response !== false ? json_decode($response, true) : null;
    return ['code' => $code, 'body' => $json !== null ? $json : [], 'raw' => $response];
}

function ok(string $name, int $code, array $body, string $expect = ''): bool
{
    global $passed, $failed;
    $success = $code >= 200 && $code < 300;
    if ($success) {
        $passed++;
        echo "  OK   {$name}\n";
        return true;
    }
    $failed++;
    $msg = $body['message'] ?? $body['errors'] ?? json_encode($body);
    echo "  FAIL {$name} (HTTP {$code}) " . (is_string($msg) ? $msg : json_encode($msg)) . "\n";
    return false;
}

echo "== Gymies API-test (support/tickets) ==\n";
echo "Base URL: {$baseUrl}\n";
echo "Email: " . $email . "\n\n";

// 1) Login
echo "1) Login...\n";
$login = request('POST', $apiBase . '/login', json_encode(['email' => $email, 'password' => $password]));
if (!ok('Login', $login['code'], $login['body'])) {
    echo "\nLogin mislukt; verdere tests hebben een token nodig. Stop.\n";
    exit(1);
}
$token = $login['body']['token'] ?? '';
if ($token === '') {
    echo "  FAIL Geen token in response.\n";
    exit(1);
}

// 2) GET support/tickets (lijst)
echo "\n2) GET support/tickets (lijst)...\n";
$list = request('GET', $apiBase . '/support/tickets', null, $token);
ok('Lijst tickets', $list['code'], $list['body']);
$tickets = $list['body']['data'] ?? [];

// 3) POST support/tickets (nieuw ticket)
echo "\n3) POST support/tickets (nieuw ticket)...\n";
$create = request('POST', $apiBase . '/support/tickets', json_encode([
    'subject' => 'Test ticket ' . date('Y-m-d H:i:s'),
    'message' => 'Automatisch testbericht van test_gymies_api_server.php',
    'category' => 'technical',
    'priority' => 'low',
]), $token);
if (!ok('Ticket aanmaken', $create['code'], $create['body'])) {
    echo "\nTicket aanmaken mislukt. Stop.\n";
    exit(1);
}
$ticketId = $create['body']['data']['id'] ?? null;
if ($ticketId === null) {
    echo "  FAIL Geen ticket id in response.\n";
    exit(1);
}

// 4) GET support/tickets/{id}
echo "\n4) GET support/tickets/{$ticketId}...\n";
$show = request('GET', $apiBase . '/support/tickets/' . $ticketId, null, $token);
ok('Ticket ophalen', $show['code'], $show['body']);

// 5) POST support/tickets/{id}/messages
echo "\n5) POST support/tickets/{$ticketId}/messages...\n";
$msg = request('POST', $apiBase . '/support/tickets/' . $ticketId . '/messages', json_encode([
    'message' => 'Follow-up testbericht.',
]), $token);
ok('Bericht toevoegen', $msg['code'], $msg['body']);

// 6) GET support/tickets/{id} opnieuw (controleren of bericht erbij staat)
echo "\n6) GET support/tickets/{$ticketId} (opnieuw, met berichten)...\n";
$show2 = request('GET', $apiBase . '/support/tickets/' . $ticketId, null, $token);
$messages = $show2['body']['data']['messages'] ?? [];
$okCount = count($messages) >= 2 ? 'OK' : 'FAIL';
if ($okCount === 'OK') {
    $passed++;
    echo "  OK   Aantal berichten >= 2 (" . count($messages) . ")\n";
} else {
    $failed++;
    echo "  FAIL Verwacht min. 2 berichten, gekregen: " . count($messages) . "\n";
}

echo "\n== Resultaat: {$passed} geslaagd, {$failed} gefaald ==\n";
exit($failed > 0 ? 1 : 0);
