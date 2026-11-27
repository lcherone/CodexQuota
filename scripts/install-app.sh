#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

DESTINATION="$HOME/Applications"
BUILD=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=false; shift ;;
    --destination)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--destination needs a directory." >&2; exit 1; }
      DESTINATION="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--no-build] [--destination directory]"
      echo "Build and install CodexQuota.app in ~/Applications (no administrator access needed)."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if /usr/bin/pgrep -x CodexQuota >/dev/null; then
  echo "Quit Codex Quota before installing or updating it." >&2
  exit 1
fi
if $BUILD; then
  ./scripts/build-app.sh
fi

APP="$PWD/build/CodexQuota.app"
codesign --verify --strict "$APP"
mkdir -p "$DESTINATION"
DESTINATION="$(cd "$DESTINATION" && pwd -P)"
TARGET="$DESTINATION/CodexQuota.app"
if [[ "$TARGET" == "$APP" ]]; then
  echo "Choose an installation directory outside build/." >&2
  exit 1
fi
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  if [[ -L "$TARGET" ]] || [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)" != "dev.codexquota.CodexQuota" ]]; then
    echo "Refusing to replace a different app or symlink at $TARGET." >&2
    exit 1
  fi
fi

STAGING="$(mktemp -d "$DESTINATION/.codexquota-install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/CodexQuota.app"
codesign --verify --strict "$STAGING/CodexQuota.app"
if [[ -e "$TARGET" ]]; then
  mv "$TARGET" "$STAGING/Previous.app"
fi
if ! mv "$STAGING/CodexQuota.app" "$TARGET"; then
  if [[ -e "$STAGING/Previous.app" ]]; then
    if ! mv "$STAGING/Previous.app" "$TARGET"; then
      trap - EXIT
      echo "The previous app is preserved at $STAGING/Previous.app." >&2
    fi
  fi
  exit 1
fi
echo "Installed: $TARGET"
echo "Open it in Finder, then enable Launch at login in the panel to start automatically."
