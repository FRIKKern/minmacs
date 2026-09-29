#!/bin/sh
# End-to-end check of close and restore using TextEdit under a temporary rule.
# Nothing else on the machine is touched. Needs the app built and installed.
set -u
BIN="$HOME/.local/bin/minmacs"; R="$HOME/Library/Application Support/MinMacs/rules.json"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-40s %s\n' "$1" "$3"; else fail=$((fail+1)); printf '  FAIL  %-40s got %s, want %s\n' "$1" "$3" "$2"; fi; }
running() { pgrep -x TextEdit >/dev/null && echo yes || echo no; }
[ -x "$BIN" ] || { echo "minmacs CLI not installed"; exit 1; }
"$BIN" plan >/dev/null; [ -f "$R" ] || { echo "no rules file"; exit 1; }
cp "$R" "$R.bak"; trap 'mv "$R.bak" "$R"; osascript -e "tell application \"TextEdit\" to quit" >/dev/null 2>&1' EXIT
python3 -c "import json;p='$R';j=json.load(open(p));j['close'].append('com.apple.TextEdit');json.dump(j,open(p,'w'))"

open -g -a TextEdit; sleep 2;                       check "TextEdit launched" yes "$(running)"
"$BIN" plan | grep -q "com.apple.TextEdit";         check "plan lists it under close" 0 "$?"
r=$("$BIN" plan --json | python3 -c "import json,sys; j=json.load(sys.stdin); print('yes' if any(a['bundleID']=='com.apple.TextEdit' for a in j['close']) else 'no')"); check "json plan lists it" yes "$r"
"$BIN" run --yes --only com.apple.TextEdit >/dev/null; sleep 1
                                                     check "run --only quits it" no "$(running)"
                                                     check "closed list recorded" yes "$(defaults read no.guerrilla.minmacs minmacs.closedBundleIDs 2>/dev/null | grep -q TextEdit && echo yes || echo no)"
"$BIN" restore >/dev/null; sleep 2;                  check "restore relaunches it" yes "$(running)"
                                                     check "closed list cleared" yes "$(defaults read no.guerrilla.minmacs minmacs.closedBundleIDs >/dev/null 2>&1 && echo no || echo yes)"
"$BIN" run --yes --only no.such.app | grep -q "nothing to close"; check "run with no targets is a no-op" 0 "$?"
echo; echo "passed $pass, failed $fail"; [ $fail = 0 ]
