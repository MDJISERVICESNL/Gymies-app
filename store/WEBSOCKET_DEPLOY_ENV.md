# Gymies WebSocket deploy checklist

Gebruik dit om de websocket verbinding voor notificaties/chat in productie te herstellen.

## 1) App build defines (Flutter)

Zet bij je release/build expliciet:

- `GYMIES_API_BASE=https://www.gymies.nl/api/gymies`
- `GYMIES_WS_BASE=wss://www.gymies.nl`
- `GYMIES_WS_NOTIFICATIONS_URL=wss://www.gymies.nl/ws/notifications?token={token}&role={role}`
- `GYMIES_WS_CHAT_URL=wss://www.gymies.nl/ws/conversations/{conversationId}?token={token}`

Belangrijk:

- Gebruik **geen** `:0` poort.
- Gebruik **geen** `https://.../api/gymies` als websocket endpoint.
- Websocket URL moet `ws://` of `wss://` zijn.

## 2) Laravel/Reverb .env (server)

Minimaal (voorbeeld):

```env
BROADCAST_CONNECTION=reverb

REVERB_APP_ID=gymies
REVERB_APP_KEY=your_key
REVERB_APP_SECRET=your_secret

REVERB_SERVER_HOST=0.0.0.0
REVERB_SERVER_PORT=8080

REVERB_HOST=www.gymies.nl
REVERB_PORT=443
REVERB_SCHEME=https
```

## 3) Nginx reverse proxy (upgrade headers)

Zorg dat websocket routes doorgezet worden naar Reverb (`127.0.0.1:8080`) met upgrade headers.

Voorbeeld:

```nginx
location /app {
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_pass http://127.0.0.1:8080;
}

location /ws {
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_pass http://127.0.0.1:8080;
}
```

## 4) Process commands (server)

Na env wijziging:

```bash
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
php artisan reverb:restart
```

Als queue/broadcast jobs gebruikt worden:

```bash
php artisan queue:restart
```

## 5) Snel testen

1. Login als trainer.
2. Trigger een notificatie event.
3. Controleer dat websocket connect op `wss://www.gymies.nl/...` gebeurt (zonder `:0`).
4. Geen melding meer: `was not upgraded to websocket`.
