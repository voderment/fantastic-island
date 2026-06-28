#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FantasticIsland/FantasticIsland.xcodeproj"
SCHEME="FantasticIsland"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"

APP_SOURCE="${1:-}"
OUTPUT_DIR="${2:-$ROOT_DIR/dist}"

VOLUME_NAME="${DMG_VOLUME_NAME:-Fantastic Island}"
DMG_NAME="${DMG_NAME:-Fantastic-Island}"
APP_BUNDLE_NAME="${DMG_APP_BUNDLE_NAME:-Fantastic Island.app}"

WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-760}"
WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-460}"
ICON_SIZE="${DMG_ICON_SIZE:-144}"
APP_ICON_X="${DMG_APP_ICON_X:-205}"
APP_ICON_Y="${DMG_APP_ICON_Y:-260}"
APPS_ICON_X="${DMG_APPS_ICON_X:-555}"
APPS_ICON_Y="${DMG_APPS_ICON_Y:-260}"

if [[ "$APP_BUNDLE_NAME" != *.app ]]; then
    APP_BUNDLE_NAME="$APP_BUNDLE_NAME.app"
fi

if [[ -z "$APP_SOURCE" ]]; then
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
        build
    APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/FantasticIsland.app"
fi

if [[ ! -d "$APP_SOURCE" ]]; then
    echo "App bundle not found: $APP_SOURCE" >&2
    echo "Usage: scripts/create-dmg.sh [path/to/FantasticIsland.app] [output-dir]" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fantastic-island-dmg.XXXXXX")"
RW_DMG="$TEMP_DIR/$DMG_NAME-rw.dmg"
FINAL_DMG="$OUTPUT_DIR/$DMG_NAME.dmg"
MOUNT_POINT=""

cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ -e "/Volumes/$VOLUME_NAME" ]]; then
    echo "A volume named '$VOLUME_NAME' is already mounted. Eject it before creating the DMG." >&2
    exit 1
fi

APP_KB="$(du -sk "$APP_SOURCE" | awk '{print $1}')"
DMG_SIZE="${DMG_SIZE:-$((APP_KB / 1024 + 96))m}"

rm -f "$FINAL_DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -size "$DMG_SIZE" \
    "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk 'index($0, "/Volumes/") {print substr($0, index($0, "/Volumes/")); exit}')"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
    echo "Unable to mount temporary DMG." >&2
    exit 1
fi

ditto "$APP_SOURCE" "$MOUNT_POINT/$APP_BUNDLE_NAME"
ln -s /Applications "$MOUNT_POINT/Applications"

VOLUME_NAME_AS="${VOLUME_NAME//\"/\\\"}"
APP_BUNDLE_NAME_AS="${APP_BUNDLE_NAME//\"/\\\"}"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME_AS"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 120, 120 + $WINDOW_WIDTH, 120 + $WINDOW_HEIGHT}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 13
        set label position of viewOptions to bottom

        set position of item "$APP_BUNDLE_NAME_AS" of container window to {$APP_ICON_X, $APP_ICON_Y}
        set position of item "Applications" of container window to {$APPS_ICON_X, $APPS_ICON_Y}

        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

echo "Created $FINAL_DMG"
