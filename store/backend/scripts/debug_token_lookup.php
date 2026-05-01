<?php
/**
 * Debug: controleer of een token gevonden kan worden.
 * Gebruik: php debug_token_lookup.php [laravel_root] [bearer_token]
 *
 * Voorbeeld: php debug_token_lookup.php . "1|abc123xyz..."
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');
$token = $argv[2] ?? '';

if ($token === '') {
    echo "Gebruik: php debug_token_lookup.php [laravel_root] [bearer_token]\n";
    echo "Token = wat de app stuurt na 'Bearer ' (bijv. 1|abc123...)\n";
    exit(1);
}

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\PersonalAccessToken;

$plainToken = str_contains($token, '|') ? substr($token, strpos($token, '|') + 1) : $token;
$hashedToken = hash('sha256', $plainToken);

echo "Token (eerste 20 chars): " . substr($token, 0, 20) . "...\n";
echo "PlainToken (eerste 20 chars): " . substr($plainToken, 0, 20) . "...\n";
echo "HashedToken (eerste 20 chars): " . substr($hashedToken, 0, 20) . "...\n\n";

echo "1. Sanctum PersonalAccessToken::findToken(plainToken): ";
try {
    $pat = PersonalAccessToken::findToken($plainToken);
    echo $pat ? "GEVONDEN (tokenable_id=" . ($pat->tokenable_id ?? '?') . ")" : "NIET GEVONDEN";
} catch (\Throwable $e) {
    echo "FOUT: " . $e->getMessage();
}
echo "\n";

echo "2. personal_access_tokens tabel: ";
if (Schema::hasTable('personal_access_tokens')) {
    $count = DB::table('personal_access_tokens')->count();
    $found = DB::table('personal_access_tokens')->where('token', $hashedToken)->first();
    echo "bestaat, {$count} rijen, lookup: " . ($found ? "GEVONDEN (tokenable_id={$found->tokenable_id})" : "NIET GEVONDEN");
} else {
    echo "BESTAAT NIET";
}
echo "\n";

echo "3. gymies_personal_access_tokens: ";
if (Schema::hasTable('gymies_personal_access_tokens')) {
    $found = DB::table('gymies_personal_access_tokens')->where('token', $hashedToken)->first();
    echo $found ? "GEVONDEN" : "NIET GEVONDEN";
} else {
    echo "BESTAAT NIET";
}
echo "\n";

echo "4. gymies_users.api_token: ";
if (Schema::hasTable('gymies_users') && Schema::hasColumn('gymies_users', 'api_token')) {
    $found = DB::table('gymies_users')->where('api_token', $token)->orWhere('api_token', $plainToken)->first();
    echo $found ? "GEVONDEN (id={$found->id})" : "NIET GEVONDEN";
} else {
    echo "kolom ontbreekt";
}
echo "\n";
