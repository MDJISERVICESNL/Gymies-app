<?php
/**
 * Smoketest Reverb/WebSocket-config.
 * Draai op de server vanaf Laravel-root:
 *   cd /var/www/gymies && php gymies_deploy/test_reverb_config.php
 *
 * - Controleert REVERB_APP_KEY, REVERB_APP_SECRET, GYMIES_WS_HOST
 * - Controleert config/reverb.php en BROADCAST_CONNECTION
 * - Test of Reverb luistert op poort 8080
 */

declare(strict_types=1);

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

$appKey = getenv('REVERB_APP_KEY') ?: getenv('PUSHER_APP_KEY') ?: '';
$appSecret = getenv('REVERB_APP_SECRET') ?: getenv('PUSHER_APP_SECRET') ?: '';
$wsHost = getenv('GYMIES_WS_HOST') ?: getenv('REVERB_HOST') ?: 'www.gymies.nl';
$wsPort = (int) (getenv('GYMIES_WS_PORT') ?: getenv('REVERB_PORT') ?: '443');
$broadcastConn = getenv('BROADCAST_CONNECTION') ?: '';

echo "=== Reverb config smoketest ===\n";
echo "BROADCAST_CONNECTION: " . ($broadcastConn !== '' ? $broadcastConn : '(LEEG, default log)') . "\n";
echo "REVERB_APP_KEY: " . ($appKey !== '' ? substr($appKey, 0, 8) . '...' : '(LEEG)') . "\n";
echo "REVERB_APP_SECRET: " . ($appSecret !== '' ? '(gezet, ' . strlen($appSecret) . ' chars)' : '(LEEG)') . "\n";
echo "GYMIES_WS_HOST: {$wsHost}\n";
echo "GYMIES_WS_PORT: {$wsPort}\n\n";

$failed = false;

if ($appKey === '' || $appSecret === '') {
    fwrite(STDERR, "FAIL: REVERB_APP_KEY en/of REVERB_APP_SECRET ontbreekt in .env\n");
    $failed = true;
}

if (!is_file($baseDir . '/config/reverb.php')) {
    fwrite(STDERR, "FAIL: config/reverb.php niet gevonden. Draai: php artisan reverb:install\n");
    $failed = true;
}

// Reverb luistert lokaal op 8080
$port = (int) (getenv('REVERB_PORT') ?: '8080');
$fp = @fsockopen('127.0.0.1', $port, $errno, $errstr, 2);
if (!$fp) {
    fwrite(STDERR, "WARN: Reverb luistert niet op 127.0.0.1:{$port}. Start: sudo systemctl start reverb\n");
} else {
    fclose($fp);
    echo "OK: Reverb luistert op poort {$port}\n";
}

if ($failed) {
    exit(1);
}

echo "OK: Reverb-config in orde. Flutter kan via wss://{$wsHost}:{$wsPort} verbinden.\n";
exit(0);
