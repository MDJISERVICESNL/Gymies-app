#!/usr/bin/env bash
# Zet APP_URL en GYMIES_PUBLIC_URL op de server (HTTPS + www) en leeg config-cache.
# Mail-links en verificatie-URL's gebruiken mailPublicBaseUrl() → GYMIES_PUBLIC_URL / APP_URL.
#
# Gebruik:
#   ./scripts/set_app_url_on_server.sh
#   SSH_TARGET=gymies REMOTE_LARAVEL=/var/www/gymies ./scripts/set_app_url_on_server.sh
#
# Wordt ook aangeroepen vanuit deploy_backend_and_ux.sh na backend-upload.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
APP_URL_VALUE="${APP_URL_VALUE:-https://www.gymies.nl}"
GYMIES_PUBLIC_URL_VALUE="${GYMIES_PUBLIC_URL_VALUE:-https://www.gymies.nl}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== APP_URL + GYMIES_PUBLIC_URL op server zetten ==="
echo "Target: $SSH_TARGET"
echo "Laravel: $REMOTE_LARAVEL"
echo "APP_URL=$APP_URL_VALUE"
echo "GYMIES_PUBLIC_URL=$GYMIES_PUBLIC_URL_VALUE"
echo ""

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "export REMOTE_LARAVEL='$REMOTE_LARAVEL' APP_URL_VALUE='$APP_URL_VALUE' GYMIES_PUBLIC_URL_VALUE='$GYMIES_PUBLIC_URL_VALUE'; bash -s" << 'REMOTE_SCRIPT'
set -e
ENV_FILE="${REMOTE_LARAVEL}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env niet gevonden: $ENV_FILE"
  exit 1
fi

set_app_url() {
  local key="$1"
  local val="$2"
  if sudo grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sudo sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    echo "${key} bijgewerkt."
  else
    echo "${key}=${val}" | sudo tee -a "$ENV_FILE" >/dev/null
    echo "${key} toegevoegd."
  fi
}

set_app_url "APP_URL" "$APP_URL_VALUE"
set_app_url "GYMIES_PUBLIC_URL" "$GYMIES_PUBLIC_URL_VALUE"

cd "$REMOTE_LARAVEL" && php artisan config:clear
echo "Config-cache geleegd."
REMOTE_SCRIPT

echo ""
echo "Klaar. Controleer op server: grep -E '^(APP_URL|GYMIES_PUBLIC_URL)=' $REMOTE_LARAVEL/.env"
