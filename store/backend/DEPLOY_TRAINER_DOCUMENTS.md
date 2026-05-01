# Deploy: Trainer documenten in database

## Probleem
Trainer documenten (bedrijfsnaam, KVK, adres, etc.) werden getoond als "opgeslagen" maar werden niet daadwerkelijk in de database opgeslagen. Bij het maken van een factuur ontbraken de gegevens.

## Oplossing
- Nieuw endpoint `trainer/documents` (GET, PUT, PATCH, POST)
- Nieuwe kolommen in `gymies_trainer_profiles` voor factuurgegevens

## Deploy-stappen

1. **Migratie draaien:**
   ```bash
   php artisan migrate
   ```
   Of alleen deze migratie:
   ```bash
   php artisan migrate --path=database/migrations/2025_03_14_000000_add_trainer_document_fields_to_gymies_trainer_profiles.php
   ```

2. **Routes** – De routes staan al in `routes_gymies_full.php`:
   - `GET trainer/documents`
   - `PUT trainer/documents`
   - `PATCH trainer/documents`
   - `POST trainer/documents`

3. **Invoice controller** – Zorg dat de factuur-generatie (bijv. GymiesInvoiceController of waar de PDF wordt gemaakt) de trainer-gegevens leest uit `gymies_trainer_profiles`:
   - `company_name`
   - `kvk_number`
   - `vat_number`
   - `trainer_address_line1`
   - `trainer_postcode`
   - `trainer_city`
   - `trainer_country`

## Flow na deploy
1. Trainer vult documenten in via Documenten-scherm
2. App roept `PUT trainer/documents` aan
3. Gegevens worden opgeslagen in `gymies_trainer_profiles`
4. Bij factuur maken haalt de app `GET trainer/documents` op → documenten zijn beschikbaar
5. Backend gebruikt dezelfde data voor factuur-PDF generatie
