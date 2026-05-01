#!/usr/bin/env php
<?php
/**
 * Controleer of Mollie gekoppelde clients ziet (List Clients API).
 *
 * Upload: scp scripts/check_mollie_clients_server.php gymies:/tmp/
 * Draai:  ssh gymies "cd /var/www/gymies && sudo -u www-data php /tmp/check_mollie_clients_server.php"
 */
declare(strict_types=1);

$envPath = '/var/www/gymies/.env';
if (!is_file($envPath)) {
    $envPath = dirname(__DIR__, 2) . '/.env';
}
if (!is_file($envPath)) {
    fwrite(STDERR, ".env niet gevonden. Run vanaf server: cd /var/www/gymies\n");
    exit(1);
}

$map = [];
foreach (file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
    $line = trim($line);
    if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) continue;
    [$k, $v] = explode('=', $line, 2);
    $map[trim($k)] = trim($v, "\"' \t");
}

// List Clients vereist OAuth token; organisatietoken werkt, API key geeft 403
$token = $map['MOLLIE_ORGANIZATION_TOKEN'] ?? '';
if ($token === '') {
    $token = $map['MOLLIE_API_KEY'] ?? '';
}
if ($token === '') {
    fwrite(STDERR, "MOLLIE_ORGANIZATION_TOKEN of MOLLIE_API_KEY niet gevonden in .env\n");
    exit(1);
}

$ch = curl_init('https://api.mollie.com/v2/clients');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $token],
    CURLOPT_TIMEOUT => 15,
]);
$body = curl_exec($ch);
$code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo "=== Mollie List Clients ===\n";
echo "HTTP: $code\n";
echo "Response:\n" . $body . "\n";

if ($code === 401) {
    fwrite(STDERR, "401: API key geweigerd. Check MOLLIE_API_KEY (test_ of live_).\n");
    exit(1);
}

if ($code === 403) {
    $detail = json_decode($body, true)['detail'] ?? '';
    if (strpos($detail, 'Partners or Marketplaces') !== false) {
        echo "\n→ Account is geen Partner/Marketplace. List Clients en Partners > Clients\n";
        echo "  werken alleen met dat statuut. Actie: Browse → Connect in Mollie, of\n";
        echo "  mail partners@mollie.com om Partner-status te activeren.\n";
    } else {
        echo "\n→ List Clients vereist een OAuth access token (organisatietoken).\n";
        echo "  Zet MOLLIE_ORGANIZATION_TOKEN in .env en draai opnieuw.\n";
    }
    exit(0);
}

if ($code === 200) {
    $data = json_decode($body, true);
    $clients = $data['_embedded']['clients'] ?? [];
    $count = $data['count'] ?? count($clients);
    echo "\nAantal clients: $count\n";
    foreach ($clients as $c) {
        echo "  - " . ($c['id'] ?? '?') . "\n";
    }
}
