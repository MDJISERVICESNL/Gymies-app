#!/bin/bash
# upload_backend.sh — GYMIES Deploy Script (AWS)
# Gebruik: ./upload_backend.sh [--demo]

DEMO_MODE=false
if [[ "$1" == "--demo" ]]; then
    DEMO_MODE=true
    echo "═══ GYMIES Deploy + DEMO DATA ═══"
else
    echo "═══ GYMIES Deploy ═══"
fi

SERVER="ubuntu@gymies.nl"
SSH_KEY="$HOME/.ssh/Amazonekey.pem"
REMOTE_PATH="/var/www/gymies"

# SSH shortcut functie
ssh_cmd() {
    ssh -i "$SSH_KEY" "$SERVER" "$@"
}

# 1. Rsync backend bestanden
echo "═══ 1. Uploaden backend bestanden ═══"
rsync -avz \
    -e "ssh -i $SSH_KEY" \
    --exclude '.env' \
    --exclude 'storage' \
    --exclude 'node_modules' \
    --exclude 'vendor' \
    --exclude '.git' \
    ./ "$SERVER:$REMOTE_PATH/"

# 2. Composer install
echo "═══ 2. Composer install ═══"
ssh_cmd "cd $REMOTE_PATH && composer install --no-dev --optimize-autoloader"

# 3. Cache rebuild
echo "═══ 3. Cache rebuild ═══"
ssh_cmd "cd $REMOTE_PATH && php artisan config:cache && php artisan route:cache"

# 4. PHP-FPM restart
echo "═══ 4. PHP-FPM restart ═══"
ssh_cmd "sudo systemctl restart php8.4-fpm"

# 5. Demo data (alleen met --demo flag)
if $DEMO_MODE; then
    echo ""
    echo "═══ 5. Demo data seeden ═══"
    echo "⚠️  Dit verwijdert alle bestaande testdata!"
    echo -n "Doorgaan? (ja/nee): "
    read CONFIRM
    if [[ "$CONFIRM" == "ja" ]]; then
        ssh_cmd "cd $REMOTE_PATH && php artisan db:seed --class=DemoDataSeeder"
        echo "  ✅ Demo data toegevoegd"
    else
        echo "  ⏭️  Demo data overgeslagen"
    fi
fi

# 6. Health check
echo ""
echo "═══ 6. Health check ═══"
HEALTH=$(ssh_cmd "curl -s https://gymies.nl/api/gymies/health")
echo "  Response: $HEALTH"

echo ""
echo "═══ Done ═══"
if $DEMO_MODE; then
    echo ""
    echo "🔑 Test accounts (wachtwoord: demodemo):"
    echo "  Trainer: mohamed@demo.nl"
    echo "  Sporter: lisa@demo.nl"
fi
