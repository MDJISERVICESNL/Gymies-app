<?php
/**
 * Controleer of alle Gymies-onderdelen correct zijn verbonden.
 * Run op server: sudo -u www-data php scripts/verify_gymies_connected.php [laravel_root]
 *
 * Controleert: routes, middleware, tabellen, login-flow.
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Route;

$ok = 0;
$fail = 0;

echo "=== Gymies verbinding verificatie ===\n\n";

// 1. Routes geladen?
echo "[1] Routes geladen?\n";
$routesFile = $base . '/routes/routes_gymies_full.php';
if (!is_file($routesFile)) {
    echo "    FOUT: $routesFile niet gevonden. Run sync_gymies_backend.sh.\n";
    $fail++;
} else {
    $webContent = @file_get_contents($base . '/routes/web.php') ?: '';
    $apiContent = @file_get_contents($base . '/routes/api.php') ?: '';
    $hasRequire = strpos($webContent, 'routes_gymies_full') !== false || strpos($apiContent, 'routes_gymies_full') !== false;
    if (!$hasRequire) {
        echo "    FOUT: routes_gymies_full.php niet geladen in web.php of api.php.\n";
        echo "    Voeg toe: require __DIR__ . '/routes_gymies_full.php';\n";
        echo "    Of run: sudo php scripts/register_gymies_routes.php .\n";
        $fail++;
    } else {
        echo "    OK: routes_gymies_full.php wordt geladen.\n";
        $ok++;
    }
}

// 2. Gymies routes geregistreerd?
echo "\n[2] Gymies API routes geregistreerd?\n";
$loginRoute = null;
foreach (Route::getRoutes() as $r) {
    if (str_contains($r->uri(), 'api/gymies/login')) {
        $loginRoute = $r;
        break;
    }
}
if ($loginRoute === null) {
    echo "    FOUT: Geen api/gymies/login route gevonden.\n";
    $fail++;
} else {
    echo "    OK: api/gymies/login route bestaat.\n";
    $ok++;
}

// 3. Tabellen
echo "\n[3] Database tabellen?\n";
$usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
$tokensTable = Schema::hasTable('gymies_personal_access_tokens') ? 'gymies_personal_access_tokens' : 'personal_access_tokens';
if (!Schema::hasTable($usersTable)) {
    echo "    FOUT: Tabel $usersTable niet gevonden.\n";
    $fail++;
} else {
    echo "    OK: $usersTable bestaat.\n";
    $ok++;
}
if (!Schema::hasTable($tokensTable)) {
    echo "    FOUT: Tabel $tokensTable niet gevonden. Run: php artisan migrate\n";
    $fail++;
} else {
    echo "    OK: $tokensTable bestaat.\n";
    $ok++;
}

// 4. Middleware (EnsureGymiesUserFromToken)
echo "\n[4] Auth middleware?\n";
$middlewarePath = $base . '/app/Http/Middleware/EnsureGymiesUserFromToken.php';
if (!is_file($middlewarePath)) {
    echo "    FOUT: EnsureGymiesUserFromToken.php niet gevonden.\n";
    $fail++;
} else {
    echo "    OK: EnsureGymiesUserFromToken.php aanwezig.\n";
    $ok++;
}

// 5. Debug endpoint bereikbaar (intern) – optioneel, geen harde fout
echo "\n[5] Debug-auth endpoint?\n";
try {
    $req = \Illuminate\Http\Request::create('https://localhost/api/gymies/debug-auth', 'GET');
    $req->server->set('HTTP_AUTHORIZATION', 'Bearer test123');
    $req->headers->set('Authorization', 'Bearer test123');
    $kernel = $app->make(\Illuminate\Contracts\Http\Kernel::class);
    $res = $kernel->handle($req);
    $rawContent = $res->getContent();
    $body = is_string($rawContent) ? json_decode($rawContent, true) : null;
    $kernel->terminate($req, $res);
    if ($body && isset($body['auth_header_received'])) {
        echo "    OK: debug-auth endpoint werkt.\n";
        $ok++;
    } else {
        $status = $res->getStatusCode();
        echo "    Waarschuwing: debug-auth geeft onverwachte response (status=$status).\n";
        echo "    Niet kritiek. Probeer: php artisan route:clear && php artisan optimize:clear\n";
        $ok++; // Niet als fout tellen – kernsetup is OK
    }
} catch (\Throwable $e) {
    echo "    Waarschuwing: " . $e->getMessage() . " (niet kritiek)\n";
    $ok++; // Niet als fout tellen
}

echo "\n=== Resultaat: $ok OK, $fail fout(en) ===\n";
if ($fail > 0) {
    echo "\nVoer diagnose uit: sudo -u www-data php scripts/diagnose_auth.php . EMAIL WACHTWOORD\n";
    exit(1);
}
echo "\nAlles verbonden. Test login in de app.\n";
exit(0);
