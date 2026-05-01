#!/bin/bash
set -e
echo "=== Avatar Debug v2 ==="

ssh gymies << 'REMOTE'
cd /var/www/gymies

# 1. Kolommen in gymies_users
echo "=== Kolommen gymies_users ==="
php -r "
require 'vendor/autoload.php';
\$app = require_once 'bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$cols = DB::getSchemaBuilder()->getColumnListing('gymies_users');
echo implode(', ', \$cols) . PHP_EOL;
" 2>&1

echo ""
echo "=== Alle trainers + avatar_url ==="
php -r "
require 'vendor/autoload.php';
\$app = require_once 'bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$profiles = DB::table('gymies_trainer_profiles')->select('user_id', 'avatar_url', 'display_name')->get();
foreach (\$profiles as \$p) {
    echo 'user_id=' . \$p->user_id . ' display_name=' . (\$p->display_name ?? '?') . ' avatar_url=' . (\$p->avatar_url ?? 'NULL') . PHP_EOL;
}

echo PHP_EOL . 'APP_URL = ' . config('app.url') . PHP_EOL;
" 2>&1

echo ""
echo "=== Storage symlink fixen (met sudo) ==="
sudo ln -sf /var/www/gymies/storage/app/public /var/www/gymies/public/storage 2>&1 && echo "✓ Symlink aangemaakt" || echo "✗ Symlink mislukt"
ls -la public/storage 2>/dev/null || echo "Geen symlink"

echo ""
echo "=== Bestanden in storage ==="
find storage/app/public -type f ! -name '.gitignore' 2>/dev/null | head -20
echo "(einde)"

REMOTE
