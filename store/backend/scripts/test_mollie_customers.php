#!/usr/bin/env php
<?php
/**
 * Test: haal klanten op uit Mollie API (met MOLLIE_API_KEY van .env).
 * Draai op server: php test_mollie_customers.php /var/www/gymies
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');
$envPath = $base . '/.env';

if (!file_exists($envPath)) {
    fwrite(STDERR, ".env niet gevonden: $envPath\n");
    exit(1);
}

$apiKey = null;
foreach (file($envPath) as $line) {
    $line = trim(explode('#', $line)[0]);
    if (preg_match('/^MOLLIE_API_KEY=(.+)$/', $line, $m)) {
        $apiKey = trim($m[1], " \t\n\r\0\x0B\"'");
        break;
    }
    if (empty($apiKey) && preg_match('/^MOLLIE_KEY=(.+)$/', $line, $m)) {
        $apiKey = trim($m[1], " \t\n\r\0\x0B\"'");
    }
}

if (empty($apiKey)) {
    fwrite(STDERR, "MOLLIE_API_KEY niet gevonden in .env\n");
    exit(1);
}

$ch = curl_init('https://api.mollie.com/v2/customers?limit=10');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $apiKey],
]);
$resp = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($code !== 200) {
    fwrite(STDERR, "Mollie API fout (HTTP $code): $resp\n");
    exit(1);
}

$data = json_decode($resp, true);
$count = $data['count'] ?? 0;
$customers = $data['_embedded']['customers'] ?? [];

echo "Mollie klanten: $count\n";
foreach (array_slice($customers, 0, 5) as $c) {
    echo "  - " . ($c['name'] ?? '-') . " (" . ($c['id'] ?? '-') . ")\n";
}
if ($count > 5) {
    echo "  ... en " . ($count - 5) . " meer\n";
}
