#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Route Debug ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. Inhoud rond de health route (regels 95-115) ═══"
sudo sed -n '95,115p' "$LP/routes/gymies.php"

echo ""
echo "═══ 2. ALLE routes met 'health' in URI (geen filter) ═══"
sudo -u www-data php artisan route:list 2>&1 | grep -i "health" || echo "  (geen health routes gevonden)"

echo ""
echo "═══ 3. ALLE routes met 'app-version' in URI ═══"
sudo -u www-data php artisan route:list 2>&1 | grep -i "app-version" || echo "  (geen app-version routes gevonden)"

echo ""
echo "═══ 4. Eerste 10 routes (controleer prefix) ═══"
sudo -u www-data php artisan route:list 2>&1 | head -15

echo ""
echo "═══ 5. Route via Tinker checken ═══"
sudo -u www-data php artisan tinker --execute="
    \$route = app('router')->getRoutes()->getByName('api.gymies.health');
    if (\$route) {
        echo 'GEVONDEN: ' . \$route->uri() . ' → ' . \$route->getActionName() . PHP_EOL;
    } else {
        echo 'NIET GEVONDEN als api.gymies.health' . PHP_EOL;
        // Zoek handmatig
        foreach (app('router')->getRoutes() as \$r) {
            if (str_contains(\$r->uri(), 'health')) {
                echo '  Route: ' . implode('|', \$r->methods()) . ' ' . \$r->uri() . ' → ' . \$r->getName() . PHP_EOL;
            }
        }
    }
" 2>&1

echo ""
echo "═══ 6. Direct PHP test: laadt de route file correct? ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$kernel = \$app->make(\Illuminate\Contracts\Http\Kernel::class);

    // Check cached routes
    \$cachePath = '$LP/bootstrap/cache/routes-v7.php';
    if (file_exists(\$cachePath)) {
        echo 'Route cache BESTAAT (' . round(filesize(\$cachePath)/1024) . ' KB)' . PHP_EOL;
        \$cached = file_get_contents(\$cachePath);
        if (strpos(\$cached, 'api/gymies/health') !== false) {
            echo '  ✓ api/gymies/health ZIT in route cache' . PHP_EOL;
        } else {
            echo '  ✗ api/gymies/health NIET in route cache!' . PHP_EOL;
        }
        if (strpos(\$cached, 'app-version') !== false) {
            echo '  ✓ app-version ZIT in route cache' . PHP_EOL;
        } else {
            echo '  ✗ app-version NIET in route cache!' . PHP_EOL;
        }
    } else {
        echo 'Geen route cache bestand gevonden' . PHP_EOL;
    }
" 2>&1

echo ""
echo "═══ 7. web.php volledig tonen ═══"
sudo cat "$LP/routes/web.php"

echo ""
echo "═══ Done ═══"
REMOTE
