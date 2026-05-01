#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Status kolom check ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// Check ENUM values voor status kolom
\$col = DB::select(\"SHOW COLUMNS FROM gymies_bookings WHERE Field = 'status'\");
if (!empty(\$col)) {
    echo 'Status type: ' . \$col[0]->Type . PHP_EOL;
    echo 'Default: ' . (\$col[0]->Default ?? 'NULL') . PHP_EOL;
} else {
    echo 'Status kolom niet gevonden!' . PHP_EOL;
}
" 2>&1

echo ""
echo "=== reserved toevoegen aan ENUM ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$col = DB::select(\"SHOW COLUMNS FROM gymies_bookings WHERE Field = 'status'\");
\$type = \$col[0]->Type ?? '';
echo 'Huidig: ' . \$type . PHP_EOL;

if (stripos(\$type, 'reserved') !== false) {
    echo '✓ reserved zit al in de ENUM.' . PHP_EOL;
} elseif (stripos(\$type, 'enum') !== false) {
    // Extract bestaande values en voeg reserved toe
    preg_match(\"/enum\((.+)\)/i\", \$type, \$m);
    \$existing = \$m[1] ?? '';
    \$newEnum = rtrim(\$existing, ')') . \",'reserved'\";
    \$sql = \"ALTER TABLE gymies_bookings MODIFY COLUMN status ENUM(\$newEnum) DEFAULT 'pending'\";
    echo 'SQL: ' . \$sql . PHP_EOL;
    DB::unprepared(\$sql);

    // Verify
    \$col2 = DB::select(\"SHOW COLUMNS FROM gymies_bookings WHERE Field = 'status'\");
    echo 'Nieuw: ' . \$col2[0]->Type . PHP_EOL;
    echo '✓ reserved toegevoegd!' . PHP_EOL;
} else {
    echo 'Status is geen ENUM, type: ' . \$type . PHP_EOL;
}

// Test insert
echo PHP_EOL . '=== Test INSERT ===' . PHP_EOL;
try {
    DB::beginTransaction();
    \$id = DB::table('gymies_bookings')->insertGetId([
        'client_user_id' => 310,
        'trainer_user_id' => 27,
        'scheduled_at' => '2026-05-03 10:00:00',
        'duration_minutes' => 60,
        'amount_cents' => 4000,
        'status' => 'reserved',
        'payment_method' => 'cash',
        'reserved_until' => now()->addMinutes(10),
        'created_at' => now(),
        'updated_at' => now(),
    ]);
    echo '✓ INSERT OK! ID=' . \$id . PHP_EOL;
    DB::rollBack();
    echo '(rollback — test alleen)' . PHP_EOL;
} catch (\Throwable \$e) {
    DB::rollBack();
    echo 'FOUT: ' . \$e->getMessage() . PHP_EOL;
}
" 2>&1

echo ""
echo "✅ Klaar! Test de boeking opnieuw in de app."
REMOTE
