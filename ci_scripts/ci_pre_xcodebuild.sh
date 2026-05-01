#!/bin/sh
# Xcode Cloud: vlak vóór xcodebuild opnieuw Flutter + CocoaPods afstemmen.
# Voorkomt lege PODS_ROOT / ontbrekende .xcfilelist als post-clone werd overgeslagen
# of de cache niet klopte.
#
# Zie: https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -euo pipefail
export LANG="${LANG:-en_US.UTF-8}"

REPO="${CI_PRIMARY_REPOSITORY_PATH:-}"
if [ -z "$REPO" ]; then
  REPO="$(cd "$(dirname "$0")/.." && pwd)"
fi
cd "$REPO"

FLUTTER_DIR="${FLUTTER_ROOT:-$HOME/flutter-ci}"
if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
  export PATH="$FLUTTER_DIR/bin:$PATH"
elif command -v flutter >/dev/null 2>&1; then
  :
else
  echo "ci_pre_xcodebuild: geen Flutter gevonden (verwacht $FLUTTER_DIR of PATH)." >&2
  echo "Zorg dat ci_post_clone.sh eerst Flutter installeert." >&2
  exit 1
fi

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"

flutter pub get

cd ios

if ! command -v pod >/dev/null 2>&1; then
  echo "ci_pre_xcodebuild: 'pod' niet gevonden. Installeer CocoaPods in de workflow of voeg toe:" >&2
  echo "  sudo gem install cocoapods" >&2
  exit 1
fi

pod install

for f in \
  "Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Release-output-files.xcfilelist" \
  "Pods/Target Support Files/Pods-Runner/Pods-Runner-resources-Release-output-files.xcfilelist"
do
  if [ ! -f "$f" ]; then
    echo "ci_pre_xcodebuild: ontbreekt: $f — controleer Podfile en pod install-log." >&2
    exit 1
  fi
done

echo "ci_pre_xcodebuild: OK (Pods + Release xcfilelists)."
