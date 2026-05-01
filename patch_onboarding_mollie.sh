#!/usr/bin/env bash
set -euo pipefail

# Patch GymiesOnboardingController op de server om MollieConnectOAuthTrait te gebruiken.
# Gebruik: bash patch_onboarding_mollie.sh
#
# Optionele env vars:
#   SSH_TARGET=gymies
#   SSH_KEY=$HOME/.ssh/id_ed25519_gymies
#   REMOTE_LARAVEL=/var/www/gymies

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

SSH_OPTS=()
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_SCRIPT="$SCRIPT_DIR/store/backend/scripts/patch_onboarding_mollie.php"
CONTROLLER_PATH="$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesOnboardingController.php"

if [[ ! -f "$PATCH_SCRIPT" ]]; then
  echo "ERROR: patch script niet gevonden: $PATCH_SCRIPT"
  exit 1
fi

echo "=== Patch GymiesOnboardingController voor Mollie Connect ==="
echo "Server: $SSH_TARGET"
echo "Controller: $CONTROLLER_PATH"
echo ""

# Upload patch script
scp "${SSH_OPTS[@]}" "$PATCH_SCRIPT" "$SSH_TARGET:/tmp/patch_onboarding_mollie.php"

# Run patch op server (sudo voor schrijven naar app/Http/Controllers)
echo "Patch uitvoeren..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo php /tmp/patch_onboarding_mollie.php $REMOTE_LARAVEL && rm -f /tmp/patch_onboarding_mollie.php" || {
  echo ""
  echo "Patch mislukt. Probeer handmatig:"
  echo "  1. ssh $SSH_TARGET"
  echo "  2. Voeg toe aan GymiesOnboardingController: use MollieConnectOAuthTrait;"
  echo "  3. Vervang startMollieConnect body met: return \$this->mollieConnectStart(\$request);"
  echo "  4. Vervang mollieConnectCallback body met: return \$this->mollieConnectCallbackHandle(\$request);"
  exit 1
}

echo ""
echo "Cache legen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan optimize:clear 2>/dev/null || true"

echo ""
echo "Controller gepatcht. Mollie Connect zou nu moeten werken."
