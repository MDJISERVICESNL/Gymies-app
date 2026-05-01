#!/usr/bin/env bash
# Zet MOLLIE_CLIENT_ID + MOLLIE_CLIENT_SECRET op de server (.env) en leeg config-cache.
# Geen keys in dit script — alleen via environment meegeven.
#
# Gebruik (lokaal, keys niet in shell history: lees van bestand of export in subshell):
#   export MOLLIE_CLIENT_ID='app_...'
#   export MOLLIE_CLIENT_SECRET='...'
#   ./scripts/set_mollie_connect_env_on_server.sh
#
# Of in één regel:
#   MOLLIE_CLIENT_ID='app_xxx' MOLLIE_CLIENT_SECRET='yyy' ./scripts/set_mollie_connect_env_on_server.sh
#
# Optioneel:
#   SSH_TARGET=gymies REMOTE_LARAVEL=/var/www/gymies ./scripts/set_mollie_connect_env_on_server.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

if [[ -z "${MOLLIE_CLIENT_ID:-}" || -z "${MOLLIE_CLIENT_SECRET:-}" ]]; then
  echo "ERROR: Zet eerst MOLLIE_CLIENT_ID en MOLLIE_CLIENT_SECRET (export of op dezelfde regel)."
  echo "  Voorbeeld: MOLLIE_CLIENT_ID='app_...' MOLLIE_CLIENT_SECRET='...' $0"
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== Mollie Connect (.env) op server zetten ==="
echo "Target: $SSH_TARGET"
echo "Laravel: $REMOTE_LARAVEL"
echo "MOLLIE_CLIENT_ID=${MOLLIE_CLIENT_ID:0:12}... (afgekort)"
echo ""

# Base64 om speciale tekens in secret veilig over SSH te sturen
ID_B64=$(printf '%s' "$MOLLIE_CLIENT_ID" | base64 | tr -d '\n')
SEC_B64=$(printf '%s' "$MOLLIE_CLIENT_SECRET" | base64 | tr -d '\n')

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "export REMOTE_LARAVEL='$REMOTE_LARAVEL' ID_B64='$ID_B64' SEC_B64='$SEC_B64'; bash -s" << 'REMOTE_SCRIPT'
set -e
ENV_FILE="${REMOTE_LARAVEL}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env niet gevonden: $ENV_FILE"
  exit 1
fi

MOLLIE_CLIENT_ID=$(printf '%s' "$ID_B64" | base64 -d)
MOLLIE_CLIENT_SECRET=$(printf '%s' "$SEC_B64" | base64 -d)

set_kv() {
  local key="$1"
  local val="$2"
  sudo sed -i "/^${key}=/d" "$ENV_FILE" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$val" | sudo tee -a "$ENV_FILE" >/dev/null
  echo "${key} gezet."
}

set_kv "MOLLIE_CLIENT_ID" "$MOLLIE_CLIENT_ID"
set_kv "MOLLIE_CLIENT_SECRET" "$MOLLIE_CLIENT_SECRET"

cd "$REMOTE_LARAVEL" && php artisan config:clear
echo "Config-cache geleegd."
REMOTE_SCRIPT

echo ""
echo "Klaar. Controleer op server:"
echo "  grep -E '^MOLLIE_CLIENT_(ID|SECRET)=' $REMOTE_LARAVEL/.env | sed 's/SECRET=.*/SECRET=***hidden***/'"
echo ""
echo "Mollie-dashboard: redirect URI exact:"
echo "  https://www.gymies.nl/api/gymies/onboarding/mollie-connect/callback"
echo "  (pas aan als APP_URL anders is)"
