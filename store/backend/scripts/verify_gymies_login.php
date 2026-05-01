<?php
/**
 * Verificeer of demo-klant kan inloggen (gymies_users).
 * Gebruik: php verify_gymies_login.php [laravel_root] [wachtwoord]
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

$email = 'demo-klant@gymies.nl';

$user = DB::table('gymies_users')->where('email', $email)->first();

if (!$user) {
    echo "User niet gevonden.\n";
    exit(1);
}

echo "User: $user->email (ID:$user->id)\n";
echo "password_hash kolom: " . (isset($user->password_hash) ? 'JA' : 'NEE') . "\n";

$ok = isset($user->password_hash) && Hash::check($password, $user->password_hash);
echo "Hash::check('$password', hash): " . ($ok ? 'JA' : 'NEE') . "\n";
echo "email_verified_at: " . ($user->email_verified_at ?? 'NULL') . "\n";
