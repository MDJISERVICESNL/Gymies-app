#!/usr/bin/env bash
# Upload Gymies API (Laravel controllers + middleware) naar de server.
# Daarna op de server: sudo bash ~/gymies_api/install_on_laravel.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND="$PROJECT_DIR/backend"
REMOTE="niyyahpath"

if [ ! -d "$BACKEND/Controllers" ]; then
  echo "Niet gevonden: $BACKEND/Controllers"
  exit 1
fi

echo "Map op de server aanmaken..."
ssh "$REMOTE" "mkdir -p ~/gymies_api/Controllers ~/gymies_api/Middleware"

echo "Uploaden Gymies API naar $REMOTE:~/gymies_api/ ..."
rsync -avz --delete \
  "$BACKEND/Controllers/" "$REMOTE:~/gymies_api/Controllers/" \
  --exclude='.DS_Store'
rsync -avz \
  "$BACKEND/Middleware/" "$REMOTE:~/gymies_api/Middleware/" \
  --exclude='.DS_Store'

# Install- en setup-scripts meesturen
scp "$PROJECT_DIR/scripts/install_gymies_api_on_server.sh" "$REMOTE:~/gymies_api/install_on_laravel.sh"
scp "$PROJECT_DIR/scripts/setup_gymies_routes_middleware.sh" "$REMOTE:~/gymies_api/setup_gymies_routes_middleware.sh"

echo "Klaar. Op de server uitvoeren:"
echo "  1. sudo bash ~/gymies_api/install_on_laravel.sh     (als nog niet gedaan)"
echo "  2. sudo bash ~/gymies_api/setup_gymies_routes_middleware.sh   (routes + middleware)"
