#!/usr/bin/env bash
# ============================================================
# GYMIES Backend Deploy
# Pakt ALLEEN bestanden uit /Users/sara/Desktop/GYMIES - APP/
# Gebruikt altijd Amazonekey.pem uit diezelfde map.
# ============================================================
# Gebruik:
#   cd "/Users/sara/Desktop/GYMIES - APP"
#   ./scripts/upload_backend.sh            # volledige backend deploy
#   ./scripts/upload_backend.sh seed       # alleen seed uploaden
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# --- Vaste configuratie: altijd vanuit GYMIES - APP, altijd Amazonekey ---
SSH_KEY="$PROJECT_DIR/Amazonekey.pem"
SSH_TARGET="ubuntu@gymies.nl"
REMOTE_LARAVEL="/var/www/gymies"
REMOTE_STAGING="~/gymies_upload"

SEED_ONLY=false
[[ "${1:-}" == "seed" || "${1:-}" == "--seed" ]] && SEED_ONLY=true

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  exit 1
fi

SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

if $SEED_ONLY; then
  echo "=== Alleen seedbestand uploaden naar $SSH_TARGET ==="
  echo ""
  echo "[1] Staging-map aanmaken..."
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING/gymies_deploy"
  echo "[2] Seedbestand uploaden..."
  scp "${SSH_OPTS[@]}" database/seed_gymies_dummy_trainers_server.sql "$SSH_TARGET:$REMOTE_STAGING/gymies_deploy/"
  echo "[3] Kopiëren naar Laravel (sudo – wachtwoord wordt gevraagd)..."
  ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo mkdir -p $REMOTE_LARAVEL/gymies_deploy && sudo cp $REMOTE_STAGING/gymies_deploy/seed_gymies_dummy_trainers_server.sql $REMOTE_LARAVEL/gymies_deploy/ && echo 'Seedbestand gekopieerd.'"
  echo "[4] Staging opruimen..."
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "rm -rf $REMOTE_STAGING"
  echo ""
  echo "=== Klaar. Seed op server draaien: ==="
  echo "  ssh -i \$SSH_KEY \$SSH_TARGET"
  echo "  cd $REMOTE_LARAVEL && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_dummy_trainers_server.sql"
  exit 0
fi

echo "=== Backend upload naar $SSH_TARGET ==="
echo "Staging (op server): $REMOTE_STAGING"
echo "Laravel: $REMOTE_LARAVEL"
echo ""

echo "[1] Lokale staging en één rsync-verbinding (minder kans op 'Connection reset')..."
TMP_STAGING=$(mktemp -d)
trap "rm -rf '$TMP_STAGING'" EXIT
mkdir -p "$TMP_STAGING/Controllers" "$TMP_STAGING/Middleware" "$TMP_STAGING/Traits" "$TMP_STAGING/Http/Requests" "$TMP_STAGING/gymies_deploy" \
  "$TMP_STAGING/Services" "$TMP_STAGING/Events/Gymies" "$TMP_STAGING/Helpers" "$TMP_STAGING/Config"
if [[ -f backend/config/gymies.php ]]; then
  cp backend/config/gymies.php "$TMP_STAGING/Config/"
fi

# Copy all .php files from backend/Controllers/ (non-Gymies subdirectory)
# This automatically includes any new controllers without needing to update this list
find backend/Controllers -maxdepth 1 -name "*.php" -type f -exec cp {} "$TMP_STAGING/Controllers/" \;

# Also copy all controllers from the Gymies/ subdirectory
if [[ -d backend/Controllers/Gymies ]]; then
  find backend/Controllers/Gymies -maxdepth 1 -name "*.php" -type f -exec cp {} "$TMP_STAGING/Controllers/" \;
fi

# Copy controller Traits (namespace App\Http\Controllers\Gymies\Traits)
mkdir -p "$TMP_STAGING/Controllers/Traits"
if [[ -d backend/Controllers/Traits ]]; then
  find backend/Controllers/Traits -name "*.php" -type f -exec cp {} "$TMP_STAGING/Controllers/Traits/" \;
fi

# Services / Events / Helpers (PDF, chat broadcast) → op server naar app/
if [[ -f backend/Services/GymiesInvoicePdfGenerator.php ]]; then
  cp backend/Services/GymiesInvoicePdfGenerator.php "$TMP_STAGING/Services/"
fi
if [[ -f backend/Events/GymiesChatMessageSent.php ]]; then
  cp backend/Events/GymiesChatMessageSent.php "$TMP_STAGING/Events/Gymies/"
fi
if [[ -f backend/Helpers/GymiesChatBroadcast.php ]]; then
  cp backend/Helpers/GymiesChatBroadcast.php "$TMP_STAGING/Helpers/"
fi
if [[ -f backend/Helpers/GymiesSupportSync.php ]]; then
  cp backend/Helpers/GymiesSupportSync.php "$TMP_STAGING/Helpers/"
fi
if ls backend/Traits/*.php 1>/dev/null 2>&1; then
  cp backend/Traits/*.php "$TMP_STAGING/Traits/"
fi
if ls backend/Http/Requests/*.php 1>/dev/null 2>&1; then
  cp backend/Http/Requests/*.php "$TMP_STAGING/Http/Requests/"
fi

cp backend/Middleware/GymiesAuthMiddleware.php \
   backend/Middleware/GymiesRateLimitMiddleware.php \
   backend/Middleware/GymiesApiErrorLoggingMiddleware.php \
   backend/Middleware/GymiesIdempotencyMiddleware.php \
   backend/Middleware/GymiesAdminIpAllowlistMiddleware.php \
   backend/Middleware/GymiesAdminCapabilityMiddleware.php \
   backend/Middleware/GymiesDebugAuthMiddleware.php \
   "$TMP_STAGING/Middleware/"

# Optioneel: smoketest Mollie Connect + Reverb (staat in backend/gymies_deploy)
if [[ -f backend/gymies_deploy/test_mollie_connect_config.php ]]; then
  cp backend/gymies_deploy/test_mollie_connect_config.php "$TMP_STAGING/gymies_deploy/"
fi
if [[ -f backend/gymies_deploy/test_reverb_config.php ]]; then
  cp backend/gymies_deploy/test_reverb_config.php "$TMP_STAGING/gymies_deploy/"
fi
if [[ -f backend/gymies_deploy/alter_gymies_trainer_bank_accounts_client_pays_fee.sql ]]; then
  cp backend/gymies_deploy/alter_gymies_trainer_bank_accounts_client_pays_fee.sql "$TMP_STAGING/gymies_deploy/"
fi

cp backend/routes_gymies_snippet.php \
   backend/routes_gymies_full.php \
   scripts/fix_gymies_all_middleware.php \
   scripts/fix_gymies_routes.php \
   scripts/gymies_deploy/fix_gymies_csrf_except.php \
   scripts/gymies_deploy/fix_gymies_web_routes_force.php \
   scripts/run_migrate_gymies_sql_server.php \
   scripts/gymies_deploy/create_client_progress_table.php \
   scripts/gymies_deploy/gymies_send_test_mail.php \
   database/create_gymies_tables.sql \
   database/create_gymies_tables_if_not_exists.sql \
   database/gymies_complete_schema.sql \
   database/seed_gymies_dummy_trainers_server.sql \
   database/seed_gymies_demo_account_full.sql \
   database/seed_gymies_dummy_trainers_storefront.sql \
   database/seed_gymies_demo_qr_test_booking.sql \
   database/seed_gymies_test_group_session_ux.sql \
   database/seed_gymies_admin_dummy.sql \
   database/seed_gymies_jamai1210_full_dummy.sql \
   database/alter_gymies_jamai1210_studio_zaldion75_sessie.sql \
   database/alter_gymies_fix_zaldion75_klant_jamai1210_trainer.sql \
   database/alter_gymies_add_klant_trainer_fields.sql \
   database/alter_gymies_all_additions.sql \
   database/alter_gymies_admin_werkbak.sql \
   database/alter_gymies_filter_definitions.sql \
   database/alter_gymies_filter_definitions_remove_trainer_plan.sql \
   database/alter_gymies_admin_ip_add_62_163_72_25.sql \
   database/alter_gymies_admin_password_reset.sql \
   database/alter_gymies_mollie_oauth_states.sql \
   database/alter_gymies_ticket_close_reason.sql \
   database/alter_gymies_admin_user_notes.sql \
   database/alter_gymies_support_ticket_contact.sql \
   database/alter_gymies_booking_confirmation_note.sql \
   database/alter_gymies_booking_reschedule_request.sql \
   database/alter_gymies_booking_reschedule_symmetric.sql \
   database/alter_gymies_email_verification.sql \
   database/alter_gymies_email_verification_link_token.sql \
   database/alter_gymies_email_verified_backfill_legacy.sql \
   database/alter_gymies_notification_read_at.sql \
   database/alter_gymies_future_tables.sql \
   database/alter_gymies_users_newsletter.sql \
   database/alter_gymies_group_sessions.sql \
   database/alter_gymies_group_sessions_add_status.sql \
   database/alter_gymies_disputes_resolution.sql \
   database/alter_gymies_packages_admin.sql \
   database/alter_gymies_broadcasts.sql \
   database/alter_gymies_cancellation_policy.sql \
   database/alter_gymies_direct_book.sql \
   database/alter_gymies_group_sessions_crowdfund.sql \
   database/alter_gymies_group_sessions_waitlist_enabled.sql \
   database/alter_gymies_incident_resolution.sql \
   database/alter_gymies_moderation.sql \
   database/alter_gymies_control_tower.sql \
   database/alter_gymies_search_demand.sql \
   database/alter_gymies_mollie_payment_tables.sql \
   database/alter_gymies_drop_legacy_wallet_payout.sql \
   database/alter_gymies_saas_model.sql \
   database/alter_gymies_saas_plans_only.sql \
   database/alter_gymies_saas_plans_seed.sql \
   database/alter_gymies_saas_subscriptions_fix.sql \
   database/alter_gymies_saas_rest.sql \
   database/alter_gymies_stickiness_features.sql \
   database/alter_gymies_master_spec_additions.sql \
   database/alter_gymies_womens_safety.sql \
   database/alter_gymies_trainer_pricing_surcharges.sql \
   database/alter_gymies_client_progress.sql \
   database/alter_gymies_client_progress_simple.sql \
   database/alter_gymies_trainer_storefront.sql \
   database/alter_gymies_trainer_storefront_instagram.sql \
   database/alter_gymies_client_dossier.sql \
   database/alter_gymies_client_dossier_share_with_client.sql \
   database/alter_gymies_promo_codes_trainer.sql \
   database/alter_gymies_trainer_booking_window.sql \
   database/alter_gymies_fix_plans_and_site_subscriptions.sql \
   database/alter_gymies_starter_unlimited_sessions.sql \
   database/alter_gymies_trainer_media.sql \
   database/alter_gymies_trainer_invoices_numbering_required_fields.sql \
   database/alter_gymies_trainer_invoices_numbering_finalize.sql \
   database/alter_gymies_ticket_berichten_sync.sql \
   database/alter_gymies_trainer_pro_suggestion_tables.sql \
   database/alter_gymies_payout_settings.sql \
   database/alter_gymies_group_sessions_add_status_key_only.sql \
   database/alter_gymies_gym_organisations.sql \
   database/alter_gymies_add_trainer_balance_cents_only.sql \
   database/alter_gymies_trainer_dossier_session_entries_goals.sql \
   database/alter_gymies_packages_subscription_fields.sql \
   database/alter_gymies_pro_client_health_and_upsell.sql \
   database/alter_gymies_users_add_register_columns.sql \
   database/alter_gymies_buddy_search_prefs.sql \
   database/alter_gymies_spoed_inval.sql \
   database/alter_gymies_spoed_inval_status_extended.sql \
   database/alter_gymies_spoed_inval_standby.sql \
   database/alter_gymies_spoed_inval_extras.sql \
   database/alter_gymies_subscription_change_plan.sql \
   database/alter_gymies_subscription_yearly_and_settings.sql \
   database/alter_gymies_upsell_settings.sql \
   database/alter_gymies_trainer_trainer_chat.sql \
   database/alter_gym_locations.sql \
   database/alter_gym_location_blocks.sql \
   database/alter_gym_teams.sql \
   database/alter_gym_team_members.sql \
   database/alter_gym_invites.sql \
   database/alter_gym_group_sessions_bookings_location.sql \
   database/alter_gymies_organisations_extra_settings.sql \
   database/alter_gymies_performance_indexes.sql \
   database/create_gymies_ambassador_tables.sql \
   "$TMP_STAGING/gymies_deploy/"
if [[ -f gymies_deploy/BACKEND_SELF_HEAL_AND_FEATURES.md ]]; then
  cp gymies_deploy/BACKEND_SELF_HEAL_AND_FEATURES.md "$TMP_STAGING/gymies_deploy/" 2>/dev/null || true
fi
if [[ -f scripts/gymies_deploy/TRAINEROPS_DOSSIER_PROGRESS_PROMO.md ]]; then
  cp scripts/gymies_deploy/TRAINEROPS_DOSSIER_PROGRESS_PROMO.md "$TMP_STAGING/gymies_deploy/" 2>/dev/null || true
fi

echo "[2] Bestanden uploaden (één rsync-verbinding)..."
rsync -avz --no-perms --no-owner --no-group \
  -e "ssh -o IdentitiesOnly=yes -i '$SSH_KEY'" \
  "$TMP_STAGING/" \
  "$SSH_TARGET:$REMOTE_STAGING/"

echo "[3] Kopiëren naar Laravel, cache legen, staging opruimen (één SSH-sessie – wachtwoord kan worden gevraagd)..."
echo "    → Als sudo om een wachtwoord vraagt: intypen en Enter."
sleep 2
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo mkdir -p $REMOTE_LARAVEL/app/Http/Controllers/Gymies/Traits $REMOTE_LARAVEL/app/Http/Middleware $REMOTE_LARAVEL/app/Http/Requests $REMOTE_LARAVEL/app/Traits $REMOTE_LARAVEL/gymies_deploy $REMOTE_LARAVEL/app/Services $REMOTE_LARAVEL/app/Events/Gymies $REMOTE_LARAVEL/app/Helpers $REMOTE_LARAVEL/config && \
  if ls $REMOTE_STAGING/Config/gymies.php 1>/dev/null 2>&1; then sudo cp $REMOTE_STAGING/Config/gymies.php $REMOTE_LARAVEL/config/; fi && \
  sudo cp $REMOTE_STAGING/Controllers/*.php $REMOTE_LARAVEL/app/Http/Controllers/Gymies/ && \
  if ls $REMOTE_STAGING/Controllers/Traits/*.php 1>/dev/null 2>&1; then sudo cp $REMOTE_STAGING/Controllers/Traits/*.php $REMOTE_LARAVEL/app/Http/Controllers/Gymies/Traits/; fi && \
  if ls $REMOTE_STAGING/Services/*.php 1>/dev/null 2>&1; then sudo cp $REMOTE_STAGING/Services/*.php $REMOTE_LARAVEL/app/Services/; fi && \
  if ls $REMOTE_STAGING/Events/Gymies/*.php 1>/dev/null 2>&1; then sudo cp $REMOTE_STAGING/Events/Gymies/*.php $REMOTE_LARAVEL/app/Events/Gymies/; fi && \
  if ls $REMOTE_STAGING/Helpers/*.php 1>/dev/null 2>&1; then sudo cp $REMOTE_STAGING/Helpers/*.php $REMOTE_LARAVEL/app/Helpers/; fi && \
  sudo rm -rf $REMOTE_LARAVEL/app/Http/Controllers/gymies && \
  if ls $REMOTE_STAGING/Traits/*.php 1>/dev/null 2>&1; then sudo cp $REMOTE_STAGING/Traits/*.php $REMOTE_LARAVEL/app/Traits/; fi && \
  if ls $REMOTE_STAGING/Http/Requests/*.php 1>/dev/null 2>&1; then sudo cp $REMOTE_STAGING/Http/Requests/*.php $REMOTE_LARAVEL/app/Http/Requests/; fi && \
  sudo cp $REMOTE_STAGING/Middleware/*.php $REMOTE_LARAVEL/app/Http/Middleware/ && \
  sudo cp $REMOTE_STAGING/gymies_deploy/* $REMOTE_LARAVEL/gymies_deploy/ && \
  echo 'Bestanden gekopieerd.' && \
  cd $REMOTE_LARAVEL && php artisan route:clear 2>/dev/null || true && php artisan config:clear 2>/dev/null || true && \
  rm -rf $REMOTE_STAGING && \
  echo 'Cache geleegd en staging opgeruimd.' && \
  echo '[4] Permissions fixen (www-data)...' && \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Http/Controllers/Gymies/ && \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Http/Controllers/Gymies/Traits/ 2>/dev/null; \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Http/Middleware/ && \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Traits/ 2>/dev/null; \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Services/ 2>/dev/null; \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Events/ 2>/dev/null; \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Helpers/ 2>/dev/null; \
  sudo chown -R www-data:www-data $REMOTE_LARAVEL/app/Http/Requests/ 2>/dev/null; \
  sudo chown www-data:www-data $REMOTE_LARAVEL/config/gymies.php 2>/dev/null; \
  sudo chmod -R 644 $REMOTE_LARAVEL/app/Http/Controllers/Gymies/*.php && \
  sudo chmod 755 $REMOTE_LARAVEL/app/Http/Controllers/Gymies/ && \
  sudo chmod 775 $REMOTE_LARAVEL/storage/logs/ && \
  sudo chmod 664 $REMOTE_LARAVEL/storage/logs/laravel.log 2>/dev/null; \
  echo 'Permissions gefixt.' && \
  echo '[5] PHP-FPM herstarten...' && \
  sudo systemctl restart php8.4-fpm && \
  echo 'PHP-FPM herstart. Deploy compleet!'"

SSH_CMD="ssh -i \"$PROJECT_DIR/Amazonekey.pem\" ubuntu@gymies.nl"

echo ""
echo "=== Backend upload klaar. ==="
echo ""
echo "Als [3] faalde met 'Connection closed': bestanden staan al in ~/gymies_upload op de server."
echo "  Log in en voer handmatig uit:"
echo "  $SSH_CMD"
echo "  sudo cp ~/gymies_upload/Controllers/*.php /var/www/gymies/app/Http/Controllers/Gymies/"
echo "  sudo cp ~/gymies_upload/Middleware/*.php /var/www/gymies/app/Http/Middleware/"
echo "  sudo cp ~/gymies_upload/gymies_deploy/* /var/www/gymies/gymies_deploy/"
echo "  cd /var/www/gymies && php artisan route:clear && php artisan config:clear"
echo "  rm -rf ~/gymies_upload"
echo ""
echo "=== Na eerste deploy: routes + middleware activeren ==="
echo "  $SSH_CMD"
echo "  cd /var/www/gymies && sudo php gymies_deploy/fix_gymies_routes.php"
echo "  sudo php gymies_deploy/fix_gymies_all_middleware.php"
echo "  php artisan route:clear && php artisan config:clear"
echo ""
echo "=== Server inloggen ==="
echo "  $SSH_CMD"
