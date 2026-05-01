#!/usr/bin/env bash
# ============================================================
# GYMIES – Deploy Trainer Profile & Revenue Fix
# ============================================================
# Deployt de gefixte bestanden voor trainer/me en trainer/revenue
# endpoints die 404 gaven door ontbrekende hasColumn checks.
#
# Wat wordt gedeployd:
#   1. GymiesTrainerController.php   – show() met hasColumn checks + try-catch fallback
#   2. GymiesTrainerOpsController.php – revenue() met hasColumn checks + try-catch
#   3. GymiesRequireTrainerTrait.php  – trait voor trainer auth check
#   4. routes_gymies_full.php         – trainer/profile alias route toegevoegd
#
# Gebruik:
#   cd "/Users/sara/Desktop/GYMIES - APP"
#   bash scripts/deploy_trainer_fix.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# --- Kleuren ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Configuratie ---
SSH_TARGET="ubuntu@gymies.nl"
REMOTE_LARAVEL="/var/www/gymies"
REMOTE_STAGING="~/gymies_trainer_fix"

# --- SSH key zoeken op bekende locaties ---
SSH_KEY=""
for candidate in \
  "$PROJECT_DIR/Amazonekey.pem" \
  "$HOME/.ssh/Amazonekey.pem" \
  "$HOME/.ssh/id_ed25519_gymies" \
  "$HOME/Desktop/Amazonekey.pem" \
  "$HOME/Downloads/Amazonekey.pem"; do
  if [[ -f "$candidate" ]]; then
    SSH_KEY="$candidate"
    break
  fi
done

if [[ -z "$SSH_KEY" ]]; then
  echo -e "${RED}FOUT: Geen SSH key gevonden.${NC}"
  echo "Zet Amazonekey.pem in een van deze locaties:"
  echo "  $PROJECT_DIR/Amazonekey.pem"
  echo "  ~/.ssh/Amazonekey.pem"
  echo "  ~/.ssh/id_ed25519_gymies"
  echo ""
  read -rp "Of geef het volledige pad naar je SSH key: " SSH_KEY
  if [[ ! -f "$SSH_KEY" ]]; then
    echo -e "${RED}Bestand niet gevonden: $SSH_KEY${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}[OK]${NC} SSH key: $SSH_KEY"

echo -e "${YELLOW}================================================${NC}"
echo -e "${YELLOW}  GYMIES – Trainer Profile & Revenue Fix Deploy  ${NC}"
echo -e "${YELLOW}================================================${NC}"
echo ""

SSH_OPTS=(-o IdentitiesOnly=yes -o ConnectTimeout=15 -i "$SSH_KEY")

# --- Bestanden check ---
CONTROLLER="backend/Controllers/Gymies/GymiesTrainerController.php"
OPS_CONTROLLER="backend/Controllers/Gymies/GymiesTrainerOpsController.php"
PLAN_MANAGER="backend/Controllers/Gymies/GymiesPlanManager.php"
TRAIT="backend/Traits/GymiesRequireTrainerTrait.php"
ROUTES="backend/routes_gymies_full.php"

for f in "$CONTROLLER" "$OPS_CONTROLLER" "$PLAN_MANAGER" "$TRAIT" "$ROUTES"; do
  if [[ ! -f "$f" ]]; then
    echo -e "${RED}FOUT: Bestand niet gevonden: $f${NC}"
    exit 1
  fi
done
echo -e "${GREEN}[OK]${NC} Alle bronbestanden gevonden."
echo ""

# --- Stap 1: Lokale staging ---
echo -e "${YELLOW}[1/5]${NC} Lokale staging map voorbereiden..."
TMP_STAGING=$(mktemp -d)
trap "rm -rf '$TMP_STAGING'" EXIT

mkdir -p "$TMP_STAGING/Controllers"
mkdir -p "$TMP_STAGING/Traits"

cp "$CONTROLLER"     "$TMP_STAGING/Controllers/GymiesTrainerController.php"
cp "$OPS_CONTROLLER" "$TMP_STAGING/Controllers/GymiesTrainerOpsController.php"
cp "$PLAN_MANAGER"   "$TMP_STAGING/Controllers/GymiesPlanManager.php"
cp "$TRAIT"          "$TMP_STAGING/Traits/GymiesRequireTrainerTrait.php"
cp "$ROUTES"         "$TMP_STAGING/routes_gymies_full.php"

echo "  - GymiesTrainerController.php      (show() hasColumn fix + fallback)"
echo "  - GymiesTrainerOpsController.php   (storefront-cms + revenue fix + try-catch)"
echo "  - GymiesPlanManager.php            (assertPro + assertProPlus toegevoegd)"
echo "  - GymiesRequireTrainerTrait.php    (trainer auth trait)"
echo "  - routes_gymies_full.php           (trainer/profile alias)"
echo ""

# --- Stap 2: Upload ---
echo -e "${YELLOW}[2/5]${NC} Bestanden uploaden naar server..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING/Controllers $REMOTE_STAGING/Traits"
rsync -avz --no-perms --no-owner --no-group \
  -e "ssh -o IdentitiesOnly=yes -o ConnectTimeout=15 -i '$SSH_KEY'" \
  "$TMP_STAGING/" \
  "$SSH_TARGET:$REMOTE_STAGING/"
echo -e "${GREEN}[OK]${NC} Upload compleet."
echo ""

# --- Stap 3: Kopieer naar Laravel + fix permissions ---
echo -e "${YELLOW}[3/5]${NC} Bestanden naar Laravel kopiëren + permissions fixen..."
echo "    (sudo wachtwoord kan worden gevraagd)"
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" bash -s <<'REMOTE_SCRIPT'
set -e
REMOTE_LARAVEL="/var/www/gymies"
REMOTE_STAGING="$HOME/gymies_trainer_fix"

# Directories aanmaken
sudo mkdir -p "$REMOTE_LARAVEL/app/Http/Controllers/Gymies"
sudo mkdir -p "$REMOTE_LARAVEL/app/Traits"

# Controllers kopiëren
echo "  Kopieer GymiesTrainerController.php..."
sudo cp "$REMOTE_STAGING/Controllers/GymiesTrainerController.php" \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesTrainerController.php"

echo "  Kopieer GymiesTrainerOpsController.php..."
sudo cp "$REMOTE_STAGING/Controllers/GymiesTrainerOpsController.php" \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesTrainerOpsController.php"

echo "  Kopieer GymiesPlanManager.php..."
sudo cp "$REMOTE_STAGING/Controllers/GymiesPlanManager.php" \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesPlanManager.php"

# Trait kopiëren
echo "  Kopieer GymiesRequireTrainerTrait.php..."
sudo cp "$REMOTE_STAGING/Traits/GymiesRequireTrainerTrait.php" \
  "$REMOTE_LARAVEL/app/Traits/GymiesRequireTrainerTrait.php"

# Routes kopiëren (activeer trainer/profile alias)
echo "  Kopieer routes_gymies_full.php..."
sudo cp "$REMOTE_STAGING/routes_gymies_full.php" \
  "$REMOTE_LARAVEL/routes/gymies.php"

# Permissions
echo "  Permissions fixen..."
sudo chown www-data:www-data \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesTrainerController.php" \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesTrainerOpsController.php" \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesPlanManager.php" \
  "$REMOTE_LARAVEL/app/Traits/GymiesRequireTrainerTrait.php" \
  "$REMOTE_LARAVEL/routes/gymies.php"

sudo chmod 644 \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesTrainerController.php" \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesTrainerOpsController.php" \
  "$REMOTE_LARAVEL/app/Http/Controllers/Gymies/GymiesPlanManager.php" \
  "$REMOTE_LARAVEL/app/Traits/GymiesRequireTrainerTrait.php" \
  "$REMOTE_LARAVEL/routes/gymies.php"

echo "  Bestanden gekopieerd en permissions gefixt."
REMOTE_SCRIPT
echo -e "${GREEN}[OK]${NC} Bestanden geplaatst."
echo ""

# --- Stap 4: Cache legen + PHP-FPM herstarten ---
echo -e "${YELLOW}[4/5]${NC} Cache legen en PHP-FPM herstarten..."
ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" bash -s <<'REMOTE_CACHE'
set -e
cd /var/www/gymies

echo "  Route cache legen..."
sudo -u www-data php artisan route:clear 2>/dev/null || true
echo "  Config cache legen..."
sudo -u www-data php artisan config:clear 2>/dev/null || true
echo "  View cache legen..."
sudo -u www-data php artisan view:clear 2>/dev/null || true

echo "  PHP-FPM herstarten..."
sudo systemctl restart php8.4-fpm

echo "  Staging map opruimen..."
rm -rf "$HOME/gymies_trainer_fix"

echo "  Klaar!"
REMOTE_CACHE
echo -e "${GREEN}[OK]${NC} Cache geleegd, PHP-FPM herstart."
echo ""

# --- Stap 5: Smoketest ---
echo -e "${YELLOW}[5/5]${NC} Smoketest: trainer/me endpoint bereikbaar?"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://www.gymies.nl/api/gymies/trainer/me" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "401" ]]; then
  echo -e "${GREEN}[OK]${NC} trainer/me retourneert 401 (Unauthorized) – endpoint werkt, auth vereist."
elif [[ "$HTTP_CODE" == "200" ]]; then
  echo -e "${GREEN}[OK]${NC} trainer/me retourneert 200 – endpoint werkt!"
elif [[ "$HTTP_CODE" == "000" ]]; then
  echo -e "${YELLOW}[WARN]${NC} Kon server niet bereiken – check je internetverbinding."
else
  echo -e "${YELLOW}[WARN]${NC} trainer/me retourneert HTTP $HTTP_CODE – check server logs."
fi

# Smoketest trainer/profile alias
HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://www.gymies.nl/api/gymies/trainer/profile" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE2" == "401" ]]; then
  echo -e "${GREEN}[OK]${NC} trainer/profile alias retourneert 401 – route werkt!"
elif [[ "$HTTP_CODE2" == "404" ]]; then
  echo -e "${YELLOW}[WARN]${NC} trainer/profile retourneert 404 – route niet geactiveerd."
fi

# Smoketest storefront-cms
HTTP_CODE3=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://www.gymies.nl/api/gymies/trainer/storefront-cms" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE3" == "401" ]]; then
  echo -e "${GREEN}[OK]${NC} trainer/storefront-cms retourneert 401 – endpoint werkt!"
elif [[ "$HTTP_CODE3" == "403" ]]; then
  echo -e "${GREEN}[OK]${NC} trainer/storefront-cms retourneert 403 – plan check werkt!"
elif [[ "$HTTP_CODE3" == "500" ]]; then
  echo -e "${RED}[FAIL]${NC} trainer/storefront-cms retourneert 500 – check server logs!"
else
  echo -e "${YELLOW}[INFO]${NC} trainer/storefront-cms retourneert HTTP $HTTP_CODE3"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Deploy compleet!                               ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Wat is gefixt:"
echo "  - trainer/me: alle profielkolommen worden nu veilig gecheckt (hasColumn)"
echo "  - trainer/me: bij SQL-fout wordt een fallback-profiel geretourneerd"
echo "  - trainer/revenue: kolommen worden veilig gecheckt + try-catch fallback"
echo "  - trainer/profile: nieuwe alias-route voor de Flutter fallback"
echo "  - trainer/storefront-cms: assertPro() + assertProPlus() toegevoegd"
echo "  - trainer/storefront-cms: slug wordt nu meegestuurd voor embed/QR"
echo "  - GymiesPlanManager: assertPro() en assertProPlus() methods toegevoegd"
echo ""
echo "Test in de app: open het Trainer dashboard → Mijn profiel en Sessie-inkomsten."
echo ""
echo "Bij problemen, check server logs:"
echo "  ssh -i \"$SSH_KEY\" $SSH_TARGET"
echo "  sudo tail -50 /var/www/gymies/storage/logs/laravel.log"
