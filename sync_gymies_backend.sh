#!/usr/bin/env bash
set -euo pipefail

# Backend sync naar Gymies server.
# Gebruik: bash sync_gymies_backend.sh
#
# Overschrijft op server: Controllers/Gymies/*, Middleware, routes_gymies_full.php, scripts/*, migrations/*

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
REMOTE_STAGING="${REMOTE_STAGING:-~/gymies_backend_upload}"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/store/backend"
[[ ! -d "$BACKEND_DIR" ]] && { echo "ERROR: store/backend niet gevonden"; exit 1; }

echo "=== Gymies backend sync naar $SSH_TARGET ==="

# 1. Staging + upload
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING/app/Http/Controllers/Gymies $REMOTE_STAGING/app/Http/Middleware $REMOTE_STAGING/app/Services $REMOTE_STAGING/config $REMOTE_STAGING/database/migrations $REMOTE_STAGING/routes $REMOTE_STAGING/scripts"

rsync -e "ssh ${SSH_OPTS[*]}" -avz \
  "$BACKEND_DIR/app/Http/Controllers/Gymies/" \
  "$SSH_TARGET:$REMOTE_STAGING/app/Http/Controllers/Gymies/"

# Services (SubscriptionBillingService voor next_billing_date)
[[ -d "$BACKEND_DIR/app/Services" ]] && rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/app/Services/" "$SSH_TARGET:$REMOTE_STAGING/app/Services/"

# Config (gymies_subscription, gymies_subscription_features)
[[ -d "$BACKEND_DIR/config" ]] && rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/config/" "$SSH_TARGET:$REMOTE_STAGING/config/"

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING/app/Http/Middleware"
# EnsureGymiesAuthPreempt + GymiesAuthMiddleware (gymies_personal_access_tokens + gymies_sessions)
[[ -f "$BACKEND_DIR/app/Http/Middleware/EnsureGymiesAuthPreempt.php" ]] && rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/app/Http/Middleware/EnsureGymiesAuthPreempt.php" "$SSH_TARGET:$REMOTE_STAGING/app/Http/Middleware/"
[[ -f "$BACKEND_DIR/app/Http/Middleware/GymiesAuthMiddleware.php" ]] && rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/app/Http/Middleware/GymiesAuthMiddleware.php" "$SSH_TARGET:$REMOTE_STAGING/app/Http/Middleware/"

[[ -f "$BACKEND_DIR/GymiesPlanManager.php" ]] && rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/GymiesPlanManager.php" "$SSH_TARGET:$REMOTE_STAGING/app/Http/Controllers/Gymies/"
[[ -f "$BACKEND_DIR/routes_gymies_full.php" ]] && rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/routes_gymies_full.php" "$SSH_TARGET:$REMOTE_STAGING/routes/"
# Migrations (incl. gymies_sessions voor sessietoken-auth)
rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/database/migrations/" "$SSH_TARGET:$REMOTE_STAGING/database/migrations/"
rsync -e "ssh ${SSH_OPTS[*]}" -avz "$BACKEND_DIR/scripts/" "$SSH_TARGET:$REMOTE_STAGING/scripts/"

# 2. Kopieer naar Laravel (routes ook naar gymies_deploy – web.php laadt vandaar)
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo cp -r $REMOTE_STAGING/app/Http/Controllers/Gymies/* $REMOTE_LARAVEL/app/Http/Controllers/Gymies/ && sudo mkdir -p $REMOTE_LARAVEL/app/Http/Middleware $REMOTE_LARAVEL/app/Services $REMOTE_LARAVEL/config $REMOTE_LARAVEL/gymies_deploy && sudo cp $REMOTE_STAGING/app/Http/Middleware/*.php $REMOTE_LARAVEL/app/Http/Middleware/ 2>/dev/null || true && sudo cp -r $REMOTE_STAGING/app/Services/* $REMOTE_LARAVEL/app/Services/ 2>/dev/null || true && sudo cp $REMOTE_STAGING/config/*.php $REMOTE_LARAVEL/config/ 2>/dev/null || true && sudo cp $REMOTE_STAGING/config/*.json $REMOTE_LARAVEL/config/ 2>/dev/null || true && sudo cp $REMOTE_STAGING/database/migrations/*.php $REMOTE_LARAVEL/database/migrations/ 2>/dev/null || true && sudo cp $REMOTE_STAGING/routes/routes_gymies_full.php $REMOTE_LARAVEL/routes/ 2>/dev/null || true && sudo cp $REMOTE_STAGING/routes/routes_gymies_full.php $REMOTE_LARAVEL/gymies_deploy/ 2>/dev/null || true && sudo cp $REMOTE_STAGING/scripts/*.php $REMOTE_LARAVEL/scripts/ 2>/dev/null || true && sudo cp $REMOTE_STAGING/scripts/*.sh $REMOTE_LARAVEL/scripts/ 2>/dev/null || true && rm -rf $REMOTE_STAGING"

# 3. Migrate + cache
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan migrate --force && sudo -u www-data php artisan optimize:clear && sudo -u www-data php artisan config:cache"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan route:cache" 2>/dev/null || echo "route:cache mislukt (controleer dubbele routes)"

# 4. Auth (eenmalig, scripts zijn idempotent)
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo php scripts/register_gymies_routes.php . 2>/dev/null || true"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo php scripts/register_gymies_auth_middleware.php . 2>/dev/null || true"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo php scripts/register_gymies_preempt.php . 2>/dev/null || true"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo php scripts/patch_apache_authorization_header.php . 2>/dev/null || true"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo bash scripts/patch_nginx_authorization_header.sh 2>/dev/null || true"

echo "Backend sync klaar."
