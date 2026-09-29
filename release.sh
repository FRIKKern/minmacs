#!/bin/sh
# Cuts a release: ./release.sh 1.2.0
# Requires a CHANGELOG entry, builds, runs the test suite against the installed app,
# bumps Info.plist, commits, tags, pushes. CI attaches the zip; the tap bumps itself.
set -eu
cd "$(dirname "$0")"
V="${1:-}"; case "$V" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "usage: ./release.sh X.Y.Z" >&2; exit 2;; esac
[ "$(git branch --show-current)" = "main" ] || { echo "release from main only" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }
git pull -q --ff-only
grep -q "^## \[$V\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$V]' section" >&2; exit 1; }
BUILD=$(echo "$V" | awk -F. '{printf "%d%02d%02d", $1, $2, $3}')
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" -c "Set :CFBundleVersion $BUILD" Info.plist
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  sh build.sh >/dev/null
  open "minmacs://quit" 2>/dev/null || true; sleep 1; open "$HOME/Applications/MinMacs.app"; sleep 2
  ./test.sh || { git checkout Info.plist; echo "test.sh failed; not releasing (SKIP_TESTS=1 to override)" >&2; exit 1; }
fi
git diff --quiet Info.plist || { git add Info.plist && git commit -q -m "Release $V"; }
git tag -a "v$V" -m "MinMacs $V"
git push -q origin main "v$V"
echo "Released v$V. Watch: gh run watch --repo FRIKKern/minmacs"
echo "Tap bump runs on schedule, or now: gh workflow run bump-formulas.yml --repo FRIKKern/homebrew-tap"
