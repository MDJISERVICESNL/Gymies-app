<?php
/**
 * Reset wachtwoord van demo-klant in gymies_users (API-login gebruikt deze tabel).
 * Gebruik: php reset_demo_password_gymies.php [laravel_root] [wachtwoord]
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

$email = 'demo-klant@gymies.nl';

if (!Schema::hasTable('gymies_users')) {
    fwrite(STDERR, "FOUT: tabel gymies_users bestaat niet\n");
    exit(1);
}

$user = DB::table('gymies_users')->where('email', $email)->first();

if (!$user) {
    echo "demo-klant@gymies.nl niet in gymies_users. Toon bestaande demo-accounts:\n";
    $demos = DB::table('gymies_users')->where('email', 'like', '%demo%')->orWhere('display_name', 'like', '%demo%')->get();
    foreach ($demos as $u) {
        echo "  ID {$u->id}: {$u->email} (role: {$u->role})\n";
    }
    if ($demos->isEmpty()) {
        echo "  Geen demo-accounts gevonden in gymies_users.\n";
    }
    exit(1);
}

$passCol = Schema::hasColumn('gymies_users', 'password_hash') ? 'password_hash' : 'password';
DB::table('gymies_users')->where('id', $user->id)->update([
    $passCol => Hash::make($newPass),
    'email_verified_at' => $user->email_verified_at ?? now(),
]);

echo "OK: $email wachtwoord gereset in gymies_users.\n";
echo "Login: $email / $newPass\n";
