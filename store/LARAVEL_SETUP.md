# Laravel Gymies – Setup & verificatie

Zorg dat de Gymies API correct is verbonden met je Laravel-app.

## Snelle sync (alles in één keer)

```bash
bash sync_gymies_backend.sh
```

Dit uploadt backend, registreert routes, middleware, en voert verificatie uit.

---

## 1. Routes laden

De gymies-routes moeten worden geladen. Voeg **onderaan** `routes/web.php` toe:

```php
// Gymies API (Flutter app)
require __DIR__ . '/routes_gymies_full.php';
```

Of run op de server:
```bash
cd /var/www/gymies && sudo php scripts/register_gymies_routes.php .
```

## 2. Middleware registreren

Op de server:
```bash
cd /var/www/gymies && sudo php scripts/register_gymies_auth_middleware.php .
sudo php scripts/register_gymies_preempt.php .
```

## 3. Nginx – auth headers doorgeven

**Belangrijk:** Zonder dit kan de app niet inloggen (401 na login).

In het `location ~ \.php$` block van je Nginx-config:

```nginx
fastcgi_param HTTP_AUTHORIZATION $http_authorization;
fastcgi_param HTTP_X_AUTHORIZATION $http_x_authorization;
fastcgi_param HTTP_X_GYMIES_TOKEN $http_x_gymies_token;
```

Of run op de server:
```bash
cd /var/www/gymies && sudo bash scripts/patch_nginx_authorization_header.sh
sudo nginx -t && sudo systemctl reload nginx
```

## 4. Verificatie

```bash
# Verbinding check (op server)
cd /var/www/gymies && sudo -u www-data php scripts/verify_gymies_connected.php .

# Volledige diagnose (login → token → /me)
cd /var/www/gymies && sudo -u www-data php scripts/diagnose_auth.php . JOUW_EMAIL JOUW_WACHTWOORD
```

## 5. Handmatige curl-test

```bash
# Login
TOKEN=$(curl -s -X POST "https://www.gymies.nl/api/gymies/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"JOUW_EMAIL","password":"JOUW_WACHTWOORD"}' | jq -r '.token')

# Met header
curl -s -H "Authorization: Bearer $TOKEN" "https://www.gymies.nl/api/gymies/me"

# Met query param (fallback voor mobiel)
curl -s "https://www.gymies.nl/api/gymies/me?access_token=$TOKEN"
```

Beide moeten 200 retourneren.

## 6. Token “kwijt” – mogelijke oorzaken

| Oorzaak | Oplossing |
|---------|-----------|
| Routes niet geladen | Voeg `require routes_gymies_full.php` toe in web.php |
| Middleware niet geregistreerd | Run `register_gymies_auth_middleware.php` en `register_gymies_preempt.php` |
| Headers gestript door Nginx | Voeg fastcgi_param toe (zie boven) – **vaak de oorzaak** |
| Token niet in DB | Login opnieuw – oude tokens werken niet |
| Mobiel netwerk strippt headers | App stuurt ook `access_token` in query – backend ondersteunt dit |

## 7. Debug endpoint

`GET /api/gymies/debug-auth` toont wat de server ontvangt:
- `auth_header_received`: komt Authorization header aan?
- `access_token_in_query`: komt access_token in de URL aan?

Test: `curl "https://www.gymies.nl/api/gymies/debug-auth?access_token=test"`
