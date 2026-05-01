#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health Route Diagnose ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. Welke routes bestanden bestaan? ═══"
echo "--- routes/ directory ---"
ls -la "$LP/routes/" 2>/dev/null
echo ""

echo "═══ 2. Waar worden gymies routes geladen? ═══"
echo "--- routes/api.php (gymies referenties) ---"
sudo grep -n "gymies\|routes_gymies" "$LP/routes/api.php" 2>/dev/null | head -20 || echo "  (geen matches)"
echo ""
echo "--- routes/web.php (gymies referenties) ---"
sudo grep -n "gymies\|routes_gymies" "$LP/routes/web.php" 2>/dev/null | head -20 || echo "  (geen matches)"
echo ""
echo "--- bootstrap/app.php (routing) ---"
sudo grep -n "routing\|routes\|withRouting\|api\|web" "$LP/bootstrap/app.php" 2>/dev/null | head -20 || echo "  (geen matches)"
echo ""

echo "═══ 3. Bestaat er een routes/gymies.php? ═══"
if [ -f "$LP/routes/gymies.php" ]; then
    echo "  JA — routes/gymies.php bestaat"
    echo "--- Eerste 50 regels ---"
    sudo head -50 "$LP/routes/gymies.php"
else
    echo "  NEE — routes/gymies.php bestaat niet"
fi
echo ""

echo "═══ 4. Heeft routes/api.php een health route? ═══"
sudo grep -n "health" "$LP/routes/api.php" 2>/dev/null || echo "  (geen health route in api.php)"
echo ""

echo "═══ 5. Volledige route list voor api/gymies/health ═══"
sudo -u www-data php artisan route:list --path=api/gymies/health 2>&1 | head -10
echo ""

echo "═══ 6. Volledige route list voor api/gymies/app-version ═══"
sudo -u www-data php artisan route:list --path=api/gymies/app-version 2>&1 | head -10
echo ""

echo "═══ 7. Hoe wordt routes_gymies_full.php geladen? ═══"
sudo grep -rn "routes_gymies_full" "$LP/routes/" "$LP/bootstrap/" "$LP/app/Providers/" 2>/dev/null || echo "  (NERGENS — routes_gymies_full.php wordt niet geladen!)"
echo ""

echo "═══ Done ═══"
REMOTE
