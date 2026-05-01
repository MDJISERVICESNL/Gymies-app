#!/usr/bin/env bash
# Reset wachtwoord van demo-klant@gymies.nl op de server naar demo123!
# Gebruik: bash reset_demo_password.sh [nieuw_wachtwoord]

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
NEW_PASS="${1:-demo123!}"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/store/backend/scripts/reset_both_demo_accounts.php"

if [[ ! -f "$PHP_SCRIPT" ]]; then
  PHP_SCRIPT="$SCRIPT_DIR/store/backend/scripts/reset_demo_password_gymies.php"
fi

if [[ ! -f "$PHP_SCRIPT" ]]; then
  echo "ERROR: reset script niet gevonden"
  exit 1
fi

echo "=== Reset wachtwoord beide demo-accounts op server $SSH_TARGET ==="
scp -q "${SSH_OPTS[@]}" "$PHP_SCRIPT" "$SSH_TARGET:/tmp/reset_demo.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php /tmp/reset_demo.php $REMOTE_LARAVEL '$NEW_PASS' && rm -f /tmp/reset_demo.php"
echo ""
echo "Login: demo-klant@gymies.nl / demo@gymies.nl met wachtwoord $NEW_PASS"
