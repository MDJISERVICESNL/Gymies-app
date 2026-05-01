#!/usr/bin/env bash
#
# Alle Gymies DB-migraties op de server uitvoeren via SSH (runner + alter_*.sql).
# Gebruik dezelfde SSH key en target als upload_backend.sh.
#
# Gebruik (vanaf projectmap):
#   SSH_TARGET=gymies ./scripts/run_all_gymies_migrations_ssh.sh
# Of:
#   SSH_TARGET=Gymiesagent@148.113.197.164 SSH_KEY=~/.ssh/id_ed25519_gymies ./scripts/run_all_gymies_migrations_ssh.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
REMOTE_STAGING="${REMOTE_STAGING:-~/gymies_migrate}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  echo "Zet SSH_KEY of plaats de key daar (bijv. id_ed25519_gymies of Gymies)."
  exit 1
fi

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET niet gezet. Bijv. export SSH_TARGET=gymies"
  exit 1
fi

SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== Gymies: alle migraties uitvoeren op server ==="
echo "SSH_TARGET: $SSH_TARGET"
echo "REMOTE_LARAVEL: $REMOTE_LARAVEL"
echo ""

# 1) Staging op server + runner + alle alter_*.sql uploaden
echo "[1] Runner en alter_*.sql naar server kopiëren..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING/gymies_deploy"
scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/run_migrate_gymies_sql_server.php" "$SSH_TARGET:$REMOTE_STAGING/gymies_deploy/"
for f in "$PROJECT_DIR"/database/alter_gymies_*.sql; do
  [[ -f "$f" ]] && scp "${SSH_OPTS[@]}" "$f" "$SSH_TARGET:$REMOTE_STAGING/gymies_deploy/"
done

# 2) Naar Laravel gymies_deploy kopiëren (sudo)
echo "[2] Bestanden naar $REMOTE_LARAVEL/gymies_deploy kopiëren (sudo)..."
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo mkdir -p $REMOTE_LARAVEL/gymies_deploy && sudo cp -r $REMOTE_STAGING/gymies_deploy/* $REMOTE_LARAVEL/gymies_deploy/ && echo 'Kopiëren klaar.'"

# 3) Alle alter_*.sql uitvoeren in alfabetische volgorde (lijst lokaal)
echo "[3] Alter-migraties uitvoeren..."
sorted=()
while IFS= read -r b; do sorted+=( "$b" ); done < <(for f in "$PROJECT_DIR"/database/alter_gymies_*.sql; do [[ -f "$f" ]] && basename "$f"; done | sort)
for basename in "${sorted[@]}"; do
  echo "  → $basename"
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/$basename" || true
done

# 4) Staging opruimen
echo "[4] Staging opruimen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "rm -rf $REMOTE_STAGING"

echo ""
echo "=== Klaar. Alle Gymies alter-migraties zijn uitgevoerd. ==="
