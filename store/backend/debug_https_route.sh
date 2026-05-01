#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"

# 1. Create a tiny debug PHP file that logs what REQUEST_URI PHP sees
echo "  Creating debug endpoint..."
sudo bash -c "cat > $LP/public/debug_request.php << 'DEBUGPHP'
<?php
header('Content-Type: application/json');
echo json_encode([
    'REQUEST_URI' => \$_SERVER['REQUEST_URI'] ?? 'NOT SET',
    'SCRIPT_NAME' => \$_SERVER['SCRIPT_NAME'] ?? 'NOT SET',
    'SCRIPT_FILENAME' => \$_SERVER['SCRIPT_FILENAME'] ?? 'NOT SET',
    'QUERY_STRING' => \$_SERVER['QUERY_STRING'] ?? 'NOT SET',
    'SERVER_NAME' => \$_SERVER['SERVER_NAME'] ?? 'NOT SET',
    'HTTP_HOST' => \$_SERVER['HTTP_HOST'] ?? 'NOT SET',
    'SERVER_PORT' => \$_SERVER['SERVER_PORT'] ?? 'NOT SET',
    'HTTPS' => \$_SERVER['HTTPS'] ?? 'NOT SET',
]);
DEBUGPHP"
sudo chown www-data:www-data "$LP/public/debug_request.php"

# 2. Test what the debug endpoint sees via different paths
echo ""
echo "=== Debug endpoint via HTTPS www.gymiesapp.nl ==="
sudo -u www-data php -r "
\$r = @file_get_contents('https://www.gymiesapp.nl/debug_request.php', false, stream_context_create(['ssl'=>['verify_peer'=>false,'verify_peer_name'=>false],'http'=>['ignore_errors'=>true]]));
echo \$r ? \$r : 'FAILED';
echo \"\n\";
"

echo ""
echo "=== Debug endpoint via HTTP localhost ==="
sudo -u www-data php -r "
\$r = @file_get_contents('http://127.0.0.1/debug_request.php', false, stream_context_create(['http'=>['ignore_errors'=>true]]));
echo \$r ? \$r : 'FAILED';
echo \"\n\";
"

# 3. Check what REQUEST_URI is when hitting the API via HTTPS
echo ""
echo "=== Nginx error log (last 10 PHP errors) ==="
sudo tail -10 /var/log/nginx/error.log 2>/dev/null || echo "No error log"

echo ""
echo "=== Laravel log (last lines with 'trainer' or 'availability') ==="
sudo grep -i 'trainer\|availability\|not found\|404' "$LP/storage/logs/laravel.log" 2>/dev/null | tail -10 || echo "Nothing found"

# 4. Direct PHP-FPM test via cgi-fcgi (simulates nginx exactly)
echo ""
echo "=== Direct FastCGI test ==="
if command -v cgi-fcgi &>/dev/null; then
    SCRIPT_FILENAME=/var/www/gymies/public/index.php \
    SCRIPT_NAME=/index.php \
    REQUEST_URI=/api/gymies/trainers/27/availability?from=2026-04-28\&to=2026-05-05 \
    REQUEST_METHOD=GET \
    SERVER_NAME=www.gymiesapp.nl \
    QUERY_STRING="from=2026-04-28&to=2026-05-05" \
    cgi-fcgi -bind -connect /run/php/php8.4-fpm.sock 2>/dev/null | head -20
else
    echo "cgi-fcgi not installed, using alternative..."
    # Use php to make a FastCGI request
    sudo -u www-data php -r "
    \$sock = stream_socket_client('unix:///run/php/php8.4-fpm.sock', \$errno, \$errstr, 5);
    if (!\$sock) { echo \"Cannot connect to FPM: \$errstr\n\"; exit(1); }

    // Build a simple FastCGI request
    \$params = [
        'SCRIPT_FILENAME' => '/var/www/gymies/public/index.php',
        'SCRIPT_NAME' => '/index.php',
        'REQUEST_URI' => '/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05',
        'REQUEST_METHOD' => 'GET',
        'SERVER_NAME' => 'www.gymiesapp.nl',
        'SERVER_PORT' => '443',
        'HTTPS' => 'on',
        'QUERY_STRING' => 'from=2026-04-28&to=2026-05-05',
        'HTTP_HOST' => 'www.gymiesapp.nl',
        'HTTP_ACCEPT' => 'application/json',
    ];

    // Just test via HTTP internal request
    echo \"Using HTTP internal test instead:\n\";
    \$ctx = stream_context_create([
        'http' => [
            'header' => \"Host: www.gymiesapp.nl\r\nAccept: application/json\r\n\",
            'ignore_errors' => true,
        ],
        'ssl' => ['verify_peer'=>false,'verify_peer_name'=>false],
    ]);
    // Test via HTTPS
    \$resp = @file_get_contents('https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05', false, \$ctx);
    \$status = 'unknown';
    if (isset(\$http_response_header)) foreach (\$http_response_header as \$h) if (preg_match('/HTTP.* (\d+)/', \$h, \$m)) \$status = \$m[1];
    echo \"HTTPS gymiesapp: HTTP \$status\n\";
    if (\$resp) {
        \$d = json_decode(\$resp, true);
        if (\$d && isset(\$d['message'])) echo \"message: {\$d['message']}\n\";
        if (\$d && isset(\$d['bookable_slots'])) echo \"bookable_slots: \" . count(\$d['bookable_slots']) . \"\n\";
    }

    // Test via HTTP with gymiesapp.nl host header
    echo \"\n\";
    \$ctx2 = stream_context_create([
        'http' => [
            'header' => \"Host: www.gymiesapp.nl\r\nAccept: application/json\r\n\",
            'ignore_errors' => true,
        ],
    ]);
    \$resp2 = @file_get_contents('http://127.0.0.1/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05', false, \$ctx2);
    \$status2 = 'unknown';
    if (isset(\$http_response_header)) foreach (\$http_response_header as \$h) if (preg_match('/HTTP.* (\d+)/', \$h, \$m)) \$status2 = \$m[1];
    echo \"HTTP localhost Host:gymiesapp: HTTP \$status2\n\";
    if (\$resp2) {
        \$d2 = json_decode(\$resp2, true);
        if (\$d2 && isset(\$d2['message'])) echo \"message: {\$d2['message']}\n\";
        if (\$d2 && isset(\$d2['bookable_slots'])) echo \"bookable_slots: \" . count(\$d2['bookable_slots']) . \"\n\";
    }
    "
fi

# Cleanup
sudo rm -f "$LP/public/debug_request.php"
REMOTE
