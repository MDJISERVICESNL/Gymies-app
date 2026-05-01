#!/usr/bin/env bash
# Fix "Target class trainmaat.auth does not exist" en maak GET trainers publiek voor de zoekpagina.
# Gebruik: bash scripts/fix_trainmaat_auth.sh [pad/naar/laravel]
# Voorbeeld: bash scripts/fix_trainmaat_auth.sh /var/www/mdjiservices.nl/laravel

set -e
LARAVEL="${1:-${LARAVEL_ROOT:-/var/www/mdjiservices.nl/laravel}}"
BOOTSTRAP_APP="$LARAVEL/bootstrap/app.php"
KERNEL="$LARAVEL/app/Http/Kernel.php"
WEB_ROUTES="$LARAVEL/routes/web.php"

if [ ! -f "$BOOTSTRAP_APP" ] && [ ! -f "$KERNEL" ]; then
  echo "Laravel niet gevonden op: $LARAVEL"
  echo "Gebruik: bash $0 /pad/naar/laravel"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$SCRIPT_DIR/../backend"

# --- 1) Zorg dat TrainMaatAuthMiddleware bestaat ---
if [ -f "$LARAVEL/app/Http/Middleware/TrainMaatAuthMiddleware.php" ]; then
  echo "[OK] TrainMaatAuthMiddleware.php bestaat al."
else
  if [ -f "$BACKEND/Middleware/TrainMaatAuthMiddleware.php" ]; then
    mkdir -p "$LARAVEL/app/Http/Middleware"
    cp "$BACKEND/Middleware/TrainMaatAuthMiddleware.php" "$LARAVEL/app/Http/Middleware/"
    echo "[OK] TrainMaatAuthMiddleware.php gekopieerd."
  else
    echo "[FOUT] Bestand niet gevonden: $BACKEND/Middleware/TrainMaatAuthMiddleware.php"
    exit 1
  fi
fi

# --- 2) Registreer middleware alias (Laravel 11: bootstrap/app.php) ---
if [ -f "$BOOTSTRAP_APP" ]; then
  if grep -q "trainmaat.auth" "$BOOTSTRAP_APP" 2>/dev/null; then
    echo "[OK] Middleware trainmaat.auth staat al in bootstrap/app.php."
  else
    cp -a "$BOOTSTRAP_APP" "${BOOTSTRAP_APP}.bak_trainmaat_$(date +%Y%m%d_%H%M%S)"
    # Laravel 11: ->alias([ 'auth' => ... ])  -> voeg onze regel toe na 'auth'
    if grep -q "->alias(" "$BOOTSTRAP_APP"; then
      # Linux sed: sed -i '...'  |  macOS sed: sed -i.bak '...'
      if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "/'auth' =>/a\\        'trainmaat.auth' => \\\\App\\\\Http\\\\Middleware\\\\TrainMaatAuthMiddleware::class," "$BOOTSTRAP_APP"
      else
        sed -i.bak "/'auth' =>/a\\
        'trainmaat.auth' => \\\\App\\\\Http\\\\Middleware\\\\TrainMaatAuthMiddleware::class,
" "$BOOTSTRAP_APP" && rm -f "${BOOTSTRAP_APP}.bak"
      fi
      echo "[OK] Middleware alias toegevoegd in bootstrap/app.php."
    else
      echo "[WAARSCHUWING] Geen ->alias( in bootstrap/app.php. Voeg handmatig toe in bootstrap/app.php:"
      echo "  'trainmaat.auth' => \\App\\Http\\Middleware\\TrainMaatAuthMiddleware::class,"
      echo "Binnen: ->withMiddleware(function (Middleware \$middleware) { \$middleware->alias([ ... ]); })"
    fi
  fi
# Laravel 10: Kernel.php
elif [ -f "$KERNEL" ]; then
  if grep -q "trainmaat.auth" "$KERNEL" 2>/dev/null; then
    echo "[OK] Middleware trainmaat.auth staat al in Kernel.php."
  else
    cp -a "$KERNEL" "${KERNEL}.bak_trainmaat_$(date +%Y%m%d_%H%M%S)"
    if grep -q "middlewareAliases\|routeMiddleware" "$KERNEL"; then
      if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "/'auth' =>/a\\        'trainmaat.auth' => \\\\App\\\\Http\\\\Middleware\\\\TrainMaatAuthMiddleware::class," "$KERNEL"
      else
        sed -i.bak "/'auth' =>/a\\
        'trainmaat.auth' => \\\\App\\\\Http\\\\Middleware\\\\TrainMaatAuthMiddleware::class,
" "$KERNEL" && rm -f "${KERNEL}.bak"
      fi
      echo "[OK] Middleware alias toegevoegd in Kernel.php."
    else
      echo "[WAARSCHUWING] Voeg handmatig toe in app/Http/Kernel.php:"
      echo "  'trainmaat.auth' => \\App\\Http\\Middleware\\TrainMaatAuthMiddleware::class,"
    fi
  fi
fi

# --- 3) Maak GET trainers en GET trainers/{id} publiek (buiten auth) voor zoekpagina ---
if [ -f "$WEB_ROUTES" ] && grep -q "TrainMaatTrainerController" "$WEB_ROUTES" 2>/dev/null; then
  if grep -q "Route::get('trainers'" "$WEB_ROUTES" 2>/dev/null && grep -q "middleware('trainmaat.auth')" "$WEB_ROUTES" 2>/dev/null; then
    echo ""
    echo "Om de zoekpagina zonder inloggen te laten werken, moeten GET trainers en GET trainers/{id}"
    echo "buiten de trainmaat.auth middleware staan. Pas routes/web.php (of api.php) handmatig aan:"
    echo ""
    echo "  Route::prefix('api/trainmaat')->group(function () {"
    echo "      Route::post('login', [...]);"
    echo "      Route::post('register', [...]);"
    echo "      Route::get('trainers', [TrainMaatTrainerController::class, 'index']);"
    echo "      Route::get('trainers/{id}', [TrainMaatTrainerController::class, 'show']);"
    echo "      Route::middleware('trainmaat.auth')->group(function () {"
    echo "          Route::get('me', [...]);"
    echo "          Route::get('bookings', [...]);"
    echo "          Route::post('bookings', [...]);"
    echo "      });"
    echo "  });"
    echo ""
  fi
fi

# --- 4) Cache legen ---
if [ -d "$LARAVEL" ]; then
  (cd "$LARAVEL" && php artisan route:clear 2>/dev/null; php artisan config:clear 2>/dev/null) || true
  echo "[OK] Route/config cache geleegd."
fi

echo ""
echo "Klaar. Test de zoekpagina: GET https://mdjiservices.nl/api/trainmaat/trainers"
echo "Zonder Bearer token zou je nu een JSON-lijst moeten krijgen (of een lege array)."
echo "Als je nog 500 krijgt, controleer Laravel logs: storage/logs/laravel.log"
echo ""
