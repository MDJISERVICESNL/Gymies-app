# Backend: visible_badges – badge-voorkeuren trainer

De app stuurt en verwacht het veld `visible_badges` voor trainerprofielen. Dit document beschrijft wat de backend moet implementeren.

## Overzicht

Trainers kunnen in de app kiezen welke badges ze op hun publieke profiel tonen. Alleen de **prijs-badge** blijft altijd zichtbaar. Het veld `visible_badges` slaat de gekozen badge-ids op.

## Endpoints

### 1. GET `trainer/me` (trainer-profiel)

**Response** moet `visible_badges` bevatten:

```json
{
  "display_name": "...",
  "specialty": "...",
  "visible_badges": ["verified", "woman2woman", "top_rated"]
}
```

- **Type:** array van strings
- **Als null/afwezig:** app toont alle badges (backward compat)
- **Als lege array `[]`:** app toont alleen de prijs-badge

### 2. PUT/POST `trainer/me` (trainer-profiel bijwerken)

**Request body** kan `visible_badges` bevatten:

```json
{
  "display_name": "...",
  "visible_badges": ["verified", "woman2woman", "top_rated"]
}
```

- **Type:** array van strings
- **Opslaan:** in `gymies_trainer_profiles.visible_badges` (JSON column) of vergelijkbaar

### 3. GET `trainers` (trainers index) en GET `trainers/{id}` (trainer detail)

**Response** per trainer moet `visible_badges` bevatten:

```json
{
  "user_id": "...",
  "display_name": "...",
  "visible_badges": ["verified", "woman2woman"]
}
```

Zodat de app bij het tonen van zoekresultaten en profielpagina de juiste badges kan filteren.

## Badge-ids (referentie)

| id | Betekenis |
|----|-----------|
| `price` | Prijs – altijd getoond, niet configureerbaar |
| `verified` | Geverifieerd |
| `woman2woman` | WOMAN2WOMAN |
| `pro` | Geverifieerd Professional |
| `elite` | Top Partner |
| `top_rated` | Topbeoordeeld |
| `favorite` | Favoriet |
| `fast_responder` | Snelste Responder |
| `diploma` | Gediplomeerd |
| `specialist` | Specialist (categorie) |
| `sessions_100` | 100+ Sessies |
| `own_location` | Eigen Locatie |
| `duo_training` | Duo-Training |
| `intro_offer` | Introductiekorting |
| `new` | Nieuw |
| `popular` | Populair |
| `location` | Locatie (stad) |

## Database

Voorstel: JSON-kolom in `gymies_trainer_profiles`:

```sql
ALTER TABLE gymies_trainer_profiles ADD COLUMN visible_badges JSON DEFAULT NULL;
```

Opslaan als JSON-array: `["verified","woman2woman"]`.
