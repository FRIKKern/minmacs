#!/bin/sh
# Builds MMXPCProbe.app with an embedded XPC service, ad-hoc signed, for macOS 14 and later.
# Usage: build.sh [outdir]. Then run: <outdir>/MMXPCProbe.app/Contents/MacOS/host <fixture folder>
set -eu
cd "$(dirname "$0")"
OUT=${1:-${TMPDIR:-/tmp}/minmacs-settling/xpc}
APP="$OUT/MMXPCProbe.app"
SVC="$APP/Contents/XPCServices/MMProbeWorker.xpc"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$SVC/Contents/MacOS"
F="-fobjc-arc -O2 -Wall -Wextra -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 -framework Foundation"
# shellcheck disable=SC2086
clang $F host.m -o "$APP/Contents/MacOS/host"
# shellcheck disable=SC2086
clang $F worker.m -o "$SVC/Contents/MacOS/MMProbeWorker"
cat >"$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>no.guerrilla.minmacs.probe</string>
<key>CFBundleExecutable</key><string>host</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
cat >"$SVC/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>no.guerrilla.minmacs.probe.worker</string>
<key>CFBundleExecutable</key><string>MMProbeWorker</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>XPCService</key><dict><key>ServiceType</key><string>Application</string></dict>
</dict></plist>
P
# Sign inside out: the service first, then the bundle that holds it.
codesign --force --sign - "$SVC"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "built and verified $APP"
