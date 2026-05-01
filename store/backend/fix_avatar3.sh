#!/bin/bash
echo "=== Avatar URLs ==="
ssh gymies << 'REMOTE'
cd /var/www/gymies
php -r "
require 'vendor/autoload.php';
\$app = require_once 'bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$rows = DB::table('gymies_trainer_profiles')
    ->join('gymies_users', 'gymies_users.id', '=', 'gymies_trainer_profiles.user_id')
    ->select('gymies_users.id', 'gymies_users.display_name', 'gymies_users.avatar_url as user_avatar', 'gymies_trainer_profiles.avatar_url as profile_avatar')
    ->get();
foreach (\$rows as \$r) {
    echo 'ID=' . \$r->id . ' name=' . (\$r->display_name ?? '?') . PHP_EOL;
    echo '  user_avatar=' . (\$r->user_avatar ?? 'NULL') . PHP_EOL;
    echo '  profile_avatar=' . (\$r->profile_avatar ?? 'NULL') . PHP_EOL;
}
echo PHP_EOL . 'APP_URL=' . config('app.url') . PHP_EOL;
" 2>&1
REMOTE
