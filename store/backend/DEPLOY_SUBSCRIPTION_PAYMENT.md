# Abonnement-betaling via Mollie – deploy-instructies

## Overzicht

Trainers kunnen hun abonnement (Starter/Pro/Elite) betalen via Mollie. Na plankeuze opent de app de Mollie checkout; na betaling wordt het plan geactiveerd via webhook.

## Wat is toegevoegd (store/backend)

1. **SubscriptionPaymentTrait** – `startSubscriptionPayment()` – maakt Mollie payment aan met platform API key; haalt prijzen uit `gymies_plans`
2. **SubscriptionWebhookTrait** – `handleSubscriptionWebhook()` – verwerkt Mollie webhook, zet subscription_plan
3. **AvailablePlansTrait** – `availablePlansResponse()` – haalt plannen uit `gymies_plans` voor GET plans
4. **StartSubscriptionPaymentController** – POST subscription/start-payment
5. **Migration** – `gymies_subscription_payments` (mollie_payment_id ↔ user_id, tier)
6. **Migration** – `gymies_plans` (slug, name, amount_cents, price_label) – prijzen dynamisch uit database

## Stap 1: Sync naar Laravel

Kopieer de bestanden naar je Laravel-app:

```bash
# Vanuit project root
LARAVEL=pad/naar/laravel  # of waar je Gymies backend staat

cp store/backend/app/Http/Controllers/Gymies/SubscriptionPaymentTrait.php $LARAVEL/app/Http/Controllers/Gymies/
cp store/backend/app/Http/Controllers/Gymies/SubscriptionWebhookTrait.php $LARAVEL/app/Http/Controllers/Gymies/
cp store/backend/app/Http/Controllers/Gymies/StartSubscriptionPaymentController.php $LARAVEL/app/Http/Controllers/Gymies/
cp store/backend/database/migrations/2025_03_17_000000_create_gymies_subscription_payments_table.php $LARAVEL/database/migrations/
cp store/backend/database/migrations/2025_03_17_100000_create_gymies_plans_table.php $LARAVEL/database/migrations/
cp store/backend/app/Http/Controllers/Gymies/AvailablePlansTrait.php $LARAVEL/app/Http/Controllers/Gymies/
```

Voeg de route toe in je Gymies routes (na subscription/change):

```php
Route::post('subscription/start-payment', \App\Http\Controllers\Gymies\StartSubscriptionPaymentController::class)->name('subscription.start-payment');
```

## Stap 2: GymiesSubscriptionController patchen

Voeg de traits toe en pas de methodes aan:

```php
use App\Http\Controllers\Gymies\SubscriptionWebhookTrait;
use App\Http\Controllers\Gymies\AvailablePlansTrait;

class GymiesSubscriptionController extends Controller
{
    use SubscriptionWebhookTrait;
    use AvailablePlansTrait;

    public function subscriptionWebhook(Request $request): Response
    {
        return $this->handleSubscriptionWebhook($request);
    }

    public function availablePlans(Request $request): JsonResponse
    {
        return $this->availablePlansResponse();
    }
}
```

## Stap 3: Migratie draaien

```bash
php artisan migrate
```

## Stap 4: Mollie API key

Zorg dat `MOLLIE_API_KEY` (of `config('services.mollie.key')`) is geconfigureerd met je **platform** Mollie API key (live of test). Dit is NIET de Mollie Connect client ID – het is de API key van het Gymies Mollie-account.

## Webhook-URL

Mollie roept aan: `https://www.gymies.nl/api/gymies/webhooks/mollie-subscription`

De webhook wordt getriggerd door de payment metadata (`type: subscription`); de lookup gebeurt via `gymies_subscription_payments`.

## gymies_plans – prijzen aanpassen

De tabel `gymies_plans` bevat de prijzen per tier:

| Kolom | Type | Beschrijving |
|-------|------|--------------|
| id | bigint | Primary key |
| slug | string | starter, pro, elite |
| name | string | Weergavenaam |
| amount_cents | int | Prijs in centen (2995 = €29,95) |
| price_label | string | Optioneel, bijv. "€29,95/mnd" |
| sort_order | int | Volgorde |

Prijzen wijzigen via SQL of admin:

```sql
UPDATE gymies_plans SET amount_cents = 3495, price_label = '€34,95/mnd' WHERE slug = 'starter';
```

De app haalt plannen op via GET `plans` en toont de prijzen dynamisch. De betaling gebruikt `amount_cents` uit de database.

## Flow

1. App: POST subscription/start-payment { tier: "pro" }
2. Backend: Maakt Mollie payment, slaat op in gymies_subscription_payments, retourneert payment_url
3. App: Opent payment_url in browser
4. Gebruiker: Betaalt bij Mollie
5. Mollie: Redirect naar gymies://subscription/complete?tier=pro + webhook naar backend
6. Backend webhook: Bij status paid → update gymies_trainer_profiles.subscription_plan
7. App: Toont success, entitlements worden herladen
