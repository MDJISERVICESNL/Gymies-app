#!/usr/bin/env bash
# Op de server uitvoeren met sudo: sudo bash ~/gymies_api/setup_gymies_routes_middleware.sh
# Voegt Gymies routes en middleware-registratie toe aan het Laravel-project.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LARAVEL="/var/www/gymies.nl/laravel"

if [ "$(id -u)" -ne 0 ]; then
  echo "Voer uit met: sudo bash $0"
  exit 1
fi

WEB_ROUTES="$LARAVEL/routes/web.php"
API_ROUTES="$LARAVEL/routes/api.php"
BOOTSTRAP_APP="$LARAVEL/bootstrap/app.php"
KERNEL="$LARAVEL/app/Http/Kernel.php"

[ -f "$BOOTSTRAP_APP" ] || { echo "Bestand niet gevonden: $BOOTSTRAP_APP"; exit 1; }

# --- 1) Routes: web.php (werkt altijd; Laravel 11 laadt api.php soms niet) ---
if grep -q "GymiesAuthController" "$WEB_ROUTES" 2>/dev/null; then
  echo "Routes voor Gymies bestaan al in web.php."
else
  [ -f "$WEB_ROUTES" ] || { echo "Bestand niet gevonden: $WEB_ROUTES"; exit 1; }
  cp -a "$WEB_ROUTES" "$WEB_ROUTES.bak_gymies_$(date +%Y%m%d_%H%M%S)"
  cat >> "$WEB_ROUTES" << 'ROUTES'

// Gymies API (prefix api/gymies omdat api.php in Laravel 11 vaak niet geladen is)
Route::prefix('api/gymies')->group(function () {
    Route::post('login', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'login']);
    Route::post('register', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'register']);
    Route::middleware('gymies.auth')->group(function () {
        Route::get('me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'me']);
        Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'index']);
        Route::get('trainers/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'show']);
        Route::get('bookings', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'index']);
        Route::post('bookings', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'store']);
    });
});
ROUTES
  echo "Routes toegevoegd aan $WEB_ROUTES (prefix api/gymies)"
fi

# --- 2) Middleware alias (Laravel 11: bootstrap/app.php) ---
if grep -q "gymies.auth" "$BOOTSTRAP_APP" 2>/dev/null; then
  echo "Middleware gymies.auth staat al in bootstrap/app.php."
else
  cp -a "$BOOTSTRAP_APP" "$BOOTSTRAP_APP.bak_gymies_$(date +%Y%m%d_%H%M%S)"
  # Laravel 11: voeg toe binnen ->alias([ ... ]). Zoek regel met 'auth' => en voeg onze regel erna in.
  if grep -q "->alias(" "$BOOTSTRAP_APP"; then
    sed -i "/'auth' =>/a\\        'gymies.auth' => \\\\App\\\\Http\\\\Middleware\\\\GymiesAuthMiddleware::class," "$BOOTSTRAP_APP"
    sed -i "/'gymies.auth' =>/a\\        'gymies.admin.capability' => \\\\App\\\\Http\\\\Middleware\\\\GymiesAdminCapabilityMiddleware::class," "$BOOTSTRAP_APP"
    sed -i "/'gymies.admin.capability' =>/a\\        'gymies.admin.ip' => \\\\App\\\\Http\\\\Middleware\\\\GymiesAdminIpAllowlistMiddleware::class," "$BOOTSTRAP_APP"
    echo "Middleware alias toegevoegd in bootstrap/app.php (Laravel 11)."
  elif [ -f "$KERNEL" ] && grep -q "routeMiddleware\|middlewareAliases" "$KERNEL" 2>/dev/null; then
    # Laravel 10 en eerder: Kernel.php
    sed -i "/'auth' =>/a\\        'gymies.auth' => \\\\App\\\\Http\\\\Middleware\\\\GymiesAuthMiddleware::class," "$KERNEL"
    echo "Middleware alias toegevoegd in app/Http/Kernel.php (Laravel 10)."
  else
    echo "Kon middleware niet automatisch toevoegen. Voeg handmatig toe in bootstrap/app.php:"
    echo "  'gymies.auth' => \\App\\Http\\Middleware\\GymiesAuthMiddleware::class,"
  fi
fi

chown www-data:www-data "$WEB_ROUTES" "$BOOTSTRAP_APP" 2>/dev/null || true

# Route-cache legen zodat nieuwe routes geladen worden
(cd "$LARAVEL" && php artisan route:clear 2>/dev/null; php artisan config:clear 2>/dev/null) || true

echo "Klaar. Test de API: curl -X POST https://gymies.nl/api/gymies/register -H 'Content-Type: application/json' -d '{\"email\":\"test@test.nl\",\"password\":\"wachtwoord\",\"role\":\"klant\"}'"
