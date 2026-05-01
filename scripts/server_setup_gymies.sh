#!/usr/bin/env bash
# Eenmalig op de server uitvoeren (met sudo) om:
# 1. Nginx config voor /Gymies/ toe te voegen
# 2. Gymies bestanden van ~/public/Gymies naar Laravel public te kopiëren
# Gebruik: sudo bash server_setup_gymies.sh

set -e
NGINX_CONF="/etc/nginx/sites-enabled/gymies.nl"
LARAVEL_PUBLIC="/var/www/gymies.nl/laravel/public"
SOURCE="${GYMIES_SOURCE:-$HOME/public/Gymies}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Voer dit script uit met sudo."
  exit 1
fi

# 1) Nginx: Gymies location toevoegen als die nog niet bestaat
if grep -q "location /Gymies/" "$NGINX_CONF"; then
  echo "Nginx: Gymies location staat er al."
else
  cp "$NGINX_CONF" "${NGINX_CONF}.bak_gymies_$(date +%Y%m%d_%H%M%S)"
  SNIPPET=$(mktemp)
  cat > "$SNIPPET" << 'NGINX_SNIPPET'
    # ========== Gymies Flutter app (SPA) ==========
    location /Gymies/ {
        try_files $uri $uri/ /Gymies/index.html;
    }
    # ========== EINDE Gymies ==========
NGINX_SNIPPET
  awk '/# Laravel public directory/ { while ((getline line < "'"$SNIPPET"'") > 0) print line; close("'"$SNIPPET"'") } { print }' "$NGINX_CONF" > "${NGINX_CONF}.new" && mv "${NGINX_CONF}.new" "$NGINX_CONF"
  rm -f "$SNIPPET"
  echo "Nginx: Gymies location toegevoegd."
fi

# 2) Gymies bestanden naar Laravel public
if [ ! -d "$SOURCE" ]; then
  echo "Bron niet gevonden: $SOURCE. Eerst lokaal deployen: rsync build naar niyyahpath:public/Gymies/"
  exit 1
fi

mkdir -p "$LARAVEL_PUBLIC/Gymies"
rsync -a --delete "$SOURCE/" "$LARAVEL_PUBLIC/Gymies/"
chown -R www-data:www-data "$LARAVEL_PUBLIC/Gymies"
echo "Bestanden gekopieerd naar $LARAVEL_PUBLIC/Gymies"

# 3) Nginx config testen en herladen
nginx -t && systemctl reload nginx
echo "Nginx herladen. Gymies staat op: https://gymies.nl/gymies/"
