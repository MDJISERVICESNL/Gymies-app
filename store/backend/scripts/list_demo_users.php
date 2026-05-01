#!/usr/bin/env php
<?php
/**
 * Toon demo-accounts (trainer + klant) en alle users met 'demo' in email of naam.
 * Gebruik: php list_demo_users.php [laravel_root]
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

echo "=== Demo-accounts (email of naam bevat 'demo') ===\n";
$demoUsers = \App\Models\User::where('email', 'like', '%demo%')
    ->orWhere('name', 'like', '%demo%')
    ->orWhere('name', 'like', '%Demo%')
    ->get(['id', 'email', 'name']);

foreach ($demoUsers as $u) {
    $isTrainer = Schema::hasTable('gymies_trainer_profiles')
        ? DB::table('gymies_trainer_profiles')->where('user_id', $u->id)->exists()
        : false;
    $role = $isTrainer ? ' [TRAINER]' : ' [KLANT]';
    echo "  ID {$u->id}: {$u->email} ({$u->name})$role\n";
}

if ($demoUsers->isEmpty()) {
    echo "  Geen demo-accounts gevonden. Toon eerste 20 users:\n";
    $any = \App\Models\User::orderBy('id')->limit(20)->get(['id', 'email', 'name']);
    foreach ($any as $u) {
        $isTrainer = Schema::hasTable('gymies_trainer_profiles')
            ? DB::table('gymies_trainer_profiles')->where('user_id', $u->id)->exists()
            : false;
        $role = $isTrainer ? ' [TRAINER]' : '';
        echo "  ID {$u->id}: {$u->email} ({$u->name})$role\n";
    }
}
