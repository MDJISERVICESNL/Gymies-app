#!/usr/bin/env bash
# Zet mailconfig op de server (Brevo: afzender gymiesapp@hotmail.com) en leeg Laravel config-cache.
# Gebruik: SSH_TARGET=gymies ./scripts/deploy_mail_config_and_clear_cache.sh

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
MAIL_FROM="${MAIL_FROM:-gymiesapp@hotmail.com}"
MAIL_FROM_NAME="${MAIL_FROM_NAME:-GYMIESNL}"
# Optioneel: Brevo SMTP-key (niet in git zetten). Zet lokaal: export BREVO_SMTP_KEY="xsmtpsib-..."
BREVO_SMTP_KEY="${BREVO_SMTP_KEY:-}"

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET niet gezet. Bijv. export SSH_TARGET=gymies"
  exit 1
fi
if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
else
  SSH_OPTS=()
fi

echo "=== Mailconfig bijwerken en cache legen op $SSH_TARGET ==="
echo "Mailadres: $MAIL_FROM"
echo "Laravel-root: $REMOTE_LARAVEL"

ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "export REMOTE_LARAVEL='$REMOTE_LARAVEL' MAIL_FROM='$MAIL_FROM' MAIL_FROM_NAME='$MAIL_FROM_NAME' BREVO_SMTP_KEY='$BREVO_SMTP_KEY'; bash -s" << 'REMOTE_SCRIPT'
set -e
ENV_FILE="${REMOTE_LARAVEL}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env niet gevonden: $ENV_FILE"
  exit 1
fi
sudo sed -i "s|^MAIL_USERNAME=.*|MAIL_USERNAME=${MAIL_FROM}|" "$ENV_FILE"
sudo sed -i "s|^MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=${MAIL_FROM}|" "$ENV_FILE"
sudo sed -i "s|^MAIL_FROM_NAME=.*|MAIL_FROM_NAME=\"${MAIL_FROM_NAME}\"|" "$ENV_FILE"
echo "MAIL_USERNAME, MAIL_FROM_ADDRESS, MAIL_FROM_NAME gezet."
if [[ -n "$BREVO_SMTP_KEY" ]]; then
  sudo sed -i "s|^MAIL_PASSWORD=.*|MAIL_PASSWORD=${BREVO_SMTP_KEY}|" "$ENV_FILE"
  echo "MAIL_PASSWORD (Brevo SMTP key) bijgewerkt."
fi
cd "$REMOTE_LARAVEL" && php artisan config:clear
echo "Config-cache geleegd."
REMOTE_SCRIPT

echo "Klaar."
