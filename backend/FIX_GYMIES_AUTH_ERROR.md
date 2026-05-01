# Fix: Inloggen geeft "Serverfout. Probeer het later opnieuw" (500)

Als inloggen op de site een **serverfout (500)** geeft, ontbreken meestal **middleware-registraties** of middleware-bestanden op de server. De login-route gebruikt o.a. `gymies.rate.limit:login`; als die niet is geregistreerd, krijg je een 500.

Ook: **"Target class gymies.auth does not exist"** – de middleware `gymies.auth` (en andere Gymies-middleware) is niet geregistreerd.

---

## Snelle fix (op de server)

### Stap 1: Alle middleware-bestanden op de server zetten

Zorg dat **alle** Gymies-middleware op de server staan (bijv. via `./scripts/upload_backend.sh`):

- `app/Http/Middleware/GymiesAuthMiddleware.php`
- `app/Http/Middleware/GymiesRateLimitMiddleware.php` ← **nodig voor login**
- `app/Http/Middleware/GymiesApiErrorLoggingMiddleware.php`
- `app/Http/Middleware/GymiesIdempotencyMiddleware.php`
- `app/Http/Middleware/GymiesAdminIpAllowlistMiddleware.php`
- `app/Http/Middleware/GymiesAdminCapabilityMiddleware.php`

Bron: `Gymies/backend/Middleware/` (alle .php behalve `VerifyCsrfToken_gymies_example.php`).

### Stap 2: Middleware-aliases registreren

**Optie A – Alle Gymies-middleware in één keer (aanbevolen)**

1. Na een backend-upload staat op de server: `gymies_deploy/fix_gymies_all_middleware.php`
2. Op de server uitvoeren:
   ```bash
   cd /var/www/gymies.nl/laravel
   php gymies_deploy/fix_gymies_all_middleware.php
   ```
3. Er wordt een backup gemaakt en **alle** Gymies-aliases (gymies.auth, gymies.rate.limit, enz.) worden toegevoegd. Daarna: `php artisan route:clear && php artisan config:clear`

**Optie B – Alleen gymies.auth (minimaal)**

1. Kopieer `Gymies/scripts/fix_gymies_auth.php` naar de Laravel-root op de server.
2. Op de server: `cd /var/www/gymies.nl/laravel && php fix_gymies_auth.php`
3. Voor **login** heb je ook `gymies.rate.limit` nodig – gebruik dan Optie A.

**Optie C – Handmatig (Laravel 11)**

Open `bootstrap/app.php` en voeg binnen de middleware-aliases de regel toe:

```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->alias([
        'auth' => \App\Http\Middleware\Authenticate::class,
        'gymies.auth' => \App\Http\Middleware\GymiesAuthMiddleware::class,   // <-- deze regel
    ]);
})
```

**Optie D – Handmatig (Laravel 10)**

In `app/Http/Kernel.php`, bij `$middlewareAliases` (of `$routeMiddleware`):

```php
'gymies.auth' => \App\Http\Middleware\GymiesAuthMiddleware::class,
```

### Stap 3: (Aanbevolen) Zoekpagina zonder inloggen

Nu de middleware werkt, vereist GET `/api/gymies/trainers` nog steeds een Bearer-token als die route **binnen** `Route::middleware('gymies.auth')->group(...)` staat. Voor de **publieke zoekpagina** moeten gasten trainers kunnen ophalen zonder inloggen.

Pas je routes aan (in `routes/web.php` of `routes/api.php`, waar de Gymies-routes staan):

**Was (alles achter auth):**
```php
Route::prefix('api/gymies')->group(function () {
    Route::post('login', [...]);
    Route::post('register', [...]);
    Route::middleware('gymies.auth')->group(function () {
        Route::get('me', [...]);
        Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'index']);
        Route::get('trainers/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'show']);
        Route::get('bookings', [...]);
        Route::post('bookings', [...]);
    });
});
```

**Wordt (trainers publiek, rest achter auth):**
```php
Route::prefix('api/gymies')->group(function () {
    Route::post('login', [...]);
    Route::post('register', [...]);

    Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'index']);
    Route::get('trainers/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'show']);

    Route::middleware('gymies.auth')->group(function () {
        Route::get('me', [...]);
        Route::get('bookings', [...]);
        Route::post('bookings', [...]);
    });
});
```

### Stap 4: Cache legen

Op de server:
```bash
cd /var/www/gymies.nl/laravel
php artisan route:clear
php artisan config:clear
```

---

## Controleren

- **Middleware geregistreerd:** Geen 500 meer met "Target class gymies.auth does not exist".
- **Zoekpagina zonder login:**  
  `curl -s https://www.gymies.nl/api/gymies/trainers`  
  moet JSON teruggeven (bijv. `{"data":[]}` of een lijst trainers), geen 401 of 500.

Als je nog een 500 ziet, kijk in `storage/logs/laravel.log` op de server voor de exacte foutmelding.
