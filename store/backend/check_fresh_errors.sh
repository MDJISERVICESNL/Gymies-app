#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies

echo "=== Laatste 30 regels laravel.log ==="
tail -30 storage/logs/laravel.log

echo ""
echo "=== Laatste nginx errors vandaag ==="
sudo tail -20 /var/log/nginx/error.log 2>/dev/null | grep "$(date -u +'%Y/%m/%d')" | tail -10

echo ""
echo "=== BookingController versie check ==="
grep -n "hasIsActive\|is_active" app/Http/Controllers/Gymies/GymiesBookingController.php | head -10

echo ""
echo "=== Volledige booking test via PHP ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

// Simuleer exacte flow van storeDirectBook
\$user = DB::table('gymies_users')->where('email', 'testklant@gymies.nl')->first();
\$trainerId = 27;
\$scheduledAt = '2026-05-03 10:00:00';
\$duration = 60;

echo '1. User: ' . \$user->id . ' (' . \$user->role . ')' . PHP_EOL;

// Prijs
\$profileCols = DB::getSchemaBuilder()->getColumnListing('gymies_trainer_profiles');
\$priceCols = array_values(array_intersect(['session_price_cents', 'hourly_rate_cents', 'trial_session_cents'], \$profileCols));
\$profile = DB::table('gymies_trainer_profiles')->where('user_id', \$trainerId)->first(\$priceCols);
\$amountCents = 0;
foreach (['session_price_cents', 'hourly_rate_cents', 'trial_session_cents'] as \$col) {
    if (isset(\$profile->\$col) && (int)\$profile->\$col > 0) {
        \$amountCents = (int)\$profile->\$col;
        echo '2. Prijs: ' . \$amountCents . ' via ' . \$col . PHP_EOL;
        break;
    }
}

// Availability check (met is_active guard)
\$slotCols = DB::getSchemaBuilder()->getColumnListing('gymies_availability_slots');
echo '3. Slot kolommen: ' . implode(', ', \$slotCols) . PHP_EOL;
\$hasIsActive = in_array('is_active', \$slotCols);
echo '   is_active: ' . (\$hasIsActive ? 'JA' : 'NEE') . PHP_EOL;

\$q = DB::table('gymies_availability_slots')->where('trainer_user_id', \$trainerId);
if (\$hasIsActive) \$q->where('is_active', true);
\$totalSlots = \$q->count();
echo '4. Totaal slots: ' . \$totalSlots . PHP_EOL;

// Lead time check
echo '5. Lead time check...' . PHP_EOL;
\$start = \Carbon\Carbon::parse(\$scheduledAt);
\$now = now();
\$diffMinutes = \$now->diffInMinutes(\$start, false);
echo '   Nu: ' . \$now . ', Sessie: ' . \$start . ', Verschil: ' . \$diffMinutes . ' min' . PHP_EOL;

// Overlap check
echo '6. Overlap check...' . PHP_EOL;
\$overlap = DB::table('gymies_bookings')
    ->where('trainer_user_id', \$trainerId)
    ->whereIn('status', ['pending', 'confirmed', 'reserved'])
    ->where('scheduled_at', \$scheduledAt)
    ->count();
echo '   Overlappende boekingen: ' . \$overlap . PHP_EOL;

// Test INSERT
echo '7. Test INSERT...' . PHP_EOL;
try {
    DB::beginTransaction();
    \$cols = DB::getSchemaBuilder()->getColumnListing('gymies_bookings');
    \$payload = [
        'client_user_id' => \$user->id,
        'trainer_user_id' => \$trainerId,
        'scheduled_at' => \$scheduledAt,
        'duration_minutes' => \$duration,
        'amount_cents' => \$amountCents,
        'status' => 'reserved',
        'created_at' => now(),
        'updated_at' => now(),
    ];
    if (in_array('payment_method', \$cols)) \$payload['payment_method'] = 'cash';
    if (in_array('reserved_until', \$cols)) \$payload['reserved_until'] = now()->addMinutes(10);

    \$id = DB::table('gymies_bookings')->insertGetId(\$payload);
    echo '   ✓ INSERT OK! ID=' . \$id . PHP_EOL;
    DB::rollBack();
    echo '   (rollback)' . PHP_EOL;
} catch (\Throwable \$e) {
    DB::rollBack();
    echo '   FOUT: ' . \$e->getMessage() . PHP_EOL;
}

echo PHP_EOL . '✅ Alle stappen doorlopen zonder crash.' . PHP_EOL;
" 2>&1
REMOTE
