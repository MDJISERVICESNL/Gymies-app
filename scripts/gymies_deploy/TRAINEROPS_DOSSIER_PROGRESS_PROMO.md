# TrainerOps: dossier + progressie + promocode (concreet)

## Concept (één zin per stuk)

| Onderdeel | Wat het is |
|-----------|------------|
| **Dossier** | Per trainer+klant één dossier: interne notities, medische achtergrond (alleen trainer), langetermijndoelen. |
| **Dossier voor klant open** | Trainer zet `shared_with_client = true` → klant ziet **alleen** `client_facing_summary` + `goals_long_term`. Nooit internal/medical. |
| **Progressie** | Metingen (gewicht, foto-URL, PR, …). `is_private = 1` → alleen trainer; `0` → klant ziet het in **Mijn progressie**. |
| **Promocode** | Trainer maakt **eigen** code (`trainer_user_id`); bij betaling alleen geldig op boekingen van **die** trainer. |

---

## API-contract

### Trainer (ingelogd als trainer)

| Methode | Pad | Beschrijving |
|--------|-----|--------------|
| GET | `/api/gymies/trainer/clients/{clientUserId}/dossier` | Volledig dossier (trainer-only velden). Response o.a. `shared_with_client`, `shared_with_client_at`, `client_facing_summary`. |
| PUT | `/api/gymies/trainer/clients/{clientUserId}/dossier` | Body: `internal_notes`, `medical_background`, `goals_long_term`, `client_facing_summary`, `shared_with_client` (boolean). Bij `true` wordt `shared_with_client_at` op nu gezet; bij `false` weer NULL. |
| GET | `/api/gymies/trainer/clients/{clientUserId}/progress` | Alle progressregels (incl. private). |
| POST | `/api/gymies/trainer/clients/{clientUserId}/progress` | Nieuwe meting: `type`, `value`, `note`, `is_private`. |
| GET/POST/PUT/DELETE | `/api/gymies/trainer/promo-codes` | CRUD eigen codes. |

### Klant (ingelogd als klant)

| Methode | Pad | Query/body | Beschrijving |
|--------|-----|------------|--------------|
| GET | `/api/gymies/me/progress` | `trainer_user_id` | Alleen niet-private progressregels bij die trainer. |
| GET | `/api/gymies/me/shared-dossier` | `trainer_user_id` | Alleen als trainer dossier heeft **geopend**; anders `shared: false` + duidelijke message. |

### Betaling

- `POST .../bookings/{id}/payments/validate-promo` — code moet bij `gymies_promo_codes` horen met `trainer_user_id` = boeking.trainer_user_id (al in PaymentController).

---

## Migraties (volgorde)

1. `alter_gymies_client_dossier.sql` — tabel dossier + session_notes  
2. `alter_gymies_client_dossier_share_with_client.sql` — `shared_with_client_at`, `client_facing_summary`  
3. `alter_gymies_client_progress.sql` — progressietabel  
4. `alter_gymies_promo_codes_trainer.sql` — `trainer_user_id` op promo_codes  

Backend probeert tabellen/kolommen **self-heal** via `GymiesSchemaEnsure` vóór 503 (promo store, dossier put, progress store).

---

## Flutter (kort)

- **Trainer CRM** → dossier scherm: naast interne velden een toggle **“Dossier voor klant open”** + tekstveld **“Samenvatting voor klant”**.  
- **Klant** → profiel of “Mijn trainers”: knop **“Progressie bij [trainer]”** → `GET me/progress?trainer_user_id=`; **“Dossier van [trainer]”** → `GET me/shared-dossier?trainer_user_id=` (alleen inhoud als `shared` true).  
- **Promo** → trainer promocodes scherm blijft; bij checkout klant vult code in → bestaande validate-promo flow.

---

## Veiligheid

- `internal_notes` en `medical_background` worden **nooit** in client-API teruggegeven.  
- Alleen expliciete `shared_with_client_at` + client-facing velden voor de klant.
