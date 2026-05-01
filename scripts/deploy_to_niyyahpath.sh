#!/usr/bin/env bash
# Build TrainMaat web en rsync naar niyyahpath (~/public/TrainMaat).
# Daarna op de server: sudo bash ~/server_setup_trainmaat.sh (eerste keer)
#   of: sudo rsync -a --delete ~/public/TrainMaat/ /var/www/mdjiservices.nl/laravel/public/TrainMaat/ && sudo chown -R www-data:www-data /var/www/mdjiservices.nl/laravel/public/TrainMaat

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"
"$SCRIPT_DIR/build_for_laravel.sh"

echo "Uploaden naar niyyahpath:public/TrainMaat/ ..."
rsync -avz --delete build/web/ niyyahpath:public/TrainMaat/

echo "Server-setup (als nog niet gedaan): ssh niyyahpath 'sudo bash ~/server_setup_trainmaat.sh'"
echo "Of alleen kopie naar Laravel public: ssh niyyahpath 'sudo rsync -a --delete ~/public/TrainMaat/ /var/www/mdjiservices.nl/laravel/public/TrainMaat/ && sudo chown -R www-data:www-data /var/www/mdjiservices.nl/laravel/public/TrainMaat'"
