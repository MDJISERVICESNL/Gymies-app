#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — API test via PHP file_get_contents         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
sudo -u www-data php << 'PHP'
<?php
$from = date('Y-m-d');
$to = date('Y-m-d', strtotime('+7 days'));

$domains = [
    'www.gymiesapp.nl' => 'https://www.gymiesapp.nl',
    'www.gymies.nl'    => 'https://www.gymies.nl',
    'localhost:80'     => 'http://127.0.0.1',
];

$trainerIds = [27, 63];

foreach ($domains as $label => $base) {
    echo "=== {$label} ===\n";
    foreach ($trainerIds as $tid) {
        $url = "{$base}/api/gymies/trainers/{$tid}/availability?from={$from}&to={$to}";
        echo "  GET {$url}\n";

        $ctx = stream_context_create([
            'http' => [
                'method' => 'GET',
                'header' => "Accept: application/json\r\nHost: {$label}\r\n",
                'timeout' => 10,
                'ignore_errors' => true,
            ],
            'ssl' => [
                'verify_peer' => false,
                'verify_peer_name' => false,
            ],
        ]);

        $resp = @file_get_contents($url, false, $ctx);

        // Get HTTP status from response headers
        $status = 'unknown';
        if (isset($http_response_header)) {
            foreach ($http_response_header as $h) {
                if (preg_match('/HTTP\/[\d.]+ (\d+)/', $h, $m)) {
                    $status = $m[1];
                }
            }
        }

        if ($resp === false) {
            echo "  FAILED (no response)\n\n";
            continue;
        }

        echo "  HTTP {$status}\n";

        // Check if HTML
        if (strpos($resp, '<!DOCTYPE') !== false || strpos($resp, '<html') !== false) {
            echo "  Response is HTML (not JSON) — first 100 chars:\n";
            echo "  " . substr(strip_tags($resp), 0, 100) . "\n\n";
            continue;
        }

        $data = json_decode($resp, true);
        if (!$data) {
            echo "  Not valid JSON — first 200 chars:\n";
            echo "  " . substr($resp, 0, 200) . "\n\n";
            continue;
        }

        // Parse response
        $bs = $data['bookable_slots'] ?? [];
        $slots = $data['slots'] ?? [];
        $settings = $data['settings'] ?? [];
        $msg = $data['message'] ?? '';

        echo "  bookable_slots: " . count($bs) . "\n";
        echo "  raw slots: " . count($slots) . "\n";
        if ($settings) echo "  settings: " . json_encode($settings) . "\n";
        if ($msg) echo "  message: {$msg}\n";

        if (count($bs) > 0) {
            $show = array_slice($bs, 0, 3);
            foreach ($show as $s) {
                $avail = $s['available'] ? 'JA' : 'NEE';
                echo "    {$s['date']} {$s['start_time']}-{$s['end_time']} ({$avail})\n";
            }
            if (count($bs) > 3) echo "    ... en " . (count($bs) - 3) . " meer\n";
        }
        echo "\n";
    }
}
PHP
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ API test klaar                                   ║"
echo "╚══════════════════════════════════════════════════════╝"
