#!/usr/bin/env bash
# Faal als main.dart.js te groot is (voorkomt stille performance-regressie).
# Gebruik: na `flutter build web ...` vanaf projectroot:
#   bash scripts/check_flutter_web_bundle_size.sh
# Optioneel: MAX_MAIN_JS_MB=9 bash scripts/check_flutter_web_bundle_size.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_JS="$ROOT/build/web/main.dart.js"
MAX_MB="${MAX_MAIN_JS_MB:-9}"

if [[ ! -f "$MAIN_JS" ]]; then
  echo "ERROR: $MAIN_JS ontbreekt. Eerst: flutter build web"
  exit 1
fi

if stat -f%z "$MAIN_JS" &>/dev/null; then
  BYTES=$(stat -f%z "$MAIN_JS")
else
  BYTES=$(stat -c%s "$MAIN_JS")
fi
MB=$(python3 -c "print(round($BYTES/1024/1024, 2))")

python3 - <<PY
import sys
m, max_m = float("$MB"), float("$MAX_MB")
if m > max_m:
    print(f"FAIL: main.dart.js is {m} MB (max {max_m} MB)")
    sys.exit(1)
print(f"OK: main.dart.js is {m} MB (max {max_m} MB)")
PY
