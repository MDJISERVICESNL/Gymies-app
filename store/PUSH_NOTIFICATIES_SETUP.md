# GYMIES Push Notificaties – Setup

**Android**: Firebase Cloud Messaging (FCM)  
**iOS**: APNs via FCM (Apple Push via Firebase)

## 1. Firebase-project aanmaken

1. Ga naar [Firebase Console](https://console.firebase.google.com/)
2. Maak een project aan of selecteer bestaand project
3. Voeg een **Android** app toe:
   - Package name: `com.example.gymies_app` (of jouw applicationId)
   - Download `google-services.json` en plaats in `android/app/google-services.json`
4. Voeg een **iOS** app toe:
   - Bundle ID: jouw iOS bundle ID (bijv. `com.example.gymiesApp`)
   - Download `GoogleService-Info.plist` en plaats in `ios/Runner/GoogleService-Info.plist`
5. **iOS**: Upload APNs key in Firebase Console (Project Settings → Cloud Messaging → Apple app config → APNs Authentication Key)

## 2. Backend – FCM Server Key

1. Firebase Console → Project Settings → Cloud Messaging
2. Kopieer de **Server key** (Legacy) of maak een **Service Account** voor HTTP v1 API
3. Zet in Laravel `.env`:
   ```
   FCM_SERVER_KEY=jouw_server_key_hier
   ```

## 3. Database-migratie

```bash
cd store/backend
php artisan migrate
```

Dit maakt de tabel `gymies_device_tokens` aan.

## 4. Push sturen vanuit de backend

Gebruik `FcmPushHelper` wanneer een notificatie moet worden verstuurd:

```php
use App\Http\Controllers\Gymies\FcmPushHelper;

// Bij nieuwe boeking voor trainer
FcmPushHelper::sendToUser(
    $trainerUserId,
    'Nieuwe boeking',
    $clientName . ' heeft een sessie geboekt.',
    ['type' => 'booking', 'booking_id' => $bookingId]
);
```

Integreer dit in de juiste plekken:
- `GymiesBookingController::store` – na succesvolle boeking → push naar trainer
- Berichten, facturen, etc. – zie `APP_PUSH_NOTIFICATIONS_VOORSTEL.md`

## 5. Configuratiebestanden

| Bestand | Locatie | Vanaf |
|---------|---------|-------|
| `google-services.json` | `android/app/` | Firebase Console |
| `GoogleService-Info.plist` | `ios/Runner/` | Firebase Console |

**Let op**: Zonder deze bestanden start de app wel, maar push werkt niet. Firebase init faalt dan stil.
