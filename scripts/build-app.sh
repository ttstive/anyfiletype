#!/bin/sh
# Builds FileFlip.app. Pass --install to copy it to /Applications and launch it.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
APP=build/FileFlip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FileFlip "$APP/Contents/MacOS/FileFlip"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature: enough to run locally, not for distribution.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    # /Applications puts it in Launchpad; fall back to ~/Applications if that isn't writable.
    DEST=/Applications
    [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
    pkill -x FileFlip 2>/dev/null || true
    sleep 0.5
    rm -rf "$DEST/FileFlip.app"
    cp -R "$APP" "$DEST/"
    # Refresh Finder/Dock icon caches and register the app for "Open With".
    touch "$DEST/FileFlip.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/FileFlip.app" 2>/dev/null || true
    open "$DEST/FileFlip.app"
    echo "Installed to $DEST/FileFlip.app"
fi
