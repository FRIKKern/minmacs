#!/bin/sh
# Removes MinMacs.app and its CLI links. The person's data stays unless --purge is given.
#
#   ./uninstall.sh
#   curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/main/uninstall.sh | sh
#
# Options. Each env var also works through a pipe.
#   --prefix DIR   remove from DIR/Applications and DIR/.local/bin. MINMACS_PREFIX. Default: $HOME.
#   --purge        also move the data to the Trash: DIR/Library/Application Support/MinMacs. MINMACS_PURGE=1.
#                  For a real uninstall it also deletes the no.guerrilla.minmacs preferences.
#
# What it removes:
#   <prefix>/Applications/MinMacs.app, and for a real uninstall /Applications/MinMacs.app when it is MinMacs
#   <prefix>/.local/bin/minmacs and locohost, only while they are links into a MinMacs.app
# What it leaves: anything that is not MinMacs, Insomnia's sudoers rule, and the standalone apps.
# Nothing is deleted outright except the app bundle and the links. The data goes to the Trash.
#
# With a prefix other than $HOME the script only removes files under the prefix. It never stops an app
# or changes preferences, so tests run it inside their own folder.
set -u

say() { printf '==> %s\n' "$*"; }
warn() { printf 'note: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

PREFIX="${MINMACS_PREFIX:-$HOME}"
PURGE="${MINMACS_PURGE:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) [ $# -ge 2 ] || die "--prefix needs a folder"; PREFIX="$2"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1. Try --help." ;;
  esac
done
case "$PREFIX" in /*) ;; *) PREFIX="$(pwd -P)/$PREFIX" ;; esac
PREFIX="${PREFIX%/}"
[ -d "$PREFIX" ] || die "the prefix $PREFIX does not exist"
REAL=0; [ "$(cd "$PREFIX" && pwd -P)" = "$(cd "$HOME" && pwd -P)" ] && REAL=1
BUNDLE_ID=no.guerrilla.minmacs
BINDIR="$PREFIX/.local/bin"
SUPPORT="$PREFIX/Library/Application Support/MinMacs"

is_minmacs() { [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ]; }

# 1. Stop a running MinMacs, for a real uninstall only. It turns its login item off first.
if [ "$REAL" = 1 ] && pgrep -x MinMacs >/dev/null 2>&1; then
  say "Asking the running MinMacs to quit"
  open -g "minmacs://login-off" 2>/dev/null; sleep 1
  open -g "minmacs://quit" 2>/dev/null
  n=0; while pgrep -x MinMacs >/dev/null 2>&1 && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
  pgrep -x MinMacs >/dev/null 2>&1 && die "MinMacs is still running. Quit it from its menu, then run this again."
fi

# 2. The links, only while they point into a MinMacs.app.
for name in minmacs locohost; do
  l="$BINDIR/$name"
  [ -L "$l" ] || { [ -e "$l" ] && warn "$l is not a link, so it is left as it is"; continue; }
  case "$(readlink "$l")" in
    */MinMacs.app/Contents/MacOS/MinMacs) rm -f "$l" && say "Removed $l" ;;
    *) warn "$l points to $(readlink "$l"), not MinMacs, so it is left as it is" ;;
  esac
done

# 3. The app.
apps="$PREFIX/Applications/MinMacs.app"
[ "$REAL" = 1 ] && apps="$apps /Applications/MinMacs.app"
for a in $apps; do
  [ -e "$a" ] || continue
  if is_minmacs "$a"; then
    rm -rf "$a" && say "Removed $a"
    if [ "$REAL" = 1 ]; then
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$a" >/dev/null 2>&1
    fi
  else
    warn "$a is not MinMacs, so it is left as it is"
  fi
done

# 4. The data, only when asked. It goes to the Trash, so it can come back.
if [ "$PURGE" = 1 ]; then
  if [ -d "$SUPPORT" ]; then
    TRASH="$PREFIX/.Trash"; mkdir -p "$TRASH"
    to="$TRASH/MinMacs data $(date +%Y-%m-%d\ %H.%M.%S)"
    mv "$SUPPORT" "$to" && say "Moved $SUPPORT to $to"
  fi
  if [ "$REAL" = 1 ]; then
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 && say "Deleted the $BUNDLE_ID preferences"
  fi
else
  [ -d "$SUPPORT" ] && say "Kept your data in $SUPPORT. Run with --purge to move it to the Trash."
fi
say "MinMacs removed."
