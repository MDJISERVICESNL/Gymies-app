#!/bin/bash
set -e
echo "=== Avatar URL Check: Youssef El Amrani ==="

ssh gymies << 'REMOTE'
cd /var/www/gymies

php -r "
require 'vendor/autoload.php';
\$app = require_once 'bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// 1. Check alle kolommen in trainer_profiles
\$cols = DB::getSchemaBuilder()->getColumnListing('gymies_trainer_profiles');
echo '=== Kolommen in gymies_trainer_profiles ===' . PHP_EOL;
\$avatarCols = array_filter(\$cols, fn(\$c) => str_contains(\$c, 'avatar') || str_contains(\$c, 'photo') || str_contains(\$c, 'image') || str_contains(\$c, 'pic'));
echo implode(', ', \$avatarCols) . PHP_EOL;

// 2. Check users tabel
\$userCols = DB::getSchemaBuilder()->getColumnListing('users');
\$userAvatarCols = array_filter(\$userCols, fn(\$c) => str_contains(\$c, 'avatar') || str_contains(\$c, 'photo') || str_contains(\$c, 'image') || str_contains(\$c, 'pic') || str_contains(\$c, 'profile'));
echo PHP_EOL . '=== Avatar-kolommen in users ===' . PHP_EOL;
echo implode(', ', \$userAvatarCols) . PHP_EOL;

// 3. Zoek Youssef
echo PHP_EOL . '=== Trainer: Youssef ===' . PHP_EOL;
\$user = DB::table('users')->where('name', 'like', '%Youssef%')->first();
if (\$user) {
    echo 'user.id=' . \$user->id . PHP_EOL;
    echo 'user.name=' . \$user->name . PHP_EOL;
    foreach (\$userAvatarCols as \$col) {
        echo 'user.' . \$col . '=' . (\$user->\$col ?? 'NULL') . PHP_EOL;
    }

    \$profile = DB::table('gymies_trainer_profiles')->where('user_id', \$user->id)->first();
    if (\$profile) {
        foreach (\$avatarCols as \$col) {
            echo 'profile.' . \$col . '=' . (\$profile->\$col ?? 'NULL') . PHP_EOL;
        }
    } else {
        echo 'Geen trainer profile gevonden!' . PHP_EOL;
    }
} else {
    echo 'Gebruiker Youssef niet gevonden!' . PHP_EOL;
    // Toon alle trainers
    echo PHP_EOL . '=== Alle trainers ===' . PHP_EOL;
    \$all = DB::table('gymies_trainer_profiles')
        ->join('users', 'users.id', '=', 'gymies_trainer_profiles.user_id')
        ->select('users.id', 'users.name')
        ->get();
    foreach (\$all as \$t) {
        echo 'ID=' . \$t->id . ' ' . \$t->name . PHP_EOL;
    }
}

// 4. Check API response
echo PHP_EOL . '=== API response avatar veld ===' . PHP_EOL;
\$trainers = DB::table('gymies_trainer_profiles')
    ->join('users', 'users.id', '=', 'gymies_trainer_profiles.user_id')
    ->limit(3)
    ->get();
foreach (\$trainers as \$t) {
    \$name = \$t->name ?? 'unknown';
    \$avatarFields = [];
    foreach (get_object_vars(\$t) as \$k => \$v) {
        if (str_contains(\$k, 'avatar') || str_contains(\$k, 'photo') || str_contains(\$k, 'image')) {
            \$avatarFields[\$k] = \$v ?? 'NULL';
        }
    }
    echo \$name . ': ' . json_encode(\$avatarFields) . PHP_EOL;
}

// 5. Check storage/app/public voor uploads
echo PHP_EOL . '=== Storage uploads ===' . PHP_EOL;
\$dirs = ['storage/app/public/avatars', 'storage/app/public/photos', 'storage/app/public/profiles', 'public/storage/avatars'];
foreach (\$dirs as \$d) {
    if (is_dir(\$d)) {
        \$count = count(glob(\$d . '/*'));
        echo \$d . ': ' . \$count . ' bestanden' . PHP_EOL;
    }
}
" 2>&1

echo ""
echo "=== Nginx/Storage symlink check ==="
ls -la public/storage 2>/dev/null || echo "public/storage symlink bestaat niet!"
ls -la storage/app/public/ 2>/dev/null | head -10

REMOTE
