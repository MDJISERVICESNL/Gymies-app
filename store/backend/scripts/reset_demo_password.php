#!/usr/bin/env php
<?php
/**
 * Reset wachtwoord van demo-klant@gymies.nl
 * Gebruik: php reset_demo_password.php [laravel_root] [nieuw_wachtwoord]
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');
$newPass = $argv[2] ?? 'demo123!';

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$user = \App\Models\User::where('email', 'demo-klant@gymies.nl')->first();
if (!$user) {
    fwrite(STDERR, "FOUT: demo-klant@gymies.nl niet gevonden\n");
    exit(1);
}

$user->password = \Illuminate\Support\Facades\Hash::make($newPass);
$user->save();

echo "OK: Wachtwoord gereset. Login met: demo-klant@gymies.nl / $newPass\n";
