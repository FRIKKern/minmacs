#!/bin/sh
# The canary loop for MinMacs: build, gate fast, install, check it lives, roll back if not, and share the build.
# For rapid iteration on development and fleet Macs. The gate tests the blast radius: the sections the changed files
# reach. Every MINMACS_FULL_EVERY seconds (default 7200, two hours) the next gate runs every section but soak instead.
#
# On any Mac, no checkout needed:
#   canary.sh update            install the newest published canary, if it is not the one running; roll back if it
#                               does not come up
#   canary.sh status            what runs here, and what the newest published canary is
#   canary.sh rollback          install the build that ran before this one
#   canary.sh list              the builds kept here, newest first
# In a checkout:
#   canary.sh                   build this checkout, gate, install here, health check (roll back on failure)
#   canary.sh publish           the same, then upload the healthy build as the canary everyone's update gets
#   options: --no-gate, --full (every section but soak now), --quick (the blast radius even when a full run is due),
#            --base <ref> (what the gate diffs against; default the commit that runs here, else origin/main; a publish
#            diffs against the newest published canary, so what it shares was tested since the last one)
#
# A build is stamped CFBundleVersion <version>+<commit>[-dirty] and signed ad hoc again, so the commit that runs is
# always known. The newest 5 builds are kept in $MINMACS_CANARY_HOME (default ~/.local/share/minmacs-canary), with a
# log line per run in canary.log. Heavy steps run under nice. Published canaries are the GitHub prerelease "canary"
# of $MINMACS_CANARY_REPO (default FRIKKern/minmacs): MinMacs-canary.zip, its .sha256, build.json, install.sh and this
# script, so a Mac with nothing on it starts with:
#   curl -fsSL https://github.com/FRIKKern/minmacs/releases/download/canary/canary.sh | sh -s update
set -eu

REPO="${MINMACS_CANARY_REPO:-FRIKKern/minmacs}"
TAG=canary
HOME_DIR="${MINMACS_CANARY_HOME:-$HOME/.local/share/minmacs-canary}"
LOG="$HOME_DIR/canary.log"
KEEP=5
BIN="$HOME/.local/bin/minmacs"
APPS="$HOME/Applications/MinMacs.app"
say() { printf '==> %s\n' "$*"; }
die() { printf 'canary: %s\n' "$*" >&2; exit 1; }
mkdir -p "$HOME_DIR/builds"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
logline() { printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG"; }
# The app's own process: started by launchd from ~/Applications, not a CLI run or its _walk helper.
running_pid() { ps -axo pid=,ppid=,comm= | awk -v app="$APPS/Contents/MacOS/MinMacs" '$2 == 1 && $3 == app { print $1; exit }'; }
installed_stamp() { plist "$APPS" CFBundleVersion || true; }
cost_line() {
  "$BIN" self --window 10 --json 2>/dev/null | python3 -I -c 'import sys,json; j=json.load(sys.stdin); print("cpu now %.2f %%, footprint %.0f MB, over: %s" % (j["now"]["cpuPercent"], j["memory"]["footprintBytes"]/1048576, ",".join(j["over"]) or "none"))' 2>/dev/null \
    || echo "no self verb in this build"
}

# Installs a kept build with the install.sh that came with it: it quits the running app, swaps the new one in
# atomically, links the CLI and launches it.
install_kept() {   # $1: the build's folder, holding MinMacs.app and install.sh
  sh "$1/install.sh" --app "$1/MinMacs.app" >"$HOME_DIR/install.out" 2>&1 || { cat "$HOME_DIR/install.out" >&2; return 1; }
}

# Up within 30 s, then 60 s with the same pid, so a crash or a crash loop shows. Prints "ok <pid>" or why not.
health() {
  want="$1"; pid=""; n=0
  while [ -z "$pid" ] && [ $n -lt 30 ]; do pid=$(running_pid); [ -n "$pid" ] || { sleep 1; n=$((n + 1)); }; done
  [ -n "$pid" ] || { echo "no app came up in 30 s"; return 1; }
  have=$(installed_stamp)
  [ "$have" = "$want" ] || { echo "the installed app is $have, not $want"; return 1; }
  sleep 60
  now=$(running_pid)
  [ "$now" = "$pid" ] || { echo "the app did not stay up: pid $pid, then ${now:-none}"; return 1; }
  echo "ok $pid"
}

keep_newest() { ls -1t "$HOME_DIR/builds" | sed -n "$((KEEP + 1)),\$p" | while read -r old; do rm -rf "${HOME_DIR:?}/builds/$old"; done; }

# Installs the build in $1, checks it, and rolls back to the one that ran before when the check fails.
install_checked() {   # $1: the build's folder, $2: its stamp, $3: what the log says it came from
  prev=$(ls -1t "$HOME_DIR/builds" | grep -v "^$(basename "$1")$" | head -1 || true)
  say "Installing $2"
  install_kept "$1" || { logline "$2	$3	install failed"; die "the install failed"; }
  say "Health check: up within 30 s, then 60 s without a restart"
  if h=$(health "$2"); then
    touch "$1"; keep_newest
    c=$(cost_line)
    logline "$2	$3	health: $h	$c"
    say "Running $2 ($h). $c."
    return 0
  fi
  logline "$2	$3	health failed: $h	rolling back"
  say "Health check failed: $h."
  rm -rf "$1"
  if [ -n "$prev" ]; then
    say "Rolling back to $prev"
    install_kept "$HOME_DIR/builds/$prev" && touch "$HOME_DIR/builds/$prev" && logline "rollback to $prev"
  fi
  return 1
}

download() {   # $1: asset name, $2: where to
  if command -v gh >/dev/null 2>&1; then gh release download "$TAG" -R "$REPO" -p "$1" -O "$2" --clobber >/dev/null 2>&1 && return 0; fi
  curl -fsSL "https://github.com/$REPO/releases/download/$TAG/$1" -o "$2" 2>/dev/null
}

case "${1:-}" in
  status)
    echo "Running here:      $(installed_stamp || echo none) (pid $(running_pid || true))"
    t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
    if download build.json "$t/build.json"; then
      python3 -I -c 'import sys,json; j=json.load(open(sys.argv[1])); print("Newest canary:     %s, %s, from %s, published %s" % (j["stamp"], j["subject"], j["branch"], j["published"]))' "$t/build.json"
    else echo "Newest canary:     none published"; fi
    exit 0 ;;
  list)
    cur=$(installed_stamp)
    for b in $(ls -1t "$HOME_DIR/builds" 2>/dev/null); do
      v=$(plist "$HOME_DIR/builds/$b/MinMacs.app" CFBundleVersion)
      if [ "$v" = "$cur" ]; then echo "* $v"; else echo "  $v"; fi
    done
    exit 0 ;;
  rollback)
    prev=$(ls -1t "$HOME_DIR/builds" 2>/dev/null | sed -n 2p)
    [ -n "$prev" ] || die "no earlier build is kept"
    say "Rolling back to $prev"
    install_kept "$HOME_DIR/builds/$prev" || die "the install failed"
    touch "$HOME_DIR/builds/$prev"
    h=$(health "$(plist "$HOME_DIR/builds/$prev/MinMacs.app" CFBundleVersion)") || true
    logline "rollback	$prev	health: $h"
    say "Now running $prev ($h)"
    exit 0 ;;
  update)
    t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
    say "Looking for the newest canary of $REPO"
    download build.json "$t/build.json" || die "no canary is published"
    stamp=$(python3 -I -c 'import sys,json; print(json.load(open(sys.argv[1]))["stamp"])' "$t/build.json")
    [ "$stamp" = "$(installed_stamp)" ] && { say "Already running the newest canary, $stamp."; exit 0; }
    for f in MinMacs-canary.zip MinMacs-canary.zip.sha256 install.sh; do download "$f" "$t/$f" || die "could not download $f"; done
    want=$(awk '{print $1; exit}' "$t/MinMacs-canary.zip.sha256"); got=$(shasum -a 256 "$t/MinMacs-canary.zip" | awk '{print $1}')
    [ "$want" = "$got" ] || die "checksum mismatch: got $got, want $want. Nothing was installed."
    out="$HOME_DIR/builds/$(echo "$stamp" | tr '+' '-')-$(date +%H%M%S)"; mkdir -p "$out"
    ditto -x -k "$t/MinMacs-canary.zip" "$out" && cp "$t/install.sh" "$out/install.sh"
    [ "$(plist "$out/MinMacs.app" CFBundleVersion)" = "$stamp" ] || die "the zip does not hold $stamp"
    install_checked "$out" "$stamp" "update" || exit 1
    exit 0 ;;
esac

# ---- Build from a checkout ----
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "run it inside a MinMacs checkout, or use update"
[ -f build.sh ] && [ -d Sources ] || die "$(pwd) is not a MinMacs checkout"
PUBLISH=0; [ "${1:-}" = publish ] && { PUBLISH=1; shift; }
GATE=1; BASE=""; FULL=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --no-gate) GATE=0; shift ;;
    --full) FULL=yes; shift ;;
    --quick) FULL=no; shift ;;
    --base) [ $# -ge 2 ] || die "--base needs a ref"; BASE="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1. Try --help." ;;
  esac
done
[ "$PUBLISH" = 1 ] && [ "$GATE" = 0 ] && die "publish always runs the gate"
[ "$PUBLISH" = 1 ] && [ -n "$(git status --porcelain --untracked-files=no)" ] && die "publish needs a clean checkout, so the stamp names a real commit"

# The gate diffs against the commit that runs here, when this checkout holds it, so a canary after a canary tests only
# what changed since. Else against origin/main.
if [ -z "$BASE" ] && [ "$PUBLISH" = 1 ]; then
  t=$(mktemp -d "$HOME_DIR/pub.XXXXXX")
  if download build.json "$t/build.json" 2>/dev/null; then
    pub=$(python3 -I -c 'import sys,json; print(json.load(open(sys.argv[1]))["commit"])' "$t/build.json" 2>/dev/null)
    [ -n "$pub" ] && git merge-base --is-ancestor "$pub" HEAD 2>/dev/null && BASE="$pub"
  fi
  rm -rf "$t"
fi
if [ -z "$BASE" ]; then
  ran=$(installed_stamp | sed -n 's/.*+\([0-9a-f]\{7,\}\).*/\1/p')
  if [ -n "$ran" ] && git merge-base --is-ancestor "$ran" HEAD 2>/dev/null; then BASE="$ran"; else BASE=origin/main; fi
fi

# The test sections the changed files reach. core.sh always runs first inside test.sh.
changed() { { git diff --name-only "$BASE" HEAD 2>/dev/null; git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u; }
gate_sections() {
  changed | awk '
    /^Sources\/UI\/Window\/|^Sources\/Shell\/MMWindow|^tools\/render/ { s["window"]; s["ui"]; render=1 }
    /^Sources\/UI\// { s["ui"] }
    /^Sources\/Core\/Act\/MMRemoval|^Sources\/Core\/Act\/MMUndo/ { s["removal"]; s["wrapup"] }
    /^Sources\/Core\/Act\// { s["act"] }
    /^Sources\/Core\/Know\/MMRegistry|^registry\// { s["know"]; s["minmacs"] }
    /^Sources\/Core\/Know\// { s["know"] }
    /^Sources\/Core\/Senses\// { s["senses"] }
    /^Sources\/Core\/Graph\// { s["graph"]; s["history"] }
    /^Sources\/Core\/Store\// { s["store"] }
    /^Sources\/Core\/.*\.h$|^test\/headers\// { s["headers"] }
    /^Sources\/Experts\/|^Sources\/Core\/Graph\// { s["idle"] }
    /^Sources\/Core\/Review\// { s["review"] }
    /^Sources\/CLI\/|^docs\/CLI.md/ { s["docs"] }
    /^Sources\/Experts\/MinMacs\// { s["minmacs"] }
    /^Sources\/Experts\/LocoHost\// { s["locohost"] }
    /^Sources\/Experts\/WorkForest\// { s["workforest"] }
    /^Sources\/Experts\/NooNoo\// { s["noonoo"] }
    /^Sources\/Experts\/Insomnia\// { s["insomnia"] }
    /^install.sh|^uninstall.sh|^release.sh/ { s["release"] }
    /^test\/[a-z]+(\.sh|\/)/ { split($0, p, "/"); k = p[2]; sub(/\.sh$/, "", k); s[k] }
    END { for (k in s) printf "%s ", k; if (render) printf "+render" }'
}

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
ID="$(git rev-parse --short HEAD)"; [ -n "$(git status --porcelain --untracked-files=no)" ] && ID="$ID-dirty"
STAMP="$VERSION+$ID"
OUT="$HOME_DIR/builds/$VERSION-$ID-$(date +%H%M%S)"
T0=$(date +%s)
mkdir -p "$OUT"

say "Building $STAMP"
BUILD_DIR="$OUT/build" nice -n 10 ./build.sh >"$HOME_DIR/build.out" 2>&1 || { cat "$HOME_DIR/build.out" >&2; rm -rf "$OUT"; logline "$STAMP	build failed"; die "the build failed"; }
ditto "$OUT/build/MinMacs.app" "$OUT/MinMacs.app" && rm -rf "$OUT/build"
cp install.sh "$OUT/install.sh"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $STAMP" "$OUT/MinMacs.app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $STAMP" "$OUT/MinMacs.app/Contents/Info.plist"
codesign -s - --force --deep "$OUT/MinMacs.app" >/dev/null 2>&1 || die "could not sign the stamped copy"

GATED="skipped"
if [ "$GATE" = 1 ]; then
  secs=$(gate_sections)
  render=0; case "$secs" in *+render*) render=1; secs=$(echo "$secs" | sed 's/+render//') ;; esac
  # A canary with nothing changed runs core alone.
  # soak is left out: it is a stability run of 40 minutes or more with its own milestone, and Apple's leaks tool
  # hangs on its fixture on some Macs. It runs on its own, never as part of a gate.
  # Every other hour the gate runs every section once, so what the blast radius misses is found within two hours.
  last=$(cat "$HOME_DIR/last-full" 2>/dev/null || echo 0)
  [ "$FULL" = auto ] && { [ $(( $(date +%s) - last )) -ge "${MINMACS_FULL_EVERY:-7200}" ] && FULL=yes || FULL=no; }
  # The time is kept when a full run starts, pass or fail, so one failing full run doesn't make every canary after it
  # a full run too: the failure is reported, fixed forward, and the next full run comes two hours later.
  [ "$FULL" = yes ] && date +%s >"$HOME_DIR/last-full"
  if [ "$FULL" = yes ]; then secs=$(ls test/*.sh | sed 's|test/||; s|\.sh$||' | grep -v -x -e core -e soak | tr '\n' ' '); render=1; BASE="everything but soak"
  elif [ -z "$(echo "$secs" | tr -d ' ')" ]; then secs="core"; fi
  say "Gate since $BASE: ${secs:-every section}$( [ $render = 1 ] && echo ' + render checks')"
  # The render and window checks draw in a real window, and AppKit animations do not end while the display is off.
  # A display that slept (2 min idle here, always on a lid-closed or unattended Mac) would fail them, so the display is
  # kept awake for as long as the gate runs.
  caffeinate -d -u -w $$ >/dev/null 2>&1 &
  # shellcheck disable=SC2086
  FLAKY=""
  if ! BUILD_DIR="$OUT/test-build" nice -n 10 ./test.sh $secs >"$HOME_DIR/gate.out" 2>&1; then
    # A check that fails only under load is still worth knowing about, but not worth blocking every build for.
    # The sections that failed run once more on their own. If they pass, the run goes on and the failures are named
    # as flaky in the log and the release notes. If they fail again, the gate fails.
    failed=$(LC_ALL=C awk '/^== [a-z]+$/ { sec = $2 } /^[[:space:]]*FAIL/ { if (sec != "") print sec }' "$HOME_DIR/gate.out" | sort -u | tr '\n' ' ')
    first=$(grep -aE 'passed' "$HOME_DIR/gate.out" | tail -1)
    if [ -n "$failed" ] && BUILD_DIR="$OUT/test-build" nice -n 10 ./test.sh $failed >"$HOME_DIR/gate-again.out" 2>&1; then
      FLAKY="$(grep -aE '^[[:space:]]*FAIL' "$HOME_DIR/gate.out" | sed 's/^[[:space:]]*FAIL[[:space:]]*//' | cut -c1-90 | paste -sd ';' -)"
      say "Failed once, passed alone (flaky under load): $failed"
      first="$first, then $(grep -aE 'passed' "$HOME_DIR/gate-again.out" | tail -1) alone ($failed)"
    else
      grep -aE '^\s*FAIL|passed' "$HOME_DIR/gate.out" | tail -15 >&2
      logline "$STAMP	gate failed: $first"
      rm -rf "$OUT"; die "the gate failed, nothing was installed. Full output: $HOME_DIR/gate.out"
    fi
    GATED="$first"
  else
    GATED=$(grep -aE 'passed' "$HOME_DIR/gate.out" | tail -1)
  fi
  [ "$FULL" = yes ] && GATED="full: $GATED" || GATED="blast radius ($(echo $secs)): $GATED"
  if [ $render = 1 ]; then
    BUILD_DIR="$OUT/render-build" nice -n 10 tools/render.sh "$OUT/render" >"$HOME_DIR/render.out" 2>&1 \
      || { grep -E '^FAIL' "$OUT/render/checks.txt" 2>/dev/null | head -5 >&2; tail -1 "$HOME_DIR/render.out" >&2
           logline "$STAMP	render checks failed"; rm -rf "$OUT"; die "the render checks failed, nothing was installed"; }
    GATED="$GATED; $(tail -1 "$HOME_DIR/render.out" | sed 's/.*, \([0-9]* checks\)/\1/')"
  fi
  rm -rf "$OUT/test-build" "$OUT/render-build" "$OUT/render"
fi

install_checked "$OUT" "$STAMP" "built, gate: $GATED${FLAKY:+, flaky: $FLAKY}, $(( $(date +%s) - T0 )) s" || exit 1
[ "$PUBLISH" = 1 ] || exit 0

say "Publishing $STAMP as the $TAG prerelease of $REPO"
command -v gh >/dev/null 2>&1 || die "publish needs gh, logged in"
p="$HOME_DIR/publish"; rm -rf "$p"; mkdir -p "$p"
ditto -c -k --keepParent "$OUT/MinMacs.app" "$p/MinMacs-canary.zip"
(cd "$p" && shasum -a 256 MinMacs-canary.zip >MinMacs-canary.zip.sha256)
cp install.sh "$p/install.sh"
cp tools/canary.sh "$p/canary.sh"
python3 -I -c 'import json,sys; json.dump(dict(zip(["stamp","commit","subject","branch","gate","published"], sys.argv[1:])), open(sys.argv[7], "w"), indent=2)' \
  "$STAMP" "$(git rev-parse HEAD)" "$(git log -1 --format=%s)" "$(git rev-parse --abbrev-ref HEAD)" "$GATED" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$p/build.json"
notes="Canary $STAMP: $(git log -1 --format=%s), from branch $(git rev-parse --abbrev-ref HEAD), commit $(git rev-parse HEAD). Gate: $GATED.${FLAKY:+ Flaky under load, passed alone: $FLAKY.} Health-checked on the publishing Mac. Not a release: install with tools/canary.sh update."
if ! gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" -R "$REPO" --prerelease --title "Canary" --notes "$notes" --target main >/dev/null
fi
gh release upload "$TAG" -R "$REPO" --clobber "$p/MinMacs-canary.zip" "$p/MinMacs-canary.zip.sha256" "$p/build.json" "$p/install.sh" "$p/canary.sh" >/dev/null
gh release edit "$TAG" -R "$REPO" --prerelease --notes "$notes" >/dev/null
logline "$STAMP	published"
say "Published. Every Mac gets it with: tools/canary.sh update"
