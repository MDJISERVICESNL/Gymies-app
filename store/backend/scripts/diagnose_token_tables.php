#!/usr/bin/env php
<?php
/**
 * Diagnose token-tabellen en zoek een specifiek token.
 * Gebruik: php diagnose_token_tables.php [laravel_root] [optioneel: bearer_token]
 *
 * Zonder token: toon tabelstructuur en aantal tokens.
 * Met token: controleer of token gevonden wordt (zelfde logica als EnsureGymiesUserFromToken).
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');
$tokenArg = $argv[2] ?? '';

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

echo "=== Gymies token-diagnose ===\n\n";

// 1. Tabellen
echo "1. Tabellen:\n";
$tables = ['gymies_users', 'users', 'gymies_personal_access_tokens', 'personal_access_tokens'];
foreach ($tables as $t) {
    $exists = Schema::hasTable($t);
    $count = $exists ? DB::table($t)->count() : 0;
    echo "   $t: " . ($exists ? "bestaat ($count rijen)" : "BESTAAT NIET") . "\n";
}

// 2. Auth flow: welke tabel gebruikt login?
$usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
$tokensTable = (Schema::hasTable('gymies_users') && Schema::hasTable('gymies_personal_access_tokens'))
    ? 'gymies_personal_access_tokens'
    : 'personal_access_tokens';
echo "\n2. Auth flow:\n";
echo "   Login gebruikt: $usersTable\n";
echo "   Tokens worden opgeslagen in: $tokensTable (voorkeur)\n";

// 3. Recente tokens (zonder hash te tonen)
if (Schema::hasTable($tokensTable)) {
    $recent = DB::table($tokensTable)
        ->orderByDesc('created_at')
        ->limit(5)
        ->get(['id', 'tokenable_id', 'tokenable_type', 'name', 'created_at']);
    echo "\n3. Meest recente tokens in $tokensTable:\n";
    foreach ($recent as $r) {
        echo "   id={$r->id} tokenable_id={$r->tokenable_id} type={$r->tokenable_type} created={$r->created_at}\n";
    }
}

// 4. Specifiek token opzoeken
if ($tokenArg !== '') {
    $token = trim($tokenArg);
    if (str_starts_with($token, 'Bearer ')) {
        $token = trim(substr($token, 7));
    }

    // 4a. Alleen token-ID (bijv. 41): toon rij in DB en hash-preview
    $tokenId = null;
    if (preg_match('/^\d+$/', $token)) {
        $tokenId = (int) $token;
        echo "\n4. Lookup token ID $tokenId in database:\n";
        foreach (['gymies_personal_access_tokens', 'personal_access_tokens'] as $t) {
            if (!Schema::hasTable($t)) continue;
            $row = DB::table($t)->where('id', $tokenId)->first();
            if ($row) {
                echo "   GEVONDEN in $t:\n";
                echo "      id={$row->id} tokenable_id={$row->tokenable_id} name=" . ($row->name ?? '?') . "\n";
                echo "      created_at={$row->created_at}\n";
                echo "      hash (eerste 24 chars): " . substr($row->token ?? '', 0, 24) . "...\n";
                $uid = (int) $row->tokenable_id;
                foreach (['gymies_users', 'users'] as $ut) {
                    if (Schema::hasTable($ut)) {
                        $u = DB::table($ut)->where('id', $uid)->first();
                        if ($u) {
                            echo "      User: id={$u->id} email=" . ($u->email ?? '?') . "\n";
                            break;
                        }
                    }
                }
            } else {
                echo "   $t: geen rij met id=$tokenId\n";
            }
        }
        exit(0);
    }

    // 4b. Volledige token (id|plainToken): zoek via hash
    $plainToken = str_contains($token, '|') ? substr($token, strpos($token, '|') + 1) : $token;
    $hashedToken = hash('sha256', $plainToken);

    echo "\n4. Token lookup (preview: " . substr($token, 0, 8) . "..." . substr($token, -4) . "):\n";
    echo "   plainToken lengte: " . strlen($plainToken) . ", hash (eerste 24): " . substr($hashedToken, 0, 24) . "...\n";

    foreach (['gymies_personal_access_tokens', 'personal_access_tokens'] as $t) {
        if (!Schema::hasTable($t)) continue;
        $row = DB::table($t)->where('token', $hashedToken)->first();
        if ($row) {
            echo "   GEVONDEN in $t: id={$row->id} tokenable_id={$row->tokenable_id}\n";
            $uid = (int) $row->tokenable_id;
            foreach (['gymies_users', 'users'] as $ut) {
                if (Schema::hasTable($ut)) {
                    $u = DB::table($ut)->where('id', $uid)->first();
                    if ($u) {
                        echo "   User in $ut: id={$u->id} email=" . ($u->email ?? '?') . "\n";
                        break;
                    }
                }
            }
            exit(0);
        }
        echo "   $t: niet gevonden (hash match)\n";
    }
    echo "   Token NIET GEVONDEN in database.\n";
    echo "   Mogelijke oorzaken: token verlopen/verwijderd, of login gebruikte andere tabel.\n";
} else {
    echo "\n4. Geen token meegegeven. Voor token-check:\n";
    echo "   php diagnose_token_tables.php . 41              # lookup op token-ID\n";
    echo "   php diagnose_token_tables.php . \"41|ASGSs...1mcO\"  # lookup op volledige token\n";
}
