#!/usr/bin/env bash
# =============================================================================
# Gymies: alles deployen op de server (backend + UX).
# =============================================================================
# Gebruik:
#   ./scripts/deploy_all.sh              # backend + UX (standaard)
#   ./scripts/deploy_all.sh backend      # alleen backend
#   ./scripts/deploy_all.sh ux           # alleen Flutter web (UX)
#
# Optioneel (voor deploy naar Gymies server):
#   export SSH_KEY="$HOME/.ssh/Gymies"
#   export SSH_TARGET="user@gymies-server"
#   export REMOTE_LARAVEL="/var/www/gymies.nl/laravel"
#   export APP_PATH=""             # leeg = root (standaard)
#   export GYMIES_DOMAIN="gymies.nl"
#   ./scripts/deploy_all.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# --- Configuratie (overschrijf via env) ---
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies.nl/laravel}"
APP_PATH="${APP_PATH:-}"
GYMIES_DOMAIN="${GYMIES_DOMAIN:-gymies.nl}"

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

echo "=============================================="
echo "  Gymies deploy: $MODE"
echo "  Server: $SSH_TARGET"
echo "  Laravel: $REMOTE_LARAVEL"
echo "  UX pad:  ${APP_PATH:-/ (root)}"
echo "=============================================="
echo ""

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET niet gezet. Bijv. export SSH_TARGET=gymies"
  exit 1
fi
if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH-sleutel niet gevonden: $SSH_KEY"
  echo "Pas aan of export: SSH_KEY=\"\$HOME/.ssh/id_ed25519_gymies\""
  exit 1
fi

# Doorgeven aan subscripts (upload_backend, sync_gymies_web)
export SSH_KEY SSH_TARGET REMOTE_LARAVEL APP_PATH GYMIES_DOMAIN

# --- 1) Backend ---
if [[ "$MODE" == "all" || "$MODE" == "backend" ]]; then
  echo "--- [1/2] Backend deployen ---"
  "$SCRIPT_DIR/upload_backend.sh"
  echo ""
fi

# --- 2) UX (Flutter web) ---
if [[ "$MODE" == "all" || "$MODE" == "ux" ]]; then
  echo "--- [2/2] UX (Flutter web) deployen ---"
  "$SCRIPT_DIR/sync_gymies_web.sh"
  echo ""
fi

echo "=============================================="
echo "  Deploy afgerond."
echo "=============================================="
echo ""
echo "  UX:     https://$GYMIES_DOMAIN/"
echo "  API:    https://$GYMIES_DOMAIN/api/gymies"
echo ""
echo "UX-backup (voor rollback):"
echo "  ./scripts/backup_ux_to_server.sh    # bouwt UX en slaat tarball op server op (~/backups/gymies_ux/)"
echo ""
echo "Optioneel – database-alters (eenmalig indien nog niet gedaan):"
echo "  ssh -i $SSH_KEY $SSH_TARGET"
echo "  cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_booking_reschedule_request.sql"
echo "  cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_booking_reschedule_symmetric.sql"
echo ""
