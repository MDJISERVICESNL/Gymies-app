# Mollie Connect: Betalingen naar trainer – deploy-instructies

## Overzicht

Betalingen moeten naar het Mollie-account van de **trainer** gaan (via Mollie Connect) in plaats van naar het centrale Gymies-account.

## Wat is toegevoegd (store/backend)

1. **MollieConnectPaymentTrait** – Logica voor payment aanmaken met trainer's OAuth token
2. **Migration** – `gymies_booking_mollie_payments` (koppeling mollie_payment_id ↔ booking_id voor webhook)
3. **GymiesTrainerClientPaymentsController** – Endpoint `GET trainer/clients/{clientUserId}/payments`

## Stap 1: Sync uitvoeren

```bash
bash sync_gymies_backend.sh
```

Dit kopieert:
- `MollieConnectPaymentTrait.php`
- `GymiesTrainerClientPaymentsController.php`
- `2025_03_13_160000_create_gymies_booking_mollie_payments_table.php`

## Stap 2: GymiesPaymentController patchen

De bestaande `GymiesPaymentController` op de server moet worden aangepast:

### 2a. Trait toevoegen

Voeg bovenaan de class (na `namespace` en `use`-statements) toe:

```php
use App\Http\Controllers\Gymies\MollieConnectPaymentTrait;

class GymiesPaymentController extends Controller
{
    use MollieConnectPaymentTrait;
```

### 2b. Methode `startPayment` vervangen

Vervang de body van `startPayment` met onderstaande logica. De methode moet:

1. Boeking ophalen (voor de ingelogde klant)
2. Trainer bepalen uit de boeking
3. Trainer's `mollie_access_token` ophalen uit `gymies_trainer_profiles`
4. Payment aanmaken via `$this->createMolliePaymentForTrainer($booking, $accessToken)`
5. Koppeling opslaan via `$this->storeBookingMolliePayment(...)`
6. Response retourneren met `payment_url`

**Voorbeeldimplementatie** (pas aan op jouw model/tabelnamen):

```php
public function startPayment(Request $request, $id): JsonResponse
{
    $user = $request->user();
    if (!$user) {
        return response()->json(['message' => 'Niet ingelogd.'], 401);
    }

    $booking = $this->getBookingForClient($id, (int) $user->id);
    if (!$booking) {
        return response()->json(['message' => 'Boeking niet gevonden.'], 404);
    }

    $trainerUserId = (int) ($booking['trainer_user_id'] ?? $booking['trainer_id'] ?? 0);
    if ($trainerUserId <= 0) {
        return response()->json(['message' => 'Geen trainer gekoppeld aan deze boeking.'], 422);
    }

    $profile = DB::table('gymies_trainer_profiles')->where('user_id', $trainerUserId)->first();
    $encryptedToken = $profile->mollie_access_token ?? null;
    if (empty($encryptedToken)) {
        return response()->json([
            'message' => 'Deze trainer heeft nog geen Mollie-account gekoppeld. Vraag de trainer om Mollie Connect te doen in de app.',
        ], 422);
    }

    try {
        $accessToken = decrypt($encryptedToken);
    } catch (\Throwable $e) {
        return response()->json(['message' => 'Kon Mollie-token niet laden. Laat de trainer Mollie opnieuw koppelen.'], 500);
    }

    try {
        $result = $this->createMolliePaymentForTrainer($booking, $accessToken);
        $this->storeBookingMolliePayment((string) $id, $result['payment_id'], $trainerUserId);
        return response()->json(['data' => $result]);
    } catch (\InvalidArgumentException $e) {
        return response()->json(['message' => $e->getMessage()], 422);
    } catch (\RuntimeException $e) {
        return response()->json(['message' => $e->getMessage()], 400);
    }
}
```

### 2c. Webhook-handler aanpassen

De `mollieWebhookHandler` moet bij status `paid` de boeking bijwerken. Via de tabel `gymies_booking_mollie_payments` kun je `booking_id` en `trainer_user_id` opzoeken. Haal met de trainer's token de payment op bij Mollie; bij status `paid` update je `paid_at` op de boeking.

## Stap 3: Route controleren

De route `GET trainer/clients/{clientUserId}/payments` moet in `routes_gymies_full.php` staan (regel ~185). Bij een full deploy is die al aanwezig. Als je alleen controllers synct, voeg de route handmatig toe.

## Controle

1. Trainer doet Mollie Connect in de app.
2. Klant start betaling voor sessie bij die trainer.
3. Payment verschijnt in het Mollie-dashboard van de **trainer**, niet in het platform-dashboard.
4. Na betaling: webhook werkt, `paid_at` wordt gezet.
5. Trainer ziet betalingen onder Klanten → [klant] → tab Betalingen.
