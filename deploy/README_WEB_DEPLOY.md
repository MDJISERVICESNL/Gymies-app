# Gymies webapp build & deploy

Gymies is de **hoofdsite** op `/`; de API draait onder `/api/gymies`. Er is geen `/gymies`-pad meer.

## Lokaal bouwen

```bash
# Alleen build (output: build/web, base-href /)
./scripts/build_and_deploy_gymies_web.sh

# Build met API-URL voor Gymies server
export GYMIES_API_BASE_URL="http://148.113.197.164/api/gymies"
./scripts/build_and_deploy_gymies_web.sh
```

## Build + deploy naar server

### Eén commando (aanbevolen): backend + UX

```bash
# Vanaf projectroot – backend (PHP/controllers/SQL) + Flutter web + APP_URL
export SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
export SSH_TARGET=gymies
export GYMIES_API_BASE_URL="https://www.gymies.nl/api/gymies"

./deploy.sh              # alles
./deploy.sh backend      # alleen backend
./deploy.sh ux           # alleen web build + sync
./deploy.sh migrate      # toon SQL-migrate commando's voor op de server
```

### Alleen web (oudere flow)

```bash
# Optioneel: API op dezelfde server
export GYMIES_API_BASE_URL="http://148.113.197.164/api/gymies"

./scripts/build_and_deploy_gymies_web.sh --deploy
```

Dit doet:
1. `flutter build web --release --base-href /`
2. rsync van `build/web/` naar server; op server: merge in `/var/www/gymies/public/` (index.php blijft staan)

## Website bekijken

- **Website (Gymies):** http://148.113.197.164/
- **API:** http://148.113.197.164/api/gymies/...

Nginx: `/` = Flutter SPA (index.html), `/api/` = Laravel.

## Nginx

Config staat in `deploy/nginx-gymies.conf`. Na wijziging op server:

```bash
scp deploy/nginx-gymies.conf gymies:~/gymies_deploy/
ssh gymies "sudo cp ~/gymies_deploy/nginx-gymies.conf /etc/nginx/sites-available/gymies && sudo nginx -t && sudo systemctl reload nginx"
```
