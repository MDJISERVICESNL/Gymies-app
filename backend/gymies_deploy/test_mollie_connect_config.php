<?php
/**
 * Smoketest Mollie Connect-config (geen echte OAuth-flow).
 * Draai op de server vanaf Laravel-root:
 *   cd /var/www/gymies && php gymies_deploy/test_mollie_connect_config.php
 *
 * - Controleert MOLLIE_CLIENT_ID / MOLLIE_CLIENT_SECRET
 * - Bouwt redirect_uri zoals de app
 * - Roept Mollie token-endpoint aan met ongeldige code:
 *   - 401 = client id/secret fout of verkeerde omgeving
 *   - 400 + invalid_grant = credentials OK, alleen code ongeldig (verwacht)
 */

declare(strict_types=1);

// gymies_deploy/ ligt in Laravel-root → .env zit één niveau omhoog
$baseDir = dirname(__DIR__);
$envFile = $baseDir . '/.env';
if (is_file($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if (strpos(trim($line), '#') === 0 || strpos($line, '=') === false) {
            continue;
        }
        [$k, $v] = explode('=', $line, 2);
        $k = trim($k);
        $v = trim($v, " \t\"'");
        if ($k !== '' && getenv($k) === false) {
            putenv("{$k}={$v}");
            $_ENV[$k] = $v;
        }
    }
}

$clientId = getenv('MOLLIE_CLIENT_ID') ?: '';
$clientSecret = getenv('MOLLIE_CLIENT_SECRET') ?: '';
$appUrl = rtrim(getenv('APP_URL') ?: 'https://www.gymies.nl', '/');
$redirectUri = $appUrl . '/api/gymies/onboarding/mollie-connect/callback';

echo "=== Mollie Connect config smoketest ===\n";
echo "APP_URL: {$appUrl}\n";
echo "redirect_uri: {$redirectUri}\n";
echo "MOLLIE_CLIENT_ID: " . ($clientId !== '' ? substr($clientId, 0, 16) . '...' : '(LEEG)') . "\n";
echo "MOLLIE_CLIENT_SECRET: " . ($clientSecret !== '' ? '(gezet, ' . strlen($clientSecret) . ' chars)' : '(LEEG)') . "\n\n";

if ($clientId === '' || $clientSecret === '') {
    fwrite(STDERR, "FAIL: MOLLIE_CLIENT_ID en/of MOLLIE_CLIENT_SECRET ontbreekt in .env\n");
    exit(1);
}

$ch = curl_init('https://api.mollie.com/oauth2/tokens');
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
    CURLOPT_POSTFIELDS => http_build_query([
        'grant_type' => 'authorization_code',
        'code' => 'invalid_code_on_purpose',
        'redirect_uri' => $redirectUri,
        'client_id' => $clientId,
        'client_secret' => $clientSecret,
    ]),
    CURLOPT_TIMEOUT => 15,
]);
$body = curl_exec($ch);
$code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo "Mollie token endpoint HTTP {$code}\n";
echo "Response (afgekort): " . substr((string) $body, 0, 200) . "\n\n";

if ($code === 401) {
    fwrite(STDERR, "FAIL: 401 — client_id/client_secret geweigerd. Check keys en test vs live in Mollie.\n");
    exit(1);
}

if ($code === 400 && str_contains((string) $body, 'invalid_grant')) {
    echo "OK: Mollie accepteert client credentials; invalid_grant is verwacht met fake code.\n";
    echo "Volgende stap: in app als trainer Mollie Connect starten en in browser afronden.\n";
    exit(0);
}

if ($code >= 200 && $code < 300) {
    fwrite(STDERR, "Onverwacht: 2xx met fake code — controleer response.\n");
    exit(1);
}

// Mollie geeft soms 500 met JSON body status 503 — upstream storing; geen bewijs dat keys/redirect fout zijn.
if ($code === 500 || $code === 502 || $code === 503 || str_contains((string) $body, 'Service Temporarily Unavailable')) {
    fwrite(STDERR, "Mollie token-endpoint tijdelijk niet bereikbaar (HTTP {$code}).\n");
    fwrite(STDERR, "Dit wijst niet op verkeerde redirect_uri of keys — bij 401 zou Mollie credentials afwijzen.\n");
    fwrite(STDERR, "Actie: later opnieuw draaien, https://status.mollie.com checken, of direct in de app Mollie Connect starten.\n");
    exit(2);
}

fwrite(STDERR, "Onverwachte HTTP {$code}. Bij 401 = keys; bij 400 invalid_grant = keys OK. Anders Mollie-support of redirect_uri in dashboard.\n");
exit(1);
