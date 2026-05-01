#!/usr/bin/env bash
# Build TrainMaat web voor deploy onder Laravel op mdjiservices.nl/TrainMaat/
# Gebruik: ./scripts/build_for_laravel.sh [pad-naar-laravel-public]
# Voorbeeld: ./scripts/build_for_laravel.sh /var/www/mdjiservices.nl/public

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_HREF="/TrainMaat/"
OUTPUT_DIR="$PROJECT_DIR/build/web"
LARAVEL_PUBLIC="${1:-}"

cd "$PROJECT_DIR"

echo "Building Flutter web met base-href $BASE_HREF ..."
flutter build web --base-href "$BASE_HREF"

# Apache: .htaccess voor SPA-routing meenemen in build
HTACCESS_SRC="$PROJECT_DIR/web/.htaccess.laravel"
if [ -f "$HTACCESS_SRC" ]; then
  cp "$HTACCESS_SRC" "$OUTPUT_DIR/.htaccess"
  echo ".htaccess voor Apache SPA-routing toegevoegd aan build."
fi

echo "Build staat in: $OUTPUT_DIR"

if [ -n "$LARAVEL_PUBLIC" ]; then
  TARGET="$LARAVEL_PUBLIC/TrainMaat"
  echo "Kopiëren naar Laravel public: $TARGET"
  mkdir -p "$TARGET"
  rsync -a --delete "$OUTPUT_DIR/" "$TARGET/"
  echo "Klaar. App bereikbaar op: .../TrainMaat/"
else
  echo "Deploy naar mdjiservices.nl:"
  echo "  1. rsync -avz --delete build/web/ niyyahpath:public/TrainMaat/"
  echo "  2. Op server: sudo bash ~/server_setup_trainmaat.sh  (of kopieer handmatig naar Laravel public)"
  echo ""
  echo "Laravel public op server: /var/www/mdjiservices.nl/laravel/public"
fi
