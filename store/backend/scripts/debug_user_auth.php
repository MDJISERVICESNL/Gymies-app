<?php
/**
 * Debug auth voor een specifieke gebruiker.
 * Controleert of de user bestaat en maakt indien gewenst een nieuw token aan.
 *
 * Gebruik: php debug_user_auth.php [laravel_root] [email] [--create-token]
 *
 * Voorbeeld: php debug_user_auth.php . jamai1210@live.nl --create-token
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');
$email = $argv[2] ?? '';
$createToken = in_array('--create-token', $argv, true);

if ($email === '') {
    echo "Gebruik: php debug_user_auth.php [laravel_root] [email] [--create-token]\n";
    echo "Voorbeeld: php debug_user_auth.php . jamai1210@live.nl --create-token\n";
    exit(1);
}

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

echo "=== Auth debug voor $email ===\n\n";

$usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
$user = DB::table($usersTable)->where('email', $email)->first();

if (!$user) {
    echo "FOUT: Gebruiker niet gevonden in $usersTable.\n";
    exit(1);
}

echo "1. Gebruiker gevonden: id={$user->id}, email={$user->email}\n";
echo "   Tabel: $usersTable\n";

$passCol = Schema::hasColumn($usersTable, 'password_hash') ? 'password_hash' : 'password';
echo "2. Wachtwoordkolom: $passCol " . (isset($user->{$passCol}) ? '(gezet)' : '(leeg!)') . "\n";

foreach (['personal_access_tokens', 'gymies_personal_access_tokens'] as $table) {
    if (!Schema::hasTable($table)) {
        echo "3. $table: BESTAAT NIET\n";
        continue;
    }
    $count = DB::table($table)->where('tokenable_id', (int) $user->id)->count();
    echo "3. $table: $count token(s) voor user_id {$user->id}\n";
}

if ($createToken) {
    echo "\n--- Nieuw token aanmaken ---\n";
    $plainToken = Str::random(40);
    $hashedToken = hash('sha256', $plainToken);
    $row = [
        'tokenable_type' => 'App\Models\User',
        'tokenable_id' => (int) $user->id,
        'name' => 'gymies-app',
        'token' => $hashedToken,
        'abilities' => '["*"]',
        'created_at' => now(),
        'updated_at' => now(),
    ];

    $inserted = false;
    foreach (['gymies_personal_access_tokens', 'personal_access_tokens'] as $table) {
        if (Schema::hasTable($table)) {
            try {
                $id = DB::table($table)->insertGetId($row);
                $fullToken = $id . '|' . $plainToken;
                echo "Token aangemaakt in $table (id=$id)\n";
                echo "Volledige token (voor app/test): $fullToken\n";
                echo "\nDe gebruiker moet UITLOGGEN en OPNIEUW INLOGGEN in de app om dit token te krijgen.\n";
                echo "Of test met: curl -H 'Authorization: Bearer $fullToken' https://www.gymies.nl/api/gymies/me\n";
                $inserted = true;
                break;
            } catch (\Throwable $e) {
                echo "Fout bij $table: " . $e->getMessage() . "\n";
            }
        }
    }
    if (!$inserted) {
        echo "Kon geen token aanmaken.\n";
        exit(1);
    }
} else {
    echo "\nTip: Voeg --create-token toe om een nieuw token aan te maken.\n";
}
