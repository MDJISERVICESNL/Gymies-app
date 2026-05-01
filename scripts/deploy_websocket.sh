#!/usr/bin/env bash
# =============================================================================
# Gymies – complete deploy inclusief WebSocket (Reverb)
# =============================================================================
# Gebruik (vanaf projectroot):
#   ./scripts/deploy_websocket.sh              # backend + UX + Reverb setup
#   ./scripts/deploy_websocket.sh --skip-reverb   # backend + UX, geen Reverb
#   ./scripts/deploy_websocket.sh reverb-only    # alleen Reverb install/config
#
# Voor Reverb moet .env op de server deze vars hebben (of worden toegevoegd):
#   BROADCAST_CONNECTION=reverb
#   REVERB_APP_ID=gymies
#   REVERB_APP_KEY=<jouw-key>       # min 1 char, zichtbaar voor client
#   REVERB_APP_SECRET=<jouw-secret> # voor signing, geheim
#   REVERB_HOST=0.0.0.0
#   REVERB_PORT=8080
#   GYMIES_WS_HOST=www.gymies.nl
#   GYMIES_WS_PORT=443
#   GYMIES_WS_SCHEME=https
#
# Optioneel:
#   export REVERB_APP_KEY=... REVERB_APP_SECRET=...  # worden op server gezet
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

SKIP_REVERB=false
REVERB_ONLY=false
for arg in "$@"; do
  [[ "$arg" == "--skip-reverb" ]] && SKIP_REVERB=true
  [[ "$arg" == "reverb-only" ]] && REVERB_ONLY=true
done

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
SSH_TARGET="${SSH_TARGET:-gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

export SSH_KEY SSH_TARGET REMOTE_LARAVEL

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  echo "Zet: export SSH_KEY=/pad/naar/jouw/key"
  exit 1
fi

echo "=============================================="
echo "  Gymies deploy – incl. WebSocket (Reverb)"
echo "  SSH: $SSH_KEY → $SSH_TARGET"
echo "  Laravel: $REMOTE_LARAVEL"
echo "  Reverb:  $([[ "$SKIP_REVERB" == "true" ]] && echo "OVERGESLAGEN" || echo "meegenomen")"
echo "=============================================="
echo ""

# --- Stap 1: Backend + UX (tenzij reverb-only)
if [[ "$REVERB_ONLY" != "true" ]]; then
  echo "--- [1] Backend + UX ---"
  "$SCRIPT_DIR/deploy_gymies.sh" all
  echo ""
fi

# --- Stap 2: Reverb op server
if [[ "$SKIP_REVERB" != "true" ]]; then
  [[ "$REVERB_ONLY" == "true" ]] && echo "--- Reverb-only: installeren en configureren ---" || echo "--- [2] Reverb op server ---"

  REVERB_APP_KEY_IN="${REVERB_APP_KEY:-}"
  REVERB_APP_SECRET_IN="${REVERB_APP_SECRET:-}"

  ssh -o IdentitiesOnly=yes -i "$SSH_KEY" "$SSH_TARGET" "bash -s" << REMOTE_SCRIPT
set -e
REMOTE_LARAVEL="${REMOTE_LARAVEL}"
REVERB_APP_KEY_IN="${REVERB_APP_KEY_IN}"
REVERB_APP_SECRET_IN="${REVERB_APP_SECRET_IN}"

cd "\$REMOTE_LARAVEL"

# Composer require Reverb (als nog niet geïnstalleerd)
if ! grep -q 'laravel/reverb' composer.json 2>/dev/null; then
  echo "[Reverb] composer require laravel/reverb..."
  sudo -u www-data composer require laravel/reverb --no-interaction 2>/dev/null || composer require laravel/reverb --no-interaction
fi

# reverb:install als config nog niet bestaat
if [[ ! -f config/reverb.php ]]; then
  echo "[Reverb] php artisan reverb:install..."
  php artisan reverb:install --no-interaction 2>/dev/null || true
fi

# .env: Reverb-vars toevoegen (zonder bestaande te overschrijven)
ENV_FILE="\$REMOTE_LARAVEL/.env"
if ! sudo grep -qF "GYMIES REVERB (deploy_websocket)" "\$ENV_FILE" 2>/dev/null; then
  echo "[Reverb] .env vars toevoegen..."
  sudo tee -a "\$ENV_FILE" > /dev/null << 'ENVBLOCK'

# --- GYMIES REVERB (deploy_websocket) ---
BROADCAST_CONNECTION=reverb
REVERB_APP_ID=gymies
REVERB_APP_KEY=gymies-ws-key
REVERB_APP_SECRET=change-me-to-random-secret
REVERB_HOST=0.0.0.0
REVERB_PORT=8080
REVERB_SCHEME=http
GYMIES_WS_HOST=www.gymies.nl
GYMIES_WS_PORT=443
GYMIES_WS_SCHEME=https
ENVBLOCK
  echo "[Reverb] .env vars toegevoegd. Pas REVERB_APP_KEY en REVERB_APP_SECRET aan!"
fi

# Optioneel: override van environment (bij voorkeur alphanumeriek)
if [[ -n "\$REVERB_APP_KEY_IN" ]]; then
  sudo sed -i "s/^REVERB_APP_KEY=.*/REVERB_APP_KEY=\${REVERB_APP_KEY_IN}/" "\$ENV_FILE" 2>/dev/null || true
fi
if [[ -n "\$REVERB_APP_SECRET_IN" ]]; then
  sudo sed -i "s|^REVERB_APP_SECRET=.*|REVERB_APP_SECRET=\${REVERB_APP_SECRET_IN}|" "\$ENV_FILE" 2>/dev/null || true
fi

# Systemd unit voor Reverb (WorkingDirectory = REMOTE_LARAVEL)
REVERB_SERVICE="/etc/systemd/system/reverb.service"
if [[ ! -f "\$REVERB_SERVICE" ]]; then
  echo "[Reverb] systemd unit aanmaken..."
  sudo tee "\$REVERB_SERVICE" > /dev/null << UNIT
[Unit]
Description=Laravel Reverb WebSocket (Gymies)
After=network.target

[Service]
User=www-data
WorkingDirectory=\$REMOTE_LARAVEL
ExecStart=/usr/bin/php artisan reverb:start
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
  sudo systemctl daemon-reload
  echo "[Reverb] systemd unit geïnstalleerd."
fi

# Reverb inschakelen en starten
echo "[Reverb] Service enable + start..."
sudo systemctl enable reverb 2>/dev/null || true
sudo systemctl restart reverb 2>/dev/null || true
sleep 1
sudo systemctl status reverb --no-pager 2>/dev/null || echo "(status check optioneel)"

# Config cache
cd "\$REMOTE_LARAVEL" && php artisan config:clear 2>/dev/null || true

echo "[Reverb] Klaar."
REMOTE_SCRIPT
  echo ""
fi

# --- Afronding
echo "=============================================="
echo "  Deploy klaar"
echo "=============================================="
echo ""
echo "  Site:     https://www.gymies.nl/"
echo "  API:      https://www.gymies.nl/api/gymies/"
if [[ "$SKIP_REVERB" != "true" ]]; then
  echo "  Reverb:   systemctl status reverb"
  echo ""
  echo "  Nginx:    Voeg toe aan je server block voor wss://:"
  echo ""
  echo "    location /app {"
  echo "        proxy_pass http://127.0.0.1:8080;"
  echo "        proxy_http_version 1.1;"
  echo "        proxy_set_header Upgrade \$http_upgrade;"
  echo "        proxy_set_header Connection \"upgrade\";"
  echo "        proxy_set_header Host \$host;"
  echo "        proxy_set_header X-Real-IP \$remote_addr;"
  echo "    }"
  echo ""
  echo "  Zonder nginx proxy: Flutter valt terug op polling (25s)."
else
  echo "  Reverb:   (overgeslagen)"
fi
echo ""
echo "  Migrate:  ./scripts/deploy_gymies.sh migrate"
echo ""
