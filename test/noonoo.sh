# ===== Noo-Noo: the clutter catalog, its walls, removal with undo, and disk trends, issues #28, #29 and #30 =====
# Sourced by test.sh after core. Builds test/noonoo/tool.m with all of Core, the kit, MMArgs and the expert, under -DMM_TESTS.
# Fixtures only, all inside $MINMACS_HOME/nn<pid>: a stand-in for / under root/, with a home, /private/tmp and $TMPDIR,
# a git repo with a worktree, caches, a simulator Devices folder, agent scratch, temp families and transcripts.
# The tool runs with its own MINMACS_HOME, the nn folder, and MINMACS_CLUTTER_ROOT inside it, so it never reads the
# person's files. Tool commands run only the fake xcrun in $MINMACS_TOOLS. Items go to the real Trash and every check
# that moves one restores it, so the Trash ends as it began. Cleanup stops only the pid this section started.

nn=$(cd "$MINMACS_HOME" && pwd -P)/nn$$
nnr="$nn/root"; nnh="$nnr/home"
mkdir -p "$nn/tools" "$nnh" "$nn/claude/projects" "$nn/codex"
nn_tab=$(printf '\t')

nn_cc="clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources"
# shellcheck disable=SC2046
$nn_cc $(find Sources/Core Sources/UI Sources/CLI Sources/Experts/NooNoo -name '*.m' | LC_ALL=C sort) test/noonoo/tool.m \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  -o "$nn/tool" >"$nn/build.log" 2>&1
nn_r=$?
check "noonoo: the test tool builds" 0 "$nn_r"
check "noonoo: Core and the expert have no warnings under -Wextra" 0 "$(grep -c 'warning:' "$nn/build.log")"
[ "$nn_r" = 0 ] || tail -20 "$nn/build.log"
cp test/noonoo/fake-xcrun.sh "$nn/tools/xcrun" && chmod +x "$nn/tools/xcrun"

echo "-- the catalog as data"
nn_rows=$(ls registry/clutter/*.json | wc -l | tr -d ' ')
check "noonoo: the catalog ships the 52 research rows and NN's extra signatures" yes "$([ "$nn_rows" -ge 52 ] && echo yes || echo no)"
python3 test/noonoo/validate_clutter.py registry/clutter/*.json >"$nn/validate.log" 2>&1
check "noonoo: every clutter row passes the schema and the catalog rules" 0 "$?"
check "noonoo: the app bundle ships every clutter row" "$nn_rows" "$(ls "$APP/Contents/Resources/registry/clutter" 2>/dev/null | wc -l | tr -d ' ')"
check "noonoo: the research rows are all in the catalog" 0 "$(python3 - <<'PY'
import json, os
t = open('docs/2.0/research/D-clutter.md').read()
rows = json.loads(t.split('## Catalog as JSON')[1].split('```json')[1].split('```')[0])
print(sum(not os.path.exists('registry/clutter/%s.json' % r['id']) for r in rows))
PY
)"

echo "-- nothing deletes for good, nothing scans on the tick"
check "noonoo: no permanent delete in the catalog, the actions or the expert" 0 \
  "$(grep -nE 'removeItemAt|unlink\(|rmdir\(|emptyTrash|rm -rf|RemoveAll' Sources/Core/Know/MMClutter.m Sources/Core/Act/MMClutterAct.m Sources/Experts/NooNoo/*.m | grep -c .)"
check "noonoo: the expert never walks, sizes or reads folders itself" 0 \
  "$(grep -nE 'MMSizer|fts_open|getattrlistbulk|contentsOfDirectory|enumeratorAtPath|MMOpenUnder|scanKinds' Sources/Experts/NooNoo/*.m | grep -c .)"
check "noonoo: the fact source only reads the last scan's items" 1 \
  "$(grep -cE 'MMClutterCatalog.shared.items' Sources/Core/MMCore.m)"
check "noonoo: the fact source and the Senses tick never scan clutter" 0 \
  "$(grep -nE 'scanDue|\] scan\]|scanKinds' Sources/Core/MMCore.m Sources/Core/Senses/*.m Sources/Core/Graph/*.m | grep -c .)"
check "noonoo: the scan timer runs on Core's labeled clutter queue" "1 1" \
  "$(grep -c '_timer = MMTimer(q' Sources/Core/Know/MMClutter.m) $(grep -c 'dispatch_queue_t q = MMQueue(@"core", @"clutter"' Sources/Core/Know/MMClutter.m)"
check "noonoo: Scan Now in the menu hands the scan to that queue" 2 \
  "$(grep -c 'dispatch_async(MMQueue(@"core", @"clutter", QOS_CLASS_UTILITY)' Sources/Experts/NooNoo/MMNooNooExpert.m)"

echo "-- fixtures"
nn_git() { GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.com GIT_COMMITTER_NAME=fixture \
  GIT_COMMITTER_EMAIL=fixture@example.com git "$@" >/dev/null 2>&1; }
nn_old() { find "$@" -exec touch -h -t 202601010000 {} + 2>/dev/null; }
nn_main="$nn/code/acme"; nn_wt="$nn/code/acme.wt/feat"
mkdir -p "$nn_main/dist"
printf '{"name":"acme"}\n' >"$nn_main/package.json"
printf 'built\n' >"$nn_main/dist/app.js"
nn_git -c init.defaultBranch=main init -q "$nn_main"
nn_git -C "$nn_main" add package.json dist/app.js
nn_git -C "$nn_main" commit -qm first
nn_git -C "$nn_main" worktree add -q -b feat "$nn_wt"
mkdir -p "$nn_main/node_modules/left-pad" "$nn_wt/node_modules/left-pad/lib" "$nn_wt/.next/cache" "$nn_wt/node_modules/inner/dist"
printf 'module.exports = 1\n' >"$nn_main/node_modules/left-pad/index.js"
dd if=/dev/urandom of="$nn_wt/node_modules/left-pad/lib/big.bin" bs=1024 count=512 2>/dev/null
printf 'x\n' >"$nn_wt/node_modules/inner/dist/i.js"
printf 'module.exports = {}\n' >"$nn_wt/next.config.js"
printf 'page\n' >"$nn_wt/.next/cache/page.html"
nn_sum=$(cd "$nn_wt/node_modules" && find . -type f -exec md5 -q {} + | sort | md5 -q)

mkdir -p "$nnh/Library/Caches/pip/http" "$nnh/.npm/_cacache" "$nnh/.Trash" "$nnh/Documents" "$nnh/Library/Caches/random-app"
dd if=/dev/zero of="$nnh/Library/Caches/pip/http/wheel.bin" bs=1048576 count=8 2>/dev/null
printf 'idx\n' >"$nnh/.npm/_cacache/index"
printf 'trashed\n' >"$nnh/.Trash/old.txt"
printf 'notes\n' >"$nnh/Documents/notes.txt"
printf 'cache\n' >"$nnh/Library/Caches/random-app/c"
ln -s "$nnh/Documents" "$nnh/Library/Caches/pip/docs-link"
mkdir -p "$nnh/Library/Application Support/Cursor/User/globalStorage" "$nnh/Library/Application Support/Cursor/Cache"
printf 'state\n' >"$nnh/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
printf 'c\n' >"$nnh/Library/Application Support/Cursor/Cache/c"

nn_dev="$nnh/Library/Developer/CoreSimulator/Devices"
nn_gone=11111111-2222-3333-4444-555555555555; nn_keep=66666666-7777-8888-9999-AAAAAAAAAAAA
mkdir -p "$nn_dev/$nn_gone/data" "$nn_dev/$nn_keep/data"
printf 'old phone\n' >"$nn_dev/$nn_gone/data/app.db"; : >"$nn_dev/$nn_gone/unavailable"
printf 'phone\n' >"$nn_dev/$nn_keep/data/app.db"

nn_dead=0b1d2c3e-0000-4000-8000-00000000dead; nn_live=5e55a0b1-0000-4000-8000-00000000beef
nn_scr="$nnr/private/tmp/claude-501/-code-acme"
mkdir -p "$nn_scr/$nn_dead/scratchpad/run" "$nn_scr/$nn_live/scratchpad/new" "$nn/claude/projects/-code-acme"
printf 'scratch\n' >"$nn_scr/$nn_dead/scratchpad/run/out.txt"
printf 'scratch\n' >"$nn_scr/$nn_live/scratchpad/new/out.txt"
printf '{}\n' >"$nn/claude/projects/-code-acme/$nn_live.jsonl"
printf '{}\n' >"$nn/claude/projects/-code-acme/$nn_dead.jsonl"
nn_old "$nn_scr/$nn_dead" "$nn/claude/projects/-code-acme/$nn_dead.jsonl"

nn_T="$nnr/private/var/folders/ab/cdef/T"
for s in a1B2c3 d4E5f6 g7H8i9 j1K2l3 m4N5o6 p7Q8r9; do mkdir -p "$nn_T/mv-test-$s"; printf 'x\n' >"$nn_T/mv-test-$s/f"; done
for s in a1B2c3 d4E5f6 g7H8i9 j1K2l3 m4N5o6 p7Q8r9; do mkdir -p "$nn_T/com.apple.launchd.$s"; done
for s in a1B2c3 d4E5f6 g7H8i9 j1K2l3 m4N5o6; do mkdir -p "$nn_T/fresh-run-$s"; done
nn_old "$nn_T"/mv-test-* "$nn_T"/com.apple.launchd.*
nn_clone="$nnr/private/var/folders/ab/cdef/X/com.google.Chrome.code_sign_clone/code_sign_clone.Ab12Cd"
mkdir -p "$nn_clone/Contents"; printf 'bin\n' >"$nn_clone/Contents/Chrome"
mkdir -p "$nnr/System/Library/Caches"; printf 'sys\n' >"$nnr/System/Library/Caches/x"
mkdir -p "$nnr/Library/Caches/shared"; printf 'lib\n' >"$nnr/Library/Caches/shared/x"

nn_env() { MINMACS_HOME="$nn" MINMACS_CLUTTER_ROOT="$nnr" MINMACS_CLUTTER_ROWS="$ROOT/registry/clutter" MINMACS_TOOLS="$nn/tools" \
           CLAUDE_CONFIG_DIR="$nn/claude" CODEX_HOME="$nn/codex" NN_PROJECTS="$nn_main:$nn_wt" NN_MERGED="$nn_wt" "$@"; }
nnt() { nn_env "$nn/tool" "$@"; }
# One field of the item at a path in `clutter list --json`, or absent.
nn_item() { nnt verb clutter list --json 2>/dev/null | python3 -c "
import json,sys; j=json.load(sys.stdin)
m=[i for i in j['items'] if i['path']==sys.argv[1]]
print(m[0].get(sys.argv[2],'') if m else 'absent')" "$1" "$2"; }
nn_undo() { nnt undo | python3 -c "import json,sys; j=json.load(sys.stdin); print($1)"; }

if [ "$nn_r" = 0 ]; then
  echo "-- no root, no scan"
  check "noonoo: with MINMACS_HOME and no clutter root the tool refuses to run" 9 \
    "$(MINMACS_HOME="$nn" MINMACS_CLUTTER_ROOT= "$nn/tool" scan >/dev/null 2>&1; echo $?)"
  check "noonoo: a clutter root outside MINMACS_HOME is refused" 9 \
    "$(MINMACS_HOME="$nn" MINMACS_CLUTTER_ROOT=/private/tmp "$nn/tool" scan >/dev/null 2>&1; echo $?)"

  echo "-- the scan"
  nn_count=$(nnt scan 2>/dev/null)
  check "noonoo: the scan finds the fixture items" yes "$([ "${nn_count:-0}" -ge 12 ] && echo yes || echo no)"
  nn_list=$(nnt verb clutter list --json 2>/dev/null)
  printf '%s' "$nn_list" >"$nn/list.json"
  check "noonoo: node_modules of a squash-merged worktree is a finished project" "finished squash-merged" \
    "$(nn_item "$nn_wt/node_modules" section) $(nn_item "$nn_wt/node_modules" ownerState)"
  check "noonoo: the worktree's .next is a finished project too" finished "$(nn_item "$nn_wt/.next" section)"
  check "noonoo: dist inside node_modules is never its own item" absent "$(nn_item "$nn_wt/node_modules/inner/dist" section)"
  check "noonoo: node_modules of the active main checkout sits with caches" caches "$(nn_item "$nn_main/node_modules" section)"
  check "noonoo: a dist folder git tracks is kept" "kept git tracks it, so it is part of the project" \
    "$(nn_item "$nn_main/dist" section) $(nn_item "$nn_main/dist" why)"
  check "noonoo: the pip cache is a cache" "caches cache" "$(nn_item "$nnh/Library/Caches/pip" section) $(nn_item "$nnh/Library/Caches/pip" class)"
  check "noonoo: the simulator Devices folder is a tool row" "caches tool" "$(nn_item "$nn_dev" section) $(nn_item "$nn_dev" class)"
  check "noonoo: a dead session's scratch is a leftover" leftovers "$(nn_item "$nn_scr/$nn_dead" section)"
  check "noonoo: a live session's scratch stays, by its transcript" "kept its transcript was written in the last 30 minutes" \
    "$(nn_item "$nn_scr/$nn_live" section) $(nn_item "$nn_scr/$nn_live" why)"
  check "noonoo: six old mktemp siblings are one family leftover" "leftovers 6" \
    "$(nn_item "$nn_T/mv-test-*" section) $(nn_item "$nn_T/mv-test-*" members)"
  check "noonoo: com.apple. siblings never form a family" absent "$(nn_item "$nn_T/com.apple.launchd.*" section)"
  check "noonoo: a family written just now stays" "kept" "$(nn_item "$nn_T/fresh-run-*" section)"
  check "noonoo: a Chrome code-sign clone nothing holds open is a leftover" leftovers "$(nn_item "$nn_clone" section)"
  check "noonoo: Claude Code transcripts are data, kept with their owner's setting" "kept data" \
    "$(nn_item "$nn/claude/projects/-code-acme" section) $(nn_item "$nn/claude/projects/-code-acme" class)"
  check "noonoo: the Trash is reported and never acted on" "kept  yes" \
    "$(nn_item "$nnh/.Trash" section) $(nn_item "$nnh/.Trash" action) $(printf '%s' "$nn_list" | json '"yes" if j["trashBytes"] > 0 else "no"')"
  check "noonoo: sizes are what deleting frees, from the Sizer" yes \
    "$(printf '%s' "$nn_list" | json '"yes" if [i for i in j["items"] if i["path"].endswith("Caches/pip")][0]["freed"] >= 8*1048576 else "no"')"

  echo "-- a file held open keeps its folder"
  (exec 3<"$nn_clone/Contents/Chrome"; exec sleep 60) &
  nn_holder=$!; procs="$procs $nn_holder"
  sleep 0.3
  nnt scan >/dev/null 2>&1
  check "noonoo: a clone a running process holds open stays" "kept a running process has a file open in it" \
    "$(nn_item "$nn_clone" section) $(nn_item "$nn_clone" why)"
  check "noonoo: clean refuses it while the file is open" 1 "$(nnt verb clean "$nn_clone" >/dev/null 2>&1; echo $?)"
  kill "$nn_holder" 2>/dev/null; wait "$nn_holder" 2>/dev/null
  nnt scan >/dev/null 2>&1
  check "noonoo: once the process ends the clone is a leftover again" leftovers "$(nn_item "$nn_clone" section)"

  echo "-- the walls: nothing outside a listed row can be touched"
  nn_walls() { nnt verb clutter check "$1" >/dev/null 2>&1; echo $?; }
  nn_refused=0; nn_tried=0
  for p in /System/Library /system/library /Library/Caches /usr/local "$HOME" "$HOME/Documents" "$HOME/Library/Caches" /private/tmp /private/etc \
           "$nnr" "$nnh" "$nnh/Documents" "$nnh/Documents/notes.txt" "$nnh/Library" "$nnh/Library/Caches" "$nnh/Library/Caches/random-app" \
           "$nnh/Library/Caches/pip/docs-link" "$nnh/Library/Caches/pip/../pip" "$nnr/System/Library/Caches/x" "$nnr/Library/Caches/shared" \
           "$nnh/Library/Application Support/Cursor/User/globalStorage/state.vscdb" "$nnh/Library/Application Support/Cursor/User" \
           "$nnh/.Trash" "$nn/claude/projects/-code-acme" "$nn_main" "$nn_wt" "$nn_main/package.json" "$nn" "$nn_T" "$nnr/private/tmp"; do
    nn_tried=$((nn_tried+1))
    [ "$(nn_walls "$p")" = 1 ] && nn_refused=$((nn_refused+1))
  done
  check "noonoo: every protected or unlisted path is refused" "$nn_tried" "$nn_refused"
  check "noonoo: the wall names /System" "never: it is under /System, which MinMacs never touches" "$(nnt verb clutter check /System/Library 2>/dev/null)"
  check "noonoo: the wall ignores case" "never: it is under /System, which MinMacs never touches" "$(nnt verb clutter check /system/library 2>/dev/null)"
  check "noonoo: the home folder itself is refused" "never: it is the home folder or holds it" "$(nnt verb clutter check "$nnh" 2>/dev/null)"
  check "noonoo: an unlisted cache is refused" "never: no clutter row lists it" "$(nnt verb clutter check "$nnh/Library/Caches/random-app" 2>/dev/null)"
  check "noonoo: a symlink is refused" "never: it is a symlink, and MinMacs never follows one" "$(nnt verb clutter check "$nnh/Library/Caches/pip/docs-link" 2>/dev/null)"
  check "noonoo: a folder holding a never path is refused" "never: its owner keeps it, and the row says never" \
    "$(nnt verb clutter check "$nnh/Library/Application Support/Cursor/User" 2>/dev/null)"
  check "noonoo: a listed cache may go" "may go: the pip cache row lists it" "$(nnt verb clutter check "$nnh/Library/Caches/pip" 2>/dev/null)"
  # Every path in the fixture tree that the walls let through is one of the listed leaves, and nothing else.
  nnt walls "$nnr" | LC_ALL=C sort >"$nn/allowed.txt"
  nnt walls "$nn/code" | LC_ALL=C sort >>"$nn/allowed.txt"
  printf '%s\n' "$nn_main/node_modules" "$nn_wt/.next" "$nn_wt/node_modules" "$nnh/.npm/_cacache" \
    "$nnh/Library/Application Support/Cursor/Cache" "$nnh/Library/Caches/pip" "$nn_dev" "$nn_scr/$nn_dead" "$nn_scr/$nn_live" \
    "$nn_scr/$nn_dead/scratchpad/run" "$nn_scr/$nn_live/scratchpad/new" "$nn_clone" \
    $(cd "$nn_T" && ls -d fresh-run-* mv-test-* | sed "s|^|$nn_T/|") | LC_ALL=C sort >"$nn/expected.txt"
  check "noonoo: the walls let through exactly the listed leaves" "" "$(LC_ALL=C sort "$nn/allowed.txt" | diff - "$nn/expected.txt" | tr '\n' ' ')"
  nn_before=$(find "$nnr" "$nn/code" | LC_ALL=C sort | md5 -q)
  for p in "$nnh" "$nnh/Documents" "$nnr/System/Library/Caches/x" "$nnh/Library/Caches/random-app" "$nnh/Library/Caches/pip/docs-link" \
           "$nn_main/dist" "$nn_scr/$nn_live" "$nnh/Library/Application Support/Cursor/User/globalStorage/state.vscdb" /System/Library "$HOME"; do
    nnt verb clean "$p" >/dev/null 2>&1
  done
  check "noonoo: clean on protected, kept or unlisted paths changes nothing" "$nn_before" "$(find "$nnr" "$nn/code" | LC_ALL=C sort | md5 -q)"
  check "noonoo: no refused clean wrote an undo record" 0 "$(nn_undo 'len(j)')"

  echo "-- removal and undo"
  # A dry run says what would happen and changes nothing.
  check "noonoo: a dry run says the item goes to the Trash" yes \
    "$(nnt verb clean "$nn_wt/node_modules" --dry-run 2>/dev/null | grep -q 'to the Trash. Undo moves it back' && echo yes || echo no)"
  check "noonoo: a dry run leaves it in place" yes "$([ -d "$nn_wt/node_modules" ] && echo yes || echo no)"
  nn_undo_one() {   # path: clean it, check it left, undo it, check it is back. Prints "gone back".
    nnt verb clean "$1" >/dev/null 2>&1
    g=$([ -e "$1" ] && echo kept || echo gone)
    rid=$(nn_undo 'j[0]["rid"] if j else ""')
    nnt verb clean --undo "$rid" >/dev/null 2>&1
    echo "$g $([ -e "$1" ] && echo back || echo missing)"
  }
  check "noonoo: finished node_modules goes to the Trash and comes back" "gone back" "$(nn_undo_one "$nn_wt/node_modules")"
  check "noonoo: what came back is the same files" "$nn_sum" "$(cd "$nn_wt/node_modules" && find . -type f -exec md5 -q {} + | sort | md5 -q)"
  check "noonoo: the record is a trash record with an audit before and after" "trash True False" \
    "$(nn_undo '"%s %s %s" % (j[0]["kind"], j[0]["payload"]["audit"]["before"][0]["exists"], j[0]["payload"]["audit"]["after"][0]["exists"])')"
  check "noonoo: the record notes where the Trash put it, and it left the Trash" "restored no" \
    "$(nn_undo 'j[0]["state"]') $([ -e "$(nn_undo 'j[0]["payload"]["trashed"][0]["to"]')" ] && echo yes || echo no)"
  check "noonoo: the record holds the statfs delta as a number" int "$(nn_undo 'type(j[0]["freedBytes"]).__name__')"
  check "noonoo: the pip cache goes to the Trash and comes back" "gone back" "$(nn_undo_one "$nnh/Library/Caches/pip")"
  check "noonoo: a dead session's scratch goes and comes back" "gone back" "$(nn_undo_one "$nn_scr/$nn_dead")"
  check "noonoo: a family's members go and come back" "gone back" "$(nn_undo_one "$nn_T/mv-test-a1B2c3")"
  check "noonoo: every member of the family was in the one record" 6 "$(nn_undo 'len(j[0]["payload"]["trashed"])')"
  nnt scan >/dev/null 2>&1
  check "noonoo: a finished project's .next goes and comes back" "gone back" "$(nn_undo_one "$nn_wt/.next")"

  echo "-- a tool row: the fake simctl, a recovery copy first, and undo"
  check "noonoo: the tool's dry run names the command and the recovery copy" yes \
    "$(nnt verb clean "$nn_dev" --dry-run 2>/dev/null | grep -q 'recovery folder, then run xcrun simctl delete unavailable' && echo yes || echo no)"
  nnt verb clean "$nn_dev" >"$nn/clean-tool.txt" 2>&1
  check "noonoo: clean runs the tool's own command" 0 "$?"
  check "noonoo: the tool removed the unavailable device only" "gone kept" \
    "$([ -e "$nn_dev/$nn_gone" ] && echo kept || echo gone) $([ -e "$nn_dev/$nn_keep" ] && echo kept || echo gone)"
  check "noonoo: the record keeps the tool's output and its saved paths" "clean Deleted $nn_gone 1" \
    "$(nn_undo '"%s %s %d" % (j[0]["kind"], j[0]["payload"]["output"].strip(), len(j[0]["payload"]["recovery"]["saved"]))')"
  check "noonoo: the recovery copy holds the removed device" yes \
    "$([ -f "$(nn_undo 'j[0]["payload"]["recovery"]["dir"]')$nn_dev/$nn_gone/data/app.db" ] && echo yes || echo no)"
  check "noonoo: the tool record can be undone" True "$(nn_undo 'j[0]["canRestore"]')"
  nnt verb clean --undo "$(nn_undo 'j[0]["rid"]')" >/dev/null 2>&1
  check "noonoo: undo puts the removed device back" "old phone" "$(cat "$nn_dev/$nn_gone/data/app.db" 2>/dev/null)"
  check "noonoo: undo leaves the kept device as it was" phone "$(cat "$nn_dev/$nn_keep/data/app.db" 2>/dev/null)"
  mv "$nn/tools/xcrun" "$nn/tools/xcrun.off"
  check "noonoo: with no fake installed the tool row is refused" 1 "$(nnt verb clean "$nn_dev" >/dev/null 2>&1; echo $?)"
  mv "$nn/tools/xcrun.off" "$nn/tools/xcrun"
  check "noonoo: every clean in this section ended restored" yes \
    "$(nn_undo '"yes" if j and all(r["state"] == "restored" for r in j) else [r["state"] for r in j]')"
  check "noonoo: the Trash holds none of this run's fixtures" 0 \
    "$(nn_undo 'sum(__import__("os").path.exists(t["to"]) for r in j for t in r["payload"].get("trashed", []))')"

  echo "-- plans: Proactive takes finished projects and leftovers, never caches or tools"
  nn_plan=$(nnt verb clutter list --json 2>/dev/null)
  check "noonoo: the rule lets finished build output go" yes \
    "$(printf '%s' "$nn_plan" | json '"yes" if [i for i in j["items"] if i["path"].endswith("feat/node_modules")][0]["section"]=="finished" else "no"')"

  echo "-- disk trends"
  check "noonoo: one point per row per day, so the log stays small" 1 "$(nnt points pip-cache)"
  check "noonoo: no growth line before there is a history" "" "$(nnt verb clutter list --json 2>/dev/null | json 'j["growthLine"]')"
  python3 - "$nn/Preferences/no.guerrilla.minmacs.plist" <<'PY'
import os, plistlib, sys
p = sys.argv[1]; os.makedirs(os.path.dirname(p), exist_ok=True)
d = plistlib.load(open(p, "rb")) if os.path.exists(p) else {}
d["noonoo.growthMinBytes"] = 2.0 * 1048576
plistlib.dump(d, open(p, "wb"))
PY
  nnt record pip-cache 14 1048576 7340032
  nnt record npm-cache 14 4096 4096
  nnt scan >/dev/null 2>&1
  check "noonoo: the recorded history and today make one point a day" 15 "$(nnt points pip-cache)"
  check "noonoo: a recorded fast-growing cache gives the right growth line" "The pip cache grew 7 MB in 14 days." \
    "$(nnt verb clutter list --json 2>/dev/null | json 'j["growthLine"]')"
  check "noonoo: a flat cache gives no line" "False" \
    "$(nnt verb clutter trends --json 2>/dev/null | json 'any("npm" in t["title"] and t["trend"]["bytesPerDay"] > 0 for t in j["trends"])')"

  echo "-- the menu and cards"
  nn_out="$ROOT/build/render/noonoo"
  rm -rf "$nn_out"; mkdir -p "$nn_out"
  nnt render "$nn_out" >/dev/null 2>&1
  check "noonoo: the render runs" 0 "$?"
  check "noonoo: the render's DESIGN.md checks pass" 0 "$([ -f "$nn_out/checks.txt" ] && { grep -c '^FAIL' "$nn_out/checks.txt"; true; } || echo missing)"
  grep '^FAIL' "$nn_out/checks.txt" 2>/dev/null | head -5
  check "noonoo: the summary leads with the growth line" yes \
    "$(grep -q '^TEXT summary The pip cache grew 7 MB in 14 days.' "$nn_out/checks.txt" && echo yes || echo no)"
  check "noonoo: finished projects come first" "Finished projects" "$(grep -m1 '^TEXT section' "$nn_out/checks.txt" | sed 's/^TEXT section //')"
  check "noonoo: the first action cleans finished projects" yes "$(grep -q '^TEXT action Clean Finished Projects' "$nn_out/checks.txt" && echo yes || echo no)"
  check "noonoo: the header counts the finished project and the Trash" yes \
    "$(grep '^TEXT header' "$nn_out/checks.txt" | grep -q '1 finished project · .*Trash holds' && echo yes || echo no)"
  check "noonoo: a finished card links its owner to WorkForest" yes \
    "$(grep -q '^TEXT fact finished | Owner | feat$' "$nn_out/checks.txt" && echo yes || echo no)"
  check "noonoo: four appearances of the menu and of a card per section" yes \
    "$([ "$(ls "$nn_out"/noonoo-menu-*.png 2>/dev/null | wc -l | tr -d ' ')" = 4 ] && [ "$(ls "$nn_out"/noonoo-card-*.png 2>/dev/null | wc -l | tr -d ' ')" -ge 12 ] && echo yes || echo no)"
fi
