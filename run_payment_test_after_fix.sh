#!/usr/bin/env bash
# 1. Wis auth-blokkade  2. Reset demo wachtwoorden  3. Test betaling
set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== 1. Wis auth-blokkade + 2. Reset demo wachtwoorden ==="
scp -q "${SSH_OPTS[@]}" "$SCRIPT_DIR/store/backend/scripts/clear_auth_block.php" "$SCRIPT_DIR/store/backend/scripts/reset_both_demo_accounts.php" "$SSH_TARGET:/tmp/"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php /tmp/clear_auth_block.php $REMOTE_LARAVEL && sudo -u www-data php /tmp/reset_both_demo_accounts.php $REMOTE_LARAVEL 'demo123!' && rm -f /tmp/clear_auth_block.php /tmp/reset_both_demo_accounts.php"
echo ""

echo "=== 3. Betalingstest (vanaf lokale machine) ==="
bash "$SCRIPT_DIR/test_booking_payment_full.sh" 'demo123!'
