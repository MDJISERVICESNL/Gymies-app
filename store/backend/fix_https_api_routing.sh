#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix HTTPS API routing                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e

echo "============================================"
echo "  STEP 1: Dump FULL nginx configs"
echo "============================================"
echo ""

echo "--- /etc/nginx/sites-enabled/gymiesapp (FULL) ---"
sudo cat -n /etc/nginx/sites-enabled/gymiesapp
echo ""
echo "--- /etc/nginx/sites-enabled/default (FULL) ---"
sudo cat -n /etc/nginx/sites-enabled/default

echo ""
echo "============================================"
echo "  STEP 2: Check Laravel route list for trainer routes"
echo "============================================"
cd /var/www/gymies
sudo -u www-data php artisan route:list --path=trainers 2>/dev/null | head -30 || echo "route:list failed"

echo ""
echo "============================================"
echo "  STEP 3: Check what 'Trainer niet gevonden' returns"
echo "============================================"
echo "Searching for 'Trainer niet gevonden' in controllers..."
sudo grep -rn "Trainer niet gevonden" /var/www/gymies/app/Http/Controllers/ 2>/dev/null || echo "Not found in controllers"
echo ""
echo "Searching in all PHP files..."
sudo grep -rn "Trainer niet gevonden" /var/www/gymies/app/ 2>/dev/null | head -10 || echo "Not found"

echo ""
echo "============================================"
echo "  STEP 4: Quick test — what does HTTPS return?"
echo "============================================"
echo "Test A: HTTPS www.gymiesapp.nl /api/gymies/trainers/27/availability"
RESP_A=$(wget -qO- --no-check-certificate --header="Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05" 2>/dev/null || echo "WGET_FAILED")
echo "  Response: $RESP_A"

echo ""
echo "Test B: HTTP 127.0.0.1 with Host: www.gymiesapp.nl"
RESP_B=$(wget -qO- --header="Accept: application/json" --header="Host: www.gymiesapp.nl" \
  "http://127.0.0.1/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05" 2>/dev/null || echo "WGET_FAILED")
echo "  Response (first 200): $(echo "$RESP_B" | head -c 200)"

echo ""
echo "Test C: HTTP 127.0.0.1 with Host: localhost"
RESP_C=$(wget -qO- --header="Accept: application/json" --header="Host: localhost" \
  "http://127.0.0.1/api/gymies/trainers/27/availability?from=2026-04-28&to=2026-05-05" 2>/dev/null || echo "WGET_FAILED")
echo "  Response (first 200): $(echo "$RESP_C" | head -c 200)"

echo ""
echo "Test D: HTTPS www.gymiesapp.nl /api/gymies/trainers/27 (WITHOUT /availability)"
RESP_D=$(wget -qO- --no-check-certificate --header="Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null || echo "WGET_FAILED")
echo "  Response (first 200): $(echo "$RESP_D" | head -c 200)"

echo ""
echo "============================================"
echo "  STEP 5: Check routes/gymies.php for route order"
echo "============================================"
echo "--- routes/gymies.php (trainer section) ---"
sudo grep -n -A2 -B2 'trainer' /var/www/gymies/routes/gymies.php 2>/dev/null || echo "Not found"

echo ""
echo "--- Check if routes/api.php also has trainer routes ---"
sudo grep -n 'trainer' /var/www/gymies/routes/api.php 2>/dev/null || echo "Not in api.php"

echo ""
echo "--- Check all route files ---"
for f in /var/www/gymies/routes/*.php; do
  if sudo grep -q 'trainer' "$f" 2>/dev/null; then
    echo "Found 'trainer' in: $f"
    sudo grep -n 'trainer' "$f" 2>/dev/null
    echo ""
  fi
done

echo ""
echo "============================================"
echo "  STEP 6: Check RouteServiceProvider"
echo "============================================"
sudo cat -n /var/www/gymies/app/Providers/RouteServiceProvider.php 2>/dev/null || echo "Not found"

echo ""
echo "============================================"
echo "  STEP 7: Laravel logs (last trainer/availability related)"
echo "============================================"
sudo tail -50 /var/www/gymies/storage/logs/laravel.log 2>/dev/null | grep -i 'trainer\|availability\|niet gevonden\|404\|route' | tail -10 || echo "Nothing relevant"

echo ""
echo "============================================"
echo "  DONE — all diagnostics collected"
echo "============================================"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Diagnostic complete — check output above          ║"
echo "╚══════════════════════════════════════════════════════╝"
