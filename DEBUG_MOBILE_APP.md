# Mobiele app werkt niet – waar kijken?

De mobiele app (iOS/Android) gebruikt dezelfde backend als web. Gebruik deze checklist om te debuggen.

---

## 1. API-base-URL

| Item | Waar | Check |
|------|------|-------|
| **Bestand** | `lib/services/api_config.dart` | Zoek `gymiesApiBaseUrl` |
| **Default** | `https://gymies.nl` (regel 9) | Moet productie-URL zijn, geen localhost/test |
| **Override** | `--dart-define=GYMIES_API_BASE=https://...` bij build | Bij debug/Release: juiste base? |

**Verificatie:** Start de app en check in de logs (als `kDebugMode`):  
`[api_config] gymiesApiBaseUrl: https://gymies.nl/api/gymies`

---

## 2. Platform-specifiek gedrag

### Android

| Bestand | Check |
|---------|-------|
| `android/app/src/main/AndroidManifest.xml` | Geen `android:usesCleartextTraffic="true"` nodig voor HTTPS-only. Laat uit voor productie. |

Als je tijdelijk HTTP test-URLs wilt toestaan, voeg toe in `<application>`:

```xml
android:usesCleartextTraffic="true"
```

**Niet** aanraden voor productie.

### iOS

| Bestand | Check |
|---------|-------|
| `ios/Runner/Info.plist` | App Transport Security (ATS) staat standaard aan; HTTPS werkt. Voor custom domains: geen wijziging nodig. |

---

## 3. Token-opslag op mobiel

| Item | Waar | Check |
|------|------|-------|
| **Storage** | `lib/services/auth_service.dart` | Gebruikt `SharedPreferences` via `_kTokenKey`, `_kUserKey` |
| **Keys** | `gymies_auth_token`, `gymies_user`, `gymies_api_base_url` | Zelfde keys als web |
| **Geen** | `flutter_secure_storage` | Niet gebruikt in dit project |

Na login wordt token opgeslagen en bij `loadStoredAuth()` geladen. Bij wijziging van API-URL wordt oude token gewist.

---

## 4. Netwerk / debugging

### Flutter DevTools

1. Start de app: `flutter run`
2. Open DevTools → **Network** tab
3. Filter op `api` of `gymies`
4. Controleer:
   - Gaan requests naar `https://gymies.nl/api/gymies/...`?
   - Staat `Authorization: Bearer ...` in de headers? (of `access_token` in query)
   - Of `X-Gymies-Access-Token`?

### Logs in de app

- `api_client.dart`: bij 401 wordt `_on401?.call()` aangeroepen
- `auth_service.dart`: bij login in debug: `[AuthService] Login token ontvangen: ...`
- Voeg tijdelijk toe: `debugPrint('API 401: $path')` in `_handleResponse` bij statusCode 401

### API-URL in runtime controleren

```dart
// In een screen of test:
debugPrint('Base: ${gymiesApiBaseUrl}');
```

---

## 5. Wat doet de app precies?

| Scenario | Waar kijken |
|----------|-------------|
| **Login werkt niet** | 401? → server/token. 301? → redirect-fix in api_client. Timeout? → netwerk. |
| **Login lukt, direct daarna 401** | Token wordt wel opgeslagen? Na login wordt `_persist(token, user)` aangeroepen. Check of `loadStoredAuth` daarna correct is. |
| **Werkt eerst, later fout** | Token expired? API-URL gewijzigd? Token wordt gewist bij wijziging `gymies_api_base_url`. |
| **Alleen op mobiel kapot** | Verschillen in User-Agent? Andere headers? Ander netwerk (WiFi vs mobiel)? |

---

## 6. Mogelijke verschillen mobiel vs web

| Aspect | Opmerking |
|--------|-----------|
| **User-Agent** | App stuurt `GymiesApp/1.0 (Flutter)`. Server kan User-Agent check uitzetten via `GYMIES_SESSION_SKIP_USER_AGENT_CHECK`. |
| **Authorization / X-Gymies-Access-Token** | Zelfde `ApiClient` voor web en mobiel →zelfde headers. |
| **URL** | Staging vs productie: controleer `gymiesApiBaseUrl` en build args. |
| **CORS** | Alleen relevant voor web; mobiel heeft geen CORS. |
| **SSL-pinning** | Niet ingesteld; standaard OS trust. |

---

## Concreet debuggen

1. **Mobiele app starten en inloggen**
   ```bash
   flutter run
   ```

2. **Controleren welke API-URL wordt gebruikt**
   - Zoek in logs: `[api_config] gymiesApiBaseUrl`
   - Of: DevTools → Network → eerste request → URL

3. **Controleren welke endpoints 401 geven**
   - DevTools → Network → filter op failed (4xx)
   - Of: voeg logging toe bij 401 in `api_client.dart`

4. **Controleren of token in request zit**
   - Na login: requests moeten `Authorization: Bearer <token>` of `access_token=<token>` bevatten
   - Token-formaat: `id|plainToken` (64 hex chars na de `|`)

---

## Snelle fixes

| Probleem | Actie |
|----------|-------|
| 301 bij login | `api_client.dart` heeft redirect-handling; zorg dat je de nieuwste versie hebt. |
| 401 na login | Server `gymies.auth` moet wijzen naar `GymiesAuthMiddleware` (gymies_sessions), niet `EnsureGymiesUserFromToken`. |
| Verkeerde API-URL | Build met: `--dart-define=GYMIES_API_BASE=https://gymies.nl` |
| Token wordt niet meegestuurd | Check `_headers()` en `_uri()` in `api_client.dart`; token moet in query en/of headers. |
