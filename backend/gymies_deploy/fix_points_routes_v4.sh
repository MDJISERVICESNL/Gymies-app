#!/bin/bash
# =============================================================================
# Fix: Verplaats points routes NAAR BINNEN de auth middleware groep
# =============================================================================
# Probleem: fix_points_routes_v3.sh plaatste routes na 'referral/validate' (publiek)
#           in plaats van na 'referral/my-code' (beveiligd). Hierdoor draait de
#           auth middleware niet, controller krijgt null user, geeft 401 terug,
#           en de app logt automatisch uit.
#
# Run: ssh gymies "bash -s" < backend/gymies_deploy/fix_points_routes_v4.sh
# =============================================================================

set -e
cd /var/www/gymies

ROUTES="/var/www/gymies/gymies_deploy/routes_gymies_full.php"

echo "============================================"
echo "  FIX: Points routes → auth middleware groep"
echo "============================================"
echo ""

echo "▸ Backup maken..."
sudo cp "$ROUTES" "${ROUTES}.bak_v4_$(date +%Y%m%d_%H%M%S)"
echo "  ✅ Backup gemaakt"

echo ""
echo "▸ Routes fixen..."

# Kopieer naar /tmp voor bewerkingen
cp "$ROUTES" /tmp/routes_fix_v4.php

php -r "
\$file = '/tmp/routes_fix_v4.php';
\$content = file_get_contents(\$file);

// === Stap 1: Verwijder ALLE bestaande points routes (waar ze ook staan) ===
\$lines = explode(\"\\n\", \$content);
\$filtered = [];
\$skipComment = false;

foreach (\$lines as \$line) {
    // Skip de comment-regel die bij de points routes hoort
    if (trim(\$line) === '// Gymies Punten: saldo, geschiedenis, inwisselen') {
        \$skipComment = true;
        continue;
    }
    // Skip de 3 route regels
    if (strpos(\$line, \"points/balance\") !== false && strpos(\$line, \"Route::\") !== false) continue;
    if (strpos(\$line, \"points/history\") !== false && strpos(\$line, \"Route::\") !== false) continue;
    if (strpos(\$line, \"points/redeem\") !== false && strpos(\$line, \"Route::\") !== false) continue;

    \$skipComment = false;
    \$filtered[] = \$line;
}

\$content = implode(\"\\n\", \$filtered);
echo \"  ✅ Stap 1: Bestaande points routes verwijderd\\n\";

// === Stap 2: Voeg routes toe NA 'referral/my-code' (BINNEN auth groep) ===
\$marker = \"referral/my-code\";
\$pos = strpos(\$content, \$marker);

if (\$pos === false) {
    echo \"  ❌ Marker 'referral/my-code' niet gevonden!\\n\";
    exit(1);
}

// Vind het einde van de regel met referral/my-code
\$lineEnd = strpos(\$content, \"\\n\", \$pos);
if (\$lineEnd === false) {
    echo \"  ❌ Einde van regel niet gevonden\\n\";
    exit(1);
}

\$pointsRoutes = \"\\n\" .
    \"\\n\" .
    \"        // Gymies Punten: saldo, geschiedenis, inwisselen\\n\" .
    \"        Route::get('points/balance', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'balance'])->name('points.balance');\\n\" .
    \"        Route::get('points/history', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'history'])->name('points.history');\\n\" .
    \"        Route::post('points/redeem', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesPointsController::class, 'redeem'])->name('points.redeem');\";

\$content = substr(\$content, 0, \$lineEnd) . \$pointsRoutes . substr(\$content, \$lineEnd);

file_put_contents(\$file, \$content);
echo \"  ✅ Stap 2: Points routes toegevoegd na 'referral/my-code' (auth groep)\\n\";
"

# Kopieer terug met sudo
sudo cp /tmp/routes_fix_v4.php "$ROUTES"
sudo chown www-data:www-data "$ROUTES" 2>/dev/null || true
rm -f /tmp/routes_fix_v4.php
echo "  ✅ Bestand opgeslagen"

echo ""

# Cache legen
echo "▸ Caches legen..."
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

echo ""

# Verificatie
echo "▸ Verificatie..."

# Check 1: Staan de routes op de juiste plek?
echo "  📍 Positie-check:"
php -r "
\$content = file_get_contents('$ROUTES');

// Zoek de auth middleware groep
\$authPos = strpos(\$content, 'EnsureGymiesAuthPreempt');
\$pointsPos = strpos(\$content, 'points/balance');
\$publicRefPos = strpos(\$content, \"referral/validate\");
\$authRefPos = strpos(\$content, \"referral/my-code\");

if (\$authPos === false) { echo \"  ❌ Auth middleware niet gevonden\\n\"; exit(1); }
if (\$pointsPos === false) { echo \"  ❌ Points routes niet gevonden\\n\"; exit(1); }

if (\$pointsPos > \$authPos) {
    echo \"  ✅ Points routes staan NA auth middleware (correct!)\\n\";
} else {
    echo \"  ❌ Points routes staan VOOR auth middleware (fout!)\\n\";
}

if (\$pointsPos > \$authRefPos) {
    echo \"  ✅ Points routes staan na referral/my-code (auth groep)\\n\";
} else {
    echo \"  ❌ Points routes staan voor referral/my-code\\n\";
}

// Check dat er geen dubbele routes zijn
\$count = substr_count(\$content, 'points/balance');
echo \"  📊 Aantal keer 'points/balance': \$count\" . (\$count === 1 ? ' ✅' : ' ❌ DUBBEL!') . \"\\n\";
"

echo ""

# Check 2: Laravel route registratie
echo "  🔗 Route registratie:"
php artisan tinker --execute="
\$routes = collect(\Illuminate\Support\Facades\Route::getRoutes())
    ->filter(fn(\$r) => str_contains(\$r->uri(), 'points'));

if (\$routes->isEmpty()) {
    echo \"  ❌ Geen points routes gevonden\\n\";
} else {
    foreach (\$routes as \$r) {
        \$middleware = implode(', ', \$r->middleware());
        echo '  ✅ ' . \$r->methods()[0] . ' ' . \$r->uri() . \" [middleware: \$middleware]\\n\";
    }
}
"

echo ""
echo "============================================"
echo "  Fix complete!                             "
echo "  Test: klik op 'Mijn Tegoed' in de app     "
echo "============================================"
