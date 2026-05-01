#!/bin/bash
# =============================================================================
# Deploy: Fix reschedule-request 503 error + add FCM push notification
# =============================================================================
# Run: ssh gymies "bash -s" < backend/gymies_deploy/deploy_reschedule_fix.sh
# =============================================================================

set -e
cd /var/www/gymies

echo "============================================"
echo "  GYMIES: Fix reschedule-request endpoint   "
echo "============================================"
echo ""

# ── Step 1: Add missing columns to gymies_bookings ──────────────────────
echo "▸ Step 1: Adding reschedule columns..."

php artisan tinker --execute="
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

\$table = 'gymies_bookings';
\$added = 0;

if (!Schema::hasColumn(\$table, 'proposed_scheduled_at')) {
    Schema::table(\$table, fn(Blueprint \$t) => \$t->timestamp('proposed_scheduled_at')->nullable()->after('scheduled_at'));
    echo \"  ✅ proposed_scheduled_at\n\"; \$added++;
} else { echo \"  ⏭️ proposed_scheduled_at exists\n\"; }

if (!Schema::hasColumn(\$table, 'proposed_duration_minutes')) {
    Schema::table(\$table, fn(Blueprint \$t) => \$t->unsignedSmallInteger('proposed_duration_minutes')->nullable()->after('proposed_scheduled_at'));
    echo \"  ✅ proposed_duration_minutes\n\"; \$added++;
} else { echo \"  ⏭️ proposed_duration_minutes exists\n\"; }

if (!Schema::hasColumn(\$table, 'proposed_by_user_id')) {
    Schema::table(\$table, fn(Blueprint \$t) => \$t->unsignedBigInteger('proposed_by_user_id')->nullable()->after('proposed_duration_minutes'));
    echo \"  ✅ proposed_by_user_id\n\"; \$added++;
} else { echo \"  ⏭️ proposed_by_user_id exists\n\"; }

if (!Schema::hasColumn(\$table, 'proposed_at')) {
    Schema::table(\$table, fn(Blueprint \$t) => \$t->timestamp('proposed_at')->nullable()->after('proposed_by_user_id'));
    echo \"  ✅ proposed_at\n\"; \$added++;
} else { echo \"  ⏭️ proposed_at exists\n\"; }

echo \"  → \$added columns added\n\";
"

echo ""

# ── Step 2: Patch BookingController — add FcmPushHelper import + push call ──
echo "▸ Step 2: Adding FCM push notification..."

CTRL="/var/www/gymies/app/Http/Controllers/Gymies/GymiesBookingController.php"

# 2a. Add FcmPushHelper import if missing
if ! grep -q 'use.*FcmPushHelper' "$CTRL" 2>/dev/null; then
    # Add after the last use statement
    sed -i '/^use Illuminate\\Support\\Facades\\Schema;/a use App\\Http\\Controllers\\Gymies\\FcmPushHelper;' "$CTRL"
    echo "  ✅ Added FcmPushHelper import"
else
    echo "  ⏭️ FcmPushHelper already imported"
fi

# 2b. Add FCM push call in rescheduleRequest (after insertStatusNotifications)
if grep -q '// FCM push: reschedule verzoek' "$CTRL" 2>/dev/null; then
    echo "  ⏭️ FCM push already in rescheduleRequest"
else
    # Create a temp PHP patcher script
    cat > /tmp/patch_reschedule_fcm.php << 'PATCHEOF'
<?php
$file = $argv[1];
$content = file_get_contents($file);

// Find: $this->insertStatusNotifications($bookingId, (int) $booking->client_user_id, $trainerId, 'reschedule_requested');
$marker = "\$this->insertStatusNotifications(\$bookingId, (int) \$booking->client_user_id, \$trainerId, 'reschedule_requested');";

$fcmBlock = <<<'FCM'

        // FCM push: reschedule verzoek naar de andere partij
        try {
            $recipientId = $isClient ? $trainerId : (int) $booking->client_user_id;
            $proposerName = trim(($user->first_name ?? '') . ' ' . ($user->last_name ?? '')) ?: 'Iemand';
            $newDt = Carbon::parse($newScheduledAt);
            $pushTitle = 'Verplaatsingsverzoek';
            $pushBody = $proposerName . ' wil de sessie verplaatsen naar ' . $newDt->translatedFormat('l j F \o\m H:i');
            FcmPushHelper::sendToUser($recipientId, $pushTitle, $pushBody, [
                'type' => 'reschedule_request',
                'booking_id' => (string) $bookingId,
            ]);
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('[Reschedule] FCM push failed: ' . $e->getMessage());
        }
FCM;

if (strpos($content, $marker) !== false && strpos($content, '// FCM push: reschedule verzoek') === false) {
    $content = str_replace($marker, $marker . $fcmBlock, $content);
    file_put_contents($file, $content);
    echo "  ✅ Added FCM push to rescheduleRequest\n";
} else {
    echo "  ⏭️ No changes needed\n";
}
PATCHEOF

    php /tmp/patch_reschedule_fcm.php "$CTRL"
    rm -f /tmp/patch_reschedule_fcm.php
fi

echo ""

# ── Step 3: Clear caches ────────────────────────────────────────────────
echo "▸ Step 3: Clearing caches..."
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

echo ""

# ── Step 4: Verify ──────────────────────────────────────────────────────
echo "▸ Step 4: Verification..."

php artisan tinker --execute="
use Illuminate\Support\Facades\Schema;
\$needed = ['proposed_scheduled_at','proposed_duration_minutes','proposed_by_user_id','proposed_at'];
\$ok = true;
foreach (\$needed as \$c) {
    \$e = Schema::hasColumn('gymies_bookings', \$c);
    if (!\$e) \$ok = false;
    echo (\$e ? '  ✅' : '  ❌') . \" \$c\n\";
}
echo \$ok ? \"\n🎉 All good! Reschedule endpoint should work now.\n\" : \"\n⚠️ Some columns missing!\n\";
"

echo ""
echo "============================================"
echo "  Deploy complete!                          "
echo "============================================"
