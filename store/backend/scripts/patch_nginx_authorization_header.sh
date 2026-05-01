#!/usr/bin/env bash
# Voeg fastcgi_param HTTP_AUTHORIZATION toe aan Nginx (fix 'Unauthorized' na login).
# Run op de server: sudo bash patch_nginx_authorization_header.sh [nginx_site]
# Of: sudo bash patch_nginx_authorization_header.sh /etc/nginx/sites-available/gymies

AUTH_LINE='fastcgi_param HTTP_AUTHORIZATION $http_authorization;
        fastcgi_param HTTP_X_GYMIES_ACCESS_TOKEN $http_x_gymies_access_token;'
SITE="${1:-gymies}"

find_config() {
  [[ -f "$SITE" ]] && echo "$SITE" && return
  [[ -f "/etc/nginx/sites-available/$SITE" ]] && echo "/etc/nginx/sites-available/$SITE" && return
  [[ -f "/etc/nginx/sites-available/${SITE}.conf" ]] && echo "/etc/nginx/sites-available/${SITE}.conf" && return
  local found
  found=$(grep -rl "gymies\|/var/www/gymies" /etc/nginx/sites-available/ 2>/dev/null | head -1)
  [[ -n "$found" ]] && echo "$found" && return
  found=$(grep -rl "gymies\|/var/www/gymies" /etc/nginx/conf.d/ 2>/dev/null | head -1)
  [[ -n "$found" ]] && echo "$found"
}

CONFIG=$(find_config)
if [[ -z "$CONFIG" || ! -f "$CONFIG" ]]; then
  echo "Geen Nginx-config gevonden. Gebruik: $0 gymies of $0 /pad/naar/config"
  echo "Voeg handmatig toe in location ~ \.php\$ block:"
  echo "  $AUTH_LINE"
  exit 1
fi

if grep -q "HTTP_AUTHORIZATION\|HTTP_X_GYMIES_ACCESS_TOKEN" "$CONFIG" 2>/dev/null; then
  echo "Auth headers al aanwezig in $CONFIG"
  exit 0
fi

# Voeg toe: Authorization + X-Gymies-Access-Token (fallback)
if grep -q "include fastcgi_params" "$CONFIG"; then
  if grep -q "HTTP_AUTHORIZATION" "$CONFIG" 2>/dev/null; then
    awk '/fastcgi_param HTTP_AUTHORIZATION/ && !done {print; print "        fastcgi_param HTTP_X_GYMIES_ACCESS_TOKEN $http_x_gymies_access_token;"; done=1; next} 1' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
  else
    sed -i.bak "0,/include fastcgi_params;/s/\([[:space:]]*\)include fastcgi_params;/\1include fastcgi_params;\n\1fastcgi_param HTTP_AUTHORIZATION \$http_authorization;\n\1fastcgi_param HTTP_X_GYMIES_ACCESS_TOKEN \$http_x_gymies_access_token;/" "$CONFIG"
  fi
else
  echo "Geen include fastcgi_params gevonden. Voeg handmatig toe in de location ~ \.php\$ block:"
  echo "  $AUTH_LINE"
  exit 1
fi

if grep -q "HTTP_AUTHORIZATION" "$CONFIG" 2>/dev/null; then
  nginx -t 2>/dev/null && (systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null) || echo "Reload nginx handmatig"
  echo "Authorization-header toegevoegd aan $CONFIG"
else
  echo "Kon niet patchen. Voeg handmatig toe aan $CONFIG:"
  echo "  $AUTH_LINE"
  exit 1
fi
