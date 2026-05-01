#!/usr/bin/env bash
# Diagnose "ERR_CONNECTION_REFUSED" op gymies.nl: controleer Nginx en poorten op de server.
# Gebruik: SSH_TARGET=gymies ./scripts/server_check_gymies.sh

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET niet gezet. Bijv. export SSH_TARGET=gymies"
  exit 1
fi
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY" -o ConnectTimeout=5)
else
  SSH_OPTS=(-o ConnectTimeout=5)
fi

echo "=== Server-check voor gymies.nl (ERR_CONNECTION_REFUSED) ==="
echo "Doel: $SSH_TARGET"
echo ""

echo "--- 1) Nginx status ---"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'systemctl is-active nginx 2>/dev/null || echo "niet actief"; systemctl status nginx 2>&1 | head -5' || true

echo ""
echo "--- 2) Luistert iets op poort 80/443? ---"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'sudo ss -tlnp | grep -E ":80 |:443 " || echo "Geen proces op 80/443"' || true

echo ""
echo "--- 3) Sites-enabled ---"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'ls -la /etc/nginx/sites-enabled/ 2>/dev/null || echo "Nginx sites-enabled niet gevonden"' || true

echo ""
echo "--- 4) Document root bestaat? ---"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'ls -la /var/www/gymies/public/index.html 2>/dev/null || echo "Geen index in /var/www/gymies/public"' || true

echo ""
echo "--- 5) Lokale test (curl op server) ---"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1/ 2>/dev/null || echo "Curl faalde"' || true

echo ""
echo "=== Als Nginx niet draaide of geen site actief: voer lokaal uit ==="
echo "  SSH_TARGET=gymies ./scripts/apply_nginx_gymies_on_server.sh"
echo ""
echo "Daarna opnieuw proberen: https://gymies.nl"
