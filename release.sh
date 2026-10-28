#!/bin/sh
# Builds a release on this Mac: the app, its zip, the checksum, the release notes and the Homebrew cask.
# It publishes nothing. It never tags, pushes or calls gh. packaging/README.md has the steps a person takes after it.
#
#   ./release.sh                   the version in Info.plist, into build/release/<version>
#
# Options:
#   --out DIR          the release folder. Default: build/release/<version>.
#   --changelog FILE   the changelog to take the notes from. Default: CHANGELOG.md.
#   --app PATH         package this MinMacs.app instead of building one. release.txt says so. For tests and retries.
#   --no-tests         skip ./test.sh. By default the whole suite runs first and a failure stops the release.
#   --allow-dirty      build from a working tree with changes not committed. release.txt says so.
#   MINMACS_SIGN_HOOK  an executable that signs and notarizes, issue #40. Without it the build stays ad-hoc signed.
#                      It is called as `<hook> sign <app>`, then `<hook> notarize <zip> <app>`.
#
# The release folder holds:
#   MinMacs-<version>.zip          MinMacs.app, made with ditto --keepParent
#   MinMacs-<version>.zip.sha256   shasum -a 256 of the zip, in shasum's format
#   RELEASE_NOTES.md               the version's section of the changelog, with install lines and the checksum
#   minmacs.rb                     packaging/minmacs.rb.in with the version and checksum filled in
#   release.txt                    the version, commit, signing state and architectures, one key=value a line
set -eu
cd "$(dirname "$0")"
ROOT=$(pwd -P)

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

OUT=""; CHANGELOG="$ROOT/CHANGELOG.md"; TESTS=1; DIRTY_OK=0; GIVEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die "--out needs a folder"; OUT="$2"; shift 2 ;;
    --changelog) [ $# -ge 2 ] || die "--changelog needs a file"; CHANGELOG="$2"; shift 2 ;;
    --app) [ $# -ge 2 ] || die "--app needs a path"; GIVEN="$2"; shift 2 ;;
    --no-tests) TESTS=0; shift ;;
    --allow-dirty) DIRTY_OK=1; shift ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1. Try --help." ;;
  esac
done

# 1. The version lives in Info.plist only.
V=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
case "$V" in [0-9]*.[0-9]*.[0-9]*) ;; *) die "Info.plist has version '$V', which is not X.Y.Z" ;; esac
case "$V" in *[!0-9.]*) die "Info.plist has version '$V', which is not X.Y.Z" ;; esac
[ -n "$OUT" ] || OUT="$ROOT/build/release/$V"
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac

# 2. The notes come from the changelog's section for this version.
[ -f "$CHANGELOG" ] || die "no changelog at $CHANGELOG"
SECTION=$(awk -v h="## [$V]" 'index($0, h) == 1 {f = 1; next} f && /^## \[/ {exit} f {print}' "$CHANGELOG")
[ -n "$(printf '%s' "$SECTION" | tr -d '[:space:]')" ] || die "$CHANGELOG has no '## [$V]' section, or it is empty"
DATE=$(grep -m1 -F "## [$V]" "$CHANGELOG" | sed -n 's/.*\] - \([0-9-]*\).*/\1/p')

# 3. The tree the release is built from.
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)
DIRTY=no
[ -z "$(git status --porcelain 2>/dev/null)" ] || DIRTY=yes
if [ "$DIRTY" = yes ] && [ "$DIRTY_OK" = 0 ]; then
  die "the working tree has changes not committed. Commit them, or pass --allow-dirty for a build to try out."
fi

# 4. The tests, unless skipped.
if [ "$TESTS" = 1 ]; then
  say "Running ./test.sh"
  ./test.sh || die "./test.sh failed, so there is no release. --no-tests skips it."
fi

# 5. The build, into the release folder.
# A folder that holds anything but an earlier release is never cleared.
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT")" ] && [ ! -f "$OUT/release.txt" ]; then
  die "$OUT holds files that are not a release. Give --out an empty or new folder."
fi
rm -rf "$OUT"; mkdir -p "$OUT"
APP="$OUT/build/MinMacs.app"
if [ -n "$GIVEN" ]; then
  [ -x "$GIVEN/Contents/MacOS/MinMacs" ] || die "$GIVEN is not a MinMacs.app"
  say "Packaging $GIVEN"
  mkdir -p "$OUT/build" && ditto "$GIVEN" "$APP"
  SOURCE="given: $GIVEN"
else
  say "Building MinMacs $V"
  BUILD_DIR="$OUT/build" ./build.sh --no-install >/dev/null || die "build.sh failed"
  SOURCE=build.sh
fi
[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")" = "$V" ] \
  || die "the built app does not say version $V"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/MinMacs")

# 6. Signing and notarizing, issue #40. Only through the hook.
HOOK="${MINMACS_SIGN_HOOK:-}"
SIGNING="ad-hoc, not notarized"
if [ -n "$HOOK" ]; then
  [ -x "$HOOK" ] || die "MINMACS_SIGN_HOOK=$HOOK is not an executable"
  say "Signing through $HOOK"
  "$HOOK" sign "$APP" || die "the signing hook failed"
  codesign --verify --deep --strict "$APP" 2>/dev/null || die "the signed app fails codesign --verify --strict"
fi

ZIP="MinMacs-$V.zip"
zipit() { rm -f "$OUT/$ZIP"; ditto -c -k --keepParent "$APP" "$OUT/$ZIP" || die "ditto could not zip the app"; }
zipit

if [ -n "$HOOK" ]; then
  say "Notarizing through $HOOK"
  "$HOOK" notarize "$OUT/$ZIP" "$APP" || die "the notarizing hook failed"
  codesign --verify --deep --strict "$APP" 2>/dev/null || die "the notarized app fails codesign --verify --strict"
  zipit   # again, so the zip holds the stapled app
  SIGNING="signed and notarized through the hook"
fi

# 7. The checksum, in shasum's own format, so shasum -c checks it.
(cd "$OUT" && shasum -a 256 "$ZIP" > "$ZIP.sha256")
SHA=$(awk '{print $1}' "$OUT/$ZIP.sha256")

# 8. A check of the zip itself: it unpacks to the same app.
CHECK=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-release-check.XXXXXX")
ditto -x -k "$OUT/$ZIP" "$CHECK" || { rm -rf "$CHECK"; die "the zip does not unpack"; }
got=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CHECK/MinMacs.app/Contents/Info.plist" 2>/dev/null)
codesign --verify "$CHECK/MinMacs.app" 2>/dev/null; signed=$?
rm -rf "$CHECK"
[ "$got" = "$V" ] || die "the zip holds version '$got', not $V"
[ "$signed" = 0 ] || die "the app in the zip fails codesign --verify"

# 9. The release notes.
if [ "$SIGNING" = "ad-hoc, not notarized" ]; then
  CAVEAT="MinMacs is ad-hoc signed and not notarized yet, so macOS blocks the first open. Open it once, then choose Open Anyway in System Settings, Privacy and Security."
else
  CAVEAT="MinMacs is signed with a Developer ID and notarized."
fi
{
  printf '# MinMacs %s\n\n' "$V"
  [ -n "$DATE" ] && printf 'Released %s.\n\n' "$DATE"
  printf '%s\n' "$SECTION" | sed -e '/./,$!d'
  printf '\n## Install\n\n'
  printf 'With Homebrew: `brew install --cask frikkern/tap/minmacs`.\n\n'
  printf 'From the zip: download `%s` and `%s.sha256` into one folder, then run `./install.sh --zip %s` from a checkout of this tag.\n\n' "$ZIP" "$ZIP" "$ZIP"
  printf 'From source: `curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/v%s/install.sh | MINMACS_REF=v%s sh`.\n\n' "$V" "$V"
  printf '%s\n\n' "$CAVEAT"
  printf 'SHA-256 of `%s`: `%s`\n' "$ZIP" "$SHA"
} > "$OUT/RELEASE_NOTES.md"

# 10. The cask for the tap.
sed -e "s|@VERSION@|$V|g" -e "s|@SHA256@|$SHA|g" -e "s|@SIGNING_CAVEAT@|$CAVEAT|g" \
  packaging/minmacs.rb.in > "$OUT/minmacs.rb"
grep -q '@[A-Z0-9_]*@' "$OUT/minmacs.rb" && die "packaging/minmacs.rb.in has a placeholder release.sh does not fill"

# 11. What was built, for the person who publishes it.
{
  printf 'version=%s\n' "$V"
  printf 'commit=%s\n' "$COMMIT"
  printf 'uncommitted_changes=%s\n' "$DIRTY"
  printf 'source=%s\n' "$SOURCE"
  printf 'archs=%s\n' "$ARCHS"
  printf 'signing=%s\n' "$SIGNING"
  printf 'tests=%s\n' "$([ "$TESTS" = 1 ] && echo passed || echo skipped)"
  printf 'zip=%s\n' "$ZIP"
  printf 'sha256=%s\n' "$SHA"
  printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/release.txt"
rm -rf "$OUT/build"

say "Release $V is in $OUT"
say "Nothing was published. packaging/README.md lists the steps: tag v$V, make the GitHub release, copy minmacs.rb into the tap."
