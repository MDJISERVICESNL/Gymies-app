#!/usr/bin/env bash
#
# Alleen SaaS 2.0 migraties: legacy tabellen droppen + SaaS-model toepassen.
# Gebruikt dezelfde SSH key als upload_backend.sh.
#
# Gebruik:
#   SSH_TARGET=gymies ./scripts/run_saas_migrations_ssh.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
REMOTE_STAGING="${REMOTE_STAGING:-~/gymies_migrate_saas}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

FILES=(
  alter_gymies_drop_legacy_wallet_payout.sql
  alter_gymies_saas_plans_only.sql
  alter_gymies_saas_plans_seed.sql
  alter_gymies_saas_subscriptions_fix.sql
  alter_gymies_saas_rest.sql
)

echo "=== Gymies SaaS: drop legacy + SaaS migraties ==="
echo "SSH_TARGET: $SSH_TARGET"
echo ""

echo "[1] Runner + SQL naar server..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING/gymies_deploy"
scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/run_migrate_gymies_sql_server.php" "$SSH_TARGET:$REMOTE_STAGING/gymies_deploy/"
for f in "${FILES[@]}"; do
  if [[ -f "$PROJECT_DIR/database/$f" ]]; then
    scp "${SSH_OPTS[@]}" "$PROJECT_DIR/database/$f" "$SSH_TARGET:$REMOTE_STAGING/gymies_deploy/"
  else
    echo "WARN: ontbreekt: database/$f"
  fi
done

echo "[2] Kopiëren naar $REMOTE_LARAVEL/gymies_deploy (sudo)..."
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo mkdir -p $REMOTE_LARAVEL/gymies_deploy && sudo cp -r $REMOTE_STAGING/gymies_deploy/* $REMOTE_LARAVEL/gymies_deploy/"

echo "[3] SQL uitvoeren (volgorde: drop → saas)..."
for f in "${FILES[@]}"; do
  echo "  → $f"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/$f" || true
done

echo "[4] Staging opruimen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "rm -rf $REMOTE_STAGING"

echo ""
echo "=== Klaar. Daarna: backend upload + artisan clear ==="
echo "  ./scripts/upload_backend.sh"
echo "  # composer moet als www-data (vendor/ is niet schrijfbaar voor Gymiesagent):"
echo "  ./scripts/server_composer_dump_autoload.sh"
echo "  # of handmatig:"
echo "  ssh -t -i $SSH_KEY $SSH_TARGET 'cd $REMOTE_LARAVEL && sudo -u www-data composer dump-autoload -o'"
echo ""
