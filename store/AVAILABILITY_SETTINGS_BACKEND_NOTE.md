# Beschikbaarheid-instellingen – Backend implementatie

## Status: Geïmplementeerd

## Database
Migratie `2025_03_17_000000_add_availability_settings_to_gymies_trainer_profiles.php` voegt toe:
- `booking_advance_days` (int, nullable, default 28) – hoeveel dagen van tevoren een sessie geboekt kan worden
- `payment_method` (string, nullable, default 'transfer_and_cash') – betaalmethode

## payment_method waarden
- `transfer_only` – Accepteer alleen overboekingen
- `transfer_and_cash` – Accepteert overboekingen & Cash
- `cash_only` – Accepteert alleen cash

## GymiesAvailabilityController
- `settings()` – GET trainer/availability-settings
- `updateSettings()` – PATCH trainer/availability-settings
- Volledige controller met slots, exceptions, publicAvailability, blockedSlots

## GymiesTrainerController
- `show()` – GET trainers/{id} retourneert `booking_advance_days` en `payment_method`
- `me()` – GET trainer/me
- `updateMe()` – PUT/POST trainer/me

## Migratie uitvoeren
Vanuit de Laravel root: `php artisan migrate`
