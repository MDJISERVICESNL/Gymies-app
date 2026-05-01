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

\$user = DB::table('gymies_users')->where('email', 'jamai1210@live.nl')->first();
if (!\$user) { echo 'Gebruiker niet gevonden.' . PHP_EOL; exit; }

\$cols = DB::getSchemaBuilder()->getColumnListing('gymies_users');
echo 'ID: ' . \$user->id . PHP_EOL;
echo 'Email: ' . \$user->email . PHP_EOL;
echo 'Role: ' . \$user->role . PHP_EOL;
echo 'Display name: ' . (\$user->display_name ?? '(geen)') . PHP_EOL;
if (in_array('email_verified_at', \$cols)) {
    echo 'Email verified: ' . (\$user->email_verified_at ?? 'NEE') . PHP_EOL;
}
" 2>&1
REMOTE
