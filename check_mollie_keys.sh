#!/usr/bin/env bash
# Toont welke Mollie keys op de server staan (test vs live) - GEEN geheimen, alleen prefix/lengte.
# Gebruik: bash check_mollie_keys.sh

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
ENV_PATH="$REMOTE_LARAVEL/.env"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== Mollie keys op server ($SSH_TARGET) ==="
echo ""

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "grep -E '^MOLLIE_' $ENV_PATH 2>/dev/null || sudo grep -E '^MOLLIE_' $ENV_PATH 2>/dev/null" | while IFS= read -r line; do
  line="${line%%#*}"
  key="${line%%=*}"
  val="${line#*=}"
  val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
  val="$(echo "$val" | tr -d ' ')"
  [ -z "$val" ] && continue
  len=${#val}
  case "$key" in
    MOLLIE_CLIENT_ID)
      echo "MOLLIE_CLIENT_ID:    ${val:0:12}... ($len tekens)"
      ;;
    MOLLIE_CLIENT_SECRET)
      echo "MOLLIE_CLIENT_SECRET: *** ($len tekens)"
      ;;
    MOLLIE_API_KEY|MOLLIE_KEY)
      if [[ "$val" == test_* ]]; then
        echo "MOLLIE_API_KEY:      test_... ($len tekens) [TEST MODE]"
      elif [[ "$val" == live_* ]]; then
        echo "MOLLIE_API_KEY:      live_... ($len tekens) [LIVE MODE]"
      else
        echo "MOLLIE_API_KEY:      *** ($len tekens)"
      fi
      ;;
    *)
      echo "$key: *** ($len tekens)"
      ;;
  esac
done

echo ""
echo "Connect gebruikt MOLLIE_CLIENT_ID + MOLLIE_CLIENT_SECRET (OAuth app in Mollie Dashboard)."
echo "Betalingen gebruiken MOLLIE_API_KEY: test_ = test, live_ = productie."
