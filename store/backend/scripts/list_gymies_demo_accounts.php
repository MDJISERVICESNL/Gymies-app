<?php
/**
 * Toon demo-accounts in gymies_users (klant + trainer).
 * Gebruik: php list_gymies_demo_accounts.php [laravel_root]
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

if (!Schema::hasTable('gymies_users')) {
    fwrite(STDERR, "Tabel gymies_users bestaat niet.\n");
    exit(1);
}

$demos = DB::table('gymies_users')
    ->where('email', 'like', '%demo%')
    ->orWhere('display_name', 'like', '%demo%')
    ->orWhere('display_name', 'like', '%Demo%')
    ->get();

echo "=== Demo-accounts in gymies_users ===\n";
foreach ($demos as $u) {
    $role = $u->role ?? '?';
    $verified = !empty($u->email_verified_at) ? '✓' : '✗';
    echo sprintf("  ID %3d: %-35s role=%s  verified=%s  (%s)\n",
        $u->id, $u->email, $role, $verified, $u->display_name ?? '-');
}

if ($demos->isEmpty()) {
    echo "  Geen demo-accounts. Toon eerste 10 users:\n";
    $any = DB::table('gymies_users')->orderBy('id')->limit(10)->get();
    foreach ($any as $u) {
        echo sprintf("  ID %3d: %-35s role=%s\n", $u->id, $u->email, $u->role ?? '?');
    }
}
