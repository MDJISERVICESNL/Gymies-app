#!/usr/bin/env bash
# =============================================================================
# Gymies deploy – backend + UX in één pipeline
# Aangeroepen via ./deploy.sh of direct: ./scripts/deploy_gymies.sh [all|backend|ux|migrate]
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

MODE="${1:-all}"
case "$MODE" in
  backend|ux|all|migrate|run-migrate) ;;
  *)
    echo "Gebruik: $0 [all|backend|ux|migrate|run-migrate]"
    echo "  all         = backend + APP_URL + UX (standaard)"
    echo "  backend     = alleen upload_backend + set_app_url"
    echo "  ux          = alleen Flutter web build + sync"
    echo "  migrate     = toon SQL-migrate commando's voor op de server"
    echo "  run-migrate = voer Pro/Elite migraties uit op de server (na backend deploy)"
    exit 1
    ;;
esac

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
export SSH_KEY SSH_TARGET REMOTE_LARAVEL

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  echo "Zet: export SSH_KEY=/pad/naar/jouw/key"
  exit 1
fi

if [[ "$MODE" == "migrate" ]]; then
  echo "=== Migrate (op server uitvoeren) ==="
  echo ""
  echo "ssh -i $SSH_KEY $SSH_TARGET"
  echo "cd $REMOTE_LARAVEL"
  echo ""
  echo "# Spoed Inval (volledig)"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval_status_extended.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval_standby.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval_extras.sql"
  echo ""
  echo "# Buddy Match (server-driven zoekstatus)"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_buddy_search_prefs.sql"
  echo ""
  echo "# Starter: onbeperkte sessies"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_starter_unlimited_sessions.sql"
  echo ""
  echo "# Storefront: Instagram handle"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_trainer_storefront_instagram.sql"
  echo ""
  echo "# Pro: subscription, upsell, pro suggestions"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_subscription_change_plan.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_upsell_settings.sql"
  echo ""
  echo "# Elite: trainer-trainer chat, locaties, teams, invites, groepsles/boeking locatie"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_trainer_trainer_chat.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_locations.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_location_blocks.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_teams.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_team_members.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_invites.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_group_sessions_bookings_location.sql"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_organisations_extra_settings.sql"
  echo ""
  echo "# Performance indexes (P1)"
  echo "sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_performance_indexes.sql"
  echo ""
  echo "sudo -u www-data php artisan route:clear && sudo -u www-data php artisan config:clear"
  echo ""
  exit 0
fi

if [[ "$MODE" == "run-migrate" ]]; then
  echo "=== Migraties uitvoeren op server ($SSH_TARGET) ==="
  echo ""
  ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$SSH_TARGET" "cd $REMOTE_LARAVEL && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval_status_extended.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval_standby.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_spoed_inval_extras.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_starter_unlimited_sessions.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_subscription_change_plan.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_upsell_settings.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_trainer_trainer_chat.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_locations.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_location_blocks.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_teams.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_team_members.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_invites.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gym_group_sessions_bookings_location.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_organisations_extra_settings.sql 2>/dev/null || true && \
    sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_performance_indexes.sql 2>/dev/null || true && \
    sudo -u www-data php artisan route:clear 2>/dev/null || true && \
    sudo -u www-data php artisan config:clear 2>/dev/null || true && \
    echo 'Migraties voltooid.'"
  echo ""
  exit 0
fi

echo "=============================================="
echo "  Gymies deploy – $MODE"
echo "  SSH: $SSH_KEY → $SSH_TARGET"
echo "  Laravel: $REMOTE_LARAVEL"
echo "=============================================="
echo ""

if [[ "$MODE" == "all" || "$MODE" == "backend" ]]; then
  echo "--- [1/3] Backend (Controllers + gymies_deploy) ---"
  "$SCRIPT_DIR/upload_backend.sh"
  echo ""
  echo "--- [2/3] APP_URL + GYMIES_PUBLIC_URL ---"
  "$SCRIPT_DIR/set_app_url_on_server.sh"
  echo ""

  echo "--- [2a] Buddy Match migratie ---"
  ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$SSH_TARGET" \
    "cd $REMOTE_LARAVEL && sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_buddy_search_prefs.sql 2>/dev/null || true" \
    || true
  echo ""
  echo "--- [2b] Starter unlimited sessies ---"
  ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$SSH_TARGET" \
    "cd $REMOTE_LARAVEL && sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_starter_unlimited_sessions.sql 2>/dev/null || true" \
    || true
  echo ""

  if [[ "${DEPLOY_COMPOSER:-}" == "1" ]]; then
    echo "--- [2c] composer dump-autoload (optioneel) ---"
    ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$SSH_TARGET" \
      "cd $REMOTE_LARAVEL && (sudo -u www-data composer dump-autoload -o 2>/dev/null || composer dump-autoload -o)" \
      || true
    echo ""
  fi
fi

if [[ "$MODE" == "all" || "$MODE" == "ux" ]]; then
  echo "--- [3/3] UX (Flutter web) ---"
  if ! command -v flutter >/dev/null 2>&1; then
    echo "ERROR: flutter niet in PATH. Installeer Flutter of voeg toe aan PATH."
    exit 1
  fi
  "$SCRIPT_DIR/sync_gymies_web.sh"
  echo ""
  echo "--- [3b] GYMIES_SESSION_SKIP_USER_AGENT_CHECK op server ---"
  "$SCRIPT_DIR/set_session_skip_user_agent_on_server.sh" || true
  echo ""
fi

echo "=== Deploy klaar. ==="
echo "  Site:    https://www.gymies.nl/"
echo "  API:     https://www.gymies.nl/api/gymies/"
echo "  Migrate: $0 migrate"
echo ""
