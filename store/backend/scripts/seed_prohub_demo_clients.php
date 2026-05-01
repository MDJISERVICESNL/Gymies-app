#!/usr/bin/env php
<?php
/**
 * Seed demo-klanten voor Pro Hub testen op demo-gymies.nl.
 * Maakt 15+ klanten aan met voltooide sessies bij de demo-trainer.
 * - Health tab: alle klanten met ≥1 sessie
 * - Upsell tab: klanten met 3+ voltooide sessies
 * - Herboek tab: klanten wiens laatste sessie >7 dagen geleden was
 *
 * Gebruik: php seed_prohub_demo_clients.php [laravel_root] [wachtwoord]
 * Op server: cd /var/www/gymies && sudo -u www-data php scripts/seed_prohub_demo_clients.php . demo123!
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');
$password = $argv[2] ?? 'demo123!';

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Hash;

echo "=== Pro Hub demo-klanten seed ===\n";

$usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
$bookingsTable = Schema::hasTable('gymies_bookings') ? 'gymies_bookings' : 'bookings';

if (!Schema::hasTable($bookingsTable)) {
    fwrite(STDERR, "Tabel $bookingsTable niet gevonden.\n");
    exit(1);
}

$trainerCol = 'trainer_user_id';
$clientCol = 'client_user_id';
$scheduledCol = 'scheduled_at';
$statusCol = 'status';
if (!Schema::hasColumn($bookingsTable, $trainerCol)) {
    $trainerCol = Schema::hasColumn($bookingsTable, 'trainer_id') ? 'trainer_id' : null;
}
if (!Schema::hasColumn($bookingsTable, $clientCol)) {
    $clientCol = Schema::hasColumn($bookingsTable, 'client_id') ? 'client_id' : (Schema::hasColumn($bookingsTable, 'user_id') ? 'user_id' : null);
}
if (!$trainerCol || !$clientCol) {
    fwrite(STDERR, "Tabel $bookingsTable mist trainer- of client-kolom.\n");
    exit(1);
}
if (!Schema::hasColumn($bookingsTable, $scheduledCol)) {
    $scheduledCol = Schema::hasColumn($bookingsTable, 'scheduledAt') ? 'scheduledAt' : (Schema::hasColumn($bookingsTable, 'session_at') ? 'session_at' : 'created_at');
}
if (!Schema::hasColumn($bookingsTable, $statusCol)) {
    $statusCol = null;
}

$nameCol = Schema::hasColumn($usersTable, 'display_name') ? 'display_name' : (Schema::hasColumn($usersTable, 'name') ? 'name' : 'email');

$trainer = DB::table($usersTable)
    ->whereIn('email', ['demo@gymies.nl', 'demo-trainer@gymies.nl'])
    ->first();

if (!$trainer) {
    fwrite(STDERR, "Demo-trainer (demo@gymies.nl of demo-trainer@gymies.nl) niet gevonden. Maak eerst een demo-trainer aan.\n");
    exit(1);
}

$trainerId = (int) $trainer->id;
echo "Demo-trainer: {$trainer->email} (ID $trainerId)\n";

$clientRole = null;
if (Schema::hasColumn($usersTable, 'role')) {
    $existingClient = DB::table($usersTable)->where('email', 'demo-klant@gymies.nl')->first();
    $clientRole = $existingClient?->role ?? null;
    if ($clientRole === null) {
        $roles = DB::table($usersTable)->distinct()->pluck('role')->filter()->values();
        $trainerRoles = ['trainer', 'TRAINER', 'admin', 'ADMIN'];
        $clientRole = $roles->first(fn ($r) => !in_array((string) $r, $trainerRoles)) ?? 'klant';
    }
}

$names = [
    'Anna', 'Bram', 'Charlotte', 'Daan', 'Emma', 'Finn', 'Gijs', 'Hannah',
    'Isaac', 'Julia', 'Koen', 'Lotte', 'Milan', 'Nina', 'Olivier', 'Puck',
    'Quinn', 'Ruben', 'Sanne', 'Thijs',
];

$created = 0;
$bookingsCreated = 0;

for ($i = 1; $i <= count($names); $i++) {
    $email = "demo-prohub-{$i}@gymies.nl";
    $name = $names[$i - 1] . ' (Pro Hub)';

    $user = DB::table($usersTable)->where('email', $email)->first();
    if (!$user) {
        $insert = ['email' => $email];
        if (Schema::hasColumn($usersTable, 'email_verified_at')) {
            $insert['email_verified_at'] = now();
        }
        if (Schema::hasColumn($usersTable, 'created_at')) {
            $insert['created_at'] = now();
        }
        if (Schema::hasColumn($usersTable, 'updated_at')) {
            $insert['updated_at'] = now();
        }
        $passCol = Schema::hasColumn($usersTable, 'password_hash') ? 'password_hash' : 'password';
        $insert[$passCol] = Hash::make($password);
        if (Schema::hasColumn($usersTable, 'name')) {
            $insert['name'] = $name;
        }
        if (Schema::hasColumn($usersTable, 'display_name')) {
            $insert['display_name'] = $name;
        }
        if (Schema::hasColumn($usersTable, 'role') && $clientRole !== null) {
            $insert['role'] = $clientRole;
        }
        $userId = (int) DB::table($usersTable)->insertGetId($insert);
        $created++;
        echo "  Aangemaakt: $email (ID $userId)\n";
    } else {
        $userId = (int) $user->id;
    }

    $existingBookings = DB::table($bookingsTable)
        ->where($trainerCol, $trainerId)
        ->where($clientCol, $userId)
        ->count();

    if ($existingBookings >= 5) {
        continue;
    }

    $sessionsToCreate = 5 - $existingBookings;
    $completedStatuses = ['completed', 'done', 'finished', 'checked_in'];

    // Variatie: oneven i = laatste sessie >7 dagen geleden (herboek-tab), even = recent
    $lastSessionDaysAgo = ($i % 2 === 1) ? 10 + ($i % 5) : 2 + ($i % 3);

    for ($s = 0; $s < $sessionsToCreate; $s++) {
        $daysAgo = $lastSessionDaysAgo + (4 - $s) * 7;
        $scheduledAt = now()->subDays($daysAgo)->setTime(10 + ($s % 3), 0, 0);

        $bookingInsert = [
            $trainerCol => $trainerId,
            $clientCol => $userId,
            $scheduledCol => $scheduledAt->format('Y-m-d H:i:s'),
        ];
        if (Schema::hasColumn($bookingsTable, 'created_at')) {
            $bookingInsert['created_at'] = now();
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $bookingInsert['updated_at'] = now();
        }
        if ($statusCol) {
            $bookingInsert[$statusCol] = 'completed';
        }
        if (Schema::hasColumn($bookingsTable, 'duration_minutes')) {
            $bookingInsert['duration_minutes'] = 60;
        }
        if (Schema::hasColumn($bookingsTable, 'amount_cents')) {
            $bookingInsert['amount_cents'] = 4500;
        }

        try {
            DB::table($bookingsTable)->insert($bookingInsert);
            $bookingsCreated++;
        } catch (\Throwable $e) {
            echo "  Waarschuwing: boeking voor $email mislukt: " . $e->getMessage() . "\n";
        }
    }
}

echo "\n=== Resultaat ===\n";
echo "Nieuwe klanten: $created\n";
echo "Nieuwe boekingen: $bookingsCreated\n";
echo "\nPro Hub test-accounts (wachtwoord: $password):\n";
for ($i = 1; $i <= count($names); $i++) {
    echo "  demo-prohub-{$i}@gymies.nl\n";
}
echo "\nLog in als trainer: demo@gymies.nl of demo-trainer@gymies.nl\n";
echo "Open Pro Hub in de app om Health, Upsell en Herboek te testen.\n";
