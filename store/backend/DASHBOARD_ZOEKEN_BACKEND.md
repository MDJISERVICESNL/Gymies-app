# Backend uitleg – Klantendashboard zoeken & filters

## Huidige API: GET trainers

**Endpoint:** `GET /api/gymies/trainers`

**Query parameters:**

| Parameter | Type   | Beschrijving |
|-----------|--------|--------------|
| `query`   | string | Zoekterm (naam, email, specialiteit, stad, regio, bio) |
| `lat`     | float  | Breedtegraad klant – voor afstandsberekening (`distance_km`) |
| `lng`     | float  | Lengtegraad klant – voor afstandsberekening (`distance_km`) |

**Response:** `{ "data": [ ... trainers ... ] }`

Elke trainer bevat o.a.: `user_id`, `display_name`, `specialty`, `city`, `region`, `hourly_rate_cents`, `rating`, `distance_km` (als lat/lng gegeven), `lesson_types`, `categories`, `offers_duo_training`, `woman2woman`, `trainer_verified`, etc.

---

## Huidige werking

- **Backend:** Levert alle trainers in één response (geen paginering).
- **App:** Filtert en sorteert client-side op regio, specialiteit, afstand, prijs, rating, lesvorm, woman2woman, etc.
- **Paginering:** Alleen in de app – 20 trainers per pagina, paginanummers 1–5.

---

## Optioneel: server-side paginering

Als er veel trainers zijn (>200), kan server-side paginering helpen:

### Nieuwe parameters

| Parameter   | Type | Default | Beschrijving        |
|-------------|------|---------|---------------------|
| `page`      | int  | 1       | Paginanummer        |
| `per_page`  | int  | 20      | Aantal per pagina   |
| `region`    | string | -     | Filter op stad/regio |
| `specialty` | string | -     | Filter op specialiteit |
| `max_distance_km` | int | - | Max. afstand in km |
| `max_price` | int | - | Max. prijs per sessie (centen) |
| `min_rating` | float | - | Min. rating |
| `lesson_type` | string | - | `duo`, `1-op-1`, `groepsles` |
| `woman2woman` | bool | - | Alleen woman2woman |
| `sort`      | string | `city` | `city`, `price_asc`, `price_desc`, `rating`, `name` |

### Response met paginering

```json
{
  "data": [ ... trainers ... ],
  "meta": {
    "current_page": 1,
    "per_page": 20,
    "total": 47,
    "last_page": 3
  }
}
```

### Implementatie in GymiesTrainerController

1. `$page = max(1, (int) $request->input('page', 1));`
2. `$perPage = min(50, max(10, (int) $request->input('per_page', 20)));`
3. Filters toepassen in de query (region, specialty, etc.).
4. `$query->skip(($page - 1) * $perPage)->take($perPage);`
5. `$total = $query->count();` (voor count, aparte query zonder skip/take).

---

## Geen wijziging nodig voor huidige app

De app doet nu **client-side** filtering en paginering. De bestaande `GET trainers` API blijft werken. Server-side paginering is alleen nodig als:

- Er 500+ trainers zijn
- De initiële load te traag wordt
- Je mobiele data wilt besparen
