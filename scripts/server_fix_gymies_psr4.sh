#!/usr/bin/env bash
# Verplaats controllers van app/Http/Controllers/gymies/ naar Gymies/ (PSR-4) en herbouw autoload.
# Eenmalig of na oude deploys. Gebruik: SSH_TARGET=gymies ./scripts/server_fix_gymies_psr4.sh
set -euo pipefail
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== PSR-4 fix: gymies/ -> Gymies/ op $SSH_TARGET ==="
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" bash -s <<REMOTE
set -e
LARAVEL="$REMOTE_LARAVEL"
LOW="\$LARAVEL/app/Http/Controllers/gymies"
HIGH="\$LARAVEL/app/Http/Controllers/Gymies"
if [[ -d "\$LOW" ]]; then
  sudo mkdir -p "\$HIGH"
  sudo cp -a "\$LOW/"*.php "\$HIGH/" 2>/dev/null || true
  sudo rm -rf "\$LOW"
  echo "OK: bestanden verplaatst naar Gymies/, oude gymies/ verwijderd."
else
  echo "Geen map \$LOW (al opgeschoond of nog niet gedeployed)."
fi
cd "\$LARAVEL" && sudo -u www-data composer dump-autoload -o
echo "OK: composer dump-autoload klaar."
REMOTE
echo "=== Klaar. Skipping-meldingen zouden weg moeten zijn. ==="
