#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Fix "Laravel" emails — APP_NAME + MAIL_FROM_NAME + crontab audit
# ═══════════════════════════════════════════════════════════════
#
# Probleem: elke 30 min komt er een mail met onderwerp "Laravel"
# Oorzaak: APP_NAME=Laravel in .env (standaard) + mogelijk
#          een artisan schedule:run in crontab die output mailt.
#
# Gebruik: bash fix_laravel_emails.sh
# ═══════════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"
LARAVEL_PATH="/var/www/gymies"

echo "═══ Fix 'Laravel' emails ═══"
echo ""

# ── STAP 1: Diagnose — wat staat er in .env? ──
echo "1. Huidige .env mail/app instellingen..."
ssh -i "$SSH_KEY" "$SSH_HOST" << 'DIAG'
ENV="/var/www/gymies/.env"
echo "  APP_NAME       = $(grep '^APP_NAME=' "$ENV" | cut -d= -f2- || echo '(niet gezet)')"
echo "  MAIL_FROM_NAME = $(grep '^MAIL_FROM_NAME=' "$ENV" | cut -d= -f2- || echo '(niet gezet)')"
echo "  MAIL_FROM_ADDRESS = $(grep '^MAIL_FROM_ADDRESS=' "$ENV" | cut -d= -f2- || echo '(niet gezet)')"
echo "  MAIL_MAILER    = $(grep '^MAIL_MAILER=' "$ENV" | cut -d= -f2- || echo '(niet gezet)')"
echo "  GYMIES_MAIL_BRAND = $(grep '^GYMIES_MAIL_BRAND=' "$ENV" | cut -d= -f2- || echo '(niet gezet)')"
DIAG

echo ""

# ── STAP 2: Diagnose — crontab audit ──
echo "2. Volledige crontab (zoek naar artisan schedule:run)..."
ssh -i "$SSH_KEY" "$SSH_HOST" << 'CRONTAB_DIAG'
echo "  === Crontab voor huidige user ==="
crontab -l 2>/dev/null | head -60 || echo "  (geen crontab)"
echo ""
echo "  === Check op artisan schedule:run ==="
if crontab -l 2>/dev/null | grep -q "schedule:run"; then
    echo "  ⚠️  GEVONDEN: artisan schedule:run in crontab!"
    crontab -l 2>/dev/null | grep "schedule:run"
else
    echo "  ✓ Geen artisan schedule:run gevonden"
fi
echo ""
echo "  === Check op MAILTO ==="
if crontab -l 2>/dev/null | grep -qi "MAILTO"; then
    echo "  ⚠️  MAILTO gezet:"
    crontab -l 2>/dev/null | grep -i "MAILTO"
else
    echo "  ✓ Geen MAILTO in crontab"
fi
echo ""
echo "  === Check www-data crontab ==="
sudo crontab -l -u www-data 2>/dev/null | head -20 || echo "  (geen www-data crontab)"
echo ""
echo "  === Check root crontab ==="
sudo crontab -l 2>/dev/null | head -20 || echo "  (geen root crontab)"
CRONTAB_DIAG

echo ""

# ── STAP 3: Fix .env — zet APP_NAME en MAIL_FROM_NAME op Gymies ──
echo "3. Fix .env instellingen..."
ssh -i "$SSH_KEY" "$SSH_HOST" << 'FIX_ENV'
ENV="/var/www/gymies/.env"
BACKUP="/var/www/gymies/.env.backup.$(date +%Y%m%d_%H%M%S)"

# Backup
cp "$ENV" "$BACKUP"
echo "  Backup: $BACKUP"

# Fix APP_NAME
if grep -q '^APP_NAME=' "$ENV"; then
    sed -i 's/^APP_NAME=.*/APP_NAME=Gymies/' "$ENV"
    echo "  ✓ APP_NAME → Gymies (was: $(grep '^APP_NAME=' "$BACKUP" | cut -d= -f2-))"
else
    echo 'APP_NAME=Gymies' >> "$ENV"
    echo "  ✓ APP_NAME=Gymies toegevoegd"
fi

# Fix MAIL_FROM_NAME
if grep -q '^MAIL_FROM_NAME=' "$ENV"; then
    CURRENT=$(grep '^MAIL_FROM_NAME=' "$ENV" | cut -d= -f2-)
    # Alleen fixen als het "Laravel" is of leeg
    if echo "$CURRENT" | grep -qi '^"*laravel"*$\|^$'; then
        sed -i 's/^MAIL_FROM_NAME=.*/MAIL_FROM_NAME="Gymies"/' "$ENV"
        echo "  ✓ MAIL_FROM_NAME → \"Gymies\" (was: $CURRENT)"
    else
        echo "  ✓ MAIL_FROM_NAME is al goed: $CURRENT"
    fi
else
    echo 'MAIL_FROM_NAME="Gymies"' >> "$ENV"
    echo "  ✓ MAIL_FROM_NAME=\"Gymies\" toegevoegd"
fi

# Zorg dat GYMIES_MAIL_BRAND ook gezet is
if ! grep -q '^GYMIES_MAIL_BRAND=' "$ENV"; then
    echo 'GYMIES_MAIL_BRAND=Gymies' >> "$ENV"
    echo "  ✓ GYMIES_MAIL_BRAND=Gymies toegevoegd"
else
    echo "  ✓ GYMIES_MAIL_BRAND al aanwezig: $(grep '^GYMIES_MAIL_BRAND=' "$ENV" | cut -d= -f2-)"
fi

echo ""
echo "  Nieuwe waarden:"
echo "  APP_NAME       = $(grep '^APP_NAME=' "$ENV" | cut -d= -f2-)"
echo "  MAIL_FROM_NAME = $(grep '^MAIL_FROM_NAME=' "$ENV" | cut -d= -f2-)"
echo "  GYMIES_MAIL_BRAND = $(grep '^GYMIES_MAIL_BRAND=' "$ENV" | cut -d= -f2-)"
FIX_ENV

echo ""

# ── STAP 4: Verwijder artisan schedule:run uit crontab (als aanwezig) ──
echo "4. Verwijder eventuele artisan schedule:run uit crontab..."
ssh -i "$SSH_KEY" "$SSH_HOST" << 'FIX_CRONTAB'
if crontab -l 2>/dev/null | grep -q "schedule:run"; then
    echo "  ⚠️  Verwijder artisan schedule:run..."
    crontab -l 2>/dev/null | grep -v "schedule:run" | crontab -
    echo "  ✓ Verwijderd"
else
    echo "  ✓ Geen artisan schedule:run om te verwijderen"
fi

# Verwijder ook MAILTO als het gezet is (voorkomt systeem-mails van cron output)
if crontab -l 2>/dev/null | grep -qi "^MAILTO="; then
    echo "  ⚠️  MAILTO gevonden, zet op leeg (geen cron-mails)..."
    # Vervang MAILTO=xxx door MAILTO="" (geen mails)
    crontab -l 2>/dev/null | sed 's/^MAILTO=.*/MAILTO=""/' | crontab -
    echo "  ✓ MAILTO=\"\" gezet"
fi

# Check www-data ook
if sudo crontab -l -u www-data 2>/dev/null | grep -q "schedule:run"; then
    echo "  ⚠️  www-data heeft ook schedule:run, verwijderen..."
    sudo crontab -l -u www-data 2>/dev/null | grep -v "schedule:run" | sudo crontab -u www-data -
    echo "  ✓ www-data schedule:run verwijderd"
fi
FIX_CRONTAB

echo ""

# ── STAP 5: Clear config cache zodat nieuwe .env waarden actief worden ──
echo "5. Config cache vernieuwen..."
ssh -i "$SSH_KEY" "$SSH_HOST" << CACHE
cd $LARAVEL_PATH
sudo -u www-data php artisan config:clear 2>/dev/null || php artisan config:clear
sudo -u www-data php artisan config:cache 2>/dev/null || php artisan config:cache
echo "  ✓ Config cache vernieuwd"
CACHE

echo ""

# ── STAP 6: Verificatie ──
echo "6. Verificatie..."
ssh -i "$SSH_KEY" "$SSH_HOST" << 'VERIFY'
ENV="/var/www/gymies/.env"
echo "  .env waarden:"
echo "    APP_NAME       = $(grep '^APP_NAME=' "$ENV" | cut -d= -f2-)"
echo "    MAIL_FROM_NAME = $(grep '^MAIL_FROM_NAME=' "$ENV" | cut -d= -f2-)"
echo "    GYMIES_MAIL_BRAND = $(grep '^GYMIES_MAIL_BRAND=' "$ENV" | cut -d= -f2-)"
echo ""
echo "  Cached config check:"
cd /var/www/gymies
php artisan tinker --execute="echo 'app.name = ' . config('app.name') . PHP_EOL . 'mail.from.name = ' . config('mail.from.name') . PHP_EOL;" 2>/dev/null || echo "  (tinker niet beschikbaar)"
echo ""
echo "  Crontab schedule:run check:"
if crontab -l 2>/dev/null | grep -q "schedule:run"; then
    echo "    ⚠️  NOG STEEDS aanwezig!"
else
    echo "    ✓ Geen schedule:run in crontab"
fi
echo ""
echo "  Crontab MAILTO check:"
if crontab -l 2>/dev/null | grep -qi '^MAILTO=[^"]'; then
    crontab -l 2>/dev/null | grep -i "^MAILTO"
else
    echo "    ✓ MAILTO is leeg of niet gezet"
fi
VERIFY

echo ""
echo "═══ Klaar! ═══"
echo ""
echo "De emails met onderwerp 'Laravel' zouden nu moeten stoppen."
echo "Wacht maximaal 30 minuten om te verifiëren dat er geen nieuwe mail komt."
echo ""
echo "Als er nog steeds mails komen, check dan:"
echo "  1. /var/log/mail.log op de server"
echo "  2. sudo grep -r 'schedule:run' /etc/cron*"
echo "  3. systemctl list-timers (voor systemd timers)"
