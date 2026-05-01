#!/bin/bash
# Deploy subscription features naar Laravel backend
# Usage: LARAVEL_ROOT=/path/to/laravel ./deploy_subscription_features.sh
#    of: ./deploy_subscription_features.sh /path/to/laravel

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE_CONFIG=false
for arg in "$@"; do
  [ "$arg" = "--force" ] && FORCE_CONFIG=true
  [ -d "$arg" ] && LARAVEL_ROOT="$arg"
done
LARAVEL_ROOT="${LARAVEL_ROOT:-}"
[ -z "$LARAVEL_ROOT" ] && [ -d "${1:-}" ] && LARAVEL_ROOT="$1"

if [ -z "$LARAVEL_ROOT" ] || [ ! -d "$LARAVEL_ROOT" ]; then
  echo "Usage: LARAVEL_ROOT=/path/to/laravel $0 [--force]"
  echo "   of: $0 /path/to/laravel [--force]"
  echo ""
  echo "  --force  overschrijf config indien aanwezig (anders behouden)"
  exit 1
fi

echo "Deploying subscription features naar $LARAVEL_ROOT"
mkdir -p "$LARAVEL_ROOT/app/Http/Controllers/Gymies"
mkdir -p "$LARAVEL_ROOT/database/migrations"

cp "$SCRIPT_DIR/app/Http/Controllers/Gymies/SubscriptionFeaturesAdminTrait.php" \
   "$LARAVEL_ROOT/app/Http/Controllers/Gymies/"
cp "$SCRIPT_DIR/app/Http/Controllers/Gymies/SubscriptionEntitlementsTrait.php" \
   "$LARAVEL_ROOT/app/Http/Controllers/Gymies/"
[ -f "$SCRIPT_DIR/app/Http/Controllers/Gymies/TrainerMediaValidationTrait.php" ] && \
cp "$SCRIPT_DIR/app/Http/Controllers/Gymies/TrainerMediaValidationTrait.php" \
   "$LARAVEL_ROOT/app/Http/Controllers/Gymies/"
cp "$SCRIPT_DIR/database/migrations/2025_03_12_000000_create_gymies_subscription_features_table.php" \
   "$LARAVEL_ROOT/database/migrations/"

echo "Traits + migration gekopieerd."
echo "Volgende stappen:"
echo "  1. Voeg use SubscriptionFeaturesAdminTrait / SubscriptionEntitlementsTrait toe aan de controllers"
echo "  2. php artisan migrate  (op de server)"
