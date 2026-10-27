#!/bin/sh
# Builds a universal MinMacs.app from every .m under Sources/.
# Usage: ./build.sh [--install | --no-install]
#   BUILD_DIR=dir    output folder, default build. Give each parallel build its own.
#   --install        also installs ~/Applications/MinMacs.app and ~/.local/bin/minmacs.
#                    The default is no install, so a 2.0 build never replaces an installed 1.2.
# A compiler warning fails the build.
set -eu
cd "$(dirname "$0")"
INSTALL=0
for a in "$@"; do
  case "$a" in
    --install) INSTALL=1 ;;
    --no-install) INSTALL=0 ;;
    *) echo "usage: ./build.sh [--install | --no-install]" >&2; exit 2 ;;
  esac
done
BUILD_DIR="${BUILD_DIR:-build}"
APP="$BUILD_DIR/MinMacs.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Sorted, so the link order is the same on every machine. Source paths must not hold spaces.
SOURCES=$(find Sources -name '*.m' | LC_ALL=C sort)
LOG="$BUILD_DIR/clang.log"
# shellcheck disable=SC2086
if ! clang -fobjc-arc -O2 -Wall -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 \
    -ISources -DMM_VERSION="\"$VERSION\"" \
    -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications \
    -framework QuartzCore -lsqlite3 \
    $SOURCES -o "$APP/Contents/MacOS/MinMacs" >"$LOG" 2>&1; then
  cat "$LOG" >&2; echo "build failed" >&2; exit 1
fi
if grep -q "warning:" "$LOG"; then
  cat "$LOG" >&2; echo "build has warnings; fix them" >&2; exit 1
fi

cp Info.plist "$APP/Contents/"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"
# Registry rows are data: every row that passes the validator ships with the app.
mkdir -p "$APP/Contents/Resources/registry/agents"
for r in registry/agents/*.json; do
  python3 tools/validate_row.py "$r" >/dev/null 2>&1 && cp "$r" "$APP/Contents/Resources/registry/agents/"
done
# Clutter rows are data too. test/noonoo checks each one against registry/clutter-schema.json.
mkdir -p "$APP/Contents/Resources/registry/clutter"
cp registry/clutter/*.json "$APP/Contents/Resources/registry/clutter/"
codesign --force --sign - "$APP" 2>/dev/null
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/MinMacs"))"
[ "$INSTALL" = 1 ] || exit 0

mkdir -p ~/Applications ~/.local/bin
rm -rf ~/Applications/MinMacs.app
cp -R "$APP" ~/Applications/
ln -sf ~/Applications/MinMacs.app/Contents/MacOS/MinMacs ~/.local/bin/minmacs
# URLs such as minmacs://quit must reach the installed app, not the copy in the build folder.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
case "$APP" in /*) ABS="$APP" ;; *) ABS="$PWD/$APP" ;; esac
"$LSREG" -u "$ABS" >/dev/null 2>&1 || true
"$LSREG" -f ~/Applications/MinMacs.app >/dev/null 2>&1 || true
echo "Installed ~/Applications/MinMacs.app and ~/.local/bin/minmacs"
