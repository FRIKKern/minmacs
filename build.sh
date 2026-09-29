#!/bin/sh
# Builds a universal MinMacs.app into ./build and installs it to ~/Applications.
# Usage: ./build.sh [--no-install]
set -e
cd "$(dirname "$0")"
APP=build/MinMacs.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
clang -fobjc-arc -O2 -Wall -mmacosx-version-min=13.0 -arch arm64 -arch x86_64 \
  -framework Cocoa -framework ServiceManagement -framework ScriptingBridge -framework IOKit \
  Sources/main.m Sources/Scanner.m Sources/Rules.m Sources/Browser.m Sources/Agents.m -o "$APP/Contents/MacOS/MinMacs"
cp Info.plist "$APP/Contents/"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"
# Harness rows are data: every row that passes the validator ships with the app.
mkdir -p "$APP/Contents/Resources/registry/agents"
for r in registry/agents/*.json; do python3 tools/validate_row.py "$r" >/dev/null 2>&1 && cp "$r" "$APP/Contents/Resources/registry/agents/"; done
codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/MinMacs"))"
[ "$1" = "--no-install" ] && exit 0
mkdir -p ~/Applications ~/.local/bin
rm -rf ~/Applications/MinMacs.app
cp -R "$APP" ~/Applications/
ln -sf ~/Applications/MinMacs.app/Contents/MacOS/MinMacs ~/.local/bin/minmacs
echo "Installed ~/Applications/MinMacs.app and ~/.local/bin/minmacs"
