<?php
/**
 * Clear auth block voor demo-klant (gymies_auth_attempts).
 * Gebruik: php clear_auth_block.php [laravel_root]
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

if (!Schema::hasTable('gymies_auth_attempts')) {
    echo "Geen gymies_auth_attempts tabel.\n";
    exit(0);
}

$deleted = DB::table('gymies_auth_attempts')
    ->where('email', 'like', '%demo%')
    ->delete();

echo "Auth attempts voor demo-accounts gewist: $deleted rows\n";
