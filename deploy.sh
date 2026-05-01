#!/usr/bin/env bash
# =============================================================================
# Gymies – één commando: backend + UX naar de server
# =============================================================================
# Gebruik (vanaf projectroot):
#   ./deploy.sh              # backend + Flutter web + APP_URL
#   ./deploy.sh backend      # alleen PHP/controllers + gymies_deploy
#   ./deploy.sh ux           # alleen flutter build web + rsync
#   ./deploy.sh migrate      # toon migrate-commando's (voer op server uit)
#   ./deploy.sh run-migrate  # voer Pro/Elite migraties uit op server
#
# Optioneel:
#   export SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
#   export SSH_TARGET=gymies
#   export REMOTE_LARAVEL=/var/www/gymies
#   export GYMIES_API_BASE_URL=https://www.gymies.nl/api/gymies   # voor flutter build
#   DEPLOY_COMPOSER=1 ./deploy.sh   # na backend: composer dump-autoload op server
#
# Inclusief WebSocket (Reverb) voor chat: ./scripts/deploy_websocket.sh
# =============================================================================

set -e
cd "$(dirname "$0")"

export SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
export SSH_TARGET="${SSH_TARGET:-gymies}"
export REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

exec ./scripts/deploy_gymies.sh "$@"
