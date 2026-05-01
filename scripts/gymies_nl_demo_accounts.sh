#!/usr/bin/env bash
# =============================================================================
# Gymies.nl — demo-accounts + SQL toepassen op de server
# =============================================================================
#
# OFFICIËLE DEMO (zie ook database/seed_gymies_demo_account_full.sql):
#
#   Trainer   demo@gymies.nl
#   Wachtwoord: password
#   → Actief (niet geschorst), Pro-abonnement (subscription_plan + gymies_subscriptions)
#
#   Klant     demo-klant@gymies.nl
#   Wachtwoord: password
#
# Bcrypt in seed komt overeen met het wachtwoord "password" (Laravel $2y$ hash).
#
# Gebruik:
#   ./scripts/gymies_nl_demo_accounts.sh info
#       Alleen deze tekst + credentials tonen.
#
#   ./scripts/gymies_nl_demo_accounts.sh apply-trainer-pro
#       Uploadt database/gymies_demo_ensure_trainer_pro_active.sql en voert het uit
#       op de server (alleen trainer actief + Pro; user moet al bestaan).
#
#   ./scripts/gymies_nl_demo_accounts.sh apply-full
#       Uploadt database/seed_gymies_demo_account_full.sql en voert het uit
#       (volledige demo: profielen, boekingen, chat, dossier, …).
#
# Omgeving (zelfde als deploy):
#   SSH_KEY, SSH_TARGET (default: gymies), REMOTE_LARAVEL (default: /var/www/gymies)
#
# Op de server: scripts/run_migrate_gymies_sql_server.php wordt mee-geüpload als het
# daar nog ontbreekt, daarna: sudo -u www-data php scripts/run_migrate_gymies_sql_server.php <sql>
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
REMOTE_SQL_DIR="${REMOTE_LARAVEL}/gymies_deploy"
MIGRATE_REL="scripts/run_migrate_gymies_sql_server.php"

SQL_FULL="${ROOT}/database/seed_gymies_demo_account_full.sql"
SQL_PRO="${ROOT}/database/gymies_demo_ensure_trainer_pro_active.sql"
MIGRATE_LOCAL="${ROOT}/scripts/run_migrate_gymies_sql_server.php"

ssh_base=(ssh -i "$SSH_KEY" -o BatchMode=yes "$SSH_TARGET")
scp_base=(scp -i "$SSH_KEY")

info() {
  cat <<'EOF'

=== Gymies.nl demo-accounts ================================================

  Trainer :  demo@gymies.nl
  Klant   :  demo-klant@gymies.nl
  Wachtwoord (beiden):  password

  Trainer staat op Pro + actief abonnement na:
    • apply-full   → database/seed_gymies_demo_account_full.sql
    • apply-trainer-pro → database/gymies_demo_ensure_trainer_pro_active.sql
      (alleen als demo@gymies.nl al bestaat)

  Site: https://www.gymies.nl/

==========================================================================
EOF
}

run_remote_sql() {
  local filename="$1"
  local remote_path="${REMOTE_SQL_DIR}/${filename}"
  echo "→ Upload ${filename} naar ${SSH_TARGET}:${remote_path}"
  "${scp_base[@]}" "${ROOT}/database/${filename}" "${SSH_TARGET}:~/gymies_demo_upload_${filename}"

  [[ -f "$MIGRATE_LOCAL" ]] || { echo "Ontbreekt migratie-PHP: $MIGRATE_LOCAL" >&2; exit 1; }
  echo "→ Upload run_migrate_gymies_sql_server.php (indien nodig op server)"
  "${scp_base[@]}" "$MIGRATE_LOCAL" "${SSH_TARGET}:~/gymies_demo_upload_run_migrate.php"

  echo "→ Installeren en uitvoeren op server"
  "${ssh_base[@]}" bash -s -- "$REMOTE_LARAVEL" "$REMOTE_SQL_DIR" "$filename" "$MIGRATE_REL" <<'REMOTE'
set -euo pipefail
REMOTE_LARAVEL="$1"
REMOTE_SQL_DIR="$2"
FILENAME="$3"
MIGRATE_REL="$4"
MIGRATE_ABS="${REMOTE_LARAVEL}/${MIGRATE_REL}"
sudo mkdir -p "$REMOTE_SQL_DIR"
sudo mkdir -p "$(dirname "$MIGRATE_ABS")"
sudo cp "$HOME/gymies_demo_upload_${FILENAME}" "${REMOTE_SQL_DIR}/${FILENAME}"
sudo chown www-data:www-data "${REMOTE_SQL_DIR}/${FILENAME}" 2>/dev/null || true
sudo cp "$HOME/gymies_demo_upload_run_migrate.php" "$MIGRATE_ABS"
sudo chown www-data:www-data "$MIGRATE_ABS" 2>/dev/null || true
rm -f "$HOME/gymies_demo_upload_run_migrate.php"
cd "$REMOTE_LARAVEL"
sudo -u www-data php "$MIGRATE_REL" "${REMOTE_SQL_DIR}/${FILENAME}"
rm -f "$HOME/gymies_demo_upload_${FILENAME}"
echo "Klaar."
REMOTE
}

case "${1:-}" in
  info|"")
    info
    if [[ "${1:-}" == "" ]]; then
      echo "Tip: voer uit met argument: info | apply-trainer-pro | apply-full"
    fi
    ;;
  apply-trainer-pro)
    info
    [[ -f "$SQL_PRO" ]] || { echo "Ontbreekt: $SQL_PRO" >&2; exit 1; }
    run_remote_sql "gymies_demo_ensure_trainer_pro_active.sql"
    ;;
  apply-full)
    info
    [[ -f "$SQL_FULL" ]] || { echo "Ontbreekt: $SQL_FULL" >&2; exit 1; }
    run_remote_sql "seed_gymies_demo_account_full.sql"
    ;;
  -h|--help|help)
    info
    echo "Argumenten: info | apply-trainer-pro | apply-full | help"
    ;;
  *)
    echo "Onbekend argument: $1" >&2
    echo "Gebruik: $0 info | apply-trainer-pro | apply-full | help" >&2
    exit 1
    ;;
esac
