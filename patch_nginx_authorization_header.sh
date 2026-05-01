#!/usr/bin/env bash
set -euo pipefail

# Voeg fastcgi_param HTTP_AUTHORIZATION toe aan Nginx (fix 'Unauthorized' na login).
# Gebruik: bash patch_nginx_authorization_header.sh
#
# Optionele env vars:
#   SSH_TARGET=gymies
#   SSH_KEY=$HOME/.ssh/id_ed25519_gymies
#   NGINX_SITE=gymies  (of pad naar config)

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
NGINX_SITE="${NGINX_SITE:-gymies}"

SSH_OPTS=()
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_SCRIPT="$SCRIPT_DIR/store/backend/scripts/patch_nginx_authorization_header.sh"

if [[ ! -f "$PATCH_SCRIPT" ]]; then
  echo "ERROR: patch script niet gevonden: $PATCH_SCRIPT"
  exit 1
fi

echo "=== Nginx Authorization-header patch ==="
echo "Server: $SSH_TARGET"
echo ""

scp "${SSH_OPTS[@]}" "$PATCH_SCRIPT" "$SSH_TARGET:/tmp/patch_nginx_authorization_header.sh"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo bash /tmp/patch_nginx_authorization_header.sh $NGINX_SITE && rm -f /tmp/patch_nginx_authorization_header.sh" || {
  echo ""
  echo "Patch mislukt. Voeg handmatig toe aan Nginx config in de location ~ \.php\$ block:"
  echo "  fastcgi_param HTTP_AUTHORIZATION \$http_authorization;"
  echo ""
  echo "Of: NGINX_SITE=jouw-site bash patch_nginx_authorization_header.sh"
  exit 1
}

echo ""
echo "Nginx Authorization-header patch toegepast."
