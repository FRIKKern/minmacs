#!/bin/sh
# Builds MMSettle.app, ad-hoc signed, for macOS 14 and later, with its LaunchAgent plist inside.
# Usage: build.sh [outdir]
set -eu
cd "$(dirname "$0")"
OUT=${1:-${TMPDIR:-/tmp}/minmacs-settling/owner}
APP="$OUT/MMSettle.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents"
clang -fobjc-arc -O2 -Wall -Wextra -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 \
  -framework Cocoa -framework ServiceManagement -framework UserNotifications -framework CoreServices \
  settle.m -o "$APP/Contents/MacOS/MMSettle"
cat >"$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>no.guerrilla.minmacs.settle</string>
<key>CFBundleName</key><string>MMSettle</string>
<key>CFBundleExecutable</key><string>MMSettle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
# The agent runs the same binary in agent-run mode. BundleProgram is relative to the bundle.
cat >"$APP/Contents/Library/LaunchAgents/no.guerrilla.minmacs.settle.agent.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>no.guerrilla.minmacs.settle.agent</string>
<key>BundleProgram</key><string>Contents/MacOS/MMSettle</string>
<key>ProgramArguments</key><array><string>MMSettle</string><string>agent-run</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP" 2>/dev/null
codesign --verify --strict "$APP" && echo "built and verified $APP"
