#!/bin/bash
echo "=== Fix trainer avatar URLs (Unsplash 404s) ==="
ssh gymies << 'REMOTE'
cd /var/www/gymies
php -r "
require 'vendor/autoload.php';
\$app = require_once 'bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// Werkende Unsplash foto's (getest april 2026)
\$avatars = [
    200 => 'https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=500&q=80', // man fitness
    201 => 'https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=500&q=80', // vrouw yoga
    202 => 'https://images.unsplash.com/photo-1526506118085-60ce8714f8c5?w=500&q=80', // man boxing
    203 => 'https://images.unsplash.com/photo-1594381898411-846e7d193883?w=500&q=80', // vrouw fitness
    204 => 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=500&q=80', // man gym
    27  => 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=500&q=80', // demo trainer
    63  => 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=500&q=80', // test trainer
];

foreach (\$avatars as \$userId => \$url) {
    // Update gymies_trainer_profiles
    \$updated1 = DB::table('gymies_trainer_profiles')
        ->where('user_id', \$userId)
        ->update(['avatar_url' => \$url]);

    // Update gymies_users
    \$updated2 = DB::table('gymies_users')
        ->where('id', \$userId)
        ->update(['avatar_url' => \$url]);

    \$name = DB::table('gymies_users')->where('id', \$userId)->value('display_name') ?? '?';
    echo 'ID=' . \$userId . ' ' . \$name . ': profile=' . \$updated1 . ' user=' . \$updated2 . PHP_EOL;
}

echo PHP_EOL . '=== Verificatie ===' . PHP_EOL;
\$rows = DB::table('gymies_trainer_profiles')
    ->join('gymies_users', 'gymies_users.id', '=', 'gymies_trainer_profiles.user_id')
    ->select('gymies_users.id', 'gymies_users.display_name', 'gymies_trainer_profiles.avatar_url')
    ->get();
foreach (\$rows as \$r) {
    echo \$r->id . ' ' . (\$r->display_name ?? '?') . ': ' . (\$r->avatar_url ?? 'NULL') . PHP_EOL;
}
" 2>&1

# Clear OPcache
sudo systemctl restart php8.4-fpm
php artisan config:cache
echo ""
echo "✅ Avatar URLs bijgewerkt!"

REMOTE
