#!/bin/bash
# ============================================================
# GYMIES — Seed beschikbaarheid + SlotEngine verificatie
# Fix: gebruikt gymies_trainer_profiles.user_id (correct)
# Fix: seeded weekdag-patronen (slot_date=NULL) voor permanent
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Beschikbaarheid seeden + SlotEngine test   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
LP="$1"
cd "$LP"

sudo -u www-data php << 'PHP'
<?php
require_once '/var/www/gymies/vendor/autoload.php';
$app = require_once '/var/www/gymies/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

// ── 1. Schema check ──
echo "  [1/4] Schema check...\n";

if (!Schema::hasTable('gymies_availability_slots')) {
    Schema::create('gymies_availability_slots', function ($table) {
        $table->id();
        $table->unsignedBigInteger('trainer_user_id')->index();
        $table->date('slot_date')->nullable()->index();
        $table->tinyInteger('day_of_week');
        $table->tinyInteger('week_number')->nullable();
        $table->string('start_time', 5);
        $table->string('end_time', 5);
        $table->boolean('is_active')->default(true);
        $table->timestamps();
    });
    echo "  ✓ gymies_availability_slots aangemaakt\n";
} else {
    $toAdd = [
        'slot_date'   => fn($t) => $t->date('slot_date')->nullable()->after('trainer_user_id')->index(),
        'day_of_week' => fn($t) => $t->tinyInteger('day_of_week')->default(1)->after('slot_date'),
        'week_number' => fn($t) => $t->tinyInteger('week_number')->nullable()->after('day_of_week'),
        'is_active'   => fn($t) => $t->boolean('is_active')->default(true)->after('end_time'),
        'updated_at'  => fn($t) => $t->timestamp('updated_at')->nullable(),
    ];
    foreach ($toAdd as $col => $cb) {
        if (!Schema::hasColumn('gymies_availability_slots', $col)) {
            Schema::table('gymies_availability_slots', $cb);
            echo "  ✓ $col kolom toegevoegd\n";
        }
    }
    echo "  ✓ Schema OK\n";
}

if (!Schema::hasTable('gymies_availability_exceptions')) {
    Schema::create('gymies_availability_exceptions', function ($table) {
        $table->id();
        $table->unsignedBigInteger('trainer_user_id')->index();
        $table->date('blocked_date');
        $table->string('reason', 500)->nullable();
        $table->boolean('is_available')->default(false);
        $table->string('start_time', 5)->nullable();
        $table->string('end_time', 5)->nullable();
        $table->timestamps();
    });
    echo "  ✓ gymies_availability_exceptions aangemaakt\n";
}

// ── 2. Trainers opzoeken (via gymies_trainer_profiles.user_id → gymies_users.id) ──
echo "\n  [2/4] Trainers opzoeken...\n";

$trainers = DB::table('gymies_trainer_profiles as tp')
    ->join('gymies_users as u', 'u.id', '=', 'tp.user_id')
    ->select('tp.id as profile_id', 'tp.user_id', 'u.display_name', 'u.email')
    ->get();

echo "  Gevonden: " . count($trainers) . " trainers\n";
foreach ($trainers as $t) {
    echo "    profile_id={$t->profile_id} → user_id={$t->user_id} ({$t->display_name})\n";
}

if ($trainers->isEmpty()) {
    echo "  ⚠ Geen trainers — script stopt.\n";
    exit(0);
}

$trainerUserIds = $trainers->pluck('user_id')->toArray();

// ── 3. Seed weekdag-patronen (slot_date = NULL → SlotEngine valt terug op day_of_week) ──
echo "\n  [3/4] Beschikbaarheid seeden...\n";

// Verwijder ALLE oude data (inclusief foutieve IDs 27, 63)
DB::table('gymies_availability_slots')->delete();
echo "  ✓ Oude data opgeruimd\n";

// Availability blokken per weekdag (ISO: 1=ma ... 7=zo)
// Dit zijn BLOKKEN, geen losse uren — SlotEngine splitst ze in slots
$blocksPerDay = [
    1 => [['07:00','12:00'], ['17:00','20:00']],  // Maandag
    2 => [['08:00','11:00'], ['16:00','19:00']],  // Dinsdag
    3 => [['07:00','12:00']],                      // Woensdag
    4 => [['08:00','10:00'], ['16:00','20:00']],  // Donderdag
    5 => [['07:00','11:00']],                      // Vrijdag
    6 => [['09:00','12:00']],                      // Zaterdag
    // Zondag: vrij
];

$now = now();
$inserted = 0;

foreach ($trainerUserIds as $userId) {
    foreach ($blocksPerDay as $dayOfWeek => $blocks) {
        foreach ($blocks as [$start, $end]) {
            DB::table('gymies_availability_slots')->insert([
                'trainer_user_id' => $userId,
                'slot_date'       => null,           // NULL = weekdag-patroon (permanent)
                'day_of_week'     => $dayOfWeek,
                'week_number'     => null,
                'start_time'      => $start,
                'end_time'        => $end,
                'is_active'       => true,
                'created_at'      => $now,
                'updated_at'      => $now,
            ]);
            $inserted++;
        }
    }
    echo "  ✓ Trainer user_id={$userId}: weekdag-patronen geseeded\n";
}

echo "  Totaal: {$inserted} availability-blokken\n";

// ── 4. Verificatie met SlotEngine ──
echo "\n  [4/4] SlotEngine verificatie...\n";

$engine = new \App\Services\SlotEngine();

foreach ($trainerUserIds as $userId) {
    echo "\n  ─── Trainer user_id={$userId} ───\n";

    // Settings check
    $settings = $engine->loadTrainerSettings($userId);
    echo "  Settings: {$settings['session_duration_min']}min sessie, {$settings['buffer_minutes']}min buffer, tz={$settings['timezone']}\n";

    // Bookable slots komende 7 dagen
    $from = date('Y-m-d');
    $to = date('Y-m-d', strtotime('+7 days'));
    $slots = $engine->getBookableSlots($userId, $from, $to, filterBooked: true);
    echo "  Bookable slots ({$from} t/m {$to}): " . count($slots) . "\n";

    if (count($slots) > 0) {
        // Toon eerste 3
        $show = array_slice($slots, 0, 3);
        foreach ($show as $s) {
            $avail = $s['available'] ? 'JA' : 'NEE';
            echo "    {$s['date']} {$s['start_time']}-{$s['end_time']} (beschikbaar: {$avail})\n";
        }
        if (count($slots) > 3) {
            echo "    ... en " . (count($slots) - 3) . " meer\n";
        }
    } else {
        echo "  ⚠ Geen bookable slots gevonden!\n";
    }
}

// Services existence check
echo "\n  ─── Services check ───\n";
$services = [
    'SlotEngine' => \App\Services\SlotEngine::class,
    'WaitlistService' => \App\Services\WaitlistService::class,
    'RecurringBookingService' => \App\Services\RecurringBookingService::class,
    'CancellationPolicyService' => \App\Services\CancellationPolicyService::class,
];
foreach ($services as $name => $class) {
    $exists = class_exists($class) ? '✓' : '✗';
    echo "  {$exists} {$name}\n";
}

echo "\n  ✓ Seed + verificatie klaar!\n";
PHP

echo ""
echo "  Cache rebuilden..."
sudo -u www-data php artisan route:clear 2>/dev/null && echo "  ✓ route:clear"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "  ✓ route:cache"

# API test
echo ""
echo "  API test: trainers availability..."
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d 2>/dev/null || date -v+7d +%Y-%m-%d)

# Haal trainer user_ids op
TRAINER_IDS=$(sudo -u www-data php -r "
require_once '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
\$ids = DB::table('gymies_trainer_profiles')->pluck('user_id')->implode(',');
echo \$ids;
")

IFS=',' read -ra IDS <<< "$TRAINER_IDS"
for TID in "${IDS[@]}"; do
    AVAIL=$(curl -s "https://www.gymies.nl/api/gymies/trainers/${TID}/availability?from=${FROM}&to=${TO}" 2>/dev/null)
    BOOKABLE=$(echo "$AVAIL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('bookable_slots',[])))" 2>/dev/null || echo "FOUT")
    echo "  Trainer #${TID}: bookable_slots=${BOOKABLE}"
done
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Beschikbaarheid geseeded + geverifieerd           ║"
echo "║                                                      ║"
echo "║  Fix: correcte user_ids (uit gymies_trainer_profiles)║"
echo "║  Fix: weekdag-patronen (permanent, geen expiry)      ║"
echo "║  Fix: grote blokken i.p.v. losse uren                ║"
echo "║       (SlotEngine splitst in 60min slots + 15min buf)║"
echo "║                                                      ║"
echo "║  Schema:                                             ║"
echo "║  Ma: 07-12 + 17-20  Di: 08-11 + 16-19               ║"
echo "║  Wo: 07-12          Do: 08-10 + 16-20               ║"
echo "║  Vr: 07-11          Za: 09-12          Zo: vrij      ║"
echo "╚══════════════════════════════════════════════════════╝"
