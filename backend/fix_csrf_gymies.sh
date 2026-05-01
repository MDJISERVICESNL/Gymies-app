#!/usr/bin/env bash
# Voegt 'api/trainmaat/*' toe aan CSRF-uitzonderingen in Laravel.
#
# Op de server uitvoeren:
#   cd /var/www/mdjiservices.nl/laravel  # of LARAVEL instellen
#   bash fix_csrf_trainmaat.sh
#
# Vanaf je Mac (zonder wachtwoord in het script): script draait zonder sudo.
# Als de server geen schrijfrechten heeft, toont het script een opdracht die je
# één keer interactief op de server uitvoert (ssh -t niyyahpath, dan sudo ...):
#   scp backend/fix_csrf_trainmaat.sh niyyahpath:/tmp/ && ssh niyyahpath 'LARAVEL=/var/www/mdjiservices.nl/laravel bash /tmp/fix_csrf_trainmaat.sh'
#
# Optioneel: LARAVEL=/pad/naar/laravel bash fix_csrf_trainmaat.sh

set -e
LARAVEL="${LARAVEL:-/var/www/mdjiservices.nl/laravel}"
CSRF_FILE="$LARAVEL/app/Http/Middleware/VerifyCsrfToken.php"
ENTRY="'api/trainmaat/*',"
BACKUP_DIR="/tmp"
BACKUP_FILE="$BACKUP_DIR/VerifyCsrfToken.php.bak_csrf_$(date +%Y%m%d_%H%M%S)"
PATCHED_FILE="$BACKUP_DIR/VerifyCsrfToken_trainmaat_patched.php"

if [ ! -f "$CSRF_FILE" ]; then
  echo "Niet gevonden: $CSRF_FILE"
  echo "Laravel 11? Zoek handmatig waar CSRF \$except staat (bv. bootstrap/app.php) en voeg $ENTRY toe. Zie backend/CSRF_FIX.md"
  exit 1
fi

if grep -q "api/trainmaat" "$CSRF_FILE"; then
  echo "api/trainmaat staat al in CSRF-uitzonderingen."
else
  cp -a "$CSRF_FILE" "$BACKUP_FILE"
  echo "Backup: $BACKUP_FILE"
  if grep -q '\$except' "$CSRF_FILE"; then
    sed "/protected \$except = \[/a\\
        $ENTRY" "$CSRF_FILE" > "$PATCHED_FILE"
    if cp "$PATCHED_FILE" "$CSRF_FILE" 2>/dev/null; then
      rm -f "$PATCHED_FILE"
      echo "CSRF-uitzondering toegevoegd in $CSRF_FILE"
    else
      echo ""
      echo "Geen schrijfrechten op de Laravel-map. Voer op de server uit (één keer inloggen, wachtwoord intypen):"
      echo "  ssh -t niyyahpath"
      echo "  sudo cp $PATCHED_FILE $CSRF_FILE"
      echo "  cd $LARAVEL && sudo php artisan config:clear && sudo php artisan cache:clear"
      echo ""
      echo "Daarna kun je het patched bestand verwijderen: rm $PATCHED_FILE"
      exit 0
    fi
  else
    echo "Kon \$except niet vinden in $CSRF_FILE. Voeg handmatig toe: $ENTRY in de \$except array."
    rm -f "$PATCHED_FILE"
    exit 1
  fi
fi

cd "$LARAVEL"
php artisan config:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "Cache geleegd. Klaar."
