# Subscription Features – Admin-beheer in Control Tower

> Admins beheren de feature-matrix in de Control Tower. De app haalt deze config op en past gating toe.

---

## Flow

1. **Admin** opent Control Tower → "Abonnement features" → ziet tabel per tier, bewerkt, slaat op.
2. **Backend** slaat de feature-matrix op (DB of config).
3. **Trainer-app** haalt bij laden `subscription/features` of `me/subscription/entitlements` op en past gating toe.
4. **Klant-app** ziet per trainer welke features beschikbaar zijn (via trainer-subscriptionTier + feature-matrix).

---

## API – Admin (vault-console)

### GET `vault-console/subscription-features`

Haalt de feature-matrix op.

**Response:**
```json
{
  "features": [
    {
      "key": "dossier",
      "label": "Dossier opstellen per klant",
      "enabled_from": "pro",
      "type": "boolean"
    },
    {
      "key": "profile_videos",
      "label": "Videos op profiel",
      "enabled_from": "pro",
      "type": "limit",
      "limit_pro": 1,
      "limit_elite": -1
    },
    {
      "key": "max_clients",
      "label": "Aantal actieve klanten",
      "enabled_from": "starter",
      "type": "limit",
      "limit_starter": -1,
      "limit_pro": -1,
      "limit_elite": -1
    }
  ],
  "tiers": ["starter", "pro", "elite"]
}
```

- `enabled_from`: `starter` | `pro` | `elite` – vanaf welke tier de feature beschikbaar is
- `type`: `boolean` (wel/niet) of `limit` (getalslimiet per tier)
- `limit_*`: voor `limit`-type; `-1` = onbeperkt

### PUT `vault-console/subscription-features`

Slaat de feature-matrix op. Body = zelfde structuur als GET-response.

**Capability:** `admin.users.manage` of nieuwe `admin.subscription.manage`

---

## API – Trainer (me)

### GET `subscription/features` of `me/subscription/entitlements`

Retourneert voor de ingelogde trainer welke features actief zijn, gebaseerd op hun tier + feature-matrix.

**Response:**
```json
{
  "tier": "pro",
  "features": {
    "dossier": true,
    "goals": true,
    "profile_videos": 1,
    "profile_stories": 1,
    "client_tags": true,
    "max_clients": -1,
    "advanced_reporting": false,
    "promoted_profile": false
  }
}
```

Of de app kan lokaal berekenen: feature-matrix ophalen (GET `subscription/features-config` publiek of gecachet) + trainer tier → entitlements.

---

## Database / opslag (backend)

Opties:

1. **Tabel** `gymies_subscription_features`: kolommen `key`, `label`, `enabled_from`, `limit_starter`, `limit_pro`, `limit_elite`, `sort_order`
2. **Config-bestand** `config/gymies_subscription_features.json`
3. **Cache** met fallback naar default config in code

---

## Control Tower UI (Flutter)

- Nieuw scherm: **Abonnement features beheren**
- Navigatie: via card op Control Tower-dashboard of overflow-menu
- Tabel: Feature | Starter | Pro | Elite
- Per feature: dropdown of toggle voor `enabled_from`; voor limits: invoervelden
- Knop **Opslaan** → PUT naar backend
- Bij 404/error: toon "Backend nog niet geconfigureerd. Wijzigingen worden lokaal getoond."

---

## Backend implementatie (Laravel)

### Trait-based implementatie (aanbevolen)

De bestanden staan in `store/backend/`. Integreer in je Laravel-app:

**1. GymiesAdminController**

Kopieer `app/Http/Controllers/Gymies/SubscriptionFeaturesAdminTrait.php` naar je Laravel-project en voeg toe:

```php
use App\Http\Controllers\Gymies\SubscriptionFeaturesAdminTrait;

class GymiesAdminController extends Controller
{
    use SubscriptionFeaturesAdminTrait;
    // ...
}
```

**2. GymiesSubscriptionController**

Kopieer `app/Http/Controllers/Gymies/SubscriptionEntitlementsTrait.php` naar je Laravel-project en voeg toe:

```php
use App\Http\Controllers\Gymies\SubscriptionEntitlementsTrait;

class GymiesSubscriptionController extends Controller
{
    use SubscriptionEntitlementsTrait;
    // ...
}
```

**3. Config-bestand**

Kopieer `config/gymies_subscription_features.json` naar `config/` in je Laravel-project.

### Routes

Al gedefinieerd in `routes_gymies_full.php`:
- `GET vault-console/subscription-features` → GymiesAdminController::subscriptionFeatures
- `PUT vault-console/subscription-features` → GymiesAdminController::updateSubscriptionFeatures
- `GET subscription/features` → GymiesSubscriptionController::subscriptionFeatures (entitlements voor trainers)

---

## Fallback

Als backend nog geen `subscription-features` endpoint heeft:
- Control Tower toont de matrix uit `SUBSCRIPTION_FEATURES.md` als read-only.
- App blijft `coachToolsEnabled` (trainer tier) gebruiken voor gating.
- Zodra backend live is: overschakelen naar API-gebaseerde config.
