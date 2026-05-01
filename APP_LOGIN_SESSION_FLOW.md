# App: Login & sessie-flow

Overzicht van hoe de Gymies-app inlogt en de sessie gebruikt. Backend: GymiesAuthMiddleware (gymies_sessions).

---

## 1. API-configuratie

| Bestand | Wat |
|---------|-----|
| `lib/services/api_config.dart` | `gymiesApiBaseUrl` = `https://gymies.nl` (+ `/api/gymies`). Override: `--dart-define=GYMIES_API_BASE=https://...` |
| | `useAuthViaQueryOnly = true` – token alleen via `?access_token=...` (headers kunnen door mobiel gestript worden) |

---

## 2. Login-flow

```
login_register_screen.dart (_LoginTab)
    ↓
AuthService.login(email, password)
    ↓
ApiClient.post('login', {email, password})
    → POST https://gymies.nl/api/gymies/login
    ↓
Response: { token: "...", user: {...} }
    ↓
AuthService._persist(token, user)
    → SharedPreferences: gymies_auth_token, gymies_user, gymies_api_base_url
    → ApiClient.setAuthToken(token)
    ↓
Navigeer naar dashboard
```

**Token-extractie (auth_service.dart:253-254):**
```dart
res['token'] ?? res['access_token'] ?? res['data']?['token'] ?? res['data']?['access_token']
```

**User-extractie (auth_service.dart:255-256):**
```dart
res['user'] ?? res['data']?['user']
```

---

## 3. App-start (opgeslagen sessie laden)

```
main.dart
    ↓
AuthService.loadStoredAuth()
    ↓
SharedPreferences: gymies_auth_token, gymies_api_base_url, gymies_user
    ↓
Als gymies_api_base_url != huidige gymiesApiBaseUrl → wis token (nieuwe URL = opnieuw inloggen)
    ↓
_token = prefs.getString(_kTokenKey)
_api.setAuthToken(_token)
    ↓
loading_screen.dart: als isLoggedIn → navigeer naar dashboard
```

---

## 4. Authenticated requests (sessie-verificatie)

| Bestand | Rol |
|---------|-----|
| `api_client.dart` | `_uri()` voegt `access_token` toe aan query |
| | `_headers()` voegt (als useAuthViaQueryOnly=false) `Authorization` + `X-Gymies-Access-Token` toe |
| | Met useAuthViaQueryOnly=true: alleen query `?access_token=...` |

**Request-URL (voorbeeld GET me):**
```
https://gymies.nl/api/gymies/me?access_token=<token>
```

**Token-sync vóór eerste request (bijv. dashboard_screen.dart:167-169):**
```dart
if (auth.isLoggedIn && auth.token != null && auth.token!.isNotEmpty) {
  apiClient.setAuthToken(auth.token);
}
```

---

## 5. Waar de token vandaan komt

| Moment | Bron |
|--------|------|
| Na login | `AuthService._persist()` → SharedPreferences + `ApiClient.setAuthToken()` |
| Bij app-start | `loadStoredAuth()` → SharedPreferences → `ApiClient.setAuthToken()` |
| Dashboard/screens | `apiClient.setAuthToken(auth.token)` bij init (zodat ApiClient de laatste token heeft) |
| main.dart | `api.setTokenProvider(() => auth.token)` – ApiClient haalt token op van AuthService |

---

## 6. SharedPreferences-keys

| Key | Inhoud |
|-----|--------|
| `gymies_auth_token` | Token string |
| `gymies_api_base_url` | API-base bij opslaan (bv. https://gymies.nl/api/gymies) |
| `gymies_user` | JSON van user-object |
| `gymies_remember_me` | boolean |

---

## 7. Belangrijke endpoints

| Actie | Endpoint | Methode |
|-------|----------|---------|
| Login | `POST /login` | POST |
| Register | `POST /register` | POST |
| Sessie valideren | `GET /me` | GET |
| Profiel updaten | `PUT /me` | PUT |
| Alle andere beveiligde calls | `GET/POST/PUT/...` + `?access_token=...` | – |

---

## 8. Mogelijke oorzaken "Ongeldige sessie" (401)

1. **Token niet correct opgeslagen** – na login faalt `_persist` of SharedPreferences
2. **Token niet naar ApiClient** – `setAuthToken` of `setTokenProvider` niet op tijd
3. **Andere API-URL** – app gebruikt andere base dan waar token geldig is (storedBase vs currentBase)
4. **Query vs headers** – met useAuthViaQueryOnly=true moet server `access_token` uit query accepteren
5. **Token-formaat** – backend (GymiesAuthMiddleware) verwacht ander formaat dan wat login teruggeeft
