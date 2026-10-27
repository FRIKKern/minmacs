# WorkForest on the shared core, issue #24. Sourced by test.sh after core.
# Ports the checks of WorkForest 0.1's test.sh, then adds the 2.0 ones: the verbs and the shim, the undo log,
# WorkForest 0.1's restore records, decision 7, the render and the invariants.
# Fixtures only: a repo with a bare origin and twelve worktrees inside $MINMACS_HOME, MINMACS_ROOTS pointing there
# and nowhere else, and test/review's fake claude and codex in place of the real CLIs. Every removal names a fixture
# path. The one process this section starts is a sleep inside one fixture worktree, and only that pid is stopped.
# Git facts come from test/workforest/gitfacts.py, which reads the fixture repos, until Know computes them itself.

wf=$(cd "$MINMACS_HOME" && mkdir -p wf && cd wf && pwd -P)
mkdir -p "$wf/bin" "$wf/home" "$wf/legacy" "$wf/claude" "$wf/codex"
# A support folder of its own, so this section's reviews and undo rows never reach another section's counts.
wf_top="$MINMACS_HOME"
export MINMACS_HOME="$wf/home"
wf_saved_claude="$CLAUDE_CONFIG_DIR"; wf_saved_codex="$CODEX_HOME"
export CLAUDE_CONFIG_DIR="$wf/claude" CODEX_HOME="$wf/codex" GIT_CONFIG_NOSYSTEM=1
export MINMACS_ROOTS="$wf/code" WORKFOREST_HOME="$wf/legacy" WF_GIT_FACTS="$wf/git.json"
export MINMACS_CLAUDE="$ROOT/test/review/fakeclaude.py" MINMACS_CODEX="$ROOT/test/review/fakecodex.py" RV_TEST_SENT="$wf/sent.json"
unset RV_TEST_GO RV_TEST_UNSURE RV_TEST_KEEP RV_TEST_CLAUDE_LIMIT RV_TEST_CODEX_UNSUPPORTED ANTHROPIC_API_KEY OPENAI_API_KEY
unset WORKFOREST_PROACTIVE_HOURS WORKFOREST_RECENT_HOURS WORKFOREST_BATCH

# The CLI: every .m under Sources but main.m, with test/workforest/wfcli.m, which runs verbs as the app does.
wf_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' | LC_ALL=C sort)
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources -DMM_VERSION='"2.0.0"' \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $wf_src test/workforest/wfcli.m -o "$wf/bin/MinMacs" >"$wf/clang.log" 2>&1
check "test/workforest/wfcli.m builds" 0 "$?"
check "the WorkForest sources have no warnings" 0 "$(grep -c 'warning:' "$wf/clang.log")"
ln -sf "$wf/bin/MinMacs" "$wf/bin/workforest"
WF="$wf/bin/workforest"     # WorkForest 0.1's syntax, through the workforest name
MM="$wf/bin/MinMacs"        # the 2.0 verbs

G() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
wf_facts() { python3 test/workforest/gitfacts.py "$WF_GIT_FACTS" "$A" "$W"/*; }
wf_has() { [ -d "$1" ] && echo yes || echo no; }

echo "== fixtures in $wf"
export GIT_AUTHOR_DATE="2025-01-01T12:00:00" GIT_COMMITTER_DATE="2025-01-01T12:00:00"   # old commits
A="$wf/code/app"; W="$wf/code/app.worktrees"
mkdir -p "$wf/code" "$W"
G init -q --bare "$wf/origin.git"
G clone -q "$wf/origin.git" "$A" 2>/dev/null
( cd "$A" && printf 'node_modules/\n.env\n' > .gitignore && echo one > a.txt && G add -A && G commit -qm first && G push -q origin main 2>/dev/null )
wt() { G -C "$A" worktree add -q -b "$1" "$W/$1" main 2>/dev/null; }
commit() { ( cd "$W/$1" && echo "$2" > "$1-$2.txt" && G add -A && G commit -qm "$3" ); }
# merged: one commit, fast-forwarded into main and pushed. squash: two commits squash-merged, remote branch deleted.
wt merged; commit merged 1 "merged work"; G -C "$W/merged" push -q -u origin merged 2>/dev/null
G -C "$A" merge -q --ff-only merged; G -C "$A" push -q origin main 2>/dev/null
wt squash; commit squash 1 "squash part one"; commit squash 2 "squash part two"; G -C "$W/squash" push -q -u origin squash 2>/dev/null
mkdir -p "$W/squash/docs"   # an empty folder git ignores, where a late change happens below
( cd "$A" && G merge -q --squash squash >/dev/null && G commit -qm "squashed" && echo later > later.txt && G add -A && G commit -qm "later work on main" \
  && G push -q origin main 2>/dev/null && G push -q origin --delete squash 2>/dev/null && G fetch -q --prune )
# The keep rules: each worktree has one reason to stay.
wt dirty; echo changed >> "$W/dirty/a.txt"
wt untracked; echo new > "$W/untracked/new.txt"
wt unpushed; commit unpushed 1 "only here"
wt locked; G -C "$A" worktree lock --reason "fixture lock" "$W/locked"
wt busy
# loose: detached, with a commit that no branch holds.
G -C "$A" worktree add -q --detach "$W/loose" main 2>/dev/null; ( cd "$W/loose" && echo l > l.txt && G add -A && G commit -qm "loose commit" )
wt recent
wt agent
# judged: pushed, not merged, quiet.
wt judged; commit judged 1 "try a thing"; G -C "$W/judged" push -q -u origin judged 2>/dev/null
# envy: merged, with an ignored .env that is saved before removal and an ignored node_modules that is not.
wt envy; printf 'DB_PASSWORD=hunter2\n' > "$W/envy/.env"; mkdir -p "$W/envy/node_modules/pkg"; echo x > "$W/envy/node_modules/pkg/index.js"
for d in "$W"/*; do [ "$d" = "$W/recent" ] || find "$d" -exec touch -h -t 202501011200 {} +; done
# agent: a Claude Code session that ran in it a minute ago. A secret in its title must not reach the model.
S="$CLAUDE_CONFIG_DIR/projects/$(printf %s "$W/agent" | tr '/.' '--')"; mkdir -p "$S"
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
python3 - "$S/wf-$$.jsonl" "$W/agent" "$NOW" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": sys.argv[3], "cwd": sys.argv[2], "sessionId": "wf-fixture",
                        "message": {"role": "user", "content": "Finish the agent fixture, password=hunter2"}}) + "\n")
    f.write(json.dumps({"type": "ai-title", "aiTitle": "try a thing token=SUPERSECRETVALUE123", "sessionId": "wf-fixture"}) + "\n")
PY
# Detached, so the shell reports nothing when it is stopped. Only this pid is ever signaled.
( ( cd "$W/busy" && exec sleep 600 ) >/dev/null 2>&1 & echo $! > "$wf/busy.pid" ); wf_busy=$(cat "$wf/busy.pid"); procs="$procs $wf_busy"
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
wf_facts
sleep 1

echo "== discovery and git facts"
"$WF" auto --mode idle --dry-run >/dev/null
check "a dry run does not start watching" no "$([ -f "$MINMACS_HOME/watching-since" ] && echo yes || echo no)"
"$WF" mode idle >/dev/null; "$WF" auto --mode idle >/dev/null
check "a real auto run does not start watching either: the app's launch does" no "$([ -f "$MINMACS_HOME/watching-since" ] && echo yes || echo no)"
# MinMacs acts on its own only after a day of watching. The fixture Mac has watched for two.
python3 -c "import time; print(int(time.time()) - 2 * 86400)" > "$MINMACS_HOME/watching-since"
L=$("$WF" list --json)
r=$(echo "$L" | json "len(j['trees'])");                                  check "list finds the twelve linked worktrees" 12 "$r"
r=$("$WF" list --all --json | json "len(j['trees'])");                    check "--all adds the main checkout" 13 "$r"
get() { echo "$L" | json "[t$2 for t in j['trees'] if t['path'].endswith('/$1')][0]"; }
check "a fast-forward merge is merged by ancestry" ancestor "$(get merged "['merged']")"
check "a squash merge is found by patch-id" squash "$(get squash "['merged']")"
check "a deleted remote branch is upstream gone" gone "$(get squash "['upstream']")"
check "an unmerged branch is not merged" None "$(get judged "['merged']")"
check "unpushed commits are counted" 1 "$(get unpushed "['unpushed']")"
check "the ignored cache counts as cache" True "$(get envy "['cacheBytes'] > 0")"
check "a process inside is found" True "$(get busy "['processes'] != []")"
check "the agent session is found" "Claude Code" "$(get agent "['session']['agent']")"
r=$("$MM" trees list --json | json "len(j['trees'])");                    check "minmacs trees list reads the same worktrees" 12 "$r"

echo "== every mode keeps work, even when the review calls it all stale"
ALL="/merged,/squash,/dirty,/untracked,/unpushed,/locked,/busy,/loose,/recent,/agent,/judged,/envy"
RV_TEST_GO=$ALL "$WF" review --model haiku --mode eager --fresh >/dev/null 2>&1; check "the review succeeds" 0 "$?"
P=$("$WF" auto --mode eager --dry-run --json)
why() { echo "$P" | json "[p['why'] for p in j['plan'] if p['path'].endswith('/$1')][0]"; }
rm_() { echo "$P" | json "[p['remove'] for p in j['plan'] if p['path'].endswith('/$1')][0]"; }
for k in "dirty:not committed" "untracked:untracked file" "unpushed:on no remote" "locked:locked" "busy:running inside" "loose:no branch holds" "recent:files changed" "agent:session active"; do
  n=${k%%:*}; w=${k#*:}
  case "$(why "$n")" in *"$w"*) r=kept;; *) r="$(why "$n")";; esac
  check "$n stays: $w" kept "$r"
done
check "a merged, quiet worktree may go" True "$(rm_ merged)"
r=$("$WF" auto --mode idle --dry-run --json | json "sum(p['remove'] for p in j['plan'])"); check "idle mode removes nothing" 0 "$r"
r=$("$MM" review workforest --json | json "j['reviews'][0]['summary'].split(':')[0]")
                                                                          check "the summary starts with Core's own count" "12 findings" "$r"
grep -q '/dirty"' "$RV_TEST_SENT";                                        check "a rule keeps uncommitted work without the model" 1 "$?"
r=$(WORKFOREST_BATCH=2 "$WF" review --model haiku --mode idle --fresh --json | json "j['summary'].split('. ', 1)[1] + ' ' + str(sum(1 for t in j['trees'] if 'review' in t))")
                                                                          check "three batches and one summary cover every worktree" "Fixture overall summary: 12 lines. 12" "$r"

echo "== what the model gets"
grep -q "SUPERSECRETVALUE123" "$RV_TEST_SENT";                            check "a secret in a session title is redacted" 1 "$?"
grep -q "hunter2" "$RV_TEST_SENT";                                        check "no .env content or session prompt is sent" 1 "$?"
grep -q "try a thing" "$RV_TEST_SENT";                                    check "the rest of the title is sent" 0 "$?"
ANTHROPIC_API_KEY=sk-ant-test "$WF" review --model haiku --mode idle --fresh >/dev/null 2>&1; check "an API key never reaches claude" 0 "$?"
r=$(RV_TEST_CLAUDE_LIMIT=1 OPENAI_API_KEY=sk-test "$WF" review --model auto --mode idle --fresh --json | json "j['model']")
                                                                          check "out of Haiku usage, Luna answers without the key" gpt-6-luna "$r"
MINMACS_CLAUDE=/usr/bin/false MINMACS_CODEX=/usr/bin/false "$WF" review --model auto --fresh >/dev/null 2>&1; check "both models failing exits 1" 1 "$?"
r=$("$WF" auto --mode eager --dry-run --json | json "sum(p['remove'] for p in j['plan'])"); check "and after a failed review nothing goes" 0 "$r"

echo "== proactive: merged and a week quiet"
RV_TEST_GO=$ALL "$WF" review --model haiku --mode proactive --fresh >/dev/null 2>&1
P=$("$WF" auto --mode proactive --dry-run --json)
check "proactive removes a merged worktree" True "$(rm_ merged)"
check "decision 7: a squash merge on no remote stays in Proactive" False "$(rm_ squash)"
case "$(why squash)" in *"git bundle"*) r=yes;; *) r="$(why squash)";; esac;  check "and says Eager may act after a git bundle" yes "$r"
check "but not unmerged work" False "$(rm_ judged)"
r=$(WORKFOREST_PROACTIVE_HOURS=100000 "$WF" auto --mode proactive --dry-run --json | json "[p['remove'] for p in j['plan'] if p['path'].endswith('/merged')][0]")
                                                                          check "proactive waits for the quiet time" False "$r"
"$WF" mode proactive >/dev/null
"$WF" auto --mode proactive --path "$W/merged" >/dev/null
check "auto removes the folder" no "$(wf_has "$W/merged")"
G -C "$A" rev-parse --verify -q merged >/dev/null;                         check "and deletes the merged branch with -d" 1 "$?"
check "the removal records the mode" proactive "$("$WF" removed --json | json "j[0]['by']")"
"$WF" restore "$W/merged" >/dev/null;                                     check "restore recreates it" 0 "$?"
check "at the same commit" "merged work" "$(G -C "$W/merged" log -1 --format=%s 2>/dev/null)"
find "$W/merged" -exec touch -h -t 202501011200 {} +
wf_facts
WF_RULES=$("$WF" rules | head -1)
python3 - "$WF_RULES" "$W/merged" <<'PY'
import json,sys; p,w=sys.argv[1],sys.argv[2]; j=json.load(open(p)); j.setdefault('protect',[]).append(w); json.dump(j,open(p,'w'))
PY
RV_TEST_GO=/merged "$WF" review --model haiku --mode proactive --fresh >/dev/null 2>&1
P=$("$WF" auto --mode proactive --dry-run --json)
check "a protected path stays" protected "$(why merged)"
"$WF" keep "$W/envy" >/dev/null
P=$("$WF" auto --mode proactive --dry-run --json)
case "$(why envy)" in "kept by you"*) r=kept;; *) r="$(why envy)";; esac;  check "a worktree you keep stays" kept "$r"
"$WF" keep "$W/envy" --off >/dev/null
RV_TEST_GO=$ALL "$WF" review --model haiku --mode proactive --fresh >/dev/null 2>&1
P=$("$WF" auto --mode proactive --dry-run --json)
check "and the mode decides again when the keep ends" True "$(rm_ envy)"

echo "== eager: the worktree must show evidence"
RV_TEST_UNSURE=/judged RV_TEST_KEEP=/judged "$WF" review --model haiku --mode eager --fresh >/dev/null 2>&1
r=$(python3 -c "
import json
hit=False
for line in open('$RV_TEST_SENT.judge'):
    if line.strip(): hit = hit or any(f['id'].endswith('/judged') for b in json.loads(line).get('blocks',[]) for f in b.get('f',[]))
print(hit)");                                                              check "an unsure worktree goes to the judge" True "$r"
P=$("$WF" auto --mode eager --dry-run --json)
check "the judge keeps it with evidence" False "$(rm_ judged)"
case "$(why judged)" in evidence:*) r=yes;; *) r="$(why judged)";; esac;  check "and says what the evidence is" yes "$r"
RV_TEST_UNSURE=/judged "$WF" review --model haiku --mode eager --fresh >/dev/null 2>&1
P=$("$WF" auto --mode eager --dry-run --json)
check "without evidence eager removes it" True "$(rm_ judged)"
wf_since=$(cat "$MINMACS_HOME/watching-since"); date +%s > "$MINMACS_HOME/watching-since"
r=$("$WF" auto --mode eager --dry-run --json | json "[p['remove'] for p in j['plan'] if p['path'].endswith('/judged')][0]")
                                                                          check "but not before MinMacs has watched a day" False "$r"
echo "$wf_since" > "$MINMACS_HOME/watching-since"
"$WF" mode eager >/dev/null
"$WF" auto --mode eager --path "$W/judged" >/dev/null
check "auto removes it" no "$(wf_has "$W/judged")"
G -C "$A" rev-parse --verify -q judged >/dev/null;                         check "and keeps the unmerged branch" 0 "$?"

echo "== ignored files are saved, caches are not"
wf_facts
RV_TEST_GO=/envy "$WF" review --model haiku --mode eager --fresh >/dev/null 2>&1
"$WF" auto --mode eager --path "$W/envy" >/dev/null
check "envy is removed" no "$(wf_has "$W/envy")"
REC=$("$WF" removed --json)
check ".env is saved" True "$(echo "$REC" | json "'.env' in j[0]['saved']")"
check "node_modules is not" False "$(echo "$REC" | json "any('node_modules' in s for s in j[0]['saved'])")"
"$WF" restore "$(echo "$REC" | json "j[0]['id']")" >/dev/null;           check "restore by id works" 0 "$?"
check "and puts .env back" "DB_PASSWORD=hunter2" "$(cat "$W/envy/.env" 2>/dev/null)"
check "without the cache" no "$(wf_has "$W/envy/node_modules")"

echo "== remove checks again"
wf_facts
"$WF" remove "$W/dirty" --yes >/dev/null 2>&1;                            check "remove refuses uncommitted changes, exit 1" 1 "$?"
check "and the worktree is still there" yes "$(wf_has "$W/dirty")"
"$WF" remove "$W/busy" --yes >/dev/null 2>&1;                             check "remove refuses with a process inside" 1 "$?"
RV_TEST_GO=/squash "$WF" review --model haiku --mode eager --fresh >/dev/null 2>&1
"$WF" list --json >/dev/null   # the walk before the change, as the app's last walk
# A file comes and goes in a subfolder. The worktree's own folder keeps its time, so only a new walk sees the change.
echo late > "$W/squash/docs/late.txt"; rm "$W/squash/docs/late.txt"
r=$("$WF" auto --mode eager --path "$W/squash" --json | json "'removed' if j['actions'] and j['actions'][0]['removed'] else 'kept'")
                                                                          check "a change just before removal keeps it" kept "$r"
check "and the worktree is still there" yes "$(wf_has "$W/squash")"

echo "== 2.0: decision 7, the undo log, the shim and WorkForest 0.1's records"
find "$W/squash" -exec touch -h -t 202501011201 {} +
wf_facts
RV_TEST_GO=/squash "$WF" review --model haiku --mode eager --fresh >/dev/null 2>&1
r=$("$WF" auto --mode eager --path "$W/squash" --json | json "'removed' if j['actions'] and j['actions'][0]['removed'] else j")
                                                                          check "eager removes a squash merge on no remote" removed "$r"
check "after a git bundle" True "$("$WF" removed --json | json "j[0]['bundle']")"
G -C "$A" rev-parse --verify -q squash >/dev/null;                         check "git branch -d keeps a squash-merged branch" 0 "$?"
"$WF" restore "$W/squash" >/dev/null;                                     check "restore recreates it from the record" 0 "$?"
check "at its commit" "squash part two" "$(G -C "$W/squash" log -1 --format=%s 2>/dev/null)"
r=$(python3 -c "import sqlite3; c=sqlite3.connect('$MINMACS_HOME/minmacs.sqlite'); print(c.execute(\"select count(distinct rid) from rows where tbl='undo' and expert='workforest'\").fetchone()[0])" 2>&1)
check "the four removals are undo records in Core's log" 4 "$r"
"$WF" restore "$(echo "$REC" | json "j[0]['id']")" >/dev/null 2>&1;      check "a second restore of the same record is refused" 1 "$?"
"$WF" remove "$W/recent" >/dev/null 2>&1;                                  check "remove without --yes asks for it, exit 2" 2 "$?"
"$WF" remove "$W/merged" --dry-run >/dev/null 2>&1;                       check "remove --dry-run of a protected worktree says kept, exit 1" 1 "$?"
check "and changes nothing" yes "$(wf_has "$W/merged")"
"$MM" _verbs >"$wf/verbs.txt" 2>/dev/null
check "MMExpert registers the trees verb" yes "$(cut -f1 "$wf/verbs.txt" | grep -qx trees && echo yes || echo no)"
check "and worktrees as its other name" yes "$(cut -f1 "$wf/verbs.txt" | grep -qx worktrees && echo yes || echo no)"
check "the legacy name is workforest" workforest "$(awk -F'\t' '$1=="legacyName" {print $2}' "$wf/verbs.txt")"
check "WorkForest registers itself with Core" yes "$(awk -F'\t' '$1=="registered" {print $2}' "$wf/verbs.txt")"
check "the shim turns workforest remove into trees remove" "trees remove /x --yes" "$(awk -F'\t' '$1=="shim" {print $2}' "$wf/verbs.txt")"
check "workforest mode reads Core's mode" eager "$("$WF" mode)"
check "the app binary lists the trees verb" yes "$("$BIN" help 2>/dev/null | grep -q '^  trees ' && echo yes || echo no)"
# WorkForest 0.1 removed a worktree and saved its .env. Its record must still restore, and its files stay as they were.
wt legacy; printf 'LEGACY_TOKEN=keepme\n' > "$W/legacy/.env"
LH=$(G -C "$W/legacy" rev-parse HEAD)
mkdir -p "$WORKFOREST_HOME/removed/0a1b2c3d/files"; cp "$W/legacy/.env" "$WORKFOREST_HOME/removed/0a1b2c3d/files/.env"
G -C "$A" worktree remove "$W/legacy" 2>/dev/null
python3 - "$WORKFOREST_HOME/removed.json" "$A" "$W/legacy" "$LH" <<'PY'
import json, sys, time
json.dump([{"id": "0a1b2c3d", "at": time.time() - 3600, "repo": sys.argv[2], "path": sys.argv[3], "branch": "legacy", "head": sys.argv[4],
            "branchDeleted": False, "merged": "ancestor", "subject": "first", "diskBytes": 4096, "cacheBytes": 0, "saved": [".env"],
            "skipped": [], "by": "Proactive", "why": "merged, quiet 9d"}], open(sys.argv[1], "w"), indent=2)
PY
wf_legacy_sum=$(shasum "$WORKFOREST_HOME/removed.json" | cut -d' ' -f1)
check "WorkForest 0.1's record is listed" 0a1b2c3d "$("$WF" removed --json | json "[r.get('legacyID') for r in j if r.get('legacyID')][0]")"
"$WF" restore 0a1b2c3d >/dev/null;                                        check "and restores by its 0.1 id" 0 "$?"
check "the worktree is back" yes "$(wf_has "$W/legacy")"
check "with its saved .env" "LEGACY_TOKEN=keepme" "$(cat "$W/legacy/.env" 2>/dev/null)"
check "WorkForest 0.1's removed.json is left as it was" "$wf_legacy_sum" "$(shasum "$WORKFOREST_HOME/removed.json" | cut -d' ' -f1)"
check "and so is its saved file" yes "$([ -f "$WORKFOREST_HOME/removed/0a1b2c3d/files/.env" ] && echo yes || echo no)"
check "a second import adds nothing" 1 "$("$WF" removed --json | json "sum(1 for r in j if r.get('legacyID'))")"
check "the expert never runs git, a process or the model" 0 "$(grep -nE 'NSTask|/usr/bin/git|MMRun\(|MMRunTask|MMGit\(|MMModel|claudePath|codexPath|popen|system\(' Sources/Experts/WorkForest/*.m | grep -c .)"
check "the expert lists no processes itself" 0 "$(grep -nE 'proc_listpids|PROC_PIDVNODEPATHINFO|KERN_PROC_ALL|proc_pidinfo|lsof|nettop|pmset' Sources/Experts/WorkForest/*.m | grep -c .)"
check "the expert walks no folder itself" 0 "$(grep -nE 'fts_open|enumeratorAtPath|contentsOfDirectoryAtPath|getattrlistbulk' Sources/Experts/WorkForest/*.m | grep -c .)"
check "the expert never deletes a file itself" 0 "$(grep -nE 'removeItemAtPath|removeItemAtURL|unlink\(|rmdir\(|trashItemAtURL' Sources/Experts/WorkForest/*.m | grep -c .)"
kill "$wf_busy" 2>/dev/null

echo "== the disk walk keeps a new walk once the old one is stale"
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources -DMM_VERSION='"2.0.0"' \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $wf_src test/workforest/treedisk.m -o "$wf/bin/treedisk" >"$wf/treedisk-clang.log" 2>&1
check "test/workforest/treedisk.m builds with no warnings" 0 "$(grep -c 'warning:' "$wf/treedisk-clang.log"; [ -x "$wf/bin/treedisk" ] || echo 1)"
mkdir -p "$wf/diskhome" "$wf/disk-fixture"; echo x > "$wf/disk-fixture/a.txt"
python3 - "$wf/diskhome/treedisk.json" "$wf/disk-fixture" <<'PY2'
import json, os, sys, time
st = os.stat(sys.argv[2]); old = time.time() - 3600
fp = "%d.%d" % (st.st_mtime_ns // 10**9, st.st_mtime_ns % 10**9)
json.dump({sys.argv[2]: {"fp": fp, "at": old, "value": {"allocated": 4096, "freed": 4096, "cache": 0, "files": 1, "touched": old, "created": 0, "at": old}}},
          open(sys.argv[1], "w"))
PY2
r=$(MINMACS_HOME="$wf/diskhome" "$wf/bin/treedisk" "$wf/disk-fixture")
check "a fresh read past 15 minutes walks again" yes "$([ "${r#* }" -lt 60 ] 2>/dev/null && echo yes || echo "$r")"
check "and keeps that walk for the next cached read" yes "$([ "${r%% *}" -lt 60 ] 2>/dev/null && echo yes || echo "$r")"

echo "== the menu and cards, rendered"
wf_r="$wf/render"
if BUILD_DIR="$wf/render-build" tools/render.sh "$wf_r" >"$wf/render.log" 2>&1; then wf_ok=0; else wf_ok=1; tail -20 "$wf/render.log"; fi
check "tools/render.sh passes every DESIGN.md check" 0 "$wf_ok"
check "the WorkForest menu follows DESIGN.md rules 3 and 4" 1 "$(grep -c '^ok    workforest: the menu follows' "$wf_r/checks.txt" 2>/dev/null)"
check "the WorkForest cards follow the card rules" 0 "$(grep -E '^FAIL  workforest' "$wf_r/checks.txt" 2>/dev/null | grep -c .)"
check "the render draws WorkForest's own specs" yes "$(grep -q '^ok    workforest: the menu is MMWFMenu' "$wf_r/checks.txt" 2>/dev/null && echo yes || echo no)"
wf_png=0
for m in light dark contrast-light contrast-dark; do [ -s "$wf_r/workforest-menu-$m.png" ] && wf_png=$((wf_png+1)); done
check "the WorkForest menu renders in light, dark and Increase Contrast" 4 "$wf_png"
check "every WorkForest card renders in four appearances" 0 "$(for c in $(ls "$wf_r" | grep -v contrast | sed -n 's/^workforest-card-\(.*\)-light\.png$/\1/p'); do for m in dark contrast-light contrast-dark; do [ -s "$wf_r/workforest-card-$c-$m.png" ] || echo "$c-$m"; done; done | grep -c .)"
check "WorkForest renders at least four cards" yes "$([ "$(ls "$wf_r" | grep -c '^workforest-card-.*-light\.png$')" -ge 4 ] && echo yes || echo no)"

unset MINMACS_CLAUDE MINMACS_CODEX RV_TEST_SENT MINMACS_ROOTS WORKFOREST_HOME WF_GIT_FACTS GIT_CONFIG_NOSYSTEM
export CLAUDE_CONFIG_DIR="$wf_saved_claude" CODEX_HOME="$wf_saved_codex"
export MINMACS_HOME="$wf_top"
