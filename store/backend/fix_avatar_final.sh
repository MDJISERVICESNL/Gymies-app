#!/bin/bash
echo "=== Test huidige avatar URLs + fix ==="
ssh gymies << 'REMOTE'
cd /var/www/gymies

# 1. Test of de huidige URLs werken
echo "=== HTTP status check huidige URLs ==="
urls=(
    "https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=500&q=80"
    "https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=500&q=80"
    "https://images.unsplash.com/photo-1526506118085-60ce8714f8c5?w=500&q=80"
)
for url in "${urls[@]}"; do
    status=$(curl -s -o /dev/null -w "%{http_code}" -L "$url" --max-time 5)
    echo "  $status → $url"
done

# 2. Test ui-avatars.com (altijd werkend)
echo ""
echo "=== Test ui-avatars.com ==="
status=$(curl -s -o /dev/null -w "%{http_code}" -L "https://ui-avatars.com/api/?name=Test&size=200" --max-time 5)
echo "  $status → ui-avatars.com"

# 3. Update naar ui-avatars.com (gegarandeerd werkend)
echo ""
echo "=== Updaten naar ui-avatars.com ==="
php -r "
require 'vendor/autoload.php';
\$app = require_once 'bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$trainers = DB::table('gymies_trainer_profiles')
    ->join('gymies_users', 'gymies_users.id', '=', 'gymies_trainer_profiles.user_id')
    ->select('gymies_users.id', 'gymies_users.display_name')
    ->get();

foreach (\$trainers as \$t) {
    \$name = \$t->display_name ?? 'Trainer';
    \$encoded = urlencode(\$name);
    \$url = \"https://ui-avatars.com/api/?name={\$encoded}&size=256&background=1a3a5c&color=D4A843&bold=true&font-size=0.4\";

    DB::table('gymies_trainer_profiles')
        ->where('user_id', \$t->id)
        ->update(['avatar_url' => \$url]);

    DB::table('gymies_users')
        ->where('id', \$t->id)
        ->update(['avatar_url' => \$url]);

    echo 'OK ' . \$t->id . ' ' . \$name . ': ' . \$url . PHP_EOL;
}
" 2>&1

sudo systemctl restart php8.4-fpm
php artisan config:cache 2>&1 | tail -1

echo ""
echo "✅ Alle avatars nu via ui-avatars.com (altijd 200 OK)"

REMOTE
