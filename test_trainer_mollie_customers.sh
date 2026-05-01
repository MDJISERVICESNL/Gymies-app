#!/usr/bin/env bash
# Test: toont Mollie klanten van een specifieke trainer (via hun Mollie Connect token).
# Trainers met betaallinks hebben klanten in hun eigen Mollie-account.
#
# Gebruik: bash test_trainer_mollie_customers.sh [user_id|email]
#   user_id of email: trainer om klanten van op te halen
#
# Voorbeeld: bash test_trainer_mollie_customers.sh 42
# Voorbeeld: bash test_trainer_mollie_customers.sh jamai1210@live.nl

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
IDENTIFIER="${1:-}"

if [[ -z "$IDENTIFIER" ]]; then
  echo "Gebruik: bash test_trainer_mollie_customers.sh <user_id|email>"
  echo "Voorbeeld: bash test_trainer_mollie_customers.sh jamai1210@live.nl"
  exit 1
fi

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/store/backend/scripts/test_trainer_mollie_customers.php"

if [[ ! -f "$PHP_SCRIPT" ]]; then
  echo "ERROR: $PHP_SCRIPT niet gevonden"
  exit 1
fi

echo "=== Mollie klanten van trainer ($IDENTIFIER) ophalen (server: $SSH_TARGET) ==="
echo ""

scp -q "${SSH_OPTS[@]}" "$PHP_SCRIPT" "$SSH_TARGET:/tmp/test_trainer_mollie_customers.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && php /tmp/test_trainer_mollie_customers.php $REMOTE_LARAVEL $IDENTIFIER"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "rm -f /tmp/test_trainer_mollie_customers.php"