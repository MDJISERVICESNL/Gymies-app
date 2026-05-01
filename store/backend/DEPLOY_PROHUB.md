# Pro Hub – fix voor "unknown column 'name' in field list"

## Probleem
De Pro Hub gaf MySQL-error 1054: `unknown column 'name' in the 'field list'`.  
De backend gebruikte `name` terwijl de users-tabel `display_name` heeft (gymies_users).

## Oplossing
Nieuwe controller `GymiesProHubController` die veilig `display_name` of `name` gebruikt.

## Deploy

1. **Controller sync** (via `sync_gymies_backend.sh`):
   - `GymiesProHubController.php` wordt automatisch naar de server gekopieerd.

2. **Routes toevoegen** – zorg dat deze routes in de Laravel app staan (bijv. in `routes_gymies_full.php` of waar die wordt geladen):

   ```php
   Route::get('trainer/pro/client-health', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'clientHealth']);
   Route::get('trainer/pro/upsell-suggestions', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'upsellSuggestions']);
   Route::get('trainer/pro/rebook-suggestions', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'rebookSuggestions']);
   ```

3. **Route cache verversen**:
   ```bash
   php artisan route:cache
   ```

Als `routes_gymies_full.php` de bron is en die wordt geïnclude in de Laravel app, dan staan de routes er al in na een sync van dat bestand.
