#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Gymies: backup van de UX (Flutter web build) maken en op de server bewaren.
# =============================================================================
# Gebruik:
#   ./scripts/backup_ux_to_server.sh           # bouwt UX, maakt tarball, uploadt
#   SKIP_BUILD=1 ./scripts/backup_ux_to_server.sh   # gebruik bestaande build/
#
# Backups komen op de server in: ~/backups/gymies_ux/ (home van SSH-user)
# Bestandsnaam: gymies_ux_YYYYMMDD_HHMMSS.tar.gz
#
# Optionele env vars (zelfde als deploy):
#   SSH_KEY=$HOME/.ssh/Gymies
#   SSH_TARGET=user@gymies-server
#   REMOTE_LARAVEL=/var/www/gymies.nl/laravel
#   APP_PATH=gymies
#   KEEP_UX_BACKUPS=10
#   REMOTE_UX_BACKUP_DIR=~/backups/gymies_ux
# =============================================================================

SSH_TARGET="${SSH_TARGET:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_gymies}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies.nl/laravel}"
APP_PATH="${APP_PATH:-gymies}"
KEEP_UX_BACKUPS="${KEEP_UX_BACKUPS:-10}"

SSH_OPTS=()
if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
  SSH_OPTS=(-o IdentitiesOnly=yes -i "$SSH_KEY")
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

STAMP="$(date +%Y%m%d_%H%M%S)"
TARBALL_NAME="gymies_ux_${STAMP}.tar.gz"
REMOTE_BACKUP_DIR="${REMOTE_UX_BACKUP_DIR:-~/backups/gymies_ux}"

echo "=============================================="
echo "  Gymies: UX-backup naar server"
echo "  Server: $SSH_TARGET"
echo "  Doel:   $REMOTE_BACKUP_DIR/"
echo "=============================================="
echo ""

if [[ -z "$SSH_TARGET" ]]; then
  echo "ERROR: SSH_TARGET niet gezet. Bijv. export SSH_TARGET=user@gymies-server"
  exit 1
fi
if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH-sleutel niet gevonden: $SSH_KEY"
  exit 1
fi

# 1) Build (tenzij SKIP_BUILD=1)
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "[1/4] Flutter web build (base-href /$APP_PATH/)..."
  flutter build web --base-href "/$APP_PATH/" --no-wasm-dry-run
else
  echo "[1/4] Build overgeslagen (SKIP_BUILD=1). Gebruik bestaande build/web/"
  if [[ ! -d "build/web" ]]; then
    echo "ERROR: build/web/ niet gevonden. Voer eerst een build uit of verwijder SKIP_BUILD."
    exit 1
  fi
fi

# 2) Tarball maken van build/web
echo "[2/4] Tarball maken: $TARBALL_NAME"
tar -czf "$TARBALL_NAME" -C build web
echo "      Grootte: $(du -h "$TARBALL_NAME" | cut -f1)"

# 3) Backup-map op server aanmaken en uploaden
echo "[3/4] Upload naar $SSH_TARGET:$REMOTE_BACKUP_DIR/"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p $REMOTE_BACKUP_DIR"
scp "${SSH_OPTS[@]}" "$TARBALL_NAME" "$SSH_TARGET:$REMOTE_BACKUP_DIR/$TARBALL_NAME"

# 4) Oude backups opruimen (houd laatste KEEP_UX_BACKUPS)
echo "[4/4] Op server: behoud laatste $KEEP_UX_BACKUPS UX-backup(s)..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "cd $REMOTE_BACKUP_DIR && ls -t gymies_ux_*.tar.gz 2>/dev/null | tail -n +$((KEEP_UX_BACKUPS + 1)) | xargs -r rm -f"

# Lokaal tarball mag weg (optioneel, bespaar schijf)
rm -f "$TARBALL_NAME"

echo ""
echo "=============================================="
echo "  UX-backup op server opgeslagen."
echo "=============================================="
echo "  Bestand: $REMOTE_BACKUP_DIR/$TARBALL_NAME"
echo ""
echo "  Terugzetten op server (als voorbeeld):"
echo "    ssh -i $SSH_KEY $SSH_TARGET"
echo "    cd $REMOTE_LARAVEL/public && rm -rf $APP_PATH && tar -xzf $REMOTE_BACKUP_DIR/$TARBALL_NAME && mv web $APP_PATH"
echo ""
