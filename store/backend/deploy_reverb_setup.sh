#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# Gymies — Laravel Reverb WebSocket Setup
# ──────────────────────────────────────────────────────────────────────
# Installeert en configureert Laravel Reverb als WebSocket server.
#
# Gebruik:
#   ssh ubuntu@gymies.nl "bash -s" < deploy_reverb_setup.sh
#
# Vereisten:
# - Laravel 11+ (Reverb is first-party)
# - Supervisor (voor process management)
# - Nginx (voor SSL termination + reverse proxy)
# ──────────────────────────────────────────────────────────────────────

GYMIES_DIR="/var/www/gymies"
NGINX_CONF="/etc/nginx/sites-available/gymies"

echo "=== Gymies Reverb Setup ==="
echo ""

# ── 1. Installeer Reverb ──
echo "1/5 — Reverb installeren..."
cd "$GYMIES_DIR"
composer require laravel/reverb --no-interaction 2>/dev/null || echo "   (al geïnstalleerd)"

# ── 2. .env variabelen (alleen toevoegen als ze nog niet bestaan) ──
echo "2/5 — .env variabelen controleren..."
ENV_FILE="$GYMIES_DIR/.env"

add_env_if_missing() {
    local key="$1"
    local value="$2"
    if ! grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        echo "${key}=${value}" >> "$ENV_FILE"
        echo "   + ${key} toegevoegd"
    else
        echo "   ~ ${key} bestaat al"
    fi
}

add_env_if_missing "BROADCAST_CONNECTION" "reverb"
add_env_if_missing "REVERB_APP_ID" "gymies-$(openssl rand -hex 4)"
add_env_if_missing "REVERB_APP_KEY" "$(openssl rand -hex 16)"
add_env_if_missing "REVERB_APP_SECRET" "$(openssl rand -hex 16)"
add_env_if_missing "REVERB_HOST" "0.0.0.0"
add_env_if_missing "REVERB_PORT" "8080"
add_env_if_missing "REVERB_SCHEME" "http"

# Verwijder oude Pusher variabelen (optioneel — comment uit als je ze wilt behouden)
echo ""
echo "   Oude Pusher variabelen uitschakelen..."
for key in PUSHER_APP_ID PUSHER_APP_KEY PUSHER_APP_SECRET PUSHER_APP_CLUSTER PUSHER_HOST PUSHER_PORT PUSHER_SCHEME; do
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s/^${key}=/#DEPRECATED_${key}=/" "$ENV_FILE"
        echo "   # ${key} → uitgeschakeld"
    fi
done

# ── 3. Supervisor config ──
echo ""
echo "3/5 — Supervisor configureren..."

sudo tee /etc/supervisor/conf.d/gymies-reverb.conf > /dev/null << 'SUPERVISOR'
[program:gymies-reverb]
command=php /var/www/gymies/artisan reverb:start --host=0.0.0.0 --port=8080
directory=/var/www/gymies
autostart=true
autorestart=true
startretries=3
user=www-data
redirect_stderr=true
stdout_logfile=/var/log/gymies-reverb.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=3
stopwaitsecs=10
SUPERVISOR

sudo supervisorctl reread
sudo supervisorctl update
echo "   Supervisor config geïnstalleerd"

# ── 4. Nginx reverse proxy ──
echo ""
echo "4/5 — Nginx WebSocket proxy configureren..."

# Check of de location /app al bestaat in de nginx config
if grep -q "location /app" "$NGINX_CONF" 2>/dev/null; then
    echo "   ~ Nginx /app location bestaat al — overslaan"
else
    # Voeg WebSocket location toe vóór de laatste sluitende }
    # Maak een backup
    sudo cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d)"

    # Insert de WebSocket location block
    sudo tee /tmp/nginx_ws_block.conf > /dev/null << 'NGINX_WS'

    # ── Laravel Reverb WebSocket ──────────────────────────────
    location /app {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    location /apps {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
NGINX_WS

    echo "   NGINX WebSocket block geschreven naar /tmp/nginx_ws_block.conf"
    echo ""
    echo "   ⚠️  HANDMATIGE STAP NODIG:"
    echo "   Voeg de inhoud van /tmp/nginx_ws_block.conf toe aan ${NGINX_CONF}"
    echo "   vóór de laatste sluitende '}'."
    echo ""
    echo "   Daarna: sudo nginx -t && sudo systemctl reload nginx"
fi

# ── 5. Start Reverb ──
echo ""
echo "5/5 — Reverb starten..."
sudo supervisorctl start gymies-reverb 2>/dev/null || sudo supervisorctl restart gymies-reverb

# Config cache legen
php "$GYMIES_DIR/artisan" config:clear 2>/dev/null || true

echo ""
echo "════════════════════════════════════════════════════"
echo "  Reverb is geconfigureerd!"
echo ""
echo "  WebSocket: wss://gymies.nl/app/{key}?protocol=7"
echo "  Intern:    ws://127.0.0.1:8080"
echo ""
echo "  Controleer status:"
echo "    sudo supervisorctl status gymies-reverb"
echo "    curl -s http://127.0.0.1:8080"
echo ""
echo "  Logs:"
echo "    tail -f /var/log/gymies-reverb.log"
echo "════════════════════════════════════════════════════"
