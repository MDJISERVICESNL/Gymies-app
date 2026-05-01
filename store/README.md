# Store – API & database bundel voor nieuw project

Alles wat je nodig hebt om **een aparte app** (bijv. alleen App Store) te bouwen **tegen dezelfde Gymies-backend**, zonder door de hele monorepo te zoeken.

## Inhoud

| Map / bestand | Doel |
|---------------|------|
| **backend/routes_gymies_full.php** | Volledige Laravel route-definitie (`api/gymies/...`). Enige bron van waarheid voor endpoints. |
| **backend/GymiesPlanManager.php** | SaaS-plan checks (starter / pro / studio) – server-side feature gates. |
| **flutter/api_client.dart** | HTTP-client met Bearer; base URL via `api_config`. |
| **flutter/api_config.dart** | Base URL logica (web vs store). |
| **flutter/app_build.dart** | `GYMIES_APP_CHANNEL` store/web. |
| **flutter/trainer_plan.dart** | Dart-spiegel van plan-features (group sessions, team, packs). |
| **PLANS_AND_FEATURES.md** | Uitleg plannen + limieten. |
| **API_BASE_AND_AUTH.md** | Hoe je de API aanroept. |
| **API_MAP.md** | Volledig overzicht van alle `api/gymies`-endpoints per categorie. |
| **database/MANIFEST.md** | Alle Gymies-SQL-bestanden met paden. |

## Gebruik in een nieuw Flutter-project

1. **Base URL**  
   - Store/mobile: `https://www.gymies.nl/api/gymies`  
   - Of kopieer `api_config.dart` + `app_build.dart` en pas aan.

2. **HTTP**  
   Kopieer `api_client.dart` naar je project en pas de import van `api_config` aan (of zet vaste `baseUrl` in de constructor).

3. **Endpoints**  
   Open `backend/routes_gymies_full.php` – elke `Route::get/post/...` is een pad onder `api/gymies/`.  
   Voorbeeld: `POST api/gymies/login` → `_client.post('/login', ...)`.

4. **Plannen**  
   Lees `PLANS_AND_FEATURES.md` + `trainer_plan.dart` voor UI/feature flags; backend handhaaft via `GymiesPlanManager`.

5. **Database**  
   Niet nodig in de app; wel als je lokaal een DB wilt spiegelen: zie `database/MANIFEST.md` en `create_gymies_tables_if_not_exists.sql` in de hoofd-repo.

## Niet meegekopieerd (bewust)

- **Geen secrets** – geen `.env` met wachtwoorden; alleen voorbeelden.
- **gymies_api.dart** (~2800 regels) – te groot; nieuwe app kan een subset endpoints zelf aanroepen via `ApiClient`.
- **Alle controllers** – blijven in `backend/Controllers/Gymies/`; routes verwijzen ernaar.

## Sync met hoofdproject

Als de API uitbreidt: opnieuw kopiëren of symlinken:

```bash
cp backend/routes_gymies_full.php store/backend/
cp backend/Controllers/Gymies/GymiesPlanManager.php store/backend/
```
