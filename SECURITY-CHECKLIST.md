# GYMIES — Security & Deployment Checklist

## Firebase API Key Restrictions

De Firebase API keys in `google-services.json` en `GoogleService-Info.plist` moeten restricted worden in de Firebase Console. Zonder restricties kan iedereen die de keys kent ze misbruiken.

### Android (google-services.json)

1. Ga naar [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Selecteer het Gymies project
3. Klik op de Android API key
4. Onder "Application restrictions" → kies **Android apps**
5. Voeg toe:
   - Package name: `nl.gymies.app` (check `android/app/build.gradle`)
   - SHA-1 fingerprint: `keytool -list -v -keystore ~/.android/debug.keystore` (debug)
   - Voor release: gebruik je upload keystore SHA-1
6. Onder "API restrictions" → kies **Restrict key** en selecteer alleen:
   - Firebase Installations API
   - Firebase Cloud Messaging API
   - Firebase Remote Config API
   - Cloud Firestore API (als gebruikt)
7. Sla op

### iOS (GoogleService-Info.plist)

1. Ga naar [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Selecteer het Gymies project
3. Klik op de iOS API key
4. Onder "Application restrictions" → kies **iOS apps**
5. Voeg toe:
   - Bundle ID: `nl.gymies.app` (check `ios/Runner.xcodeproj`)
6. Onder "API restrictions" → restrict zoals hierboven
7. Sla op

## HMAC Secret Configuratie

### Flutter build (VERPLICHT)

De app crasht in release mode zonder HMAC secret:

```bash
# Android APK
flutter build apk --dart-define=GYMIES_HMAC_SECRET=<jouw-secret>

# Android App Bundle (Play Store)
flutter build appbundle --dart-define=GYMIES_HMAC_SECRET=<jouw-secret>

# iOS
flutter build ios --dart-define=GYMIES_HMAC_SECRET=<jouw-secret>
```

### Laravel backend

Zelfde secret moet in `.env` op de server staan:

```
GYMIES_HMAC_SECRET=<jouw-secret>
```

### Secret genereren

```bash
openssl rand -hex 32
```

Dit genereert een 64-karakter hex string. Gebruik dezelfde waarde in zowel Flutter als Laravel.

## Productie .env Checklist

Zorg dat deze waarden NIET de defaults zijn op je productieserver:

```
GYMIES_HMAC_SECRET=<64-char-hex>          # NIET leeg
GYMIES_CRON_KEY=<32-char-random>          # NIET test-cron-key-lokaal
GYMIES_DEBUG_AUTH=false                    # MOET false zijn
APP_DEBUG=false                           # MOET false zijn
APP_ENV=production                        # MOET production zijn
```

## AWS Server

- SSH key (`Amazonekey.pem`) hoort ALLEEN in `~/.ssh/`, NOOIT in de project directory
- De key is verwijderd uit de project root en staat in `.gitignore`
- Roteer de key als deze ooit in een Git repository is gecommit
