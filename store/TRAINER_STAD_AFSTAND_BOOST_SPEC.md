# Trainer-weergave: stad-eerst, afstand, boost

Dit document beschrijft de volledige implementatie van:
1. **Stad-eerst weergave** – trainers uit jouw stad bovenaan
2. **Afstand na stad** – daarna trainers op afstand
3. **Boost** – medewerkers kunnen een trainer in de top 5 van zijn stad zetten

---

## Overzicht

| Onderdeel | Beschrijving |
|-----------|--------------|
| **Klantstad** | Stad van de klant (uit profiel of instellingen) |
| **Trainerstad** | Stad/regio van de trainer (uit trainerprofiel) |
| **Boost** | Trainer krijgt tijdelijk voorrang in top 5 van zijn stad |

---

## 1. Sorteerlogica (frontend)

### Standaard: "Stad & afstand"

De volgorde is:

1. **Trainers uit jouw stad**
   - **Top 5**: Gebooste trainers (max 5), willekeurig geschud
   - **Daarna**: Overige gebooste trainers (als er meer dan 5 zijn), geschud
   - **Daarna**: Niet-gebooste trainers uit jouw stad, geschud

2. **Trainers uit andere steden**
   - Gesorteerd op **afstand** (dichtstbij eerst)

### Geen stad ingesteld

Als de klant geen stad heeft ingesteld: alle trainers worden willekeurig geschud.

### Handmatige sortering

De klant kan nog steeds kiezen voor:
- Naam A–Z
- Prijs oplopend / aflopend
- Beoordeling hoog naar laag

---

## 2. Klantstad

### Waar wordt het opgeslagen?

- **Backend**: `me`-profiel, veld `city` (als de backend dit ondersteunt)
- **App**: SharedPreferences, key `gymies_client_city`

### Hoe wordt het ingesteld?

1. **Profielscherm**: Klant vult "Mijn stad" in (bijv. Rotterdam, Amsterdam) en slaat op.
2. **Sync**: Bij opslaan wordt `city` naar de backend gestuurd (PUT/POST `me`) en lokaal in SharedPreferences opgeslagen.
3. **Dashboard**: Laadt stad uit `getMe()` (als ingelogd) of uit SharedPreferences.

### Backend-aanpassing (optioneel)

Als de backend `me` nog geen `city` ondersteunt:

- Voeg `city` toe aan de users/clients-tabel.
- Bij PUT/POST `me`: accepteer `city` en sla op.
- Bij GET `me`: retourneer `city`.

---

## 3. Trainer-boost

### Doel

Medewerkers kunnen een trainer tijdelijk in de **top 5** van zijn stad zetten, zodat die vaker wordt bekeken.

### Database

**Tabel**: `gymies_trainer_profiles`  
**Kolom**: `boosted_until` (datetime, nullable)

- `NULL` = niet geboost
- Datum in de toekomst = geboost tot dat moment
- Datum in het verleden = boost verlopen

**Migratie**: `2025_03_16_000000_add_boosted_until_to_gymies_trainer_profiles.php`

### Admin-API

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| POST | `vault-console/trainers/{trainerUserId}/boost` | Boost instellen |
| GET | `vault-console/trainers/{trainerUserId}/boost` | Boost-status ophalen |
| DELETE | `vault-console/trainers/{trainerUserId}/boost` | Boost verwijderen |

**POST body** (boost instellen):

```json
{
  "boosted_until": "2025-03-21T23:59:59"
}
```

Ondersteunde formaten: ISO 8601, `Y-m-d H:i:s`, `Y-m-d`.

### Trainers-index: `boosted_until` meegeven

De **GET trainers**-response moet per trainer `boosted_until` bevatten (uit `gymies_trainer_profiles`), zodat de app kan bepalen of een trainer geboost is.

Voorbeeld:

```json
{
  "user_id": "123",
  "display_name": "Jan",
  "city": "Rotterdam",
  "region": "Zuid-Holland",
  "boosted_until": "2025-03-21T23:59:59",
  ...
}
```

---

## 4. Bestandenoverzicht

### Backend

| Bestand | Functie |
|---------|---------|
| `database/migrations/2025_03_16_000000_add_boosted_until_to_gymies_trainer_profiles.php` | Kolom `boosted_until` toevoegen |
| `app/Http/Controllers/Gymies/TrainerBoostAdminController.php` | Admin-endpoints voor boost |
| `routes_gymies_full.php` | Routes voor boost-endpoints |

### Frontend

| Bestand | Functie |
|---------|---------|
| `lib/models/trainer.dart` | `boostedUntil`, `isBoosted` |
| `lib/screens/dashboard_screen.dart` | Stad-eerst sorteerlogica, `_clientCity`, `_applyCityFirstSort()` |
| `lib/screens/client_profile_screen.dart` | Veld "Mijn stad", sync met backend en SharedPreferences |
| `lib/services/gymies_api.dart` | `updateMe(city: ...)` |

---

## 5. Gebruiksflow

### Voor de klant

1. **Stad instellen**: Profiel → "Mijn stad" invullen → Opslaan.
2. **Trainers bekijken**: Dashboard → standaard "Stad & afstand".
3. **Resultaat**: Eerst trainers uit eigen stad (geboost eerst), daarna trainers op afstand.

### Voor de medewerker

1. **Boost zetten**:  
   `POST /api/gymies/vault-console/trainers/{trainerUserId}/boost`  
   Body: `{ "boosted_until": "2025-03-28T23:59:59" }`

2. **Boost verwijderen**:  
   `DELETE /api/gymies/vault-console/trainers/{trainerUserId}/boost`

3. **Boost bekijken**:  
   `GET /api/gymies/vault-console/trainers/{trainerUserId}/boost`

---

## 6. Randgevallen

| Situatie | Gedrag |
|----------|--------|
| Geen stad ingesteld | Alle trainers worden geschud |
| Stad ingesteld, geen trainers in die stad | Alle trainers op afstand |
| Meer dan 5 gebooste trainers in stad | Eerste 5 geboost (geschud), rest bij overige stad-trainers |
| Boost verlopen | Trainer valt terug in normale shuffle |
| Trainer zonder `city`/`region` | Komt niet in "stad-eerst" groep; alleen in afstand-sortering |

---

## 7. Stad-matching

- Vergelijking: **case-insensitive** (na `toLowerCase()`).
- Match op: `trainer.city` of `trainer.region`.
- Voorbeelden: "Rotterdam" matcht "Rotterdam", "rotterdam"; "Den Haag" matcht "den haag".

---

## 8. Samenvatting

1. **Trainers uit jouw stad** → bovenaan (geboost eerst, max 5, rest geschud).
2. **Daarna** → trainers op afstand (dichtstbij eerst).
3. **Boost** → medewerker zet `boosted_until` via admin-API.
4. **Klantstad** → in profiel en/of SharedPreferences; backend `me` kan `city` ondersteunen.
