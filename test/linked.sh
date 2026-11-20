# ===== A repo reached through a root that is a link =====
# Sourced by test.sh after core. Fixtures only, all inside $MINMACS_HOME/linked.<pid>: one repo in code/, a link named
# root that leads to code/, and a session status file that names this shell's own pid in the repo, by the resolved
# path as the kernel gives it. The one process it starts is a Python http.server in the repo's web folder, on a high
# port this section picks, stopped at the end by the pid its own pid file names. The built binary reads them cold.
# The repo index keeps the checkout as root/shop, WorkForest names its finding code/shop, and the graph compared the
# two as text: the worktree finding had no workstream, and `work` found none at the path. The same held for any home
# under /tmp or /var/folders, which lead to /private. Every run here is a read.

lk_dir="$(cd "$MINMACS_HOME" && pwd -P)/linked.$$"
lk_procs_before="$procs"
mkdir -p "$lk_dir/code" "$lk_dir/claude/sessions" "$lk_dir/claude/projects" "$lk_dir/codex" "$lk_dir/clutter" "$lk_dir/pids"
ln -s "$lk_dir/code" "$lk_dir/root"
lk_git() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
lk_git init -q "$lk_dir/code/shop"
mkdir -p "$lk_dir/code/shop/web"
( cd "$lk_dir/code/shop" && echo one >a.txt && echo page >web/index.html && lk_git add -A && lk_git commit -qm first )
printf '{"pid":%s,"sessionId":"linked-live-%s","cwd":"%s","startedAt":%s000,"kind":"interactive","status":"idle","statusUpdatedAt":%s000}\n' \
  "$$" "$$" "$lk_dir/code/shop" "$(date +%s)" "$(date +%s)" >"$lk_dir/claude/sessions/$$.json"
lk_cold() { # roots home words...; roots are names in lk_dir, colon separated
  lk_root="$1"; lk_home="$lk_dir/home-$2"; shift 2; mkdir -p "$lk_home"
  MINMACS_HOME="$lk_home" MINMACS_ROOTS="$(printf %s "$lk_root" | sed "s|[^:][^:]*|$lk_dir/&|g")" MINMACS_CLUTTER_ROOT="$lk_dir/clutter" MINMACS_COLD=1 GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$lk_dir/claude" CODEX_HOME="$lk_dir/codex" "$BIN" "$@" 2>/dev/null
}
lk_trees="' '.join(f['title'] for f in"

check "linked: under a root that is a link, the checkout's worktree finding is in its workstream" "shop" \
  "$(lk_cold root all work --json | json "$lk_trees [f for w in j['workstreams'] for f in w['findings']] if f['kind'] == 'worktree')")"
check "linked: work finds that workstream at the path under the link" "shop shop" \
  "$(lk_cold root kept work "$lk_dir/root/shop" --json | json "'%s %s' % (j['workstream']['name'], $lk_trees j['workstream']['findings'] if f['kind'] == 'worktree'))")"
check "linked: and at the resolved path" "shop shop" \
  "$(lk_cold root real work "$lk_dir/code/shop" --json | json "'%s %s' % (j['workstream']['name'], $lk_trees j['workstream']['findings'] if f['kind'] == 'worktree'))")"

# A server in a subfolder of the checkout. Its project name, its subfolder and its finding id come from the checkout
# LocoHost finds for its folder. A keep rule and a verdict hang on that id, so the link in the root must not move it:
# the same server read under the plain root gives the same three.
LK_PY='import http.server, os, sys
os.setsid()
open(os.path.join(sys.argv[2], "server-%d" % os.getpid()), "w").close()
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler).serve_forever()'
lk_port=$("$PORT" free $((50200 + $$ % 6000)))
( ( cd "$lk_dir/code/shop/web" && exec python3 -c "$LK_PY" "$lk_port" "$lk_dir/pids" "linked-fixture-$$" ) >/dev/null 2>&1 & )
"$PORT" wait "$lk_port"
for f in "$lk_dir"/pids/server-*; do [ -e "$f" ] && procs="$procs ${f##*server-}"; done
lk_host="'%s|%s|%s' % (j.get('project'), j.get('subdir'), j.get('findingID'))"
lk_plain=$(lk_cold code host-plain hosts "$lk_port" --json | json "$lk_host")
lk_linked=$(lk_cold root host-linked hosts "$lk_port" --json | json "$lk_host")
lk_tail=no
case "$lk_plain" in *"/code/shop/web:$lk_port") lk_tail=yes ;; esac
check "linked: a server in a subfolder has its project name, its subfolder and an id that ends in both, under a plain root" "shop/web|web|yes" \
  "${lk_plain%|*}|$lk_tail"
check "linked: under a root that is a link it keeps all three, the id to the letter" "$lk_plain" "$lk_linked"

# Issue #101: three more checkouts. done is merged and its agent finished three days ago, hid sits in a hidden folder
# that only .git/worktrees names, and wip holds a commit on no remote. Under the link the walk finds done and wip by the
# root's path, and .git/worktrees names all three by the resolved path git wrote. Each reader must see one checkout per
# folder with the git facts, keeps and ids of the plain root: before, the index held both names, WorkForest took the
# resolved one, and under a test home the git facts of a resolved path outside the roots were never read.
lk_then=$(date -v-3d +%Y-%m-%dT%H:%M:%S)
(
  export GIT_AUTHOR_DATE="$lk_then" GIT_COMMITTER_DATE="$lk_then"
  lk_git -C "$lk_dir/code/shop" worktree add -q -b done "$lk_dir/code/shop.wt/done" main 2>/dev/null
  cd "$lk_dir/code/shop.wt/done" && echo two >b.txt && lk_git add -A && lk_git commit -qm "done work"
  lk_git -C "$lk_dir/code/shop" merge -q --ff-only done
  lk_git -C "$lk_dir/code/shop" worktree add -q -b hid "$lk_dir/code/shop/.worktrees/hid" main 2>/dev/null
  printf '.worktrees/\n' >>"$lk_dir/code/shop/.git/info/exclude"
  lk_git -C "$lk_dir/code/shop" worktree add -q -b wip "$lk_dir/code/shop.wt/wip" main 2>/dev/null
  cd "$lk_dir/code/shop.wt/wip" && echo wip >c.txt && lk_git add -A && lk_git commit -qm "wip work"
)
lk_s="$lk_dir/claude/projects/$(printf %s "$lk_dir/code/shop.wt/done" | tr '/.' '--')"; mkdir -p "$lk_s"
python3 - "$lk_s/linked-done-$$.jsonl" "$lk_dir/code/shop.wt/done" <<'PY'
import datetime, json, sys
t = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=3)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": t, "cwd": sys.argv[2], "sessionId": "linked-done", "message": {"role": "user", "content": "Finish"}}) + "\n")
PY
for d in "$lk_s" "$lk_dir/code/shop.wt" "$lk_dir/code/shop/.worktrees"; do find "$d" -exec touch -h -t "$(date -v-3d +%Y%m%d%H%M)" {} + 2>/dev/null; done
lk_rows="'|'.join('%s %s %s %s' % (t['findingID'][len('workforest:worktree:$lk_dir/'):], t['merged'], t['gitKnown'], t.get('keep')) for t in sorted(j['trees'], key=lambda t: t['findingID']))"
lk_plain=$(lk_cold code rows-plain trees list --all --json | json "$lk_rows")
check "linked: the plain root lists four checkouts, done and hid merged, each with its git facts" \
  "code/shop None True the main checkout|code/shop.wt/done ancestor True None|code/shop.wt/wip None True 3 commits on no remote and not in main|code/shop/.worktrees/hid ancestor True None" \
  "$lk_plain"
check "linked: under a root that is a link, the same four with the same git facts, keeps and ids" "$lk_plain" \
  "$(lk_cold root rows-link trees list --all --json | json "$lk_rows")"
check "linked: with the link and its target both listed, each checkout once, the same four" "$lk_plain" \
  "$(lk_cold code:root rows-both trees list --all --json | json "$lk_rows")"
check "linked: and with the link listed first" "$lk_plain" "$(lk_cold root:code rows-both2 trees list --all --json | json "$lk_rows")"
lk_wrap="'%s %s %s' % (j['ready'], j['whyNot'], ' '.join(p['findingID'][len('workforest:worktree:$lk_dir/'):] for p in j['parts'] if p['step'] == 'worktree'))"
check "linked: the finished worktree wraps up under the plain root" "True None code/shop.wt/done" \
  "$(lk_cold code wrap-plain work wrap-up "$lk_dir/code/shop.wt/done" --dry-run --json | json "$lk_wrap")"
check "linked: and under a root that is a link, by its path there" "True None code/shop.wt/done" \
  "$(lk_cold root wrap-link work wrap-up "$lk_dir/root/shop.wt/done" --dry-run --json | json "$lk_wrap")"
check "linked: clean-up lists the two merged worktrees under the link, as under the plain root" "2 2" \
  "$(lk_cold code clean-plain trees clean-up --merged --dry-run | grep -c merged) $(lk_cold root clean-link trees clean-up --merged --dry-run | grep -c merged)"

# Stop the server this section started, by the pid its own pid file names, while its command line is still ours.
for f in "$lk_dir"/pids/server-*; do
  [ -e "$f" ] || continue
  lk_x=${f##*server-}
  case "$(ps -o command= -p "$lk_x" 2>/dev/null)" in *"linked-fixture-$$"*) kill "$lk_x" 2>/dev/null ;; esac
done
"$PORT" gone "$lk_port" 50
procs="$lk_procs_before"

# ===== end of linked =====
