#!/usr/bin/env bash
# Zet WebSocket/Reverb-vars in .env op de server (met sudo).
#
# Gebruik (lokaal):
#   REVERB_APP_KEY='gymies-ws-key' REVERB_APP_SECRET='jouw-geheime-secret' ./scripts/set_reverb_env_on_server.sh
#
# Of export vooraf:
#   export REVERB_APP_KEY='...'
#   export REVERB_APP_SECRET='...'
#   ./scripts/set_reverb_env_on_server.sh
#
# Optioneel overriden:
#   GYMIES_WS_HOST=app.gymies.nl ./scripts/set_reverb_env_on_server.sh
#
# Zonder keys: script toont welke vars nodig zijn en stopt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

# Reverb keys – vereist
REVERB_APP_KEY="${REVERB_APP_KEY:-}"
REVERB_APP_SECRET="${REVERB_APP_SECRET:-}"

if [[ -z "$REVERB_APP_KEY" || -z "$REVERB_APP_SECRET" ]]; then
  echo "ERROR: Zet REVERB_APP_KEY en REVERB_APP_SECRET."
  echo ""
  echo "  REVERB_APP_KEY='gymies-ws-key' REVERB_APP_SECRET='jouw-secret' $0"
  echo ""
  echo "Andere vars (optioneel, defaults worden gebruikt):"
  echo "  BROADCAST_CONNECTION, REVERB_APP_ID, REVERB_HOST, REVERB_PORT, REVERB_SCHEME"
  echo "  GYMIES_WS_HOST, GYMIES_WS_PORT, GYMIES_WS_SCHEME"
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

# Optionele overrides
BROADCAST_CONNECTION="${BROADCAST_CONNECTION:-reverb}"
REVERB_APP_ID="${REVERB_APP_ID:-gymies}"
REVERB_HOST="${REVERB_HOST:-0.0.0.0}"
REVERB_PORT="${REVERB_PORT:-8080}"
REVERB_SCHEME="${REVERB_SCHEME:-http}"
GYMIES_WS_HOST="${GYMIES_WS_HOST:-www.gymies.nl}"
GYMIES_WS_PORT="${GYMIES_WS_PORT:-443}"
GYMIES_WS_SCHEME="${GYMIES_WS_SCHEME:-https}"

# Base64 voor veilige overdracht van speciale tekens over SSH
KEY_B64=$(printf '%s' "$REVERB_APP_KEY" | base64 | tr -d '\n')
SEC_B64=$(printf '%s' "$REVERB_APP_SECRET" | base64 | tr -d '\n')

SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== Reverb (.env) op server zetten ==="
echo "Target: $SSH_TARGET"
echo "Laravel: $REMOTE_LARAVEL"
echo "REVERB_APP_KEY=${REVERB_APP_KEY:0:8}... (afgekort)"
echo ""

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "export \
  REMOTE_LARAVEL='$REMOTE_LARAVEL' \
  KEY_B64='$KEY_B64' SEC_B64='$SEC_B64' \
  BROADCAST_CONNECTION='$BROADCAST_CONNECTION' \
  REVERB_APP_ID='$REVERB_APP_ID' \
  REVERB_HOST='$REVERB_HOST' REVERB_PORT='$REVERB_PORT' REVERB_SCHEME='$REVERB_SCHEME' \
  GYMIES_WS_HOST='$GYMIES_WS_HOST' GYMIES_WS_PORT='$GYMIES_WS_PORT' GYMIES_WS_SCHEME='$GYMIES_WS_SCHEME' \
  ; bash -s" << 'REMOTE_SCRIPT'
set -e
ENV_FILE="${REMOTE_LARAVEL}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env niet gevonden: $ENV_FILE"
  exit 1
fi

REVERB_APP_KEY=$(printf '%s' "$KEY_B64" | base64 -d)
REVERB_APP_SECRET=$(printf '%s' "$SEC_B64" | base64 -d)

set_kv() {
  local key="$1"
  local val="$2"
  sudo sed -i "/^${key}=/d" "$ENV_FILE" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$val" | sudo tee -a "$ENV_FILE" >/dev/null
  echo "${key} gezet."
}

# Elke var: bestaande regel verwijderen, nieuwe toevoegen (sudo)
set_kv "BROADCAST_CONNECTION" "$BROADCAST_CONNECTION"
set_kv "REVERB_APP_ID" "$REVERB_APP_ID"
set_kv "REVERB_APP_KEY" "$REVERB_APP_KEY"
set_kv "REVERB_APP_SECRET" "$REVERB_APP_SECRET"
set_kv "REVERB_HOST" "$REVERB_HOST"
set_kv "REVERB_PORT" "$REVERB_PORT"
set_kv "REVERB_SCHEME" "$REVERB_SCHEME"
set_kv "GYMIES_WS_HOST" "$GYMIES_WS_HOST"
set_kv "GYMIES_WS_PORT" "$GYMIES_WS_PORT"
set_kv "GYMIES_WS_SCHEME" "$GYMIES_WS_SCHEME"

cd "$REMOTE_LARAVEL" && php artisan config:clear
echo "Config-cache geleegd."

# Reverb herstarten als de service draait
sudo systemctl restart reverb 2>/dev/null || echo "(Reverb service niet actief – start handmatig: sudo systemctl start reverb)"

echo "Reverb .env klaar."
REMOTE_SCRIPT

echo ""
echo "Klaar. Controleer op server:"
echo "  grep -E '^(BROADCAST_CONNECTION|REVERB_|GYMIES_WS_)' $REMOTE_LARAVEL/.env | sed 's/SECRET=.*/SECRET=***hidden***/'"
echo ""
