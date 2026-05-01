#!/usr/bin/env php
<?php
/**
 * Test: haal Mollie klanten op van een specifieke trainer (via hun OAuth access token).
 * Trainers die betaallinks gebruiken hebben klanten in hun eigen Mollie-account.
 *
 * Gebruik: php test_trainer_mollie_customers.php [base_path] [user_id|email]
 *   base_path: Laravel root (default: __DIR__/../..)
 *   user_id of email: trainer om klanten van op te halen
 *
 * Voorbeeld: php test_trainer_mollie_customers.php /var/www/gymies 42
 * Voorbeeld: php test_trainer_mollie_customers.php /var/www/gymies jamai1210@live.nl
 */

$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim($base, '/');
$identifier = $argv[2] ?? null;

if (empty($identifier)) {
    fwrite(STDERR, "Gebruik: php test_trainer_mollie_customers.php [base_path] <user_id|email>\n");
    exit(1);
}

$autoload = $base . '/vendor/autoload.php';
if (!file_exists($autoload)) {
    fwrite(STDERR, "Laravel vendor niet gevonden: $base\n");
    exit(1);
}

require $autoload;
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Http;

if (!Schema::hasTable('gymies_trainer_profiles')) {
    fwrite(STDERR, "Tabel gymies_trainer_profiles ontbreekt.\n");
    exit(1);
}

if (!Schema::hasColumn('gymies_trainer_profiles', 'mollie_access_token')) {
    fwrite(STDERR, "Kolom mollie_access_token ontbreekt. Draai migratie: php artisan migrate\n");
    exit(1);
}

// Zoek trainer op user_id of email
$profile = null;
if (is_numeric($identifier)) {
    $profile = DB::table('gymies_trainer_profiles')->where('user_id', (int) $identifier)->first();
} else {
    $user = DB::table('users')->where('email', $identifier)->first();
    if ($user) {
        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $user->id)->first();
    }
}

if (!$profile) {
    fwrite(STDERR, "Trainer niet gevonden voor: $identifier\n");
    exit(1);
}

$encryptedToken = $profile->mollie_access_token ?? null;
if (empty($encryptedToken)) {
    fwrite(STDERR, "Trainer heeft geen Mollie access token (nog niet verbonden of her-verbinden).\n");
    fwrite(STDERR, "Laat de trainer Mollie Connect opnieuw doen om tokens op te slaan.\n");
    exit(1);
}

try {
    $accessToken = decrypt($encryptedToken);
} catch (\Throwable $e) {
    fwrite(STDERR, "Kan token niet decrypten (APP_KEY gewijzigd?): " . $e->getMessage() . "\n");
    exit(1);
}

$resp = Http::withToken($accessToken)->get('https://api.mollie.com/v2/customers', [
    'limit' => 50,
]);

if (!$resp->successful()) {
    $body = $resp->json();
    $msg = $body['detail'] ?? $body['title'] ?? $resp->body();
    fwrite(STDERR, "Mollie API fout (HTTP {$resp->status()}): $msg\n");
    exit(1);
}

$data = $resp->json();
$count = $data['count'] ?? 0;
$customers = $data['_embedded']['customers'] ?? [];

$trainerName = DB::table('users')->where('id', $profile->user_id)->value('name') ?? 'Trainer #' . $profile->user_id;
echo "Mollie klanten van $trainerName (user_id={$profile->user_id}): $count\n";
echo str_repeat('-', 50) . "\n";

foreach ($customers as $c) {
    $name = $c['name'] ?? '-';
    $email = $c['email'] ?? '-';
    $id = $c['id'] ?? '-';
    echo "  - $name | $email | ID: $id\n";
}

if ($count > count($customers)) {
    echo "  ... en " . ($count - count($customers)) . " meer (limit 50)\n";
}
