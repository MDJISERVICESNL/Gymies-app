#!/bin/bash
# Fix: voeg points routes toe aan server
# Run: ssh gymies "bash -s" < backend/gymies_deploy/fix_points_routes.sh
set -e
cd /var/www/gymies

echo "▸ Finding routes file and adding points routes..."

# Zoek welk bestand de gymies routes bevat
ROUTES_FILE=""
for f in routes/web.php routes/api.php; do
    if [ -f "$f" ] && grep -q "api/gymies" "$f" 2>/dev/null; then
        ROUTES_FILE="$f"
        break
    fi
done

# Check ook of er een apart gymies routes bestand is
for f in routes/gymies.php routes/gymies_api.php; do
    if [ -f "$f" ]; then
        ROUTES_FILE="$f"
        break
    fi
done

if [ -z "$ROUTES_FILE" ]; then
    echo "  ❌ Kon geen routes bestand vinden met gymies routes"
    echo "  Zoeken in alle route bestanden..."
    grep -rl "gymies" routes/ 2>/dev/null || echo "  Geen gevonden in routes/"
    exit 1
fi

echo "  📄 Routes bestand: $ROUTES_FILE"

# Check of points routes al bestaan
if grep -q "points/balance" "$ROUTES_FILE" 2>/dev/null; then
    echo "  ⏭️ Points routes bestaan al in $ROUTES_FILE"
else
    # Probeer diverse markers om de juiste plek te vinden
    php << 'PHPEOF'
<?php
$file = null;
foreach (['routes/web.php', 'routes/api.php', 'routes/gymies.php'] as $f) {
    if (file_exists($f) && strpos(file_get_contents($f), 'api/gymies') !== false) {
        $file = $f;
        break;
    }
}
if (!$file) {
    // Zoek breder
    foreach (glob('routes/*.php') as $f) {
        if (strpos(file_get_contents($f), 'gymies') !== false) {
            $file = $f;
            break;
        }
    }
}
if (!$file) {
    echo "  ❌ Kon geen gymies routes bestand vinden\n";
    exit(1);
}

$content = file_get_contents($file);

// Probeer diverse markers
$markers = [
    "referral/my-code",
    "referral",
    "conversations",
    "bookings",
    "trainer/summary",
];

$inserted = false;
foreach ($markers as $marker) {
    $pos = strpos($content, $marker);
    if ($pos !== false) {
        // Vind het einde van de regel
        $lineEnd = strpos($content, "\n", $pos);
        if ($lineEnd === false) continue;

        $routes = "\n" .
            "        // Gymies Punten: saldo, geschiedenis, inwisselen\n" .
            "        Route::get('points/balance', [\\App\\Http\\Controllers\\Gymies\\GymiesPointsController::class, 'balance'])->name('points.balance');\n" .
            "        Route::get('points/history', [\\App\\Http\\Controllers\\Gymies\\GymiesPointsController::class, 'history'])->name('points.history');\n" .
            "        Route::post('points/redeem', [\\App\\Http\\Controllers\\Gymies\\GymiesPointsController::class, 'redeem'])->name('points.redeem');\n";

        $content = substr($content, 0, $lineEnd + 1) . $routes . substr($content, $lineEnd + 1);
        file_put_contents($file, $content);
        echo "  ✅ Points routes toegevoegd na '$marker' in $file\n";
        $inserted = true;
        break;
    }
}

if (!$inserted) {
    echo "  ❌ Geen geschikte locatie gevonden\n";
    echo "  Bestand inhoud (eerste 50 regels):\n";
    $lines = explode("\n", $content);
    foreach (array_slice($lines, 0, 50) as $i => $line) {
        echo "  " . ($i+1) . ": $line\n";
    }
}
PHPEOF
fi

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
php artisan tinker --execute="
\$has = \Illuminate\Support\Facades\Route::has('api.gymies.points.balance');
echo \$has ? '  ✅ Route points/balance geregistreerd' : '  ❌ Route points/balance NIET gevonden';
echo \"\n\";
if (!\$has) {
    // Debug: zoek alle points routes
    \$routes = collect(\Illuminate\Support\Facades\Route::getRoutes())->filter(fn(\$r) => str_contains(\$r->uri(), 'points'));
    if (\$routes->isEmpty()) {
        echo \"  ℹ️ Geen 'points' routes gevonden in router\n\";
        // Zoek alle gymies routes voor context
        \$gymies = collect(\Illuminate\Support\Facades\Route::getRoutes())->filter(fn(\$r) => str_contains(\$r->uri(), 'gymies'))->take(5);
        echo \"  ℹ️ Eerste 5 gymies routes:\n\";
        foreach (\$gymies as \$r) {
            echo \"    \" . \$r->methods()[0] . \" \" . \$r->uri() . \"\n\";
        }
    } else {
        foreach (\$routes as \$r) {
            echo \"  → \" . \$r->methods()[0] . \" \" . \$r->uri() . \" (\" . \$r->getName() . \")\n\";
        }
    }
}
"

echo ""
echo "============================================"
echo "  Done!                                     "
echo "============================================"
