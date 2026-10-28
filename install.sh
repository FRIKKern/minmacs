#!/bin/sh
# Installs MinMacs.app into <prefix>/Applications and links its CLI in <prefix>/.local/bin.
#
#   ./install.sh                             in a checkout: builds it with build.sh, then installs that build
#   ./install.sh --app build/MinMacs.app     installs a build that already exists
#   ./install.sh --zip MinMacs-2.0.0.zip     installs a release zip from release.sh, checked against its .sha256 file
#   curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/main/install.sh | sh
#                                            fetches MINMACS_REF, builds it and installs it
#
# Options. Each env var also works through a pipe.
#   --prefix DIR      install into DIR/Applications and DIR/.local/bin. MINMACS_PREFIX. Default: $HOME.
#   --sha256 HEX      the zip's checksum, when no <zip>.sha256 file sits next to it.
#   --no-checksum     install a zip that has no checksum.
#   --no-launch       install only. MINMACS_NO_LAUNCH=1.
#   --login           also register Launch at Login. MINMACS_LOGIN=1.
#   MINMACS_REF=v2.0.0  the git ref a piped install fetches. Default: legacy, the 1.x line, until 2.0 ships.
#
# What it installs:
#   <prefix>/Applications/MinMacs.app
#   <prefix>/.local/bin/minmacs    a link to the app's binary
#   <prefix>/.local/bin/locohost   a link to the same binary, for a 2.x app. Run under that name it takes LocoHost 1.x commands.
# A locohost that is a file and not a link is left as it is, and the script says so.
#
# With a prefix other than $HOME the script only copies and links. It never stops, launches or registers an app,
# so tests run it inside their own folder.
set -eu

say() { printf '==> %s\n' "$*"; }
warn() { printf 'note: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

PREFIX="${MINMACS_PREFIX:-$HOME}"
NO_LAUNCH="${MINMACS_NO_LAUNCH:-0}"
LOGIN="${MINMACS_LOGIN:-0}"
REF="${MINMACS_REF:-legacy}"
REPO="https://github.com/FRIKKern/minmacs"
SRC_APP=""; SRC_ZIP=""; SHA=""; NO_SUM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) [ $# -ge 2 ] || die "--prefix needs a folder"; PREFIX="$2"; shift 2 ;;
    --app) [ $# -ge 2 ] || die "--app needs a path"; SRC_APP="$2"; shift 2 ;;
    --zip) [ $# -ge 2 ] || die "--zip needs a path"; SRC_ZIP="$2"; shift 2 ;;
    --sha256) [ $# -ge 2 ] || die "--sha256 needs a checksum"; SHA="$2"; shift 2 ;;
    --no-checksum) NO_SUM=1; shift ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    --login) LOGIN=1; shift ;;
    -h|--help) sed -n '2,26p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1. Try --help." ;;
  esac
done
[ -n "$SRC_APP" ] && [ -n "$SRC_ZIP" ] && die "give --app or --zip, not both"

[ "$(uname -s)" = Darwin ] || die "MinMacs is a macOS app."
case "$PREFIX" in /*) ;; *) PREFIX="$(pwd -P)/$PREFIX" ;; esac
PREFIX="${PREFIX%/}"
[ -d "$PREFIX" ] || die "the prefix $PREFIX does not exist"
REAL=0; [ "$(cd "$PREFIX" && pwd -P)" = "$(cd "$HOME" && pwd -P)" ] && REAL=1
APPS="$PREFIX/Applications"; BINDIR="$PREFIX/.local/bin"; DEST="$APPS/MinMacs.app"
BUNDLE_ID=no.guerrilla.minmacs

TMP=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-install.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

# 1. The app to install.
if [ -n "$SRC_ZIP" ]; then
  [ -f "$SRC_ZIP" ] || die "no zip at $SRC_ZIP"
  if [ -z "$SHA" ] && [ -f "$SRC_ZIP.sha256" ]; then SHA=$(awk '{print $1; exit}' "$SRC_ZIP.sha256"); fi
  if [ -n "$SHA" ]; then
    got=$(shasum -a 256 "$SRC_ZIP" | awk '{print $1}')
    [ "$got" = "$SHA" ] || die "checksum mismatch for $SRC_ZIP: got $got, want $SHA"
    say "Checksum matches"
  elif [ "$NO_SUM" = 1 ]; then
    warn "installing $SRC_ZIP with no checksum"
  else
    die "no checksum for $SRC_ZIP. Put $SRC_ZIP.sha256 next to it, pass --sha256, or pass --no-checksum."
  fi
  mkdir "$TMP/zip"
  ditto -x -k "$SRC_ZIP" "$TMP/zip" || die "could not unzip $SRC_ZIP"
  [ -d "$TMP/zip/MinMacs.app" ] || die "$SRC_ZIP holds no MinMacs.app at its top"
  SRC_APP="$TMP/zip/MinMacs.app"
elif [ -z "$SRC_APP" ]; then
  HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || echo "")
  if [ -n "$HERE" ] && [ -f "$HERE/build.sh" ] && [ -d "$HERE/Sources" ]; then
    say "Building this checkout"
    BUILD_DIR="$TMP/build" sh "$HERE/build.sh" --no-install >/dev/null || die "build.sh failed"
    SRC_APP="$TMP/build/MinMacs.app"
  else
    xcode-select -p >/dev/null 2>&1 && command -v clang >/dev/null 2>&1 \
      || die "the Command Line Tools are missing. Run xcode-select --install, then this script again."
    say "Fetching $REPO@$REF"
    mkdir "$TMP/src"
    curl -fsSL "$REPO/archive/$REF.tar.gz" | tar -xz -C "$TMP/src" --strip-components=1 || die "could not fetch $REF"
    say "Building"
    (cd "$TMP/src" && sh build.sh --no-install >/dev/null) || die "build.sh failed"
    SRC_APP="$TMP/src/build/MinMacs.app"
  fi
fi

[ -x "$SRC_APP/Contents/MacOS/MinMacs" ] || die "$SRC_APP is not a MinMacs.app"
[ "$(plist "$SRC_APP" CFBundleIdentifier)" = "$BUNDLE_ID" ] || die "$SRC_APP is not MinMacs: its bundle id is not $BUNDLE_ID"
codesign --verify "$SRC_APP" 2>/dev/null || die "$SRC_APP fails codesign --verify"
VERSION=$(plist "$SRC_APP" CFBundleShortVersionString)
MAJOR=${VERSION%%.*}
FLOOR=$(plist "$SRC_APP" LSMinimumSystemVersion); FLOOR=${FLOOR%%.*}
OS=$(sw_vers -productVersion | cut -d. -f1)
[ -z "$FLOOR" ] || [ "$OS" -ge "$FLOOR" ] || die "MinMacs $VERSION needs macOS $FLOOR or newer. This Mac runs $(sw_vers -productVersion)."

# 2. Stop a running MinMacs, for a real install only.
if [ "$REAL" = 1 ] && pgrep -x MinMacs >/dev/null 2>&1; then
  say "Asking the running MinMacs to quit"
  open -g "minmacs://quit" 2>/dev/null || true
  n=0; while pgrep -x MinMacs >/dev/null 2>&1 && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
  pgrep -x MinMacs >/dev/null 2>&1 && die "MinMacs is still running. Quit it from its menu, then run this again."
fi

# 3. The app. A new copy goes in beside the old one, then takes its place.
if [ -e "$DEST" ]; then
  [ "$(plist "$DEST" CFBundleIdentifier)" = "$BUNDLE_ID" ] || die "$DEST is not MinMacs, so it is left as it is"
fi
mkdir -p "$APPS"
NEW="$APPS/.MinMacs.app.new.$$"; OLD="$APPS/.MinMacs.app.old.$$"
rm -rf "$NEW"
ditto "$SRC_APP" "$NEW"
[ -e "$DEST" ] && mv "$DEST" "$OLD"
mv "$NEW" "$DEST"
rm -rf "$OLD"
say "Installed MinMacs $VERSION at $DEST"

# 4. The links. Only a link is replaced, never a file.
BIN="$DEST/Contents/MacOS/MinMacs"
mkdir -p "$BINDIR"
link() {
  if [ -e "$BINDIR/$1" ] && [ ! -L "$BINDIR/$1" ]; then
    warn "$BINDIR/$1 is a file, not a link, so it is left as it is. Remove it and run this again to link $1."
    return 0
  fi
  ln -sfh "$BIN" "$BINDIR/$1"
  say "Linked $BINDIR/$1"
}
link minmacs
if [ "$MAJOR" -ge 2 ] 2>/dev/null; then link locohost; fi
"$BINDIR/minmacs" version >/dev/null 2>&1 || die "$BINDIR/minmacs version failed"
case ":$PATH:" in *":$BINDIR:"*) ;; *) [ "$REAL" = 1 ] && warn "$BINDIR is not on your PATH" ;; esac

# 5. Launch, for a real install only.
[ "$REAL" = 1 ] || { say "Installed under $PREFIX. Nothing was launched."; exit 0; }
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$DEST" >/dev/null 2>&1 || true
[ "$NO_LAUNCH" = 1 ] && { say "Launch it with: open $DEST"; exit 0; }
say "Launching"
open "$DEST"
if [ "$LOGIN" = 1 ]; then
  sleep 2; open -g "minmacs://login-on"
  say "Asked for Launch at Login. macOS may ask you to approve it once."
fi
say "Done. Try: minmacs status"
