#!/bin/bash
set -e
SSH_HOST="gymies"

ssh "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

echo '=== Klant-accounts ===' . PHP_EOL;
\$clients = DB::table('gymies_users')
    ->where('role', 'klant')
    ->select('id', 'name', 'email', 'role')
    ->orderBy('id')
    ->limit(10)
    ->get();

if (\$clients->isEmpty()) {
    echo '  Geen klant-accounts gevonden.' . PHP_EOL;
    echo PHP_EOL;
    echo '  Test-klant aanmaken...' . PHP_EOL;
    \$id = DB::table('gymies_users')->insertGetId([
        'name' => 'Test Klant',
        'display_name' => 'Test Klant',
        'email' => 'testklant@gymies.nl',
        'password' => bcrypt('TestKlant2026!'),
        'role' => 'klant',
        'created_at' => now(),
        'updated_at' => now(),
    ]);
    echo '  ✓ Test-klant aangemaakt (ID: ' . \$id . ')' . PHP_EOL;
    echo '  Email: testklant@gymies.nl' . PHP_EOL;
    echo '  Wachtwoord: TestKlant2026!' . PHP_EOL;
} else {
    foreach (\$clients as \$c) {
        echo '  ID=' . \$c->id . '  ' . str_pad(\$c->name ?? '(geen naam)', 25) . ' ' . \$c->email . PHP_EOL;
    }
}

echo PHP_EOL;
echo '=== Alle rollen ===' . PHP_EOL;
\$roles = DB::table('gymies_users')
    ->selectRaw('role, COUNT(*) as cnt')
    ->groupBy('role')
    ->orderByDesc('cnt')
    ->get();
foreach (\$roles as \$r) {
    echo '  ' . str_pad(\$r->role ?? '(null)', 15) . \$r->cnt . ' users' . PHP_EOL;
}
" 2>&1
REMOTE
