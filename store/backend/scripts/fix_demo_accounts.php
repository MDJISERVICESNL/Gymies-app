<?php
/**
 * Fix demo-accounts:
 * - demo-klant: verwijder trainer profile (moet KLANT zijn)
 * - demo-trainer: aanmaken als niet bestaat, of vinden
 * - Wachtwoord reset naar demo123! voor beide
 *
 * Gebruik: php fix_demo_accounts.php [laravel_root] [wachtwoord]
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');
$password = $argv[2] ?? 'demo123!';

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

echo "=== Demo-accounts fix ===\n";

// 1. demo-klant@gymies.nl = KLANT (geen trainer profile)
$klant = \App\Models\User::where('email', 'demo-klant@gymies.nl')->first();
if ($klant) {
    if (Schema::hasTable('gymies_trainer_profiles')) {
        $deleted = DB::table('gymies_trainer_profiles')->where('user_id', $klant->id)->delete();
        echo "demo-klant: trainer profile " . ($deleted ? "verwijderd" : "was er niet") . "\n";
    }
    $klant->password = \Illuminate\Support\Facades\Hash::make($password);
    $klant->save();
    echo "demo-klant@gymies.nl: wachtwoord gereset. Rol: KLANT\n";
} else {
    $klant = \App\Models\User::create([
        'name' => 'Demo Klant',
        'email' => 'demo-klant@gymies.nl',
        'password' => \Illuminate\Support\Facades\Hash::make($password),
        'email_verified_at' => now(),
    ]);
    echo "demo-klant@gymies.nl: aangemaakt (KLANT)\n";
}

// 2. demo-trainer@gymies.nl = TRAINER (met trainer profile)
$trainer = \App\Models\User::where('email', 'demo-trainer@gymies.nl')->first();
if ($trainer) {
    $trainer->password = \Illuminate\Support\Facades\Hash::make($password);
    $trainer->save();
    if (Schema::hasTable('gymies_trainer_profiles')) {
        $exists = DB::table('gymies_trainer_profiles')->where('user_id', $trainer->id)->exists();
        if (!$exists) {
            DB::table('gymies_trainer_profiles')->insert([
                'user_id' => $trainer->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            echo "demo-trainer: trainer profile toegevoegd\n";
        }
    }
    echo "demo-trainer@gymies.nl: wachtwoord gereset. Rol: TRAINER\n";
} else {
    $trainer = \App\Models\User::create([
        'name' => 'Demo Trainer',
        'email' => 'demo-trainer@gymies.nl',
        'password' => \Illuminate\Support\Facades\Hash::make($password),
        'email_verified_at' => now(),
    ]);
    if (Schema::hasTable('gymies_trainer_profiles')) {
        DB::table('gymies_trainer_profiles')->insert([
            'user_id' => $trainer->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }
    echo "demo-trainer@gymies.nl: aangemaakt (TRAINER)\n";
}

echo "\n=== Login-gegevens (beide: wachtwoord $password) ===\n";
echo "  Klant:  demo-klant@gymies.nl\n";
echo "  Trainer: demo-trainer@gymies.nl\n";
