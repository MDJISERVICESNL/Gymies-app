# Gymies API (Laravel)

Backend voor de Gymies Flutter-app: auth, trainers, boekingen, betalingen, admin, cron.

**Fout "Target class gymies.auth does not exist"?** → Zie **[FIX_GYMIES_AUTH_ERROR.md](FIX_GYMIES_AUTH_ERROR.md)**. Kort: registreer de middleware in `bootstrap/app.php`.

## Deploy naar server

```bash
# Vanaf projectroot
export SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
export SSH_TARGET=gymies

./scripts/upload_backend.sh
```

Dit uploadt Controllers, Middleware, Traits, Http/Requests, Services, Helpers, Events en SQL-bestanden naar `/var/www/gymies`. Na deploy: `php artisan route:clear && php artisan config:clear`.

## Installatie (nieuw Laravel-project)

1. **Middleware** – Kopieer `Middleware/*.php` naar `app/Http/Middleware/`. Registreer in `bootstrap/app.php`:

```php
'gymies.auth' => \App\Http\Middleware\GymiesAuthMiddleware::class,
'gymies.rate.limit' => \App\Http\Middleware\GymiesRateLimitMiddleware::class,
// … zie scripts/fix_gymies_all_middleware.php
```

2. **Routes** – Laad `routes_gymies_full.php` in `routes/web.php` (zie `scripts/fix_gymies_routes.php`).

3. **Controllers, Traits, FormRequests** – Kopieer naar `app/Http/Controllers/Gymies/`, `app/Traits/`, `app/Http/Requests/`.

4. **Database** – Schema: `database/create_gymies_tables.sql`. Migraties: `database/alter_gymies_*.sql` via `gymies_deploy/run_migrate_gymies_sql_server.php`.

5. **CSRF** – Voeg `api/gymies/*` toe aan CSRF-uitzonderingen (zie `scripts/gymies_deploy/fix_gymies_csrf_except.php`).

## Structuur

- `Controllers/` – GymiesAuthController, GymiesBookingController, GymiesAdminController, …
- `Traits/` – GymiesRequireTrainerTrait, GymiesRequireAdminTrait
- `Http/Requests/` – GymiesLoginRequest, GymiesRegisterRequest, GymiesDirectBookingRequest
- `Middleware/` – GymiesAuthMiddleware, GymiesRateLimitMiddleware, …

## Endpoints (selectie)

| Method | Endpoint | Beschrijving |
|--------|----------|--------------|
| POST | /api/gymies/login | Body: email, password → { user, token } |
| POST | /api/gymies/register | Body: email, password, role (klant/trainer) → { user, token } |
| GET | /api/gymies/me | Bearer → { user } |
| GET | /api/gymies/trainers | Bearer, optioneel ?q= → { data: [trainers] } |
| POST | /api/gymies/bookings/direct-book | Bearer, body: trainer_user_id, scheduled_at, amount_cents, … |

Base URL in Flutter: `https://www.gymies.nl/api/gymies` (zie `lib/core/api_config.dart`).
