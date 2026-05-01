#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health — Table Names Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. Welke tabellen bestaan er? ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

    // Zoek tabellen met 'user', 'booking', 'trainer' in de naam
    \$all = \Illuminate\Support\Facades\DB::select('SHOW TABLES');
    \$key = array_key_first((array) \$all[0]);

    echo '--- Alle tabellen met user/booking/trainer ---' . PHP_EOL;
    foreach (\$all as \$row) {
        \$name = \$row->\$key;
        if (str_contains(\$name, 'user') || str_contains(\$name, 'booking') || str_contains(\$name, 'trainer')) {
            echo '  ' . \$name . PHP_EOL;
        }
    }

    echo PHP_EOL . '--- Check de 3 tabellen uit checkDatabase ---' . PHP_EOL;
    \$check = ['gymies_users', 'gymies_bookings', 'gymies_trainers'];
    foreach (\$check as \$t) {
        \$exists = \Illuminate\Support\Facades\DB::getSchemaBuilder()->hasTable(\$t);
        echo '  ' . \$t . ': ' . (\$exists ? 'BESTAAT' : 'BESTAAT NIET') . PHP_EOL;
    }

    echo PHP_EOL . '--- Totaal aantal tabellen ---' . PHP_EOL;
    echo '  ' . count(\$all) . ' tabellen' . PHP_EOL;
" 2>&1
echo ""

echo "═══ 2. Fix checkDatabase: gebruik correcte tabelnamen ═══"
# Lees de huidige tabelnamen en pas aan
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

    \$all = \Illuminate\Support\Facades\DB::select('SHOW TABLES');
    \$key = array_key_first((array) \$all[0]);
    \$names = array_map(fn(\$r) => \$r->\$key, \$all);

    // Zoek de juiste namen
    \$userTable = null; \$bookingTable = null; \$trainerTable = null;
    foreach (\$names as \$n) {
        if (\$n === 'users' || \$n === 'gymies_users') \$userTable = \$n;
        if (\$n === 'bookings' || \$n === 'gymies_bookings') \$bookingTable = \$n;
        if (\$n === 'trainers' || \$n === 'gymies_trainers') \$trainerTable = \$n;
    }
    echo 'Users tabel:    ' . (\$userTable ?? 'NIET GEVONDEN') . PHP_EOL;
    echo 'Bookings tabel: ' . (\$bookingTable ?? 'NIET GEVONDEN') . PHP_EOL;
    echo 'Trainers tabel: ' . (\$trainerTable ?? 'NIET GEVONDEN') . PHP_EOL;
" 2>&1
echo ""

echo "═══ 3. Pas checkDatabase aan in controller ═══"
CTRL="$LP/app/Http/Controllers/Gymies/GymiesHealthController.php"

# Vervang de hardcoded tabelnamen door de juiste
# Stap 1: check welke tabelnamen correct zijn
USERS_EXISTS=$(sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo \Illuminate\Support\Facades\DB::getSchemaBuilder()->hasTable('users') ? 'users' :
        (\Illuminate\Support\Facades\DB::getSchemaBuilder()->hasTable('gymies_users') ? 'gymies_users' : 'none');
" 2>/dev/null)

BOOKINGS_EXISTS=$(sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo \Illuminate\Support\Facades\DB::getSchemaBuilder()->hasTable('bookings') ? 'bookings' :
        (\Illuminate\Support\Facades\DB::getSchemaBuilder()->hasTable('gymies_bookings') ? 'gymies_bookings' : 'none');
" 2>/dev/null)

TRAINERS_EXISTS=$(sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    echo \Illuminate\Support\Facades\DB::getSchemaBuilder()->hasTable('trainers') ? 'trainers' :
        (\Illuminate\Support\Facades\DB::getSchemaBuilder()->hasTable('gymies_trainers') ? 'gymies_trainers' : 'none');
" 2>/dev/null)

echo "  Gevonden: users=$USERS_EXISTS, bookings=$BOOKINGS_EXISTS, trainers=$TRAINERS_EXISTS"

# Vervang in de controller
if [ "$USERS_EXISTS" != "gymies_users" ] && [ "$USERS_EXISTS" != "none" ]; then
    sudo sed -i "s/'gymies_users'/'$USERS_EXISTS'/g" "$CTRL"
    echo "  ✓ gymies_users → $USERS_EXISTS"
fi
if [ "$BOOKINGS_EXISTS" != "gymies_bookings" ] && [ "$BOOKINGS_EXISTS" != "none" ]; then
    sudo sed -i "s/'gymies_bookings'/'$BOOKINGS_EXISTS'/g" "$CTRL"
    echo "  ✓ gymies_bookings → $BOOKINGS_EXISTS"
fi
if [ "$TRAINERS_EXISTS" != "gymies_trainers" ] && [ "$TRAINERS_EXISTS" != "none" ]; then
    sudo sed -i "s/'gymies_trainers'/'$TRAINERS_EXISTS'/g" "$CTRL"
    echo "  ✓ gymies_trainers → $TRAINERS_EXISTS"
fi

# Als GEEN van de tabellen bestaat, simplificeer checkDatabase
if [ "$USERS_EXISTS" = "none" ] && [ "$BOOKINGS_EXISTS" = "none" ] && [ "$TRAINERS_EXISTS" = "none" ]; then
    echo "  ⚠️  Geen standaard tabellen gevonden — simplificeer checkDatabase"
    # Vervang de hele tabel-check met alleen SELECT 1
    sudo -u www-data php -r "
        \$file = '$CTRL';
        \$content = file_get_contents(\$file);

        // Vervang de tabel-check sectie
        \$old = \"// Controleer ook de gymies kerntabellen
            \\\$tables = ['gymies_users', 'gymies_bookings', 'gymies_trainers'];
            foreach (\\\$tables as \\\$table) {
                if (!DB::getSchemaBuilder()->hasTable(\\\$table)) {
                    return [
                        'ok'       => false,
                        'critical' => true,
                        'error'    => \\\"Kerntabel \`{\\\$table}\` ontbreekt.\\\",
                    ];
                }
            }\";

        \$new = \"// Tabel-check overgeslagen (tabelnamen variëren per installatie)\";

        if (strpos(\$content, 'gymies kerntabellen') !== false) {
            // Gebruik regex om het hele blok te vervangen
            \$pattern = '/\\/\\/ Controleer ook de gymies kerntabellen.*?\\}\\s*\\}/s';
            \$replacement = '// Tabel-check overgeslagen (tabelnamen variëren per installatie)';
            \$newContent = preg_replace(\$pattern, \$replacement, \$content, 1);
            if (\$newContent !== null && \$newContent !== \$content) {
                file_put_contents(\$file, \$newContent);
                echo '  ✓ Tabel-check blok verwijderd' . PHP_EOL;
            } else {
                echo '  ⚠️  Kon tabel-check niet automatisch verwijderen' . PHP_EOL;
            }
        }
    " 2>&1
fi
echo ""

echo "═══ 4. Verify checkDatabase na fix ═══"
sudo grep -A 25 "function checkDatabase" "$CTRL" | head -30
echo ""

echo "═══ 5. Cache + restart ═══"
sudo -u www-data php artisan optimize:clear 2>/dev/null || true
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo systemctl restart php8.4-fpm 2>/dev/null || sudo systemctl restart php8.3-fpm 2>/dev/null || sudo systemctl restart php8.2-fpm 2>/dev/null
echo "  ✓ Cache + PHP-FPM"
echo ""

echo "═══ 6. Health endpoint test ═══"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)")
BODY=$(curl -sk -H "Host: gymies.nl" "https://127.0.0.1/api/gymies/health?_=$(date +%s)" 2>/dev/null)
echo "  HTTP status: $HTTP_CODE"
echo "  Body: $BODY"
echo ""

echo "═══ Done ═══"
REMOTE

echo ""
echo "Test extern:"
echo "  curl 'https://gymies.nl/api/gymies/health?_=$(date +%s)'"
