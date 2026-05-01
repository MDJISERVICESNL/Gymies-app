#!/bin/bash
# Fix "file not found" / 404 op Gymies server.
# Oorzaak: route cache verouderd of routes niet geladen.
#
# Gebruik: bash fix_server_routes.sh

set -e
SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"

SSH_OPTS=()
[[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] && SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")

echo "=== Gymies server route-fix ==="
echo "Host: $SSH_TARGET"
echo "Laravel: $REMOTE_LARAVEL"
echo ""

echo "[1] Route cache legen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan route:clear"

echo "[2] Cache opnieuw bouwen..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan optimize:clear && sudo -u www-data php artisan config:cache"

echo "[3] Route cache opnieuw aanmaken..."
if ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan route:cache"; then
  echo "Route cache OK."
else
  echo "Waarschuwing: route:cache mislukt. Mogelijk dubbele route-namen."
  echo "Probeer zonder route cache: route:clear (geen route:cache) - routes worden dan live geladen."
fi

echo ""
echo "[4] Controleer of trainers/reviews route bestaat..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_LARAVEL && sudo -u www-data php artisan route:list | grep -E 'reviews|trainers' | head -20"

echo ""
echo "[5] Controleer of GymiesTrainerReviewsController aanwezig is..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "ls -la $REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesTrainerReviewsController.php 2>/dev/null || echo 'Controller niet gevonden!'"

echo ""
echo "=== Klaar. Test opnieuw: https://www.gymies.nl/api/gymies/trainers/3/reviews ==="
