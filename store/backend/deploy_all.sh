#!/bin/bash
# ============================================================
# GYMIES — Deploy alles in 2 SSH-verbindingen
# 1x scp (alle bestanden batch)
# 1x ssh (installeren + testdata + cache)
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL_DIR="$SCRIPT_DIR/app/Http/Controllers/Gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Volledige deploy (controllers + testdata)  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── STAP 1: Alle bestanden uploaden in ÉÉN scp-call ──
echo "=== 1/2 Bestanden uploaden (batch) ==="
scp -i "$SSH_KEY" \
  "$CTRL_DIR/GymiesAvailabilityController.php" \
  "$CTRL_DIR/GymiesBookingController.php" \
  "$CTRL_DIR/GymiesSpoedInvalController.php" \
  "$CTRL_DIR/GymiesTrainerController.php" \
  "$CTRL_DIR/GymiesSpecialtyController.php" \
  "$SCRIPT_DIR/routes_gymies_full.php" \
  "$SSH_HOST:/tmp/"
echo "  ✓ 6 bestanden geüpload"

# ── STAP 2: Alles installeren + testdata + cache in ÉÉN ssh-call ──
echo ""
echo "=== 2/2 Installeren + testdata + cache ==="
ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
LP="$1"
DEST="$LP/app/Http/Controllers/Gymies"

# ── A: Controllers installeren ──
echo "  [A] Controllers kopiëren..."
sudo cp /tmp/GymiesAvailabilityController.php "$DEST/"
sudo cp /tmp/GymiesBookingController.php "$DEST/"
sudo cp /tmp/GymiesSpoedInvalController.php "$DEST/"
sudo cp /tmp/GymiesTrainerController.php "$DEST/"
sudo cp /tmp/GymiesSpecialtyController.php "$DEST/"
sudo cp /tmp/routes_gymies_full.php "$LP/routes/routes_gymies_full.php"

sudo chown www-data:www-data \
  "$DEST/GymiesAvailabilityController.php" \
  "$DEST/GymiesBookingController.php" \
  "$DEST/GymiesSpoedInvalController.php" \
  "$DEST/GymiesTrainerController.php" \
  "$DEST/GymiesSpecialtyController.php" \
  "$LP/routes/routes_gymies_full.php"

rm -f /tmp/GymiesAvailabilityController.php \
  /tmp/GymiesBookingController.php \
  /tmp/GymiesSpoedInvalController.php \
  /tmp/GymiesTrainerController.php \
  /tmp/GymiesSpecialtyController.php \
  /tmp/routes_gymies_full.php

echo "  ✓ Controllers geïnstalleerd"

# ── B: Schema upgrade + Testdata ──
echo ""
echo "  [B] Schema + testdata..."
cd "$LP"

sudo -u www-data php << 'PHP'
<?php
require_once '/var/www/gymies/vendor/autoload.php';
$app = require_once '/var/www/gymies/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

// ── Schema upgraden ──
echo "    Schema check...\n";

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
    echo "    ✓ gymies_availability_slots aangemaakt\n";
} else {
    // Kolommen toevoegen als ze missen
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
            echo "    ✓ $col kolom toegevoegd\n";
        }
    }
    echo "    ✓ gymies_availability_slots OK\n";
}

// Exceptions tabel
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
    echo "    ✓ gymies_availability_exceptions aangemaakt\n";
}

// Bookings kolommen
if (Schema::hasTable('gymies_bookings')) {
    foreach (['slot_date' => 'date', 'day_of_week' => 'tinyInteger', 'week_number' => 'tinyInteger'] as $col => $type) {
        if (!Schema::hasColumn('gymies_bookings', $col)) {
            Schema::table('gymies_bookings', function ($table) use ($col, $type) {
                $table->{$type}($col)->nullable();
            });
            echo "    ✓ gymies_bookings.$col toegevoegd\n";
        }
    }
}

// ── Trainers opzoeken ──
echo "\n    Trainers opzoeken...\n";
$usersCols = Schema::getColumnListing('gymies_users');
$nameCol = 'id';
foreach (['display_name', 'name', 'full_name', 'first_name'] as $try) {
    if (in_array($try, $usersCols)) { $nameCol = $try; break; }
}

$trainers = DB::table('gymies_trainer_profiles')
    ->join('gymies_users', 'gymies_users.id', '=', 'gymies_trainer_profiles.user_id')
    ->select('gymies_trainer_profiles.user_id', "gymies_users.{$nameCol} as trainer_name")
    ->get();

echo "    Trainers: " . count($trainers) . "\n";
foreach ($trainers as $t) {
    echo "      - #{$t->user_id}: {$t->trainer_name}\n";
}

if ($trainers->isEmpty()) {
    echo "    ⚠ Geen trainers — script stopt.\n";
    exit(0);
}

// ── Testdata invullen ──
echo "\n    Testdata invullen...\n";
$trainerIds = $trainers->pluck('user_id')->toArray();
$existingColumns = Schema::getColumnListing('gymies_availability_slots');

// Clean start
DB::table('gymies_availability_slots')->whereIn('trainer_user_id', $trainerIds)->delete();

$timesPerDay = [
    1 => [['07:00','08:00'],['08:00','09:00'],['09:00','10:00'],['10:00','11:00'],['17:00','18:00'],['18:00','19:00'],['19:00','20:00']],
    2 => [['08:00','09:00'],['09:00','10:00'],['10:00','11:00'],['16:00','17:00'],['17:00','18:00'],['18:00','19:00']],
    3 => [['07:00','08:00'],['08:00','09:00'],['09:00','10:00'],['10:00','11:00'],['11:00','12:00']],
    4 => [['08:00','09:00'],['09:00','10:00'],['16:00','17:00'],['17:00','18:00'],['18:00','19:00'],['19:00','20:00']],
    5 => [['07:00','08:00'],['08:00','09:00'],['09:00','10:00'],['10:00','11:00']],
    6 => [['09:00','10:00'],['10:00','11:00'],['11:00','12:00']],
];

$now = now();
$startDate = new \DateTime('now', new \DateTimeZone('Europe/Amsterdam'));
$inserted = 0;

foreach ($trainerIds as $trainerId) {
    $date = clone $startDate;
    for ($d = 0; $d < 28; $d++) {
        $isoWeekday = (int) $date->format('N');
        $weekNum = (int) $date->format('W');
        $dateStr = $date->format('Y-m-d');

        if (isset($timesPerDay[$isoWeekday])) {
            foreach ($timesPerDay[$isoWeekday] as [$start, $end]) {
                $row = [
                    'trainer_user_id' => $trainerId,
                    'start_time'      => $start,
                    'end_time'        => $end,
                    'created_at'      => $now,
                ];
                if (in_array('is_active', $existingColumns))   $row['is_active'] = true;
                if (in_array('updated_at', $existingColumns))  $row['updated_at'] = $now;
                if (in_array('day_of_week', $existingColumns)) $row['day_of_week'] = $isoWeekday;
                if (in_array('slot_date', $existingColumns))   $row['slot_date'] = $dateStr;
                if (in_array('week_number', $existingColumns)) $row['week_number'] = $weekNum;

                DB::table('gymies_availability_slots')->insert($row);
                $inserted++;
            }
        }
        $date->modify('+1 day');
    }
    echo "    ✓ Trainer #{$trainerId}: 4 weken slots\n";
}

echo "\n    Totaal: {$inserted} slots\n";
echo "    Periode: {$startDate->format('d-m-Y')} t/m " . (clone $startDate)->modify('+27 days')->format('d-m-Y') . "\n";

// Verificatie
echo "\n    Verificatie:\n";
$sample = DB::table('gymies_availability_slots')->limit(3)->orderBy('slot_date')->orderBy('start_time')->get();
foreach ($sample as $s) {
    $r = (array) $s;
    echo "    #{$r['id']} | {$r['slot_date']} | dag:{$r['day_of_week']} | {$r['start_time']}-{$r['end_time']}\n";
}
PHP

echo "  ✓ Testdata ingevuld"

# ── C: Cache rebuilden ──
echo ""
echo "  [C] Cache rebuilden..."
sudo -u www-data php artisan config:clear 2>/dev/null && echo "    config:clear OK"
sudo -u www-data php artisan route:clear 2>/dev/null && echo "    route:clear OK"
sudo -u www-data php artisan config:cache 2>/dev/null && echo "    config:cache OK"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "    route:cache OK"
echo "  ✓ Cache klaar"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ALLES GEDEPLOYED                                    ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  ✓ 5 Controllers + routes                           ║"
echo "║  ✓ Schema upgrade (slot_date, week_number)          ║"
echo "║  ✓ Testdata 4 weken (alle trainers)                 ║"
echo "║  ✓ Cache rebuilden                                   ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Ma: 07-11 + 17-20  Di: 08-11 + 16-19              ║"
echo "║  Wo: 07-12          Do: 08-10 + 16-20              ║"
echo "║  Vr: 07-11          Za: 09-12          Zo: vrij     ║"
echo "╚══════════════════════════════════════════════════════╝"
