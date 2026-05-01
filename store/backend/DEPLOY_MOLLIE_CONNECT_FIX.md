# Mollie Connect "State verlopen of ongeldig" – fix

## Probleem
Bij het koppelen van Mollie via de app krijg je na de OAuth-flow:
```json
{"message":"State verlopen of ongeldig. Start Mollie Connect opnieuw vanuit de app (binnen 30 minuten na start). Zorg dat de migratie gymies_mollie_oauth_states is gedraaid als dit blijft gebeuren."}
```

**Oorzaak:** De OAuth `state` wordt niet correct opgeslagen en gevalideerd. Session/cache werkt niet omdat de callback een losse request is (geen sessie). De state moet in de database worden opgeslagen.

## Oplossing

1. **Migratie:** Tabel `gymies_mollie_oauth_states` aanmaken
2. **Trait:** `MollieConnectOAuthTrait` met correcte state-logica
3. **Controller:** `GymiesOnboardingController` moet de trait gebruiken

## Deploy

### Optie A: Via sync_gymies_backend.sh (aanbevolen)

```bash
bash sync_gymies_backend.sh
```

Dit kopieert de trait, migratie, voert de migratie uit, **patched automatisch** de GymiesOnboardingController en controleert de Mollie env.

### Optie B: Handmatig of via deploy_mollie_connect_fix.sh

```bash
cd store/backend
./deploy_mollie_connect_fix.sh
```

### Patch apart uitvoeren

Als alleen de controller nog moet worden aangepast:
```bash
bash patch_onboarding_mollie.sh
```

### Handmatig:
- Kopieer `MollieConnectOAuthTrait.php` naar `app/Http/Controllers/Gymies/`
- Kopieer `2025_03_13_120000_create_gymies_mollie_oauth_states_table.php` naar `database/migrations/`
- Run: `php artisan migrate --force`

### Stap 2: GymiesOnboardingController aanpassen

Open `app/Http/Controllers/Gymies/GymiesOnboardingController.php` en:

1. Voeg de trait toe aan de class:
```php
use App\Http\Controllers\Gymies\MollieConnectOAuthTrait;

class GymiesOnboardingController extends Controller
{
    use MollieConnectOAuthTrait;
```

2. Vervang de methode `startMollieConnect`:
```php
public function startMollieConnect(Request $request): JsonResponse
{
    return $this->mollieConnectStart($request);
}
```

3. Vervang de methode `mollieConnectCallback`:
```php
public function mollieConnectCallback(Request $request): JsonResponse
{
    return $this->mollieConnectCallbackHandle($request);
}
```

### Stap 3: .env

Controleer:
```
MOLLIE_CLIENT_ID=app_xxxxx
MOLLIE_CLIENT_SECRET=xxxxx
APP_URL=https://www.gymies.nl
```

De `redirect_uri` in Mollie’s app-dashboard moet exact zijn:  
`https://www.gymies.nl/api/gymies/onboarding/mollie-connect/callback`

### Stap 4: Mollie merchant-ID opslaan

De trait slaat de organisatie-ID op in `mollie_connect_id` of `mollie_organization_id` als die kolommen bestaan in `gymies_trainer_profiles`. Voeg desnoods een migratie toe:

```php
Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
    $table->string('mollie_connect_id', 64)->nullable();
});
```

## Controleren

1. Start Mollie Connect in de app
2. Autoriseer bij Mollie
3. Callback moet tonen: `{"message":"Mollie gekoppeld! Sluit dit venster en ga terug naar de app.","success":true}`
