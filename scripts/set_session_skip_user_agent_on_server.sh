#!/usr/bin/env bash
# Voegt GYMIES_SESSION_SKIP_USER_AGENT_CHECK=true toe aan .env op de server.
# Oplost 401 "Sessieverificatie mislukt" bij Flutter web (andere User-Agent tussen login en API-calls).
#
# Gebruik:
#   ./scripts/set_session_skip_user_agent_on_server.sh
#
# Optioneel:
#   SSH_TARGET=gymies REMOTE_LARAVEL=/var/www/gymies ./scripts/set_session_skip_user_agent_on_server.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  echo "  Zet: export SSH_KEY=\$HOME/.ssh/id_ed25519_gymies"
  exit 1
fi

SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== GYMIES_SESSION_SKIP_USER_AGENT_CHECK op server zetten ==="
echo "Target: $SSH_TARGET"
echo "Laravel: $REMOTE_LARAVEL"
echo ""

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "export REMOTE_LARAVEL='$REMOTE_LARAVEL'; bash -s" << 'REMOTE_SCRIPT'
set -e
ENV_FILE="${REMOTE_LARAVEL}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env niet gevonden: $ENV_FILE"
  exit 1
fi

KEY="GYMIES_SESSION_SKIP_USER_AGENT_CHECK"
VAL="true"

if sudo grep -q "^${KEY}=" "$ENV_FILE" 2>/dev/null; then
  sudo sed -i "s|^${KEY}=.*|${KEY}=${VAL}|" "$ENV_FILE"
  echo "${KEY} bijgewerkt."
else
  echo "${KEY}=${VAL}" | sudo tee -a "$ENV_FILE" >/dev/null
  echo "${KEY} toegevoegd."
fi

cd "$REMOTE_LARAVEL" && php artisan config:clear
echo "Config-cache geleegd."
REMOTE_SCRIPT

echo ""
echo "Klaar. Controleer op server: grep GYMIES_SESSION_SKIP_USER_AGENT_CHECK $REMOTE_LARAVEL/.env"
echo ""
