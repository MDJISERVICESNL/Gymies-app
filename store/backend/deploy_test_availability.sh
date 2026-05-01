#!/bin/bash
# ============================================================
# Vul test beschikbaarheid in voor trainers op de Gymies server
# Schema upgrade: slot_date + week_number kolommen
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="${LARAVEL_PATH:-/var/www/gymies}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Beschikbaarheid Schema + Testdata          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
cd "$1"

sudo -u www-data php << 'PHP'
<?php
require_once '/var/www/gymies/vendor/autoload.php';
$app = require_once '/var/www/gymies/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

// ── STAP 1: Schema upgraden ──────────────────────────────
echo "=== 1/4 Schema check & upgrade ===\n";

if (!Schema::hasTable('gymies_availability_slots')) {
    echo "  Tabel bestaat niet — wordt aangemaakt met volledig schema...\n";
    Schema::create('gymies_availability_slots', function ($table) {
        $table->id();
        $table->unsignedBigInteger('trainer_user_id')->index();
        $table->date('slot_date')->nullable()->index();      // Specifieke datum (2026-04-28)
        $table->tinyInteger('day_of_week');                   // ISO weekdag (1=ma, 7=zo)
        $table->tinyInteger('week_number')->nullable();       // ISO weeknummer (1-53)
        $table->string('start_time', 5);                      // HH:MM
        $table->string('end_time', 5);                        // HH:MM
        $table->boolean('is_active')->default(true);
        $table->timestamps();
    });
    echo "  ✓ gymies_availability_slots aangemaakt (volledig schema)\n";
} else {
    echo "  ✓ gymies_availability_slots bestaat\n";

    // Kolommen toevoegen als ze missen
    if (!Schema::hasColumn('gymies_availability_slots', 'slot_date')) {
        Schema::table('gymies_availability_slots', function ($table) {
            $table->date('slot_date')->nullable()->after('trainer_user_id')->index();
        });
        echo "  ✓ slot_date kolom toegevoegd\n";
    } else {
        echo "  · slot_date kolom bestaat al\n";
    }

    if (!Schema::hasColumn('gymies_availability_slots', 'week_number')) {
        Schema::table('gymies_availability_slots', function ($table) {
            $table->tinyInteger('week_number')->nullable()->after('day_of_week');
        });
        echo "  ✓ week_number kolom toegevoegd\n";
    } else {
        echo "  · week_number kolom bestaat al\n";
    }

    if (!Schema::hasColumn('gymies_availability_slots', 'day_of_week')) {
        Schema::table('gymies_availability_slots', function ($table) {
            $table->tinyInteger('day_of_week')->default(1)->after('slot_date');
        });
        echo "  ✓ day_of_week kolom toegevoegd\n";
    } else {
        echo "  · day_of_week kolom bestaat al\n";
    }

    if (!Schema::hasColumn('gymies_availability_slots', 'is_active')) {
        Schema::table('gymies_availability_slots', function ($table) {
            $table->boolean('is_active')->default(true)->after('end_time');
        });
        echo "  ✓ is_active kolom toegevoegd\n";
    } else {
        echo "  · is_active kolom bestaat al\n";
    }

    if (!Schema::hasColumn('gymies_availability_slots', 'updated_at')) {
        Schema::table('gymies_availability_slots', function ($table) {
            $table->timestamp('updated_at')->nullable();
        });
        echo "  ✓ updated_at kolom toegevoegd\n";
    } else {
        echo "  · updated_at kolom bestaat al\n";
    }
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
    echo "  ✓ gymies_availability_exceptions aangemaakt\n";
} else {
    echo "  ✓ gymies_availability_exceptions bestaat\n";
}

// Bookings tabel: slot_date, day_of_week, week_number kolommen toevoegen
if (Schema::hasTable('gymies_bookings')) {
    if (!Schema::hasColumn('gymies_bookings', 'slot_date')) {
        Schema::table('gymies_bookings', function ($table) {
            $table->date('slot_date')->nullable()->after('scheduled_at')->index();
        });
        echo "  ✓ gymies_bookings.slot_date kolom toegevoegd\n";
    }
    if (!Schema::hasColumn('gymies_bookings', 'day_of_week')) {
        Schema::table('gymies_bookings', function ($table) {
            $table->tinyInteger('day_of_week')->nullable()->after('slot_date');
        });
        echo "  ✓ gymies_bookings.day_of_week kolom toegevoegd\n";
    }
    if (!Schema::hasColumn('gymies_bookings', 'week_number')) {
        Schema::table('gymies_bookings', function ($table) {
            $table->tinyInteger('week_number')->nullable()->after('day_of_week');
        });
        echo "  ✓ gymies_bookings.week_number kolom toegevoegd\n";
    }
}

// Toon finale kolomstructuur
$cols = Schema::getColumnListing('gymies_availability_slots');
echo "\n  Finale kolommen: " . implode(', ', $cols) . "\n";

// ── STAP 2: Trainers opzoeken ────────────────────────────
echo "\n=== 2/4 Trainers opzoeken ===\n";

$usersCols = Schema::getColumnListing('gymies_users');
$nameCol = 'id';
foreach (['display_name', 'name', 'full_name', 'first_name'] as $try) {
    if (in_array($try, $usersCols)) { $nameCol = $try; break; }
}

$trainers = DB::table('gymies_trainer_profiles')
    ->join('gymies_users', 'gymies_users.id', '=', 'gymies_trainer_profiles.user_id')
    ->select('gymies_trainer_profiles.user_id', "gymies_users.{$nameCol} as trainer_name")
    ->get();

echo "  Trainers: " . count($trainers) . "\n";
foreach ($trainers as $t) {
    echo "    - #{$t->user_id}: {$t->trainer_name}\n";
}

if ($trainers->isEmpty()) {
    echo "  ⚠ Geen trainers — script stopt.\n";
    exit(0);
}

// ── STAP 3: Beschikbaarheid invullen ─────────────────────
echo "\n=== 3/4 Testdata invullen ===\n";

$trainerIds = $trainers->pluck('user_id')->toArray();
$existingColumns = Schema::getColumnListing('gymies_availability_slots');
$hasSlotDate = in_array('slot_date', $existingColumns);
$hasWeekNumber = in_array('week_number', $existingColumns);
$hasWeekday = in_array('weekday', $existingColumns);
$hasDayOfWeek = in_array('day_of_week', $existingColumns);
$hasIsActive = in_array('is_active', $existingColumns);
$hasUpdatedAt = in_array('updated_at', $existingColumns);

// Clean start
DB::table('gymies_availability_slots')->whereIn('trainer_user_id', $trainerIds)->delete();
echo "  ✓ Bestaande slots verwijderd\n";

// Definieer tijdslots per weekdag (ISO: 1=ma, 7=zo)
$timesPerDay = [
    1 => [['07:00','08:00'],['08:00','09:00'],['09:00','10:00'],['10:00','11:00'],['17:00','18:00'],['18:00','19:00'],['19:00','20:00']], // ma
    2 => [['08:00','09:00'],['09:00','10:00'],['10:00','11:00'],['16:00','17:00'],['17:00','18:00'],['18:00','19:00']],                   // di
    3 => [['07:00','08:00'],['08:00','09:00'],['09:00','10:00'],['10:00','11:00'],['11:00','12:00']],                                     // wo
    4 => [['08:00','09:00'],['09:00','10:00'],['16:00','17:00'],['17:00','18:00'],['18:00','19:00'],['19:00','20:00']],                   // do
    5 => [['07:00','08:00'],['08:00','09:00'],['09:00','10:00'],['10:00','11:00']],                                                       // vr
    6 => [['09:00','10:00'],['10:00','11:00'],['11:00','12:00']],                                                                         // za
    // 7 = zo → vrij
];

// Genereer slots voor 4 weken vooruit (vandaag t/m +28 dagen)
$now = now();
$startDate = new \DateTime('now', new \DateTimeZone('Europe/Amsterdam'));
$inserted = 0;

foreach ($trainerIds as $trainerId) {
    $date = clone $startDate;
    for ($d = 0; $d < 28; $d++) {
        $isoWeekday = (int) $date->format('N');  // 1=ma ... 7=zo
        $weekNum = (int) $date->format('W');      // ISO weeknummer
        $dateStr = $date->format('Y-m-d');

        if (isset($timesPerDay[$isoWeekday])) {
            foreach ($timesPerDay[$isoWeekday] as [$start, $end]) {
                $row = [
                    'trainer_user_id' => $trainerId,
                    'start_time'      => $start,
                    'end_time'        => $end,
                    'created_at'      => $now,
                ];
                if ($hasIsActive)   $row['is_active'] = true;
                if ($hasUpdatedAt)  $row['updated_at'] = $now;
                if ($hasDayOfWeek)  $row['day_of_week'] = $isoWeekday;
                if ($hasWeekday)    $row['weekday'] = $isoWeekday;
                if ($hasSlotDate)   $row['slot_date'] = $dateStr;
                if ($hasWeekNumber) $row['week_number'] = $weekNum;

                DB::table('gymies_availability_slots')->insert($row);
                $inserted++;
            }
        }
        $date->modify('+1 day');
    }
    echo "  ✓ Trainer #{$trainerId}: slots voor 4 weken\n";
}

echo "\n  Totaal: {$inserted} slots aangemaakt\n";
echo "  Periode: {$startDate->format('d-m-Y')} t/m " . (clone $startDate)->modify('+27 days')->format('d-m-Y') . "\n";

// ── STAP 4: Verificatie ──────────────────────────────────
echo "\n=== 4/4 Verificatie ===\n";
$sample = DB::table('gymies_availability_slots')
    ->limit(5)
    ->orderBy('slot_date')
    ->orderBy('start_time')
    ->get();
foreach ($sample as $s) {
    $r = (array) $s;
    $date = $r['slot_date'] ?? '-';
    $dow = $r['day_of_week'] ?? $r['weekday'] ?? '?';
    $wk = $r['week_number'] ?? '?';
    echo "  #{$r['id']} | {$date} | dag:{$dow} | wk:{$wk} | {$r['start_time']}-{$r['end_time']}\n";
}
echo "  ...\n";

PHP

# Cache rebuilden
echo ""
echo "=== Cache rebuilden ==="
sudo -u www-data php artisan config:clear 2>/dev/null && echo "  config:clear OK"
sudo -u www-data php artisan route:clear 2>/dev/null && echo "  route:clear OK"
sudo -u www-data php artisan config:cache 2>/dev/null && echo "  config:cache OK"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "  route:cache OK"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Beschikbaarheid INGESTELD                           ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                      ║"
echo "║  Schema: slot_date + week_number + day_of_week       ║"
echo "║  Data:   4 weken vooruit, per trainer                ║"
echo "║                                                      ║"
echo "║  • Ma: 07-11 + 17-20 (7 slots/dag)                  ║"
echo "║  • Di: 08-11 + 16-19 (6 slots/dag)                  ║"
echo "║  • Wo: 07-12 (5 slots/dag)                           ║"
echo "║  • Do: 08-10 + 16-20 (6 slots/dag)                  ║"
echo "║  • Vr: 07-11 (4 slots/dag)                           ║"
echo "║  • Za: 09-12 (3 slots/dag)                           ║"
echo "║  • Zo: vrij                                          ║"
echo "║                                                      ║"
echo "╚══════════════════════════════════════════════════════╝"
