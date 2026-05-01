#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix trainer 27 profile                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// Check user 27 profile
\$profile = DB::table('gymies_trainer_profiles')->where('user_id', 27)->first();
if (\$profile) {
    echo 'Profile for user 27:' . PHP_EOL;
    echo '  profile_id: ' . \$profile->id . PHP_EOL;
    echo '  moderation_status: ' . (\$profile->moderation_status ?? 'NULL') . PHP_EOL;
    echo '  is_available: ' . (\$profile->is_available ?? 'NULL') . PHP_EOL;
    echo '  display_name (user): ';
    \$user = DB::table('gymies_users')->where('id', 27)->first();
    echo (\$user->display_name ?? 'NULL') . PHP_EOL;
    echo '  role: ' . (\$user->role ?? 'NULL') . PHP_EOL;
} else {
    echo 'No profile found for user_id=27!' . PHP_EOL;
}

// Fix: set moderation_status to approved
echo PHP_EOL . 'Fixing moderation_status...' . PHP_EOL;
\$affected = DB::table('gymies_trainer_profiles')
    ->where('user_id', 27)
    ->update([
        'moderation_status' => 'approved',
        'is_available' => 1,
    ]);
echo 'Updated: ' . \$affected . ' row(s)' . PHP_EOL;

// Also fix user 63
\$affected63 = DB::table('gymies_trainer_profiles')
    ->where('user_id', 63)
    ->update([
        'moderation_status' => 'approved',
        'is_available' => 1,
    ]);
echo 'User 63 updated: ' . \$affected63 . ' row(s)' . PHP_EOL;

// Also update display_name for user 27 to something more trainer-like
DB::table('gymies_users')->where('id', 27)->update(['display_name' => 'Demo Trainer']);
echo 'User 27 display_name set to Demo Trainer' . PHP_EOL;

// Set display_name for user 63 too
DB::table('gymies_users')->where('id', 63)->update(['display_name' => 'Test Trainer']);
echo 'User 63 display_name set to Test Trainer' . PHP_EOL;
" 2>&1

echo ""
echo "=== Clear OPcache + restart ==="
cd "$LP"
php artisan cache:clear 2>&1
sudo systemctl restart php8.4-fpm
echo "  ✓ Done"

echo ""
echo "=== Test trainer 27 show ==="
RESP=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null)
echo "$RESP" | python3 -m json.tool 2>/dev/null | head -25 || echo "$RESP" | head -c 400

echo ""
echo "=== Test trainer 27 availability ==="
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)
RESP2=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP2" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    bookable = data.get('bookable_slots', [])
    print(f'  bookable_slots: {len(bookable)}')
    if bookable:
        for s in bookable[:3]:
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]} available={s.get(\"available\", \"?\")}')
except Exception as e:
    print(f'  Error: {e}')
" 2>/dev/null

echo ""
echo "=== Done ==="
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Trainer 27 profile fixed                          ║"
echo "╚══════════════════════════════════════════════════════╝"
