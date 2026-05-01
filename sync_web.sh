#!/usr/bin/env bash
set -euo pipefail

# Backend sync naar Gymies server.
# Geen Flutter/web deploy – alleen backend (Controllers, migrations, routes, scripts).
# Gebruik: bash sync_web.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

bash "$SCRIPT_DIR/sync_gymies_backend.sh"
