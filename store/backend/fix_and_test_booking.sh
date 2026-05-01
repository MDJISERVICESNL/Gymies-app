#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== PHP versie check ==="
php -v | head -1
echo ""

echo "=== Juiste PHP-FPM herstarten (8.4) ==="
sudo systemctl restart php8.4-fpm
sleep 1
echo "✓ php8.4-fpm herstart"
sudo systemctl status php8.4-fpm --no-pager | head -5

echo ""
echo "=== Caches rebuilden ==="
php artisan config:cache
php artisan route:cache

echo ""
echo "=== Nginx server_name check ==="
grep -r "server_name" /etc/nginx/sites-enabled/ 2>/dev/null | head -5

echo ""
echo "=== Login test ==="
# Probeer met server IP
DOMAIN=$(grep -r "server_name" /etc/nginx/sites-enabled/ 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';')
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "_" ]; then
    DOMAIN="18.159.130.187"
fi
echo "Test domain: $DOMAIN"

LOGIN_RESP=$(curl -s -X POST "http://$DOMAIN/api/gymies/login" \
    -H "Content-Type: application/json" \
    -H "Host: $DOMAIN" \
    -d '{"email":"testklant@gymies.nl","password":"TestKlant2026!"}')
echo "Login response: ${LOGIN_RESP:0:300}"

TOKEN=$(echo "$LOGIN_RESP" | php -r "\$d=json_decode(file_get_contents('php://stdin'),true); echo \$d['token'] ?? 'GEEN';")
echo "Token: ${TOKEN:0:30}..."

if [ "$TOKEN" = "GEEN" ] || [ -z "$TOKEN" ]; then
    echo ""
    echo "Login failed. Probeer met 127.0.0.1 + Host header..."
    LOGIN_RESP=$(curl -s -X POST "http://127.0.0.1/api/gymies/login" \
        -H "Content-Type: application/json" \
        -H "Host: $DOMAIN" \
        -d '{"email":"testklant@gymies.nl","password":"TestKlant2026!"}')
    echo "Response: ${LOGIN_RESP:0:300}"
    TOKEN=$(echo "$LOGIN_RESP" | php -r "\$d=json_decode(file_get_contents('php://stdin'),true); echo \$d['token'] ?? 'GEEN';")
fi

if [ "$TOKEN" = "GEEN" ] || [ -z "$TOKEN" ]; then
    echo ""
    echo "⚠ Login werkt niet via curl. Test booking direct via PHP..."
    echo ""
    php -r "
    require '/var/www/gymies/vendor/autoload.php';
    \$app = require_once '/var/www/gymies/bootstrap/app.php';
    \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
    \$kernel->bootstrap();

    // Simuleer de booking flow stap voor stap
    echo '=== Stap 1: Klant ophalen ===' . PHP_EOL;
    \$user = DB::table('gymies_users')->where('email', 'testklant@gymies.nl')->first();
    if (!\$user) { echo 'FOUT: testklant niet gevonden!' . PHP_EOL; exit(1); }
    echo 'Klant: ID=' . \$user->id . ' role=' . \$user->role . PHP_EOL;

    echo PHP_EOL . '=== Stap 2: Trainer ophalen ===' . PHP_EOL;
    \$trainer = DB::table('gymies_users')->where('id', 27)->where('role', 'trainer')->first();
    if (!\$trainer) { echo 'FOUT: trainer 27 niet gevonden!' . PHP_EOL; exit(1); }
    echo 'Trainer: ID=' . \$trainer->id . ' name=' . (\$trainer->display_name ?? 'n/a') . PHP_EOL;

    echo PHP_EOL . '=== Stap 3: Prijs bepalen ===' . PHP_EOL;
    \$profileCols = DB::getSchemaBuilder()->getColumnListing('gymies_trainer_profiles');
    echo 'Profiel kolommen (prijs-gerelateerd): ';
    \$priceCols = array_intersect(['session_price_cents', 'hourly_rate_cents', 'trial_session_cents'], \$profileCols);
    echo implode(', ', \$priceCols) . PHP_EOL;

    \$profile = DB::table('gymies_trainer_profiles')->where('user_id', 27)->first(\$priceCols);
    if (\$profile) {
        foreach (\$priceCols as \$col) {
            echo '  ' . \$col . ': ' . (\$profile->\$col ?? 'NULL') . PHP_EOL;
        }
        \$price = (int)(\$profile->session_price_cents ?? 0);
        if (\$price === 0) \$price = (int)(\$profile->hourly_rate_cents ?? 0);
        if (\$price === 0) \$price = (int)(\$profile->trial_session_cents ?? 0);
        echo '  → Berekende prijs: ' . \$price . ' cents (€' . number_format(\$price/100, 2) . ')' . PHP_EOL;
    }

    echo PHP_EOL . '=== Stap 4: Beschikbaarheid check ===' . PHP_EOL;
    if (Schema::hasTable('gymies_availability_slots')) {
        \$slots = DB::table('gymies_availability_slots')
            ->where('trainer_user_id', 27)
            ->where('is_active', 1)
            ->limit(5)
            ->get(['id', 'day_of_week', 'start_time', 'end_time']);
        echo 'Actieve slots: ' . \$slots->count() . PHP_EOL;
        foreach (\$slots as \$s) {
            echo '  dag=' . \$s->day_of_week . ' ' . \$s->start_time . '-' . \$s->end_time . PHP_EOL;
        }
    } else {
        echo 'gymies_availability_slots tabel bestaat niet!' . PHP_EOL;
    }

    echo PHP_EOL . '=== Stap 5: Overlap/conflict check ===' . PHP_EOL;
    \$existing = DB::table('gymies_bookings')
        ->where('trainer_user_id', 27)
        ->whereIn('status', ['pending', 'confirmed', 'reserved'])
        ->where('scheduled_at', '>=', now())
        ->limit(5)
        ->get(['id', 'status', 'scheduled_at', 'client_user_id']);
    echo 'Bestaande boekingen: ' . \$existing->count() . PHP_EOL;
    foreach (\$existing as \$b) {
        echo '  ID=' . \$b->id . ' status=' . \$b->status . ' at=' . \$b->scheduled_at . ' client=' . \$b->client_user_id . PHP_EOL;
    }

    echo PHP_EOL . '=== Stap 6: Probeer INSERT ===' . PHP_EOL;
    try {
        DB::beginTransaction();
        \$id = DB::table('gymies_bookings')->insertGetId([
            'client_user_id' => \$user->id,
            'trainer_user_id' => 27,
            'scheduled_at' => '2026-05-03 10:00:00',
            'duration_minutes' => 60,
            'amount_cents' => \$price ?? 4000,
            'status' => 'reserved',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        echo '✓ Booking INSERT geslaagd! ID=' . \$id . PHP_EOL;
        // Rollback zodat we niet echt een boeking maken
        DB::rollBack();
        echo '  (rollback — test alleen)' . PHP_EOL;
    } catch (\Throwable \$e) {
        DB::rollBack();
        echo 'FOUT bij INSERT: ' . \$e->getMessage() . PHP_EOL;
    }
    " 2>&1
fi

echo ""
echo "=== Verse errors in log ==="
tail -5 storage/logs/laravel.log 2>/dev/null | grep -i "error\|exception" || echo "(geen verse errors)"
REMOTE
