<?php
/**
 * Toon alle users met hun rol (trainer of klant).
 * Gebruik: php list_all_users_with_roles.php [laravel_root]
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

echo "=== Alle gebruikers (id, email, naam, rol) ===\n";
$users = \App\Models\User::orderBy('id')->get(['id', 'email', 'name']);

$hasTrainerTable = Schema::hasTable('gymies_trainer_profiles');

foreach ($users as $u) {
    $role = 'klant';
    if ($hasTrainerTable && DB::table('gymies_trainer_profiles')->where('user_id', $u->id)->exists()) {
        $role = 'TRAINER';
    }
    echo sprintf("  ID %3d: %-35s %-20s [%s]\n", $u->id, $u->email, $u->name, $role);
}

echo "\n=== Demo-accounts specifiek ===\n";
$demos = $users->filter(fn($u) => stripos($u->email, 'demo') !== false || stripos($u->name ?? '', 'demo') !== false);
foreach ($demos as $u) {
    $role = $hasTrainerTable && DB::table('gymies_trainer_profiles')->where('user_id', $u->id)->exists() ? 'TRAINER' : 'klant';
    echo "  {$u->email} ({$u->name}) = $role\n";
}
