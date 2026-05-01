#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
echo "=== FULL gymiesapp nginx (HTTPS server block www.gymiesapp.nl) ==="
sudo cat /etc/nginx/sites-enabled/gymiesapp | awk '/server_name.*www\.gymiesapp\.nl/{found=1} found{print NR": "$0} found && /^}/{exit}'

echo ""
echo "=== FULL default nginx (HTTPS server block www.gymies.nl) ==="
sudo cat /etc/nginx/sites-enabled/default | awk '/server_name.*www\.gymies\.nl/{found=1} found{print NR": "$0} found && /^}/{exit}'

echo ""
echo "=== Port 8080 — what's listening? ==="
sudo ss -tlnp | grep 8080

echo ""
echo "=== Test: what does port 8080 return for this URL? ==="
sudo -u www-data php -r "
\$resp = @file_get_contents('http://127.0.0.1:8080/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05', false, stream_context_create(['http'=>['timeout'=>5,'ignore_errors'=>true]]));
\$status = 'unknown';
if (isset(\$http_response_header)) foreach (\$http_response_header as \$h) if (preg_match('/HTTP.* (\d+)/', \$h, \$m)) \$status = \$m[1];
echo \"HTTP \$status\n\";
if (\$resp) echo substr(\$resp, 0, 300) . \"\n\";
else echo \"No response\n\";
"

echo ""
echo "=== Nginx access log (last 5 gymies/trainers requests) ==="
sudo grep 'trainers.*availability' /var/log/nginx/access.log 2>/dev/null | tail -5 || echo "Not found in access.log"
sudo grep 'trainers.*availability' /var/log/nginx/gymiesapp.access.log 2>/dev/null | tail -5 || echo "Not found in gymiesapp.access.log"
REMOTE
