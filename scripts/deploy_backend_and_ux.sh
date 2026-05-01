#!/usr/bin/env bash
# Eerst backend deployen, daarna Flutter web (UX) naar de server.
# Gebruik: ./scripts/deploy_backend_and_ux.sh
#
# Optioneel: alleen backend  -> ./scripts/deploy_backend_and_ux.sh backend
#            alleen UX       -> ./scripts/deploy_backend_and_ux.sh ux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

MODE="${1:-all}"
case "$MODE" in
  backend|ux|all) ;;
  *)
    echo "Gebruik: $0 [backend|ux|all]"
    echo "  all     = eerst backend, dan UX (standaard)"
    echo "  backend = alleen backend uploaden"
    echo "  ux      = alleen Flutter web build + sync"
    exit 1
    ;;
esac

# Zelfde default als upload_backend.sh / set_app_url_on_server.sh
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
# Zelfde root als upload_backend.sh — sync_gymies_web.sh deployt naar $REMOTE_LARAVEL/public
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

# sync_gymies_web.sh draait als subprocess: zonder export ziet het script SSH_TARGET niet
export SSH_KEY SSH_TARGET REMOTE_LARAVEL

echo "=== Deploy: $MODE ==="
echo ""

if [[ "$MODE" == "all" || "$MODE" == "backend" ]]; then
  echo "--- 1) Backend deployen ---"
  "$SCRIPT_DIR/upload_backend.sh"
  echo ""
  echo "--- 1b) APP_URL + GYMIES_PUBLIC_URL (https://www.gymies.nl) op server ---"
  "$SCRIPT_DIR/set_app_url_on_server.sh"
  echo ""
  echo "Optioneel (nieuwe features): voer op de server uit om sluitreden + gebruikersnotities te activeren:"
  echo "  ssh -i $SSH_KEY $SSH_TARGET"
  echo "  cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_ticket_close_reason.sql"
  echo "  cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_admin_user_notes.sql"
  echo ""
fi

if [[ "$MODE" == "all" || "$MODE" == "ux" ]]; then
  echo "--- 2) UX (Flutter web) deployen ---"
  "$SCRIPT_DIR/sync_gymies_web.sh"
  echo ""
fi

echo "=== Deploy klaar. ==="
echo "Admin Control Tower (UX): https://www.gymies.nl/gymies/#/vault-console-portal"
