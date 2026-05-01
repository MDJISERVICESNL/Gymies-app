#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — DNS + HTTPS deep trace                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "=== 1. DNS resolution ==="
echo "Server IP:"
hostname -I
echo ""
echo "DNS for www.gymiesapp.nl:"
dig +short www.gymiesapp.nl 2>/dev/null || nslookup www.gymiesapp.nl 2>/dev/null | grep -i address || host www.gymiesapp.nl 2>/dev/null || echo "dig/nslookup not available"
echo ""
echo "DNS for www.gymies.nl:"
dig +short www.gymies.nl 2>/dev/null || nslookup www.gymies.nl 2>/dev/null | grep -i address || host www.gymies.nl 2>/dev/null || echo "dig/nslookup not available"

echo ""
echo "=== 2. curl verbose to see where HTTPS actually goes ==="
curl -vsk --max-time 10 -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>&1 | head -30
echo ""

echo ""
echo "=== 3. Test with --resolve (force localhost) ==="
echo "Forcing www.gymiesapp.nl:443 → 127.0.0.1..."
RESP=$(curl -sk --resolve "www.gymiesapp.nl:443:127.0.0.1" -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "  Response (first 400):"
echo "  $(echo "$RESP" | head -c 400)"
echo ""
echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
    if len(bs) > 0:
        for s in bs[:3]:
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]}')
except Exception as e:
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "=== 4. Test with --resolve for gymies.nl too ==="
echo "Forcing www.gymies.nl:443 → 127.0.0.1..."
RESP2=$(curl -sk --resolve "www.gymies.nl:443:127.0.0.1" -H "Accept: application/json" \
  "https://www.gymies.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "  Response (first 400):"
echo "  $(echo "$RESP2" | head -c 400)"

echo ""
echo "=== 5. Check if there's a /etc/hosts override ==="
grep -i 'gymies' /etc/hosts 2>/dev/null || echo "No gymies entries in /etc/hosts"

echo ""
echo "=== 6. Direct HTTPS via server IP ==="
echo "Testing https://148.113.197.164 with Host: www.gymiesapp.nl..."
RESP3=$(curl -sk -H "Host: www.gymiesapp.nl" -H "Accept: application/json" \
  "https://148.113.197.164/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "  Response (first 400):"
echo "  $(echo "$RESP3" | head -c 400)"

echo ""
echo "=== 7. Create a debug PHP and test via --resolve ==="
sudo bash -c "cat > $LP/public/debug_phpinfo.php << 'DBGPHP'
<?php
header('Content-Type: application/json');
echo json_encode([
    'reached' => true,
    'REQUEST_URI' => \$_SERVER['REQUEST_URI'] ?? 'N/A',
    'SCRIPT_FILENAME' => \$_SERVER['SCRIPT_FILENAME'] ?? 'N/A',
    'HTTP_HOST' => \$_SERVER['HTTP_HOST'] ?? 'N/A',
    'SERVER_PORT' => \$_SERVER['SERVER_PORT'] ?? 'N/A',
    'HTTPS' => \$_SERVER['HTTPS'] ?? 'N/A',
], JSON_PRETTY_PRINT);
DBGPHP"
sudo chown www-data:www-data "$LP/public/debug_phpinfo.php"

echo "Testing debug_phpinfo.php via --resolve HTTPS..."
curl -sk --resolve "www.gymiesapp.nl:443:127.0.0.1" \
  "https://www.gymiesapp.nl/debug_phpinfo.php" 2>/dev/null
echo ""

echo ""
echo "Testing debug_phpinfo.php via HTTPS (normal DNS)..."
curl -sk "https://www.gymiesapp.nl/debug_phpinfo.php" 2>/dev/null
echo ""

# Cleanup
sudo rm -f "$LP/public/debug_phpinfo.php"

echo ""
echo "--- Done ---"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ DNS + HTTPS trace klaar                           ║"
echo "╚══════════════════════════════════════════════════════╝"
