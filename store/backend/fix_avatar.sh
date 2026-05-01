#!/bin/bash
set -e
echo "=== Fix Avatar URL + Storage ==="

ssh gymies << 'REMOTE'
cd /var/www/gymies

php -r "
require 'vendor/autoload.php';
\$app = require_once 'bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// 1. Zoek de users tabel
echo '=== Alle tabellen met user ===' . PHP_EOL;
\$tables = DB::select('SHOW TABLES');
\$dbKey = array_key_first((array) \$tables[0]);
foreach (\$tables as \$t) {
    \$name = \$t->\$dbKey;
    if (str_contains(\$name, 'user')) {
        echo '  ' . \$name . PHP_EOL;
    }
}

// 2. Probeer gymies_users
\$userTable = null;
foreach (['gymies_users', 'users', 'gymies_user'] as \$candidate) {
    try {
        DB::table(\$candidate)->limit(1)->first();
        \$userTable = \$candidate;
        break;
    } catch (\Exception \$e) {
        continue;
    }
}
echo PHP_EOL . '=== Users tabel: ' . (\$userTable ?? 'NIET GEVONDEN') . ' ===' . PHP_EOL;

if (\$userTable) {
    // 3. Zoek Youssef
    \$user = DB::table(\$userTable)->where('name', 'like', '%Youssef%')->first();
    if (!\$user) {
        // Toon alle trainers
        echo 'Youssef niet gevonden, alle trainers:' . PHP_EOL;
        \$all = DB::table('gymies_trainer_profiles')
            ->join(\$userTable, \$userTable . '.id', '=', 'gymies_trainer_profiles.user_id')
            ->select(\$userTable . '.id', \$userTable . '.name', 'gymies_trainer_profiles.avatar_url')
            ->get();
        foreach (\$all as \$t) {
            echo '  ID=' . \$t->id . ' ' . \$t->name . ' avatar=' . (\$t->avatar_url ?? 'NULL') . PHP_EOL;
        }
    } else {
        echo 'Gevonden: ID=' . \$user->id . ' ' . \$user->name . PHP_EOL;
        \$profile = DB::table('gymies_trainer_profiles')->where('user_id', \$user->id)->first();
        if (\$profile) {
            echo 'avatar_url = ' . (\$profile->avatar_url ?? 'NULL') . PHP_EOL;
        }
    }
}

// 4. Check APP_URL
echo PHP_EOL . '=== APP_URL ===' . PHP_EOL;
echo config('app.url') . PHP_EOL;

// 5. Check hoe de API avatar_url returnt
echo PHP_EOL . '=== API trainer endpoint avatar veld ===' . PHP_EOL;
\$profile = DB::table('gymies_trainer_profiles')->whereNotNull('avatar_url')->where('avatar_url', '!=', '')->first();
if (\$profile) {
    echo 'Raw avatar_url uit DB: ' . \$profile->avatar_url . PHP_EOL;
    // Check of het een volledig URL is of relatief pad
    if (str_starts_with(\$profile->avatar_url, 'http')) {
        echo 'Type: Absolute URL' . PHP_EOL;
    } else {
        echo 'Type: Relatief pad - moet gecombineerd worden met APP_URL' . PHP_EOL;
        echo 'Volledige URL zou zijn: ' . config('app.url') . '/storage/' . \$profile->avatar_url . PHP_EOL;
    }
}
" 2>&1

echo ""
echo "=== Storage symlink fix ==="
if [ ! -L public/storage ]; then
    echo "Symlink ontbreekt! Aanmaken..."
    php artisan storage:link 2>&1 || ln -sf ../storage/app/public public/storage
    echo "✓ Symlink aangemaakt"
else
    echo "✓ Symlink bestaat al"
fi
ls -la public/storage

echo ""
echo "=== Storage directory inhoud ==="
find storage/app/public -type f 2>/dev/null | head -20 || echo "Geen bestanden in storage/app/public"

echo ""
echo "=== Nginx config check (server_name + root) ==="
grep -E 'server_name|root ' /etc/nginx/sites-enabled/* 2>/dev/null | head -5

REMOTE
