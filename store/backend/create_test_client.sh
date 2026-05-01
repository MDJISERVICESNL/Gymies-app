#!/bin/bash
set -e
ssh gymies << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// Check kolommen
\$cols = DB::getSchemaBuilder()->getColumnListing('gymies_users');
echo 'Kolommen: ' . implode(', ', array_slice(\$cols, 0, 15)) . '...' . PHP_EOL;

// Check of test klant al bestaat
\$existing = DB::table('gymies_users')->where('email', 'testklant@gymies.nl')->first();
if (\$existing) {
    echo 'Test-klant bestaat al: ID=' . \$existing->id . ', role=' . \$existing->role . PHP_EOL;
    exit;
}

// Bouw insert payload op basis van bestaande kolommen
\$payload = [
    'email' => 'testklant@gymies.nl',
    'role' => 'klant',
    'created_at' => now(),
    'updated_at' => now(),
];

if (in_array('password_hash', \$cols)) {
    \$payload['password_hash'] = bcrypt('TestKlant2026!');
} elseif (in_array('password', \$cols)) {
    \$payload['password'] = bcrypt('TestKlant2026!');
}

if (in_array('display_name', \$cols)) {
    \$payload['display_name'] = 'Test Klant';
}
if (in_array('first_name', \$cols)) {
    \$payload['first_name'] = 'Test';
}
if (in_array('last_name', \$cols)) {
    \$payload['last_name'] = 'Klant';
}
if (in_array('email_verified_at', \$cols)) {
    \$payload['email_verified_at'] = now();
}
if (in_array('gender', \$cols)) {
    \$payload['gender'] = 'male';
}

\$id = DB::table('gymies_users')->insertGetId(\$payload);
echo PHP_EOL;
echo '✓ Test-klant aangemaakt!' . PHP_EOL;
echo '  ID: ' . \$id . PHP_EOL;
echo '  Email: testklant@gymies.nl' . PHP_EOL;
echo '  Wachtwoord: TestKlant2026!' . PHP_EOL;
echo '  Role: klant' . PHP_EOL;
" 2>&1
REMOTE
