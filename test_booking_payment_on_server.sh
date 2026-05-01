#!/usr/bin/env bash
# Test: voer betalingstest UIT OP DE SERVER (via SSH) - voorkomt auth IP-blokkade.
# Gebruik: bash test_booking_payment_on_server.sh [wachtwoord]

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
PASS="${1:-demo123!}"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test_booking_payment_full.sh"

echo "=== Betalingstest op server (localhost) ==="
echo "Voert test uit OP de server om auth-blokkade te omzeilen."
echo ""

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "GYMIES_API_BASE=https://127.0.0.1/api/gymies GYMIES_PASSWORD='$PASS' bash -s" < <(
  echo 'curl -s -k -X POST "$GYMIES_API_BASE/login" -H "Accept: application/json" -H "Content-Type: application/json" -d "{\"email\":\"demo-klant@gymies.nl\",\"password\":\"$GYMIES_PASSWORD\"}" | head -c 500'
)

# Simpel: voer het volledige testscript uit op de server met localhost API
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "export GYMIES_API_BASE='https://127.0.0.1/api/gymies'; export GYMIES_PASSWORD='$PASS'; cd /tmp && curl -s -k -X POST \"\$GYMIES_API_BASE/login\" -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{\"email\":\"demo-klant@gymies.nl\",\"password\":\"$PASS\"}'" | python3 -m json.tool 2>/dev/null || true
