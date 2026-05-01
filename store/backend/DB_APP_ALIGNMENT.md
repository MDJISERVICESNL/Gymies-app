# Gymies: Database ↔ App termen – overzicht

Dit document beschrijft hoe de kolommen in `gymies_users` en `gymies_personal_access_tokens` overeenkomen met wat de Flutter-app verwacht.

## gymies_users

| DB-kolom (aanbevolen) | Alternatief (fallback) | API-response key | App leest |
|------------------------|------------------------|------------------|-----------|
| `display_name` | `name` | `display_name`, `name` | `display_name` \| `name` \| `first_name` |
| `role` | `user_role` | `role`, `user_role` | `role`, `user_role`, `userType`, `user_type`, etc. |
| `password_hash` | `password` | (niet teruggegeven) | — |
| `email` | — | `email` | `email` |
| `email_verified_at` | — | `email_verified_at` | — |
| `phone` | — | — | — |
| `city` | — | — | — |

### Rolwaarden

- **Klant**: `client`, `klant`
- **Trainer**: `trainer`
- **Admin**: `admin`, `staff` – of `is_admin` / `is_admin_user` op het user-object

### Backend-gedrag

- `GymiesAuthController` leest wachtwoord uit `password_hash` of `password` (welke kolom er ook bestaat).
- `userToResponse()` stuurt zowel `role` als `user_role` (zelfde waarde).
- `userToResponse()` stuurt zowel `display_name` als `name` (zelfde waarde).

---

## gymies_personal_access_tokens

| DB-kolom | Doel |
|----------|------|
| `id` | Token-identificatie; samen met plain token vormt dit `"id\|plainToken"` |
| `tokenable_type` | Meestal `App\Models\User` (voor lookup wordt dit niet gebruikt) |
| `tokenable_id` | Foreign key naar `gymies_users.id` |
| `name` | Token-naam (bijv. `gymies-app`) |
| `token` | SHA256-hash van het plain token (64 karakters) |
| `abilities` | JSON, bijv. `["*"]` |

### Tokenflow

1. **Login**: Backend maakt `plainToken = Str::random(40)`, slaat `hash('sha256', plainToken)` op in `token`.
2. **Response**: App krijgt `id|plainToken` (bijv. `42|abc123...xyz`).
3. **Verificatie**: Middleware haalt `plainToken` uit Bearer of `access_token`, hasht die, en zoekt op `token = hash`.
4. **User lookup**: Via `tokenable_id` wordt de user opgehaald uit `gymies_users`.

De app zelf ziet de database nooit; ze stuurt alleen het token mee. De termen hier zijn voor de backend en database-admins.

---

## Overzicht: wat moet overeenkomen

| Laag | Naam | Waarden / opmerkingen |
|------|------|------------------------|
| DB `gymies_users` | `role` of `user_role` | `client`, `klant`, `trainer`, `admin`, `staff` |
| DB `gymies_users` | `display_name` of `name` | Weergavenaam gebruiker |
| DB `gymies_users` | `password_hash` of `password` | bcrypt-hash |
| API response `user` | `role`, `user_role` | Zelfde waarde als DB |
| API response `user` | `display_name`, `name` | Zelfde waarde als DB |
| App `AuthService` | `role`, `user_role` | Eerste match voor isTrainer / isAdmin |

---

## Controleren op de server

Vanuit de projectroot:

```bash
# Zonder argument: gebruikt backend-map automatisch (scripts/../..)
cd store/backend && php scripts/diagnose_token_tables.php

# Of met expliciet pad (gebruik . voor huidige map)
cd store/backend && php scripts/diagnose_token_tables.php .

# Token testen
php scripts/diagnose_token_tables.php . "42|jouwPlainToken"
```

Als `gymies_users` alleen `password` heeft en geen `password_hash`, werken de reset-scripts niet tenzij ze dynamisch de juiste kolom gebruiken. De controller doet dit al via `passwordColumn()`; de reset-scripts zijn daarop aangepast.
