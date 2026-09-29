#!/bin/sh
# End-to-end checks against the installed CLI, using fixtures only:
#   TextEdit (graceful quit + restore) and build/Stubborn.app, a test app that refuses to quit.
# Nothing else on the machine is touched. `./test.sh --browser` adds a live Chrome tab test
# that opens its own two tabs and closes only the one on vimeo.com.
set -u
cd "$(dirname "$0")"
BIN="$HOME/.local/bin/minmacs"; R="$HOME/Library/Application Support/MinMacs/rules.json"
STUB=no.guerrilla.minmacs.stubborn
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-46s %s\n' "$1" "$3"; else fail=$((fail+1)); printf '  FAIL  %-46s got %s, want %s\n' "$1" "$3" "$2"; fi; }
running() { pgrep -x "$1" >/dev/null && echo yes || echo no; }
rule() { python3 - "$R" "$@" <<'PY'
import json,sys
p,op,key,val=sys.argv[1:5]; j=json.load(open(p)); l=j[key]
if op=='add' and val not in l: l.append(val)
if op=='del' and val in l: l.remove(val)
json.dump(j,open(p,'w'),indent=2)
PY
}
[ -x "$BIN" ] || { echo "minmacs CLI not installed; run ./build.sh"; exit 1; }
"$BIN" plan >/dev/null; [ -f "$R" ] || { echo "no rules file"; exit 1; }

# fixture: the app that will not quit
mkdir -p build/Stubborn.app/Contents/MacOS
clang -fobjc-arc -framework Cocoa tools/stubborn.m -o build/Stubborn.app/Contents/MacOS/Stubborn || exit 1
cat > build/Stubborn.app/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>Stubborn</string><key>CFBundleIdentifier</key><string>$STUB</string>
<key>CFBundleExecutable</key><string>Stubborn</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PL
codesign --force --sign - build/Stubborn.app >/dev/null 2>&1

cp "$R" "$R.bak"
cleanup() { pkill -9 -x Stubborn 2>/dev/null; osascript -e 'tell application "TextEdit" to quit' >/dev/null 2>&1; mv "$R.bak" "$R"
            defaults delete no.guerrilla.minmacs minmacs.closedBundleIDs >/dev/null 2>&1; defaults delete no.guerrilla.minmacs minmacs.closedTabs >/dev/null 2>&1; }
trap cleanup EXIT
rule add close com.apple.TextEdit; rule add close $STUB

echo "== graceful quit and restore (TextEdit)"
open -g -a TextEdit; sleep 2;                                   check "TextEdit launched" yes "$(running TextEdit)"
"$BIN" plan | grep -q "com.apple.TextEdit";                     check "plan lists it under Will quit" 0 "$?"
r=$("$BIN" plan --json | python3 -c "import json,sys; j=json.load(sys.stdin); print('yes' if any(a['bundleID']=='com.apple.TextEdit' for a in j['close']) else 'no')")
                                                                 check "json plan lists it" yes "$r"
"$BIN" run --yes --only com.apple.TextEdit >/dev/null; sleep 1; check "run --only quits it" no "$(running TextEdit)"
"$BIN" restore >/dev/null; sleep 2;                             check "restore relaunches it" yes "$(running TextEdit)"
"$BIN" run --yes --only no.such.app | grep -q "nothing to close"; check "run with no targets is a no-op" 0 "$?"

echo "== force quit (an app that refuses to quit)"
open -g -n build/Stubborn.app; sleep 2;                         check "Stubborn launched" yes "$(running Stubborn)"
"$BIN" run --yes --only $STUB >/dev/null; rc=$?;                check "normal run leaves it running" yes "$(running Stubborn)"
                                                                 check "and reports it with exit 3" 3 "$rc"
"$BIN" run --yes --force --only $STUB >/dev/null; rc=$?; sleep 1; check "run --force kills it" no "$(running Stubborn)"
                                                                 check "and exits 0" 0 "$rc"

echo "== serving detection (loopback listener)"
open -g -n build/Stubborn.app --args --listen 47999; sleep 2
"$BIN" plan | grep -q "Spared Stubborn: serving on 127.0.0.1:47999"; check "plan spares it and names the port" 0 "$?"
"$BIN" run --yes --force --only $STUB >/dev/null;               check "run --force does not touch a spared app" yes "$(running Stubborn)"
rule add ignoreServing $STUB
"$BIN" plan | grep -A3 "Will quit" | grep -q Stubborn;          check "ignoreServing puts it back on the quit list" 0 "$?"
"$BIN" run --yes --force --only $STUB >/dev/null; sleep 1;      check "then --force kills it" no "$(running Stubborn)"

echo "== tab classification"
check "youtube.com is noise"            noise "$("$BIN" classify https://www.youtube.com/watch?v=x)"
check "subdomain of a noise host"       noise "$("$BIN" classify music.youtube.com)"
check "github.com is work"              work  "$("$BIN" classify https://github.com/FRIKKern/minmacs)"
check "localhost with a port is work"   work  "$("$BIN" classify http://localhost:4000/studio)"
check "unknown host is left alone"      other "$("$BIN" classify https://example.org/)"
check "work wins when both could match" work  "$("$BIN" classify https://aws.amazon.com/console)"

if [ "${1:-}" = "--browser" ]; then
  echo "== live browser trim (opens two tabs of its own in Chrome)"
  was=$(pgrep -f "Google Chrome.app/Contents/MacOS/Google Chrome$" >/dev/null && echo yes || echo no)
  open -g -a "Google Chrome" "https://vimeo.com/" "https://github.com/FRIKKern/minmacs"; sleep 6
  "$BIN" plan | grep -q "vimeo.com";                            check "plan lists the vimeo tab as noise" 0 "$?"
  "$BIN" plan | grep "Will trim" | grep -q "Google Chrome";     check "Chrome is trimmed, not quit" 0 "$?"
  "$BIN" trim --yes --only-host vimeo.com >/dev/null; sleep 2
  "$BIN" plan | grep -q "vimeo.com";                            check "vimeo tab is gone" 1 "$?"
  check "Chrome is still running" yes "$(pgrep -f 'Google Chrome.app/Contents/MacOS/Google Chrome$' >/dev/null && echo yes || echo no)"
  "$BIN" restore >/dev/null; sleep 4
  "$BIN" plan | grep -q "vimeo.com";                            check "restore reopens the closed tab" 0 "$?"
  "$BIN" trim --yes --only-host vimeo.com >/dev/null
  defaults delete no.guerrilla.minmacs minmacs.closedTabs >/dev/null 2>&1
  [ "$was" = "no" ] && echo "  (Chrome was not running before the test; it is left open with the GitHub tab)"
fi

echo; echo "passed $pass, failed $fail"; [ $fail = 0 ]
