# Abonnement factuurdatum – dynamische configuratie

## Overzicht

- **Alle** abonnementswijzigingen (upgrade én downgrade) gaan in bij de **volgende factuurdatum**.
- De factuurdatum is **configureerbaar** via `config/gymies_subscription.php`.

## Configuratie

### Bestand
`config/gymies_subscription.php`

### Environment variabele
```
GYMIES_SUBSCRIPTION_BILLING_DAY=1
```
- Waarde 1–28 (dag van de maand)
- 1 = 1e van de maand
- 15 = 15e van de maand
- Default: 1

### Deployment
Zorg dat `config/gymies_subscription.php` in de hoofd-Laravel-app staat:
```bash
cp store/backend/config/gymies_subscription.php config/
```

Optioneel in `.env`:
```
GYMIES_SUBSCRIPTION_BILLING_DAY=1
```

## Gebruik

- `SubscriptionBillingService::nextBillingDate()` – berekent de volgende factuurdatum (Y-m-d).
- `GET subscription/features` – bevat `next_billing_date` voor de app.
- `POST subscription/change` – wijziging wordt gepland voor `next_billing_date`.
