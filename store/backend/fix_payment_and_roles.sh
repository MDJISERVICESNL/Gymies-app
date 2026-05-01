#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix PaymentController syntax + trainer roles║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

echo "=== 1. Fix GymiesPaymentController.php line 658 ==="
echo "  Before:"
sed -n '658,659p' "$LP/app/Http/Controllers/Gymies/GymiesPaymentController.php"

# Fix: remove the stray \Illuminate\Support\Facades\ before $this
sudo sed -i 's|\\Illuminate\\Support\\Facades\\$this->columnExists|$this->columnExists|g' \
  "$LP/app/Http/Controllers/Gymies/GymiesPaymentController.php"

echo "  After:"
sed -n '658,659p' "$LP/app/Http/Controllers/Gymies/GymiesPaymentController.php"

echo ""
echo "  Syntax check:"
php -l "$LP/app/Http/Controllers/Gymies/GymiesPaymentController.php" 2>&1

echo ""
echo "=== 2. Fix trainer roles: user 27 and 63 → trainer ==="
php -r "
require '$LP/vendor/autoload.php';
\$app = require_once '$LP/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// Update user 27 to trainer
\$affected27 = DB::table('gymies_users')->where('id', 27)->update(['role' => 'trainer']);
echo 'User 27 role updated: ' . \$affected27 . ' row(s)' . PHP_EOL;

// Update user 63 to trainer
\$affected63 = DB::table('gymies_users')->where('id', 63)->update(['role' => 'trainer']);
echo 'User 63 role updated: ' . \$affected63 . ' row(s)' . PHP_EOL;

// Verify
\$u27 = DB::table('gymies_users')->where('id', 27)->first(['id','role','display_name']);
echo 'User 27 now: role=' . \$u27->role . ' name=' . \$u27->display_name . PHP_EOL;

\$u63 = DB::table('gymies_users')->where('id', 63)->first(['id','role','display_name']);
echo 'User 63 now: role=' . \$u63->role . ' name=' . (\$u63->display_name ?? 'null') . PHP_EOL;
" 2>&1

echo ""
echo "=== 3. Clear caches + restart ==="
cd "$LP"
php artisan route:clear 2>&1
php artisan config:clear 2>&1
php artisan cache:clear 2>&1
php artisan view:clear 2>&1
sudo systemctl restart php8.4-fpm
echo "  ✓ Caches cleared, PHP-FPM restarted"

echo ""
echo "=== 4. Test route:list ==="
php artisan route:list --path=trainers 2>&1 | head -25

echo ""
echo "=== 5. Rebuild route cache ==="
php artisan route:cache 2>&1

echo ""
echo "=== 6. Test API — trainer 27 (Demo Klant, now trainer) ==="
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

RESP27=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "Trainer 27 response:"
echo "$RESP27" | python3 -m json.tool 2>/dev/null | head -40 || echo "$RESP27" | head -c 500

echo ""
echo "=== 7. Test API — trainer 200 (Youssef, confirmed trainer) ==="
RESP200=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/200/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "Trainer 200 response:"
echo "$RESP200" | python3 -m json.tool 2>/dev/null | head -40 || echo "$RESP200" | head -c 500

echo ""
echo "=== 8. Test trainer/27 show endpoint ==="
RESP_SHOW=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null)
echo "Trainer 27 show:"
echo "$RESP_SHOW" | python3 -m json.tool 2>/dev/null | head -20 || echo "$RESP_SHOW" | head -c 300

echo ""
echo "=== Done ==="
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ All fixes applied and tested                      ║"
echo "╚══════════════════════════════════════════════════════╝"
