# Gymies Auth – Stap-voor-stap diagnose

Volg deze stappen om te achterhalen waar de 401 "Ongeldige of verlopen sessie" vandaan komt.

---

## Overzicht van de flow

```
[App] login → token "id|plainToken" → opslaan
[App] GET /me → Authorization: Bearer id|plainToken + X-Gymies-Access-Token: id|plainToken
[Webserver] Nginx/Apache → moet headers doorgeven aan PHP
[PHP] EnsureGymiesUserFromToken → token uit header → hash(sha256, plainToken) → lookup in DB
[DB] gymies_personal_access_tokens of personal_access_tokens → token kolom = hashed
```

---

## Stap 1: Token aanmaak bij login (server)

**Locatie:** `GymiesAuthController::createTokenForUser()`

- Maakt `plainToken = Str::random(40)`
- Slaat op: `hash('sha256', $plainToken)` in kolom `token`
- Retourneert: `"$id|$plainToken"` (bijv. `41|ASGSs...1mcO`)

**Check:** Na login, staat het token in de database?

```bash
cd store/backend
php artisan tinker
# Of: mysql -e "SELECT id, tokenable_id, LEFT(token,16) as token_preview FROM gymies_personal_access_tokens ORDER BY id DESC LIMIT 5;"
```

---

## Stap 2: Wat stuurt de app?

**Locatie:** `api_client.dart` → `_headers()`

De app stuurt:
- `Authorization: Bearer <token>` (token = exact wat server bij login gaf: `id|plainToken`)
- `X-Gymies-Access-Token: <token>`

**Check:** In Flutter debug console na login zie je:
```
[AuthService] Login token ontvangen: XX chars, preview: 41|ASGS...1mcO
```

---

## Stap 3: Ontvangt de server de headers?

**Probleem:** Nginx en Apache strippen vaak de `Authorization` header. PHP krijgt dan geen token.

**Check:** Run het diagnose-script op de server:

```bash
cd store/backend
php scripts/diagnose_auth.php . jouw@email.nl jouwwachtwoord
```

Let op:
- `[2b] auth_header_received: JA` → headers komen aan
- `[2b] auth_header_received: NEE` → **Nginx/Apache strippen de header**

---

## Stap 4: Nginx/Apache configuratie

### Check: load balancer + Nginx location

Voer eerst het check-script uit om te zien of er een load balancer is en waar de auth-headers staan:

```bash
cd /var/www/gymies
sudo bash scripts/check_nginx_and_loadbalancer.sh
```

Dit toont o.a.:
- HAProxy of andere load balancers
- Welke Nginx-configs auth headers hebben
- In welke location-block de PHP-requests terechtkomen

### Nginx

De `Authorization` header moet expliciet worden doorgegeven:

```nginx
location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param HTTP_AUTHORIZATION $http_authorization;
    fastcgi_param HTTP_X_GYMIES_ACCESS_TOKEN $http_x_gymies_access_token;
    # ... rest van config
}
```

**Fix uitvoeren:**
```bash
cd store/backend
sudo bash scripts/patch_nginx_authorization_header.sh
# Of: sudo bash scripts/patch_nginx_authorization_header.sh /etc/nginx/sites-available/gymies
```

Daarna: `sudo nginx -t && sudo systemctl reload nginx`

### Apache

Als je `.htaccess` gebruikt:

```apache
RewriteCond %{HTTP:Authorization} ^(.+)$
RewriteRule .* - [E=HTTP_AUTHORIZATION:%1]
```

**Fix uitvoeren:**
```bash
cd store/backend
php scripts/patch_apache_authorization_header.php
```

---

## Stap 5: Token lookup in database

**Locatie:** `EnsureGymiesUserFromToken::findTokenViaDb()`

- Haalt `plainToken` uit `id|plainToken` (alles na `|`)
- Berekent `hash('sha256', $plainToken)`
- Zoekt in `gymies_personal_access_tokens` en `personal_access_tokens`

**Check:** Handmatig token testen:

```bash
cd store/backend
# Na login, kopieer het token uit de app (SharedPreferences of debug log)
php scripts/debug_token_lookup.php . "41|jouwPlainTokenHier"
```

---

## Stap 6: Debug-auth endpoint (live test)

Test of headers aankomen op de productieserver:

```bash
# 1. Login en haal token op
TOKEN=$(curl -s -X POST https://www.gymies.nl/api/gymies/login \
  -H "Content-Type: application/json" \
  -d '{"email":"jouw@email.nl","password":"jouwwachtwoord"}' \
  | jq -r '.token')

# 2. Test debug-auth met Bearer header
curl -s "https://www.gymies.nl/api/gymies/debug-auth" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Gymies-Access-Token: $TOKEN"

# Verwacht: auth_header_received: true als Nginx goed is geconfigureerd
```

---

## Stap 7: Interne request (bypass webserver)

Het diagnose-script doet ook een interne request (stap 4). Als die **200** geeft maar de echte HTTP-request **401** geeft, dan is de webserver de oorzaak.

---

## Samenvatting: waar kan het misgaan?

| Stap | Mogelijke fout | Oplossing |
|------|----------------|-----------|
| 1 | Token niet in DB na login | Check `createTokenForUser`, migraties |
| 2 | App stuurt verkeerd token | Check `_persist` en `setAuthToken` |
| 3 | Headers komen niet aan | **Meest waarschijnlijk** – Nginx patch |
| 4 | Nginx strippt headers | `patch_nginx_authorization_header.sh` |
| 5 | Hash/lookup faalt | `debug_token_lookup.php` met echt token |
| 6 | Verkeerde tabel/kolom | Check of `gymies_personal_access_tokens` bestaat |

---

## Fallback: access_token in query

De app stuurt nu ook `?access_token=...` mee bij elke request. De server leest dit in `EnsureGymiesUserFromToken::getToken()`. Als Nginx de headers strippen, zou de token via de query moeten werken.
