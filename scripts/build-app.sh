#!/bin/sh
# Builds FileFlip.app. Pass --install to copy it to ~/Applications and launch it.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
APP=build/FileFlip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FileFlip "$APP/Contents/MacOS/FileFlip"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: enough to run locally, not for distribution.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    pkill -x FileFlip 2>/dev/null || true
    rm -rf "$HOME/Applications/FileFlip.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/FileFlip.app"
    echo "Installed to ~/Applications/FileFlip.app"
fi
