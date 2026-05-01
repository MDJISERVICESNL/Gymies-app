#!/usr/bin/env bash
set -euo pipefail

# Check of MOLLIE_CLIENT_ID en MOLLIE_CLIENT_SECRET in .env op de server staan.
# Gebruik:
#   bash check_mollie_env.sh
#   bash check_mollie_env.sh /pad/naar/lokaal/.env   (lokaal bestand checken)
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

check_env_file() {
  local file="$1"
  local source="$2"
  echo "=== Mollie OAuth config check ($source) ==="
  echo "Bestand: $file"
  echo ""

  if [[ ! -f "$file" ]]; then
    echo "❌ Bestand niet gevonden: $file"
    return 1
  fi

  local has_client_id=false
  local has_client_secret=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line// /}"
    [[ -z "$line" ]] && continue
    if [[ "$line" == MOLLIE_CLIENT_ID=* ]]; then
      val="${line#MOLLIE_CLIENT_ID=}"
      if [[ -n "$val" && "$val" != '""' && "$val" != "''" ]]; then
        has_client_id=true
      fi
    fi
    if [[ "$line" == MOLLIE_CLIENT_SECRET=* ]]; then
      val="${line#MOLLIE_CLIENT_SECRET=}"
      if [[ -n "$val" && "$val" != '""' && "$val" != "''" ]]; then
        has_client_secret=true
      fi
    fi
  done < "$file"

  if $has_client_id; then
    echo "✅ MOLLIE_CLIENT_ID staat ingesteld"
  else
    echo "❌ MOLLIE_CLIENT_ID ontbreekt of is leeg"
  fi

  if $has_client_secret; then
    echo "✅ MOLLIE_CLIENT_SECRET staat ingesteld"
  else
    echo "❌ MOLLIE_CLIENT_SECRET ontbreekt of is leeg"
  fi

  echo ""
  if $has_client_id && $has_client_secret; then
    echo "Mollie Connect OAuth is correct geconfigureerd."
    return 0
  else
    echo "Voeg MOLLIE_CLIENT_ID en MOLLIE_CLIENT_SECRET toe aan .env voor Mollie Connect."
    echo "Zie: deploy/env_mollie_connect.example (indien aanwezig)"
    return 1
  fi
}

if [[ -n "${1:-}" ]]; then
  # Lokaal .env bestand checken
  check_env_file "$1" "lokaal"
else
  # .env op server checken via SSH (controleert op server, geen .env lokaal kopiëren)
  ENV_PATH="$REMOTE_LARAVEL/.env"
  echo "=== Mollie OAuth config check (server: $SSH_TARGET) ==="
  echo "Bestand: $ENV_PATH"
  echo ""

  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "test -f $ENV_PATH || { echo '❌ .env niet gevonden'; exit 1; }" || exit 1

  # Remote check: regel bestaat met minstens 1 karakter na = (geen waarden teruggeven)
  RESULT=$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "
    f='$ENV_PATH'
    grep -qE '^MOLLIE_CLIENT_ID=.' \"\$f\" 2>/dev/null && echo 'CID_OK'
    grep -qE '^MOLLIE_CLIENT_SECRET=.' \"\$f\" 2>/dev/null && echo 'SEC_OK'
  " 2>/dev/null || true)

  # Fallback: sudo als user geen read op .env heeft
  if [[ -z "$RESULT" ]] || [[ "$RESULT" != *"CID_OK"* ]] || [[ "$RESULT" != *"SEC_OK"* ]]; then
    RESULT=$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "
      f='$ENV_PATH'
      sudo grep -qE '^MOLLIE_CLIENT_ID=.' \"\$f\" 2>/dev/null && echo 'CID_OK'
      sudo grep -qE '^MOLLIE_CLIENT_SECRET=.' \"\$f\" 2>/dev/null && echo 'SEC_OK'
    " 2>/dev/null || true)
  fi

  CID_OK=0
  SEC_OK=0
  [[ "$RESULT" == *"CID_OK"* ]] && CID_OK=1
  [[ "$RESULT" == *"SEC_OK"* ]] && SEC_OK=1

  if [[ $CID_OK -eq 1 ]]; then
    echo "✅ MOLLIE_CLIENT_ID staat ingesteld"
  else
    echo "❌ MOLLIE_CLIENT_ID ontbreekt of is leeg"
  fi

  if [[ $SEC_OK -eq 1 ]]; then
    echo "✅ MOLLIE_CLIENT_SECRET staat ingesteld"
  else
    echo "❌ MOLLIE_CLIENT_SECRET ontbreekt of is leeg"
  fi

  echo ""
  if [[ $CID_OK -eq 1 && $SEC_OK -eq 1 ]]; then
    echo "Mollie Connect OAuth is correct geconfigureerd."
  else
    echo "Voeg MOLLIE_CLIENT_ID en MOLLIE_CLIENT_SECRET toe aan .env voor Mollie Connect."
    echo "Zie: deploy/env_mollie_connect.example (indien aanwezig)"
    exit 1
  fi
fi
