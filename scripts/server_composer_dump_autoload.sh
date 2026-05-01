#!/usr/bin/env bash
# Composer dump-autoload op de server als www-data (vendor/ is meestal niet schrijfbaar voor Gymiesagent).
# Gebruik: SSH_TARGET=gymies ./scripts/server_composer_dump_autoload.sh
set -euo pipefail
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
echo "=== composer dump-autoload -o als www-data op $SSH_TARGET ==="
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data composer dump-autoload -o"
echo "=== Klaar. ==="
