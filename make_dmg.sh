#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-build/RestNow.app}"
DMG_NAME="RestNow"
FINAL_DMG="${DMG_NAME}.dmg"
BG_IMG="dmg_install_screen.png"

WIN_LEFT="${WIN_LEFT:-200}"
WIN_TOP="${WIN_TOP:-200}"
WIN_RIGHT="${WIN_RIGHT:-1320}"
WIN_BOTTOM="${WIN_BOTTOM:-948}"

APP_ICON_X="${APP_ICON_X:-280}"
APP_ICON_Y="${APP_ICON_Y:-420}"
APPLICATIONS_ICON_X="${APPLICATIONS_ICON_X:-840}"
APPLICATIONS_ICON_Y="${APPLICATIONS_ICON_Y:-420}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$BG_IMG" ]]; then
  echo "Background image not found at: $BG_IMG" >&2
  exit 1
fi

STAGING_DIR="build/dmg-root"
RW_DMG="build/${DMG_NAME}-rw.dmg"
MOUNT_DIR=""

cleanup() {
  set +e
  if [[ -n "${MOUNT_DIR}" && -d "${MOUNT_DIR}" ]]; then
    hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1
  fi
}

trap cleanup EXIT

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -sf /Applications "$STAGING_DIR/Applications"

rm -f "$RW_DMG" "$FINAL_DMG"

hdiutil create \
  -volname "$DMG_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

MOUNT_DIR="$(mktemp -d "/tmp/${DMG_NAME}.XXXX")"

hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -noverify >/dev/null

mkdir -p "$MOUNT_DIR/.background"
cp "$BG_IMG" "$MOUNT_DIR/.background/"

/usr/bin/osascript <<OSA
set dmgName to "${DMG_NAME}"
set bgName to "${BG_IMG}"

tell application "Finder"
  tell disk dmgName
    open
    delay 0.5

    set theWindow to container window
    set current view of theWindow to icon view
    delay 0.5

    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false

    set bounds of theWindow to {${WIN_LEFT}, ${WIN_TOP}, ${WIN_RIGHT}, ${WIN_BOTTOM}}

    set viewOptions to the icon view options of theWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128

    set background picture of viewOptions to file (".background:" & bgName)

    delay 0.5

    set position of item "RestNow.app" of theWindow to {${APP_ICON_X}, ${APP_ICON_Y}}
    set position of item "Applications" of theWindow to {${APPLICATIONS_ICON_X}, ${APPLICATIONS_ICON_Y}}

    close
    open
    delay 0.5
    update without registering applications
  end tell
end tell
OSA

hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL_DMG" >/dev/null

rm -f "$RW_DMG"

echo "Created: $FINAL_DMG"
