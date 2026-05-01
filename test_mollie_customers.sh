#!/usr/bin/env bash
# Test script: toont Mollie klanten op de server (via MOLLIE_API_KEY).
# Gebruik: bash test_mollie_customers.sh

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/store/backend/scripts/test_mollie_customers.php"

if [[ ! -f "$PHP_SCRIPT" ]]; then
  echo "ERROR: $PHP_SCRIPT niet gevonden"
  exit 1
fi

echo "=== Mollie klanten ophalen (server: $SSH_TARGET) ==="
echo ""

scp -q "${SSH_OPTS[@]}" "$PHP_SCRIPT" "$SSH_TARGET:/tmp/test_mollie_customers.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo php /tmp/test_mollie_customers.php $REMOTE_LARAVEL; rm -f /tmp/test_mollie_customers.php"
