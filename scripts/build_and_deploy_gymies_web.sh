#!/usr/bin/env bash
# Build Flutter web voor Gymies server (base-href /gymies/) en optioneel deployen.
# Gebruik: ./scripts/build_and_deploy_gymies_web.sh           → alleen build
#          ./scripts/build_and_deploy_gymies_web.sh --deploy   → build + upload naar server

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Gymies = hoofdsite op / (geen /gymies meer)
BASE_HREF="/"
OUTPUT_DIR="$PROJECT_DIR/build/web"

# Server (Gymies VPS). Voor API op deze server:
#   export GYMIES_API_BASE_URL="http://148.113.197.164/api/gymies"
SSH_HOST="${SSH_HOST:-gymies}"
REMOTE_PUBLIC="${REMOTE_PUBLIC:-/var/www/gymies/public}"

DEPLOY=false
if [[ "${1:-}" == "--deploy" ]]; then
  DEPLOY=true
fi

cd "$PROJECT_DIR"

# Optioneel: API URL voor deze server (via dart-define)
# Voorbeeld: flutter build web --dart-define=GYMIES_API_BASE=http://148.113.197.164/api/gymies
GYMIES_API_DEFINE=""
if [[ -n "${GYMIES_API_BASE_URL:-}" ]]; then
  GYMIES_API_DEFINE="--dart-define=GYMIES_API_BASE=$GYMIES_API_BASE_URL"
fi

echo "== Gymies web build =="
echo "  base-href: $BASE_HREF"
echo "  output:    $OUTPUT_DIR"
echo ""

echo "[1/2] Flutter web build..."
flutter build web --release --base-href "$BASE_HREF" -O4 --source-maps $GYMIES_API_DEFINE

echo "[2/2] Build klaar: $OUTPUT_DIR"
echo ""

if [[ "$DEPLOY" == true ]]; then
  echo "Deploy naar $SSH_HOST:$REMOTE_PUBLIC (Flutter in public root, index.php blijft staan)..."
  rsync -avz -e ssh "$OUTPUT_DIR/" "$SSH_HOST:~/gymies_deploy/web/"
  ssh "$SSH_HOST" "sudo rsync -a ~/gymies_deploy/web/ $REMOTE_PUBLIC/ && sudo chown -R www-data:www-data $REMOTE_PUBLIC"
  echo "Deploy klaar. Website: http://<server>/"
else
  echo "Deploy overslaan. Gebruik: $0 --deploy"
  echo "Handmatig: rsync -avz build/web/ $SSH_HOST:$REMOTE_PUBLIC/ (let op: index.php niet overschrijven)"
fi
