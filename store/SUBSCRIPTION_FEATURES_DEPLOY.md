# Subscription Features – Deploy checklist

Gebruik dit bij het uploaden van de subscription features backend naar productie.

---

## 1) Deploy-script draaien

```bash
cd store/backend
chmod +x deploy_subscription_features.sh
./deploy_subscription_features.sh /pad/naar/laravel
```

Of met environment variable:

```bash
export LARAVEL_ROOT=/var/www/gymies  # pas aan
./deploy_subscription_features.sh
```

Het script kopieert:
- `SubscriptionFeaturesAdminTrait.php` → `app/Http/Controllers/Gymies/`
- `SubscriptionEntitlementsTrait.php` → `app/Http/Controllers/Gymies/`
- `2025_03_12_000000_create_gymies_subscription_features_table.php` → `database/migrations/`

---

## 2) Controllers aanpassen (eenmalig)

**GymiesAdminController:**

```php
use App\Http\Controllers\Gymies\SubscriptionFeaturesAdminTrait;

class GymiesAdminController extends Controller
{
    use SubscriptionFeaturesAdminTrait;
    // ...
}
```

**GymiesSubscriptionController:**

```php
use App\Http\Controllers\Gymies\SubscriptionEntitlementsTrait;

class GymiesSubscriptionController extends Controller
{
    use SubscriptionEntitlementsTrait;
    // ...
}
```

---

## 3) Migration draaien (server)

```bash
php artisan migrate
```

Maakt de tabel `gymies_subscription_features` aan en vult deze met standaardfeatures.

---

## 4) Post-deploy (server)

```bash
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
```

---

## 5) Snel testen

1. **Admin:** GET `https://www.gymies.nl/api/gymies/vault-console/subscription-features` (met admin Bearer token) → JSON met `features` en `tiers`.
2. **Trainer:** GET `https://www.gymies.nl/api/gymies/subscription/features` (met trainer Bearer token) → JSON met `tier` en `features`.

---

## Waterdicht maken – extra’s

| Actie | Doel |
|-------|------|
| **Database back-up** | Voor migrate: `mysqldump ... gymies_subscription_features` of volledige DB-back-up |
| **Health-check endpoint** | Voeg toe aan monitoring: `GET subscription/features` moet 200 of 401 geven (geen 500) |
| **Fallback in traits** | Lege tabel? Admin-trait seedt defaults. Entitlements-trait valt terug op hardcoded defaults |
| **Traits in version control** | Zorg dat de traits in je Laravel-repo staan na eerste integratie |
| **Middleware controle** | Admin-routes gebruiken `gymies.admin.capability:admin.users.view` (GET) en `admin.users.manage` (PUT) |
| **Tier-sync met Mollie** | Zorg dat `gymies_trainer_profiles.subscription_plan` (of user-attribuut) in sync blijft met Mollie-abonnementen |

---

## Database-structuur

De migration maakt tabel `gymies_subscription_features` met kolommen: `key`, `label`, `enabled_from`, `type`, `limit_starter`, `limit_pro`, `limit_elite`, `sort_order`. Bij eerste run wordt de tabel gevuld met standaardfeatures uit SUBSCRIPTION_FEATURES.md.
