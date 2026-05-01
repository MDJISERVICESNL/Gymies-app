#!/usr/bin/env bash
# Reset wachtwoord van BEIDE demo-accounts (demo@gymies.nl + demo-klant@gymies.nl) naar demo123!
# Gebruik: bash reset_both_demo_accounts.sh [wachtwoord]

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
NEW_PASS="${1:-demo123!}"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/store/backend/scripts/reset_both_demo_accounts.php"

scp -q "${SSH_OPTS[@]}" "$PHP_SCRIPT" "$SSH_TARGET:/tmp/reset_both_demo.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php /tmp/reset_both_demo.php $REMOTE_LARAVEL '$NEW_PASS' && rm -f /tmp/reset_both_demo.php"
echo ""
echo "Login met: demo@gymies.nl / $NEW_PASS  (trainer)"
echo "         demo-klant@gymies.nl / $NEW_PASS  (klant)"
