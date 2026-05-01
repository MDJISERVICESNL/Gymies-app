#!/usr/bin/env bash
# Zet demo-accounts goed: demo-klant als klant, demo-trainer als trainer, wachtwoord demo123!
set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHP_SCRIPT="$SCRIPT_DIR/store/backend/scripts/fix_demo_accounts.php"

scp -q "${SSH_OPTS[@]}" "$PHP_SCRIPT" "$SSH_TARGET:/tmp/fix_demo_accounts.php"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php /tmp/fix_demo_accounts.php $REMOTE_LARAVEL; rm -f /tmp/fix_demo_accounts.php"
