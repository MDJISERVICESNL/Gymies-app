<?php
/**
 * Reset wachtwoord van beide demo-accounts in gymies_users naar demo123!
 * Gebruik: php reset_both_demo_accounts.php [laravel_root] [wachtwoord]
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');
$newPass = $argv[2] ?? 'demo123!';

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Hash;

$emails = ['demo@gymies.nl', 'demo-klant@gymies.nl'];

if (!Schema::hasTable('gymies_users')) {
    fwrite(STDERR, "FOUT: tabel gymies_users bestaat niet\n");
    exit(1);
}

$passCol = Schema::hasColumn('gymies_users', 'password_hash') ? 'password_hash' : 'password';
foreach ($emails as $email) {
    $user = DB::table('gymies_users')->where('email', $email)->first();
    if ($user) {
        DB::table('gymies_users')->where('id', $user->id)->update([
            $passCol => Hash::make($newPass),
        ]);
        echo "OK: $email (role={$user->role}) wachtwoord gereset.\n";
    } else {
        echo "SKIP: $email niet gevonden.\n";
    }
}

echo "\nLogin: demo@gymies.nl / $newPass  (trainer)\n";
echo "Login: demo-klant@gymies.nl / $newPass  (klant)\n";
