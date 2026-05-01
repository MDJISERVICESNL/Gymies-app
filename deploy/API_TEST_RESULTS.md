# Gymies API – testresultaten (server)

**Server:** http://148.113.197.164  
**Base:** http://148.113.197.164/api/gymies  

## Geslaagd

| Endpoint | Methode | Verwacht | Resultaat |
|----------|---------|----------|-----------|
| `/trainers` | GET | 200, lijst trainers | **200** – JSON met `data[]` (o.a. id, user_id, display_name, region) |
| `/group-sessions` | GET | 200 | **200** – `{"data":[]}` |
| `/me` (zonder token) | GET | 401 | **401** – `{"message":"Unauthorized"}` |
| `/ops/health` (zonder token) | GET | 401 | **401** – `{"message":"Unauthorized"}` |
| `/trainers/3` (user_id) | GET | 200, detail trainer | **200** – Volledig trainerobject (Anne de Vries) |

## Opmerkingen

1. **Trainer detail:** `GET /trainers/{id}` verwacht **user_id** (niet profile-id). De lijst bij `GET /trainers` bevat beide; gebruik `user_id` voor detail, packages en availability.
2. **POST endpoints (login, forgot-password):** geven **419** (CSRF token mismatch) omdat de Gymies-routes via `web.php` lopen en daarmee de web-middleware (o.a. VerifyCsrfToken) krijgen. Voor een stateless API kun je in Laravel `VerifyCsrfToken` uitzonderen voor `api/*`, of de Gymies-API onder `routes/api.php` met de `api` middlewaregroep registreren zodat er geen CSRF wordt geëist.

## Aanbeveling

- CSRF uitzondering voor `api/*` toevoegen (in `App\Http\Middleware\VerifyCsrfToken` of Laravel 11 equivalent), zodat POST `/api/gymies/login` etc. zonder CSRF-token werken met Bearer-auth.
