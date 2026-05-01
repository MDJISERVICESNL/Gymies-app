#!/usr/bin/env bash
set -euo pipefail

# Flutter web build + sync naar Gymies server.
# Gebruik:
#   bash scripts/sync_gymies_web.sh
#
# Optionele env vars:
#   SSH_TARGET=user@gymies-server
#   SSH_KEY=$HOME/.ssh/gymies
#   REMOTE_LARAVEL=/var/www/gymies.nl/laravel
#   APP_PATH=          (leeg = root)
#   GYMIES_DOMAIN=gymies.nl

# Default gelijk aan upload_backend.sh / deploy_backend_and_ux.sh
SSH_TARGET="${SSH_TARGET:-gymies}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies}"
APP_PATH="${APP_PATH:-}"
GYMIES_DOMAIN="${GYMIES_DOMAIN:-gymies.nl}"

# Lege APP_PATH = deploy naar document root met base-href /
if [[ -z "$APP_PATH" ]]; then
  BASE_HREF="/"
  REMOTE_WEB_DIR="$REMOTE_LARAVEL/public"
else
  BASE_HREF="/$APP_PATH/"
  REMOTE_WEB_DIR="$REMOTE_LARAVEL/public/$APP_PATH"
fi

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET is leeg. Zet bijv. export SSH_TARGET=gymies"
  exit 1
fi

SSH_OPTS=()
RSYNC_SSH_OPTS=()
if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
  RSYNC_SSH_OPTS=(-e "ssh -o IdentitiesOnly=yes -i $SSH_KEY")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

echo "=== Gymies web sync naar $SSH_TARGET (root) ==="
echo "[1/3] Build web met base-href $BASE_HREF"
# -O4 = maximale compressie, --source-maps voor Lighthouse "Missing source maps" audit
# --pwa-strategy deprecated; Flutter default is moving away from service worker
flutter build web --base-href "$BASE_HREF" -O4 --source-maps --no-wasm-dry-run

echo "[1b/3] Force disable stale service worker + cache, reload voor verse deploy"
python3 - <<'PY'
from pathlib import Path
index_path = Path("build/web/index.html")
bootstrap_path = Path("build/web/flutter_bootstrap.js")
content = index_path.read_text(encoding="utf-8")
marker = "window.__gymies_sw_cleanup_done__"
if marker not in content:
    inject = """
  <script>
    (function() {
      // Alleen herladen als er echt een oude SW/cache was — anders dubbele laadtijd bij elke nieuwe sessie.
      var pSw = 'serviceWorker' in navigator ? navigator.serviceWorker.getRegistrations().then(function(regs) {
        if (!regs.length) return false;
        return Promise.all(regs.map(function(r) { return r.unregister(); })).then(function() { return true; });
      }) : Promise.resolve(false);
      var pCache = 'caches' in window ? caches.keys().then(function(keys) {
        if (!keys.length) return false;
        return Promise.all(keys.map(function(k) { return caches.delete(k); })).then(function() { return true; });
      }) : Promise.resolve(false);
      Promise.all([pSw, pCache]).then(function(results) {
        if (results[0] || results[1]) location.reload();
      }).catch(function() {});
    })();
  </script>
"""
    content = content.replace("</body>", inject + "\n</body>")
    index_path.write_text(content, encoding="utf-8")

# Ensure main.dart.js URL is cache-busted per deploy
if bootstrap_path.exists():
    boot = bootstrap_path.read_text(encoding="utf-8")
    if '"mainJsPath":"main.dart.js"' in boot:
        import time
        build_id = str(int(time.time()))
        boot = boot.replace(
            '"mainJsPath":"main.dart.js"',
            f'"mainJsPath":"main.dart.js?v={build_id}"',
            1,
        )
        bootstrap_path.write_text(boot, encoding="utf-8")
PY

REMOTE_STAGING="${REMOTE_STAGING:-~/gymies_web_upload}"
echo "[2/3] Staging op server: $REMOTE_STAGING"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_STAGING"

echo "[3/3] Upload build/web -> staging..."
rsync "${RSYNC_SSH_OPTS[@]}" -avz --delete build/web/ "$SSH_TARGET:$REMOTE_STAGING/"

echo "[4/4] Kopiëren naar document root (sudo)..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo mkdir -p $REMOTE_WEB_DIR && sudo rsync -a --delete $REMOTE_STAGING/ $REMOTE_WEB_DIR/ && sudo chown -R www-data:www-data $REMOTE_WEB_DIR && rm -rf $REMOTE_STAGING"

# Root-deploy: Laravel index.php herstellen zodat /api/ weer werkt (registreren, inloggen, etc.)
if [[ -z "$APP_PATH" ]]; then
  LARAVEL_INDEX="$ROOT_DIR/deploy/laravel_public_index.php"
  if [[ -f "$LARAVEL_INDEX" ]]; then
    echo "[5/4] Laravel index.php terugzetten voor /api/..."
    scp "${SSH_OPTS[@]}" "$LARAVEL_INDEX" "$SSH_TARGET:/tmp/laravel_index.php"
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "sudo cp /tmp/laravel_index.php $REMOTE_LARAVEL/public/index.php && sudo chown www-data:www-data $REMOTE_LARAVEL/public/index.php && rm -f /tmp/laravel_index.php"
  fi
fi

if [[ -z "$APP_PATH" ]]; then
  echo "Klaar: https://$GYMIES_DOMAIN/"
else
  echo "Klaar: https://$GYMIES_DOMAIN/$APP_PATH/"
fi
