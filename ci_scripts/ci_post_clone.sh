#!/bin/sh
# Xcode Cloud: na clone Flutter + CocoaPods klaarzetten vóór Xcode Archive.
# Vereist: dit bestand uitvoerbaar (chmod +x) en in git gecommit.
#
# Zie: https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -euo pipefail
export LANG="${LANG:-en_US.UTF-8}"

REPO="${CI_PRIMARY_REPOSITORY_PATH:-}"
if [ -z "$REPO" ]; then
  echo "CI_PRIMARY_REPOSITORY_PATH ontbreekt; lokaal testen vanaf projectroot:"
  REPO="$(cd "$(dirname "$0")/.." && pwd)"
fi
cd "$REPO"

# Flutter (Xcode Cloud heeft geen Flutter in PATH)
FLUTTER_DIR="${FLUTTER_ROOT:-$HOME/flutter-ci}"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Flutter installeren naar $FLUTTER_DIR ..."
  rm -rf "$FLUTTER_DIR"
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

# Voorkom interactieve prompts
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"

flutter --version
flutter precache --ios
flutter pub get

cd ios

if ! command -v pod >/dev/null 2>&1; then
  echo "ci_post_clone: CocoaPods ('pod') niet in PATH. Probeer:" >&2
  echo "  sudo gem install cocoapods" >&2
  exit 1
fi

pod install

for f in \
  "Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Release-output-files.xcfilelist" \
  "Pods/Target Support Files/Pods-Runner/Pods-Runner-resources-Release-output-files.xcfilelist"
do
  if [ ! -f "$f" ]; then
    echo "ci_post_clone: verwacht bestand ontbreekt na pod install: $f" >&2
    exit 1
  fi
done

echo "ci_post_clone: klaar (Flutter + Pods)."
