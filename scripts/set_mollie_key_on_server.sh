#!/usr/bin/env bash
# Zet MOLLIE_API_KEY in .env op de server (test key voor betaalpagina).
# Gebruik: ./scripts/set_mollie_key_on_server.sh
# Zelfde SSH-opties als upload_backend.sh: SSH_TARGET=gymies, SSH_KEY=~/.ssh/id_ed25519_gymies, REMOTE_LARAVEL=/var/www/gymies

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
MOLLIE_KEY="${MOLLIE_KEY:-test_JaKE2emRwW4GGfPFsvCerAJGP7QpGs}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  echo "Zet SSH_KEY op het juiste pad, bijv. export SSH_KEY=~/.ssh/id_ed25519_gymies"
  exit 1
fi

echo "Target: $SSH_TARGET  Laravel: $REMOTE_LARAVEL"
ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$SSH_TARGET" "sudo bash -s" << REMOTE
  ENV_FILE="$REMOTE_LARAVEL/.env"
  if [ ! -f "\$ENV_FILE" ]; then
    echo "ERROR: .env niet gevonden: \$ENV_FILE"
    exit 1
  fi
  if grep -q '^MOLLIE_API_KEY=' "\$ENV_FILE"; then
    sed -i 's/^MOLLIE_API_KEY=.*/MOLLIE_API_KEY=$MOLLIE_KEY/' "\$ENV_FILE"
    echo "MOLLIE_API_KEY in .env bijgewerkt."
  else
    echo "" >> "\$ENV_FILE"
    echo "# Mollie (Gymies betaalpagina)" >> "\$ENV_FILE"
    echo "MOLLIE_API_KEY=$MOLLIE_KEY" >> "\$ENV_FILE"
    echo "MOLLIE_API_KEY toegevoegd aan .env."
  fi
  grep 'MOLLIE_API_KEY' "\$ENV_FILE" | sed 's/=.*/=***/'
REMOTE
echo "Klaar."
