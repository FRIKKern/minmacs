# Cross-links and real git facts in the experts, issue #26. Sourced by test.sh after core.
# A server's card names its worktree and whether it is merged, and opens WorkForest's card of that worktree.
# A worktree's card lists the servers inside it, each opening LocoHost's card. Both go through the kit's link rows
# and the shell's MMLinkMenu, one mechanism for every expert. The git facts come from Core's repo index, and the cold
# CLI lists the fixture worktrees from it.
# Fixtures only: one repo with a bare origin and two worktrees inside $MINMACS_HOME, MINMACS_ROOTS pointing there and
# nowhere else, and three Python HTTP servers on high ports this section picks. Only their pids are ever stopped.

ln_top="$MINMACS_HOME"
ln=$(cd "$MINMACS_HOME" && mkdir -p links && cd links && pwd -P)
mkdir -p "$ln/bin" "$ln/home" "$ln/pids" "$ln/render" "$ln/code"
export MINMACS_HOME="$ln/home" MINMACS_ROOTS="$ln/code" GIT_CONFIG_NOSYSTEM=1

ln_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' | LC_ALL=C sort)
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources -DMM_VERSION='"2.0.0"' \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $ln_src test/links/links.m -o "$ln/bin/links-$$" >"$ln/clang.log" 2>&1
check "test/links/links.m builds" 0 "$?"
check "the sources have no warnings" 0 "$(grep -c 'warning:' "$ln/clang.log")"

G() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
A="$ln/code/shop"; W="$ln/code/shop.worktrees"
G init -q --bare "$ln/origin.git"
G clone -q "$ln/origin.git" "$A" 2>/dev/null
( cd "$A" && echo one > a.txt && G add -A && G commit -qm first && G push -q origin main 2>/dev/null )
# done: one commit, fast-forwarded into main and pushed. wip: a commit that is in no other branch.
G -C "$A" worktree add -q -b done "$W/done" main 2>/dev/null
( cd "$W/done" && echo d > d.txt && G add -A && G commit -qm "done work" && G push -q -u origin done 2>/dev/null )
G -C "$A" merge -q --ff-only done; G -C "$A" push -q origin main 2>/dev/null
G -C "$A" worktree add -q -b wip "$W/wip" main 2>/dev/null
( cd "$W/wip" && echo w > w.txt && G add -A && G commit -qm "wip work" )

echo "== the cold CLI lists the fixture worktrees from the repo index"
r=$(MINMACS_COLD=1 "$BIN" trees list --all --json 2>/dev/null | json "sorted(t['path'].split('/')[-1] for t in j['trees'])")
check "minmacs trees list --all finds the main checkout and both worktrees" "['done', 'shop', 'wip']" "$r"
r=$(MINMACS_COLD=1 "$BIN" trees list --json 2>/dev/null | json "sorted((t['path'].split('/')[-1], t['merged']) for t in j['trees'])")
check "with git facts from the index: done is merged, wip is not" "[('done', 'ancestor'), ('wip', None)]" "$r"
r=$(MINMACS_COLD=1 "$BIN" trees list --json 2>/dev/null | json "[t['unpushed'] for t in j['trees'] if t['path'].endswith('/wip')][0]")
check "and wip's commit on no remote is counted" 1 "$r"

# The servers: two in done, one in wip. Detached, so no shell is above them, and each writes its pid file.
LN_PY='import http.server, os, sys
os.setsid()   # a session of its own, so nothing aimed at it can reach the test run, and nothing aimed at the run reaches it
open(os.path.join(sys.argv[2], "pid-%d" % os.getpid()), "w").close()
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler).serve_forever()'
ln_serve() { ( ( cd "$1" && exec python3 -c "$LN_PY" "$2" "$ln/pids" "links-fixture-$$" ) >/dev/null 2>&1 & ); }
ln_stop() { for f in "$ln"/pids/pid-*; do [ -e "$f" ] && kill "${f##*pid-}" 2>/dev/null; rm -f "$f"; done; }
ln_free() { p=$1; while nc -z 127.0.0.1 "$p" >/dev/null 2>&1; do p=$((p + 1)); done; echo "$p"; }
P1=$(ln_free $((41000 + $$ % 3000))); P2=$(ln_free $((P1 + 1))); P3=$(ln_free $((P2 + 1)))
ln_serve "$W/done" "$P1"; ln_serve "$W/done" "$P2"; ln_serve "$W/wip" "$P3"
for p in $P1 $P2 $P3; do i=0; while ! nc -z 127.0.0.1 "$p" >/dev/null 2>&1 && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; done
ln_procs_before="$procs"
for f in "$ln"/pids/pid-*; do [ -e "$f" ] && procs="$procs ${f##*pid-}"; done

echo "== a server's card links to its worktree, and back"
"$ln/bin/links-$$" "$W/done" "$P1" "$ln/render" >"$ln/done.json" 2>"$ln/done.err"
check "the link check runs" 0 "$?"
q() { json "$1" <"$ln/done.json"; }
check "the server's card names its worktree and that it is merged" "done, merged" "$(q "[f['value'] for f in j['serverCard']['facts'] if f['label'] == 'Worktree'][0]")"
check "the Worktree fact is a link row of the card" 1 "$(q "len(j['serverCard']['links'])")"
check "picking it opens WorkForest's card of that worktree" "workforest $(q "j['worktree']")" "$(q "j['serverCard']['links'][0]['expert'] + ' ' + j['serverCard']['links'][0]['key']")"
check "the WorkForest menu opens with that card as the first row below the header" 2 "$(q "j['serverOpens']['focusedAt']")"
check "and the row holds the card" True "$(q "j['serverOpens']['rowHasCard']")"
check "the opened menu still follows DESIGN.md" "[]" "$(q "j['serverOpens']['menuProblems']")"
check "the card it opens is the worktree's" "The done worktree of shop" "$(q "j['serverOpens']['card']['title']")"
check "in One Icon mode the WorkForest part comes first" "WorkForest 2" "$(q "j['serverOpensOneIcon']['firstSection'] + ' ' + str(j['serverOpensOneIcon']['focusedAt'])")"
check "the worktree's card lists both servers inside it" "[':$P1', ':$P2']" "$(q "sorted(f['value'].split(' ')[0] for f in j['treeCard']['facts'] if f['link'].startswith('locohost:'))")"
check "each server is a link row" 2 "$(q "len(j['treeCard']['links'])")"
check "each opens LocoHost's card of that server" "locohost locohost" "$(q "' '.join(sorted(l['expert'] for l in j['treeCard']['links']))")"
check "the first server's link names the server we started from" True "$(q "j['server'] in [l['key'] for l in j['treeCard']['links']]")"
check "LocoHost's menu opens with the server's card first below the header" "2 2" "$(q "' '.join(str(o['focusedAt']) for o in j['treeOpens'])")"
check "and that card links back to the same worktree" True "$(q "all(o['card']['links'][0]['key'] == j['worktree'] for o in j['treeOpens'])")"
check "the opened LocoHost menus follow DESIGN.md" "[[], []]" "$(q "[o['menuProblems'] for o in j['treeOpens']]")"
"$ln/bin/links-$$" "$W/wip" "$P3" "$ln/render-wip" >"$ln/wip.json" 2>/dev/null
check "a server in an unmerged worktree says so" "wip, not merged" "$(json "[f['value'] for f in j['serverCard']['facts'] if f['label'] == 'Worktree'][0]" <"$ln/wip.json")"
check "and that worktree's card lists its one server" "[':$P3']" "$(json "[f['value'].split(' ')[0] for f in j['treeCard']['facts'] if f['link'].startswith('locohost:')]" <"$ln/wip.json")"

echo "== both cards render with their links"
check "both cards follow the card rules" "[]" "$(q "j['cardProblems']")"
check "both cards render in light, dark and Increase Contrast" 8 "$(q "len(j['pngs'])")"
check "every PNG is written" 8 "$(ls "$ln/render"/links-card-*.png 2>/dev/null | grep -c .)"
mkdir -p "$ROOT/build/render/links" 2>/dev/null && cp "$ln/render"/links-card-*.png "$ROOT/build/render/links/" 2>/dev/null

echo "== one mechanism, in the kit and the shell"
check "no expert opens another expert's menu itself" 0 "$(grep -nE 'performClick|popUpMenu|statusItem|NSStatusBar' Sources/Experts/*/*.m | grep -c .)"
check "MMCard makes the link rows" yes "$(grep -q 'MMLinkOfItem' Sources/UI/MMCard.h && echo yes || echo no)"
check "the shell sets the one link opener" 1 "$(grep -c 'MMSetLinkOpener(' Sources/Shell/MMShell.m)"
check "Noo-Noo runs git through MMGit on its own queue" "1 0" "$(grep -c 'MMQueue(@"core", @"clutter.git"' Sources/Core/Know/MMClutter.m) $(grep -c 'CommandLineTools/usr/bin/git' Sources/Core/Know/MMClutter.m)"
check "WorkForest's tests hand over no git facts" 0 "$( { ls test/workforest/gitfacts.py 2>/dev/null; grep -l WF_GIT_FACTS test/workforest.sh test/workforest/wfcli.m; } | grep -c .)"
ln_stop
procs="$ln_procs_before"   # stopped, so the harness never signals those pids again once the system reuses them
unset MINMACS_ROOTS GIT_CONFIG_NOSYSTEM
export MINMACS_HOME="$ln_top"
