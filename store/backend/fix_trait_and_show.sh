#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix trait collision + TrainerController      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

# ═══════════════════════════════════════════════════════════
# FIX 1: SubscriptionController trait collision
# ═══════════════════════════════════════════════════════════
echo "=== Fix 1: SubscriptionController trait collision ==="

FILE="$LP/app/Http/Controllers/Gymies/GymiesSubscriptionController.php"
sudo cp "$FILE" "$FILE.bak"

# Replace the trait use block
# Old:
#   use AssignSubscriptionTrait;
#   use ChangeSubscriptionTrait;
#   use SubscriptionPaymentTrait {
#       SubscriptionPaymentTrait::getSubscriptionMollieApiKey as protected getSubscriptionMollieApiKeyFromTrait;
#   }
#   use ExpireSubscriptionTrialsTrait;
#   use SubscriptionWebhookTrait;
#
# New: combine into one use block with insteadof
sudo php -r "
\$file = '$FILE';
\$content = file_get_contents(\$file);

\$old = <<<'PHP'
    use AssignSubscriptionTrait;
    use ChangeSubscriptionTrait;
    use SubscriptionPaymentTrait {
        SubscriptionPaymentTrait::getSubscriptionMollieApiKey as protected getSubscriptionMollieApiKeyFromTrait;
    }
    use ExpireSubscriptionTrialsTrait;
    use SubscriptionWebhookTrait;
PHP;

\$new = <<<'PHP'
    use AssignSubscriptionTrait;
    use ChangeSubscriptionTrait;
    use ExpireSubscriptionTrialsTrait;
    use SubscriptionPaymentTrait, SubscriptionWebhookTrait {
        SubscriptionWebhookTrait::getSubscriptionMollieApiKey insteadof SubscriptionPaymentTrait;
        SubscriptionPaymentTrait::getSubscriptionMollieApiKey as protected getSubscriptionMollieApiKeyFromTrait;
    }
PHP;

if (strpos(\$content, trim(\$old)) !== false) {
    \$content = str_replace(trim(\$old), trim(\$new), \$content);
    file_put_contents(\$file, \$content);
    echo '  ✓ Trait collision fixed' . PHP_EOL;
} else {
    echo '  ✗ Could not find old trait block — manual fix needed' . PHP_EOL;
    echo '  Looking for trait lines:' . PHP_EOL;
    foreach (explode(PHP_EOL, \$content) as \$i => \$line) {
        if (preg_match('/use\s+(Assign|Change|Subscription|Expire)/', \$line)) {
            echo '    Line ' . (\$i+1) . ': ' . trim(\$line) . PHP_EOL;
        }
    }
}
"

echo ""
echo "  Syntax check:"
php -l "$FILE" 2>&1

# ═══════════════════════════════════════════════════════════
# FIX 2: TrainerController duplicate leftJoin
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== Fix 2: TrainerController duplicate leftJoin ==="

FILE2="$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php"
sudo cp "$FILE2" "$FILE2.bak"

# The show() method has two leftJoin on 'gymies_trainer_profiles as p'.
# First one is in the moderation_status block — remove that join but keep the where clause.
# The join will be added in the later $hasProfiles block.
sudo php -r "
\$file = '$FILE2';
\$content = file_get_contents(\$file);

// Find and fix: remove the leftJoin from the moderation block in show()
// Pattern: in the moderation block, there's a leftJoin followed by a where
// We need to remove only the leftJoin line, keep the where clause

\$old = \"            \\\$query->leftJoin('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id');
            \\\$query->where(function (\\\$q) {
                \\\$q->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
            });\";

\$new = \"            // moderation filter — join is added below in the \\\$hasProfiles block
            \\\$query->where(function (\\\$q) {
                \\\$q->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
            });\";

if (strpos(\$content, \$old) !== false) {
    \$content = str_replace(\$old, \$new, \$content);
    file_put_contents(\$file, \$content);
    echo '  ✓ Duplicate leftJoin removed from moderation block' . PHP_EOL;
} else {
    echo '  ✗ Could not find duplicate join pattern' . PHP_EOL;
    echo '  Searching for leftJoin lines in show() context...' . PHP_EOL;
    \$lines = explode(PHP_EOL, \$content);
    \$inShow = false;
    foreach (\$lines as \$i => \$line) {
        if (preg_match('/function show\s*\(/', \$line)) \$inShow = true;
        if (\$inShow && strpos(\$line, 'leftJoin') !== false) {
            echo '    Line ' . (\$i+1) . ': ' . trim(\$line) . PHP_EOL;
        }
        if (\$inShow && preg_match('/^    public function /', \$line) && !preg_match('/function show/', \$line)) \$inShow = false;
    }
}
"

echo ""
echo "  Syntax check:"
php -l "$FILE2" 2>&1

# ═══════════════════════════════════════════════════════════
# FIX 3: Fix ownership + clear caches + restart
# ═══════════════════════════════════════════════════════════
echo ""
echo "=== Clear caches + restart ==="
sudo chown -R ubuntu:ubuntu "$LP/app/"
cd "$LP"
php artisan route:clear 2>&1
php artisan config:clear 2>&1
php artisan cache:clear 2>&1
sudo systemctl restart php8.4-fpm
echo "  ✓ PHP-FPM restarted"

echo ""
echo "=== Rebuild route cache ==="
php artisan route:cache 2>&1

echo ""
echo "=== Test route:list ==="
php artisan route:list --path=trainers 2>&1 | head -25

echo ""
echo "=== Test API ==="
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "--- Trainer 27 show ---"
RESP=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>/dev/null)
echo "$RESP" | python3 -m json.tool 2>/dev/null | head -25 || echo "$RESP" | head -c 400

echo ""
echo "--- Trainer 27 availability ---"
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
    print(f'  Parse error: {e}')
" 2>/dev/null

echo ""
echo "--- Trainer 200 show ---"
RESP3=$(curl -sk -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/200" 2>/dev/null)
echo "$RESP3" | python3 -m json.tool 2>/dev/null | head -20 || echo "$RESP3" | head -c 400

echo ""
echo "=== Done ==="
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Trait collision + TrainerController fixed          ║"
echo "╚══════════════════════════════════════════════════════╝"
