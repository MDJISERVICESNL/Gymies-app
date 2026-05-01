<?php
/**
 * Volledige diagnose: login → token → /me.
 * Voert een echte HTTP-request uit om te zien of de Authorization-header aankomt.
 *
 * Gebruik: php diagnose_auth.php [laravel_root] [email] [wachtwoord]
 * Voorbeeld: php diagnose_auth.php . demo-klant@gymies.nl demo123!
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');
$email = $argv[2] ?? 'demo-klant@gymies.nl';
$password = $argv[3] ?? 'demo123!';

require $base . '/vendor/autoload.php';
$app = require $base . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Http;

echo "=== Gymies auth diagnose ===\n";
echo "Email: $email\n\n";

// Basis-URL: app en website gebruiken gymies.nl (zonder www)
$baseHost = 'https://gymies.nl';
$apiBase = $baseHost . '/api/gymies';

// Stap 1: Login (zelfde URL als Flutter-app)
echo "[1] Login via $apiBase/login ...\n";
$loginUrl = $apiBase . '/login';
$loginRes = Http::post($loginUrl, [
    'email' => $email,
    'password' => $password,
]);
$loginBody = $loginRes->json();
$token = $loginBody['token'] ?? null;

if (!$token) {
    echo "    FOUT: Geen token. Response: " . $loginRes->body() . "\n";
    exit(1);
}
echo "    OK: Token ontvangen (" . strlen($token) . " chars)\n\n";

// Stap 2: Token in DB?
echo "[2] Token in database?\n";
$plainToken = str_contains($token, '|') ? substr($token, strpos($token, '|') + 1) : $token;
$hashedToken = hash('sha256', $plainToken);

$foundInGymies = false;
$foundInSanctum = false;
if (Schema::hasTable('gymies_personal_access_tokens')) {
    $row = DB::table('gymies_personal_access_tokens')->where('token', $hashedToken)->first();
    $foundInGymies = $row !== null;
    echo "    gymies_personal_access_tokens: " . ($foundInGymies ? "GEVONDEN (tokenable_id={$row->tokenable_id})" : "NIET GEVONDEN") . "\n";
}
if (Schema::hasTable('personal_access_tokens')) {
    $row = DB::table('personal_access_tokens')->where('token', $hashedToken)->first();
    $foundInSanctum = $row !== null;
    echo "    personal_access_tokens: " . ($foundInSanctum ? "GEVONDEN (tokenable_id={$row->tokenable_id})" : "NIET GEVONDEN") . "\n";
}
if (!$foundInGymies && !$foundInSanctum) {
    echo "    FOUT: Token staat in GEEN van beide tabellen!\n";
    echo "    >>> gymies.nl en deze server gebruiken mogelijk een ANDERE database.\n";
    echo "    >>> Of: gymies.nl wijst naar een ander backend (cdn/static). Probeer www.gymies.nl.\n";
}
echo "\n";

// Stap 2b: Debug-auth (controleer of header aankomt)
echo "[2b] Debug-auth endpoint (ontvangt server de Authorization header?)\n";
$debugRes = Http::withToken($token)->get($apiBase . '/debug-auth');
$debug = $debugRes->json();
$headerReceived = $debug['auth_header_received'] ?? false;
$bearerPrefix = $debug['bearer_prefix'] ?? false;
$queryReceived = $debug['access_token_in_query'] ?? false;
echo "    auth_header_received: " . ($headerReceived ? 'JA' : 'NEE') . "\n";
echo "    bearer_prefix: " . ($bearerPrefix ? 'JA' : 'NEE') . "\n";
echo "    access_token_in_query: " . ($queryReceived ? 'JA' : 'NEE (app stuurt ook ?access_token=... als fallback)') . "\n";
if (!$headerReceived) {
    echo "    >>> WAARSCHUWING: Authorization header komt NIET aan. Nginx/Apache strippen deze. <<<\n";
    echo "    De app stuurt ook access_token in de query – die zou moeten werken.\n";
    echo "    Fix Nginx: bash scripts/patch_nginx_authorization_header.sh\n";
}
echo "\n";

// Stap 3a: HTTP GET /me met Bearer token (zoals de app doet)
echo "[3a] GET /me met Authorization: Bearer ... (zoals de app)\n";
$meUrl = $apiBase . '/me';
$meRes = Http::withToken($token)->get($meUrl);
$meStatus = $meRes->status();
$meBody = $meRes->json();

echo "    Status: $meStatus\n";
echo "    Response: " . substr(json_encode($meBody), 0, 200) . "\n";

if ($meStatus === 401) {
    echo "\n    >>> 401 via header – probeer access_token in query (fallback voor mobiel)\n";
} elseif ($meStatus === 200) {
    echo "\n    OK: /me werkt met header!\n";
}
echo "\n";

// Stap 3b: GET /me met access_token in query (fallback – mobiele carriers strippen soms headers)
echo "[3b] GET /me met ?access_token=... (fallback voor mobiele app)\n";
$meUrlQuery = $apiBase . '/me?access_token=' . urlencode($token);
$meResQuery = Http::get($meUrlQuery);
$meStatusQuery = $meResQuery->status();
$meBodyQuery = $meResQuery->json();
echo "    Status: $meStatusQuery\n";
if ($meStatusQuery === 200) {
    echo "    OK: /me werkt met access_token in query! (app gebruikt deze fallback)\n";
} elseif ($meStatusQuery === 401) {
    echo "    FOUT: Ook access_token in query geeft 401. Token-lookup faalt.\n";
}
echo "\n";

// Stap 4: Test via interne request (bypass webserver - test of middleware werkt)
echo "[4] Interne request (bypass webserver - test of middleware werkt)\n";
$request = \Illuminate\Http\Request::create('/api/gymies/me', 'GET');
$request->headers->set('Authorization', 'Bearer ' . $token);
$request->server->set('HTTP_AUTHORIZATION', 'Bearer ' . $token);
$request->server->set('REDIRECT_HTTP_AUTHORIZATION', 'Bearer ' . $token);

$response = null;
try {
    $kernel = $app->make(\Illuminate\Contracts\Http\Kernel::class);
    $response = $kernel->handle($request);
    $internalStatus = $response->getStatusCode();
    echo "    Status: $internalStatus\n";
    if ($internalStatus === 200) {
        echo "    OK: Middleware + token lookup werken correct.\n";
        if ($meStatus === 401 && $meStatusQuery === 200) {
            echo "    >>> CONCLUSIE: Headers worden gestript, maar access_token in query werkt. App zou moeten werken. <<<\n";
        } elseif ($meStatus === 401) {
            echo "    >>> CONCLUSIE: WEBSERVER strippt headers. Fix: bash scripts/patch_nginx_authorization_header.sh <<<\n";
        }
    } else {
        echo "    Response: " . substr($response->getContent(), 0, 300) . "\n";
    }
    if ($response) {
        $kernel->terminate($request, $response);
    }
} catch (\Throwable $e) {
    echo "    FOUT: " . $e->getMessage() . "\n";
}

echo "\n=== Einde diagnose ===\n";
