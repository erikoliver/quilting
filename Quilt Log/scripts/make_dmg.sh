#!/usr/bin/env zsh
set -euo pipefail

usage() {
  echo "Usage: $0 [path/to/QuiltLog.app] [version]" >&2
  echo "Default app path: dist/QuiltLog.app" >&2
}

if [[ $# -gt 2 ]]; then
  usage
  exit 64
fi

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-"$REPO_ROOT/dist/QuiltLog.app"}"
APP_PATH="${APP_PATH%/}"

if [[ ! -d "$APP_PATH" || "${APP_PATH##*.}" != "app" ]]; then
  echo "error: expected a .app bundle path, got: $APP_PATH" >&2
  exit 66
fi

APP_NAME="$(basename "$APP_PATH" .app)"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: missing Info.plist in app bundle: $INFO_PLIST" >&2
  exit 66
fi

VERSION="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")}"
if [[ -z "$VERSION" ]]; then
  echo "error: could not determine app version" >&2
  exit 65
fi

DIST_DIR="$REPO_ROOT/dist"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg.XXXXXX")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.mount.XXXXXX")"

cleanup() {
  if mount | grep -q "on $MOUNT_DIR "; then
    hdiutil detach "$MOUNT_DIR" >/dev/null || true
  fi
  rm -rf "$STAGING_DIR" "$MOUNT_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"

echo "Checking app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -vv --type execute "$APP_PATH"

echo "Staging DMG contents..."
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

echo "Creating $DMG_PATH..."
hdiutil create \
  -volname "Quilt Log" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Verifying DMG..."
hdiutil verify "$DMG_PATH"

echo "Checking packaged app signature..."
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_DIR" >/dev/null
spctl -a -vv --type execute "$MOUNT_DIR/${APP_NAME}.app"
hdiutil detach "$MOUNT_DIR" >/dev/null

echo "Created: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
