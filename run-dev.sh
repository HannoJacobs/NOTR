#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NOTR"
BUILD_DIR="$SCRIPT_DIR/build-dev"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
BINARY_SRC=""

cd "$SCRIPT_DIR"

note() { echo "==> $*"; }

note "Building $APP_NAME"
swift build -c debug

BINARY_SRC="$(swift build -c debug --show-bin-path)/$APP_NAME"
[ -x "$BINARY_SRC" ] || { echo "Missing binary at $BINARY_SRC" >&2; exit 1; }

if [ ! -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    note "Generating AppIcon.icns"
    swift "$SCRIPT_DIR/make-icon.swift" "$SCRIPT_DIR/AppIcon.icns"
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    note "Stopping running $APP_NAME"
    pkill -x "$APP_NAME" || true
    sleep 0.5
fi

note "Assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
ditto "$BINARY_SRC" "$APP_PATH/Contents/MacOS/$APP_NAME"
ditto "$SCRIPT_DIR/Sources/NOTR/Info.plist" "$APP_PATH/Contents/Info.plist"
ditto "$SCRIPT_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"

note "Ad-hoc signing"
codesign --force --deep --sign - "$APP_PATH"

note "Launching $APP_PATH"
open "$APP_PATH"
echo "NOTR is running as a menu bar app (note.text icon). Click it to pin files."
