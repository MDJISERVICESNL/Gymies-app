#!/bin/bash
set -e
SSH_HOST="gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix SubscriptionController + TrainerShow    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"

echo "=== 1. Show SubscriptionController trait collision ==="
sed -n '1,30p' "$LP/app/Http/Controllers/Gymies/GymiesSubscriptionController.php"

echo ""
echo "=== 2. Check both traits for the colliding method ==="
echo "--- SubscriptionWebhookTrait ---"
grep -n 'getSubscriptionMollieApiKey' "$LP/app/Http/Controllers/Gymies/SubscriptionWebhookTrait.php" 2>/dev/null || echo "  Method not found or file missing"

echo "--- SubscriptionPaymentTrait ---"
grep -n 'getSubscriptionMollieApiKey' "$LP/app/Http/Controllers/Gymies/SubscriptionPaymentTrait.php" 2>/dev/null || echo "  Method not found or file missing"

echo ""
echo "=== 3. Show TrainerController show() method ==="
grep -n 'function show' "$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php" 2>/dev/null
# Show the show method area
SHOW_LINE=$(grep -n 'function show' "$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$SHOW_LINE" ]; then
    END_LINE=$((SHOW_LINE + 60))
    sed -n "${SHOW_LINE},${END_LINE}p" "$LP/app/Http/Controllers/Gymies/GymiesTrainerController.php"
fi

echo ""
echo "=== 4. Check recent laravel.log errors ==="
tail -50 "$LP/storage/logs/laravel.log" 2>/dev/null | grep -A5 "trainers/27\|TrainerController\|Server Error" | head -40 || echo "  No recent errors"

REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Diagnostics complete                              ║"
echo "╚══════════════════════════════════════════════════════╝"
