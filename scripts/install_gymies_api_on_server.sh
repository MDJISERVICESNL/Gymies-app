#!/usr/bin/env bash
# Op de server uitvoeren met sudo: sudo bash ~/gymies_api/install_on_laravel.sh
# Kopieert Gymies controllers en middleware naar het Laravel-project.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LARAVEL="/var/www/gymies.nl/laravel"
SOURCE="$SCRIPT_DIR"

if [ "$(id -u)" -ne 0 ]; then
  echo "Voer uit met: sudo bash $0"
  exit 1
fi

if [ ! -d "$SOURCE/Controllers" ]; then
  echo "Eerst lokaal uploaden: ./scripts/upload_gymies_api.sh"
  exit 1
fi

mkdir -p "$LARAVEL/app/Http/Controllers/Gymies"
cp -r "$SOURCE/Controllers/"*.php "$LARAVEL/app/Http/Controllers/Gymies/"
cp "$SOURCE/Middleware/GymiesAuthMiddleware.php" "$LARAVEL/app/Http/Middleware/"

chown -R www-data:www-data "$LARAVEL/app/Http/Controllers/Gymies" "$LARAVEL/app/Http/Middleware/GymiesAuthMiddleware.php"

echo "Gymies API-bestanden geïnstalleerd in $LARAVEL"
echo "Voeg nog routes en middleware-registratie toe (zie backend/README.md)."
