#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix PaymentController + Trainer ID 27       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

echo "=== 1. Show GymiesPaymentController.php around line 658 ==="
sed -n '650,670p' "$LP/app/Http/Controllers/Gymies/GymiesPaymentController.php"

echo ""
echo "=== 2. Check user_id 27 in gymies_users ==="
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

\$user27 = DB::table('gymies_users')->where('id', 27)->first();
if (\$user27) {
    echo 'User 27 exists: role=' . \$user27->role . ' name=' . (\$user27->display_name ?? 'null') . ' email=' . (\$user27->email ?? 'null') . PHP_EOL;
} else {
    echo 'User 27 does NOT exist in gymies_users!' . PHP_EOL;
}

// Also check user 63
\$user63 = DB::table('gymies_users')->where('id', 63)->first();
if (\$user63) {
    echo 'User 63 exists: role=' . \$user63->role . ' name=' . (\$user63->display_name ?? 'null') . ' email=' . (\$user63->email ?? 'null') . PHP_EOL;
} else {
    echo 'User 63 does NOT exist in gymies_users!' . PHP_EOL;
}

// List ALL users with their roles
echo PHP_EOL . 'All users in gymies_users:' . PHP_EOL;
\$all = DB::table('gymies_users')->get(['id', 'role', 'display_name', 'email']);
foreach (\$all as \$u) {
    echo '  id=' . \$u->id . ' role=' . \$u->role . ' name=' . (\$u->display_name ?? 'null') . PHP_EOL;
}
" 2>&1

echo ""
echo "=== 3. Quick test with trainer ID=2 (Richard Miller, confirmed trainer) ==="
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)
RESP=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/2/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP" | python3 -m json.tool 2>/dev/null | head -30 || echo "$RESP" | head -c 500

REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Diagnostics complete                              ║"
echo "╚══════════════════════════════════════════════════════╝"
