#!/bin/bash
# Quick debug: nginx routing + raw API response
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
echo "=== NGINX CONFIG ==="
# Show relevant nginx config sections for gymies.nl
sudo grep -rn 'server_name\|location.*api\|proxy_pass\|fastcgi_pass\|try_files\|root ' /etc/nginx/sites-enabled/ 2>/dev/null | head -40

echo ""
echo "=== RAW API RESPONSE (wget) ==="
RESP=$(wget -qO- --header="Accept: application/json" "https://www.gymies.nl/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05" 2>&1 || true)
echo "$RESP" | head -20

echo ""
echo "=== TRY localhost:8000 directly ==="
# Maybe Laravel runs on a different port
RESP2=$(wget -qO- "http://127.0.0.1:8000/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05" 2>&1 || true)
echo "$RESP2" | head -10

echo ""
echo "=== CHECK PHP-FPM socket ==="
ls -la /run/php/ 2>/dev/null || echo "No /run/php/"
ls -la /var/run/php/ 2>/dev/null || echo "No /var/run/php/"

echo ""
echo "=== LARAVEL routes/web.php ==="
cat /var/www/gymies/routes/web.php

echo ""
echo "=== LARAVEL routes/gymies.php (first 30 lines) ==="
head -30 /var/www/gymies/routes/gymies.php 2>/dev/null || echo "File not found"

echo ""
echo "=== CHECK if Next.js is running ==="
ps aux | grep -i 'next\|node' | grep -v grep | head -5
REMOTE
