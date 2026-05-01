#!/usr/bin/env bash
# Nginx-config naar Gymies-server kopiëren en herladen.
# Daarmee wijst de document root naar /var/www/gymies/public (waar we deployen).
# Gebruik: SSH_TARGET=gymies ./scripts/apply_nginx_gymies_on_server.sh

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NGINX_CONF_SRC="$PROJECT_DIR/deploy/nginx-gymies.conf"

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET niet gezet. Bijv. export SSH_TARGET=gymies"
  exit 1
fi
if [[ ! -f "$NGINX_CONF_SRC" ]]; then
  echo "ERROR: Config niet gevonden: $NGINX_CONF_SRC"
  exit 1
fi
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
else
  SSH_OPTS=()
fi

echo "=== Nginx-config toepassen op $SSH_TARGET ==="
echo "1) Config uploaden naar server..."
scp "${SSH_OPTS[@]}" "$NGINX_CONF_SRC" "$SSH_TARGET:/tmp/nginx-gymies.conf"
echo "2) Op server: oude default uitschakelen, Gymies als enige default zetten, nginx herladen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'sudo rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/gymies && sudo cp /tmp/nginx-gymies.conf /etc/nginx/sites-available/gymies && sudo ln -s ../sites-available/gymies /etc/nginx/sites-enabled/default && sudo nginx -t && sudo systemctl start nginx; sudo systemctl reload nginx && rm -f /tmp/nginx-gymies.conf'
echo "Klaar. Document root is nu /var/www/gymies/public"
echo "Test: curl -sI http://127.0.0.1/ | head -5"
