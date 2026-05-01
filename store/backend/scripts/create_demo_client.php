#!/usr/bin/env php
<?php
/**
 * Maak demo-klant@gymies.nl aan met wachtwoord demo123! (als die niet bestaat).
 * Gebruik: php create_demo_client.php [laravel_root] [wachtwoord]
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');
$password = $argv[2] ?? 'demo123!';

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$email = 'demo-klant@gymies.nl';
$user = \App\Models\User::where('email', $email)->first();

if ($user) {
    $user->password = \Illuminate\Support\Facades\Hash::make($password);
    $user->save();
    echo "OK: $email bestaat al, wachtwoord gereset.\n";
} else {
    $user = \App\Models\User::create([
        'name' => 'Demo Klant',
        'email' => $email,
        'password' => \Illuminate\Support\Facades\Hash::make($password),
        'email_verified_at' => now(),
    ]);
    echo "OK: $email aangemaakt met wachtwoord.\n";
}
echo "Login: $email / $password\n";
