#!/bin/bash
# Deploy Mollie Connect state-fix naar Gymies server
# Oplost: "State verlopen of ongeldig" bij OAuth callback
# Gebruik: ./deploy_mollie_connect_fix.sh [LARAVEL_PATH]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LARAVEL_PATH="${1:-/var/www/gymies}"
SSH_HOST="${SSH_HOST:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"

echo "=== Deploy Mollie Connect state-fix ==="
echo "Target: $SSH_HOST:$LARAVEL_PATH"
echo ""

# Lokaal: kopieer naar Laravel (als LARAVEL_PATH lokaal is)
if [ -d "$LARAVEL_PATH" ] && [ ! "$LARAVEL_PATH" = "/var/www/gymies" ]; then
  echo "Lokale deploy naar $LARAVEL_PATH"
  cp "$SCRIPT_DIR/app/Http/Controllers/Gymies/MollieConnectOAuthTrait.php" \
     "$LARAVEL_PATH/app/Http/Controllers/Gymies/"
  cp "$SCRIPT_DIR/database/migrations/2025_03_13_120000_create_gymies_mollie_oauth_states_table.php" \
     "$LARAVEL_PATH/database/migrations/"
  echo "Bestanden gekopieerd. Run: cd $LARAVEL_PATH && php artisan migrate --force"
  echo ""
  echo "Belangrijk: Voeg MollieConnectOAuthTrait toe aan GymiesOnboardingController."
  echo "Zie store/backend/DEPLOY_MOLLIE_CONNECT_FIX.md"
  exit 0
fi

# SSH deploy
echo "Kopiëren naar server..."
scp -i "$SSH_KEY" \
  "$SCRIPT_DIR/app/Http/Controllers/Gymies/MollieConnectOAuthTrait.php" \
  "$SSH_HOST:$LARAVEL_PATH/app/Http/Controllers/Gymies/"

scp -i "$SSH_KEY" \
  "$SCRIPT_DIR/database/migrations/2025_03_13_120000_create_gymies_mollie_oauth_states_table.php" \
  "$SSH_HOST:$LARAVEL_PATH/database/migrations/"

echo ""
echo "Migration draaien..."
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LARAVEL_PATH && php artisan migrate --force"
ssh -i "$SSH_KEY" "$SSH_HOST" "cd $LARAVEL_PATH && php artisan optimize:clear && php artisan config:cache && php artisan route:cache"

echo ""
echo "=== Klaar ==="
echo ""
echo "Belangrijk: Update GymiesOnboardingController op de server:"
echo "  1. Voeg toe: use App\\Http\\Controllers\\Gymies\\MollieConnectOAuthTrait;"
echo "  2. Voeg toe in de class: use MollieConnectOAuthTrait;"
echo "  3. Vervang startMollieConnect() body met: return \$this->mollieConnectStart(\$request);"
echo "  4. Vervang mollieConnectCallback() body met: return \$this->mollieConnectCallbackHandle(\$request);"
echo ""
echo "Zie store/backend/DEPLOY_MOLLIE_CONNECT_FIX.md voor details."
