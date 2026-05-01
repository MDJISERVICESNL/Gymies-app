# Auth-fouten: "Niet ingelogd" / "Unauthorized" / "Personal access token doesn't exist"

## Samenvatting: wat we hebben gecontroleerd en gefixt

| Onderdeel | Fix |
|-----------|-----|
| **Server-middleware** | `gymies.auth` moet wijzen naar **GymiesAuthMiddleware** (gymies_sessions), niet naar EnsureGymiesUserFromToken (Sanctum/personal_access_tokens). Check `bootstrap/app.php` → `'gymies.auth' => \App\Http\Middleware\GymiesAuthMiddleware::class`. |
| **User-Agent** | `GYMIES_SESSION_SKIP_USER_AGENT_CHECK=true` in `.env` – Flutter web kan een andere User-Agent sturen dan bij login, waardoor sessievalidatie faalt. |
| **Nginx** | `fastcgi_param HTTP_AUTHORIZATION $http_authorization` en `HTTP_X_GYMIES_ACCESS_TOKEN` – headers worden goed doorgegeven (debug-auth test). |
| **Token in DB** | Login slaat tokens op in `gymies_sessions` (64-hex). Debug: `curl ".../debug-token-check?access_token=TOKEN"` → `found_in_gymies_sessions: true`. |
| **Refresh = uitloggen** | Geen redirect naar login terwijl `loadStoredAuth` nog loopt (zie Flutter: `AuthService.loadingStored`). |

### GymiesAuthMiddleware – token-bronnen (in volgorde)

1. `?access_token=<token>` (query) – fallback als Nginx headers strippen  
2. `Authorization: Bearer <token>` (via `$request->bearerToken()`)  
3. `X-Authorization: Bearer <token>`  
4. `X-Gymies-Token: <token>`

**Bron:** `gymies_sessions.token` (64 hex). **Aanmaken:** bij login in `GymiesAuthController::createTokenForUser()`.  
**Flow:** Client stuurt token → middleware normaliseert (64 hex) → lookup in `gymies_sessions` → `gymies_user` op request gezet.

### Env-variabelen (server)

| Variabele | Beschrijving |
|-----------|---------------|
| `GYMIES_SESSION_SKIP_USER_AGENT_CHECK=true` | Zet uit: validatie dat request User-Agent overeenkomt met sessie. Handig voor Flutter web, waar de User-Agent bij refresh/navigatie kan verschillen van bij login. |

---

## Problemen

1. **"Niet ingelogd"** – ingelogde trainer/klant ziet dit op beveiligde schermen.
2. **"Unauthorized"** – na inloggen krijgt de app 401 op beveiligde endpoints.
3. **"gymies personal access token doesn't exist"** – Sanctum faalt omdat users in `gymies_users` staan i.p.v. `users`.

## Oorzaak (historisch)

- Sanctum's tokenable-lookup gebruikt het User model → `users` tabel.
- Gymies gebruikt nu **gymies_sessions** (64-hex token) en **GymiesAuthMiddleware**. Zorg dat `gymies.auth` naar GymiesAuthMiddleware wijst.

## Oplossing (actueel)

### gymies.auth → GymiesAuthMiddleware (verplicht)

De beveiligde gymies-routes gebruiken `gymies.auth`, die moet wijzen naar **GymiesAuthMiddleware** (zoekt in `gymies_sessions`). Niet naar EnsureGymiesUserFromToken (die kijkt naar Sanctum-tabellen).

**Registreer op de server:**

```bash
cd /var/www/gymies
php store/backend/scripts/register_gymies_auth_middleware.php .
```

Of handmatig in `bootstrap/app.php`:

```php
'gymies.auth' => \App\Http\Middleware\GymiesAuthMiddleware::class,
'gymies.auth.preempt' => \App\Http\Middleware\EnsureGymiesAuthPreempt::class,
```

### Alternatief (legacy): EnsureGymiesUserFromToken

Zorg dat het User model (of het model dat Sanctum gebruikt) de `gymies_users` tabel gebruikt:

```php
// app/Models/User.php
protected $table = 'gymies_users';
```

### Optie 3: Custom guard

Maak een guard die `gymies_users` gebruikt en gebruik die voor de gymies routes.

## Fix: "Unauthorized" na inloggen

1. **Authorization header** – Apache/PHP-FPM strippen soms de header. Voer uit:
   ```bash
   php scripts/patch_apache_authorization_header.php .
   ```
   Of voeg handmatig toe aan `public/.htaccess`:
   ```
   RewriteCond %{HTTP:Authorization} ^(.+)$
   RewriteRule .* - [E=HTTP_AUTHORIZATION:%1]
   ```

2. **EnsureGymiesAuthPreempt** – De preempt-middleware draait vóór auth:sanctum en zet de user. Voorkomt "Unauthorized". **Verplicht uitvoeren na deploy:**
   ```bash
   cd /var/www/gymies  # of jouw Laravel root
   php store/backend/scripts/register_gymies_preempt.php .
   ```

3. **Gymies auth middleware** – Registreer de gymies.auth en gymies.auth.preempt aliassen:
   ```bash
   php store/backend/scripts/register_gymies_auth_middleware.php .
   ```

4. **gymies_personal_access_tokens** – Zorg dat de migratie is uitgevoerd:
   ```bash
   php artisan migrate
   ```
   Bij `gymies_users` worden tokens nu in `gymies_personal_access_tokens` opgeslagen (geen Sanctum/FK-conflict).

5. **Routes zonder auth:sanctum** – Zorg dat `routes_gymies_full.php` wordt geladen zonder `auth:sanctum` op de parent. De beveiligde groep gebruikt `withoutMiddleware('auth:sanctum')` en `gymies.auth` voor token-validatie.

6. **Nginx** – Voeg toe aan de `location` block:
   ```
   fastcgi_param HTTP_AUTHORIZATION $http_authorization;
   ```

## Fix: "Unauthorized" voor specifieke gebruiker

1. **Uitloggen en opnieuw inloggen** – Een oud token (van vóór de GymiesAuthController) werkt niet. De gebruiker moet in de app volledig uitloggen en opnieuw inloggen.

2. **Debug op server** – Controleer of de gebruiker bestaat en maak eventueel een nieuw token:
   ```bash
   ssh gymies "cd /var/www/gymies && sudo -u www-data php scripts/debug_user_auth.php . jamai1210@live.nl --create-token"
   ```
   Dit toont of de user in gymies_users staat en maakt een nieuw token aan. De gebruiker moet daarna opnieuw inloggen in de app (of het gegenereerde token handmatig testen).

3. **Token-lookup testen** – Als je het token hebt dat de app stuurt:
   ```bash
   ssh gymies "cd /var/www/gymies && sudo -u www-data php scripts/debug_token_lookup.php . 'TOKEN_HIER'"
   ```

## Debug: 401 "Unauthorized" na login (trainer/summary, bookings)

De app logt "Login geslaagd" maar krijgt direct daarna 401 op beveiligde endpoints. Het bericht is "Unauthorized" (niet "Niet ingelogd" of "Ongeldige of verlopen sessie") – dat wijst op Laravel/Sanctum, niet op onze GymiesAuthMiddleware.

### Stap 1: Token in DB?

Na inloggen: noteer het token uit de app-logs (bijv. `d8d55504...be6e`). Test dan:

```bash
# Vervang TOKEN door het volledige 64-hex token
curl -s "https://www.gymies.nl/api/gymies/debug-token-check?access_token=TOKEN"
```

- `found_in_gymies_sessions: true` → token staat in DB; middleware zou moeten werken
- `found_in_gymies_sessions: false` → token niet gevonden; check of login correct in `gymies_sessions` insert

### Stap 2: Ontvangt de server het token?

```bash
curl -s "https://www.gymies.nl/api/gymies/debug-auth?access_token=TOKEN"
```

- `access_token_in_query: true` → query-param bereikt de server
- `auth_header_received: false` maar query OK → Nginx strippt headers; `access_token` in query is de fallback (moet werken)

### Stap 3: Serverconfiguratie

1. **Waar worden gymies-routes geladen?**  
   `grep -n "routes_gymies_full\|gymies_deploy" /var/www/gymies/routes/web.php /var/www/gymies/routes/api.php`
   - Als alleen in **web.php**: web-middleware, geen Sanctum
   - Als in **api.php**: voer `php scripts/register_gymies_preempt.php .` uit zodat preempt vóór Sanctum draait

2. **Nginx Authorization-header:**
   ```bash
   bash patch_nginx_authorization_header.sh
   # Of lokaal: ./patch_nginx_authorization_header.sh (via sync script)
   ```

3. **Logs:** `tail -50 /var/www/gymies/storage/logs/laravel.log`  
   - Geen `[GymiesAuth 401]` = onze middleware retourneert niet de 401; iets anders (bijv. Sanctum) doet dat

### Stap 4: Sessie in DB controleren

```bash
ssh gymies "cd /var/www/gymies && php -r \"
require 'vendor/autoload.php';
\\\$app = require 'bootstrap/app.php';
\\\$app->make('Illuminate\Contracts\Console\Kernel')->bootstrap();
\\\$r = DB::table('gymies_sessions')->where('token','like','d8d55504%')->first();
echo \\\$r ? json_encode(\\\$r) : 'not found';
\""
```

(vervang `d8d55504` door de eerste 8 tekens van je token)

## Debug: 401 "Unauthorized" na succesvolle login (64-hex sessietoken)

**Kenmerk:** Login geeft 200 + token, maar `trainer/summary` / `bookings` geven 401 met `message: "Unauthorized"`. Geen `[GymiesAuth 401]` in Laravel-logs.

**"Unauthorized"** komt van Laravel’s standaard auth-handler (Sanctum/ Authenticate), niet van onze GymiesAuthMiddleware (die "Niet ingelogd" of "Ongeldige of verlopen sessie" stuurt). De 401 ontstaat dus vóór onze middleware of door andere auth-middleware.

### Diagnostiek

1. **Token in DB controleren (direct na login):**
   ```bash
   # Vervang TOKEN door het 64-hex token uit de app (Xcode/logs na login)
   curl -s "https://www.gymies.nl/api/gymies/debug-token-check?access_token=TOKEN"
   ```
   - `found_in_gymies_sessions: true` → token staat in DB; probleem is middleware/routing.
   - `found_in_gymies_sessions: false` → token niet opgeslagen; controleer `GymiesAuthController::createTokenForUser`.

2. **Headers op server controleren:**
   ```bash
   curl -s "https://www.gymies.nl/api/gymies/debug-auth?access_token=TOKEN"
   ```
   - `access_token_in_query: true` → token komt aan via query (Nginx kan headers strippen).
   - `auth_header_received: false` + `access_token_in_query: true` → Nginx strippen van Authorization; query werkt nog.

3. **Nginx: Authorization-header doorgeven**
   ```bash
   # Run patch_nginx_authorization_header.sh op de server
   bash patch_nginx_authorization_header.sh
   ```

4. **Waar worden gymies-routes geladen?**
   - Als routes via **api.php** geladen worden → run `register_gymies_preempt.php` zodat EnsureGymiesAuthPreempt vóór auth:sanctum draait.
   - Als via **web.php** → `withoutMiddleware('auth:sanctum')` zou moeten volstaan; controleer of geen globale auth op de parent zit.

5. **Preempt en middleware registreren (na deploy):**
   ```bash
   cd /var/www/gymies
   php store/backend/scripts/register_gymies_preempt.php .
   php store/backend/scripts/register_gymies_auth_middleware.php .
   ```

### Waarschijnlijke oorzaken

| Oorzaak | Oplossing |
|--------|-----------|
| Nginx strippen van Authorization | `patch_nginx_authorization_header.sh` draaien |
| auth:sanctum draait vóór onze preempt | Preempt aan api-middleware toevoegen via `register_gymies_preempt.php` |
| Routes via api.php zonder preempt | Preempt-script uitvoeren |
| Token niet in gymies_sessions | Controleer `createTokenForUser`; migratie `gymies_sessions` uitgevoerd? |

## Debug: 401 "Unauthorized" na login (64-hex token, gymies_sessions)

Login slaagt, maar `trainer/summary`, `bookings` en andere beveiligde endpoints geven 401 "Unauthorized". De melding "Unauthorized" komt van Laravel's auth/Sanctum, níet van onze GymiesAuthMiddleware (die "Niet ingelogd" of "Ongeldige of verlopen sessie" retourneert).

### Diagnose-stappen

1. **Token in DB?** Na login, haal het token uit de app-logs (bv. `token preview: d8d55504...be6e`) en test:
   ```bash
   curl -s "https://www.gymies.nl/api/gymies/debug-token-check?access_token=VOLLEDIG_TOKEN"
   ```
   Controleer: `found_in_gymies_sessions: true` → token staat in DB. `false` → sessie niet opgeslagen.

2. **Headers/query bij server?** Test of de server het token ontvangt:
   ```bash
   curl -s "https://www.gymies.nl/api/gymies/debug-auth?access_token=TOKEN"
   ```
   Verwacht: `access_token_in_query: true`, `token_length: 64`.

3. **Nginx Authorization-header** – Als Nginx de header strippen, werkt alleen de query. Voer uit:
   ```bash
   bash patch_nginx_authorization_header.sh
   ```
   Of handmatig in de Nginx `location ~ \.php$` block:
   ```
   fastcgi_param HTTP_AUTHORIZATION $http_authorization;
   fastcgi_param HTTP_X_GYMIES_ACCESS_TOKEN $http_x_gymies_access_token;
   ```
   Daarna: `sudo nginx -t && sudo systemctl reload nginx`.

4. **Preempt voor api-routes** – Als gymies routes via `api.php` worden geladen, draait de api middleware group. Voer uit op de server:
   ```bash
   cd /var/www/gymies && php scripts/register_gymies_preempt.php .
   ```
   Dit voegt `EnsureGymiesAuthPreempt` toe aan het begin van de api-group, vóór auth:sanctum.

5. **Waar worden gymies-routes geladen?** Controleer:
   ```bash
   grep -n "routes_gymies_full\|gymies_deploy" /var/www/gymies/routes/web.php /var/www/gymies/routes/api.php 2>/dev/null
   ```
   Moeten vanuit `web.php` geladen worden (geen auth:sanctum op parent). De beveiligde groep gebruikt `withoutMiddleware('auth:sanctum')`.

6. **Serverlogs** – Als onze middleware de 401 retourneert, staat er `[GymiesAuth 401]` in `storage/logs/laravel.log`. Geen entries → 401 komt vóór onze middleware (waarschijnlijk Sanctum).

## Diagnose: 401 "Unauthorized" na geslaagde login (64-hex sessietoken)

Login slaagt, token wordt opgeslagen, maar `trainer/summary`, `bookings` etc. geven 401. Bericht: "Unauthorized" (niet "Niet ingelogd" – dat komt van onze middleware).

### Stap 1: Token-check (publieke endpoint)

Na inloggen, haal het token uit de app-logs (preview: `d8d55504...be6e`). Test:

```bash
# Vervang TOKEN door het volledige 64-hex token
curl -s "https://www.gymies.nl/api/gymies/debug-token-check?access_token=TOKEN"
```

Interpreteer:
- `found_in_gymies_sessions: true` → Token staat in DB; middleware zou moeten werken.
- `found_in_gymies_sessions: false` → Token niet gevonden; check of login daadwerkelijk in `gymies_sessions` schrijft.
- `token_received: false` → Server krijgt token niet (Nginx/proxy strippen headers of query).

### Stap 2: Headers/query ontvangen

```bash
curl -s "https://www.gymies.nl/api/gymies/debug-auth?access_token=TOKEN"
```

Controleer `access_token_in_query` en `auth_header_received`. Als beide false: Nginx strippen headers; voer `patch_nginx_authorization_header.sh` uit.

### Stap 3: Serverconfiguratie

1. **Routes** – Waar worden gymies-routes geladen?
   ```bash
   ssh gymies "grep -l 'routes_gymies_full' /var/www/gymies/routes/*.php"
   ```
   - In `web.php` → geen `auth:sanctum` op parent.
   - In `api.php` → voer `register_gymies_preempt.php` uit.

2. **Nginx** – Authorization-header doorgeven:
   ```bash
   bash patch_nginx_authorization_header.sh
   ```

3. **Laravel-logs** – Zoek naar `[GymiesAuth 401]`:
   ```bash
   ssh gymies "grep 'GymiesAuth 401' /var/www/gymies/storage/logs/laravel.log | tail -20"
   ```
   - Geen entries → 401 komt van vóór onze middleware (bv. `auth:sanctum`).
   - Wel entries → Onze middleware vindt token niet; check DB-lookup en `expires_at`/`revoked_at`.

### Stap 4: Tijdelijke workaround

Als headers worden gestript: zet `useAuthViaQueryOnly = true` in `lib/services/api_config.dart`. De token gaat dan alleen via query (`?access_token=...`), die meestal wél doorkomt.

## Debug: "Ongeldige of verlopen sessie" na login

Als je direct na inloggen deze fout ziet, draai op de server:

```bash
cd /var/www/gymies
# Vervang TOKEN door het token dat de app stuurt (uit logs of na login)
php scripts/debug_token_lookup.php . "TOKEN"
```

Dit toont of de token in personal_access_tokens staat en of de lookup werkt.

## Diagnose: 401 "Unauthorized" na succesvolle login (64-hex token)

**Situatie:** Login 200 OK, token 64 hex, maar `trainer/summary` / `bookings` geven 401 "Unauthorized". Geen `[GymiesAuth 401]` in Laravel-logs.

**Belangrijk:** "Unauthorized" (Engels) komt van Laravel's standaard auth (Sanctum/Authenticate), niet van onze middleware (die "Niet ingelogd" of "Ongeldige of verlopen sessie" retourneert).

### Stap 1: Token in DB checken

Na login: haal het token uit de app-logs (bijv. `d8d55504...be6e`) en test:

```bash
curl -s "https://www.gymies.nl/api/gymies/debug-token-check?access_token=JOUW_TOKEN"
```

Controleer:
- `found_in_gymies_sessions`: true → token staat in DB, middleware-lookup zou moeten werken
- `found_in_gymies_sessions`: false → token niet opgeslagen bij login, check `GymiesAuthController::createTokenForUser`

### Stap 2: Bereikt de server het token?

```bash
curl -s "https://www.gymies.nl/api/gymies/debug-auth?access_token=JOUW_TOKEN"
```

- `access_token_in_query`: true → query param bereikt PHP
- `auth_header_received`: false + Nginx → voer `patch_nginx_authorization_header.sh` uit

### Stap 3: Serverconfiguratie

1. **Nginx Authorization header** (als headers gestript worden):
   ```bash
   bash patch_nginx_authorization_header.sh
   ```

2. **Preempt in api-middleware** (als gymies via api.php geladen wordt):
   ```bash
   cd /var/www/gymies && php store/backend/scripts/register_gymies_preempt.php .
   ```

3. **Routes-bron:** Controleer of gymies via web.php wordt geladen (geen auth:sanctum):
   ```bash
   grep -n "routes_gymies_full\|gymies_deploy" /var/www/gymies/routes/web.php /var/www/gymies/routes/api.php
   ```

4. **Laravel-logs:**
   ```bash
   tail -100 /var/www/gymies/storage/logs/laravel.log
   ```
   Zoek naar `[GymiesAuth 401]` – als die er zijn, komt de 401 van onze middleware (token niet gevonden).

## Verificatie

Na de fix zou een ingelogde trainer op alle beveiligde schermen moeten kunnen zonder "Niet ingelogd" te zien.

## Sync script

Het sync script (`sync_gymies_backend.sh`) kopieert momenteel geen middleware. Voeg handmatig toe of pas het script aan om `app/Http/Middleware/EnsureGymiesUserFromToken.php` te syncen.
