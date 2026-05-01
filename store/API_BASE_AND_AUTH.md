# Gymies API – base URL & auth

## Base URL

- **Productie (mobiel / store-build):**  
  `https://www.gymies.nl/api/gymies`  
  Geen trailing slash nodig; client voegt paden als `/login` toe.

- **Web (zelfde origin):**  
  Als de site op `https://www.gymies.nl` draait → API = `https://www.gymies.nl/api/gymies`.

- **Override:**  
  `--dart-define=GYMIES_API_BASE=https://staging.../api/gymies`

Alle paden in `routes_gymies_full.php` zijn **relatief** tegen deze base (bijv. `POST /login` = `POST .../api/gymies/login`).

## Authenticatie

- **Login / register** retourneren `token` (en `user`).
- Daarna elke request:  
  `Authorization: Bearer <token>`
- `ApiClient` in `store/flutter/api_client.dart` zet dit automatisch na `setAuthToken(token)`.

## Publiek vs beveiligd

- **Zonder token:** login, register, forgot-password, trainers index/show, group-sessions index/show, webhooks, crons (vaak met secret), etc. – zie routes-bestand.
- **Met token:** `middleware gymies.auth` – o.a. `me`, `bookings`, `trainer/me`, gym-routes, admin-routes.

## Rate limiting (middleware)

- `gymies.rate.limit:login`
- `gymies.rate.limit:register`
- `gymies.rate.limit:api`

Te veel requests → 429; app moet vriendelijke melding tonen.

## Idempotency

Sommige POSTs zitten in `gymies.idempotency` – dubbele submit voorkomen; bij nieuwe app eventueel eigen idempotency-key header als backend dat verwacht (check controller).
