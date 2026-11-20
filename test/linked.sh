# ===== A repo reached through a root that is a link =====
# Sourced by test.sh after core. Fixtures only, all inside $MINMACS_HOME/linked.<pid>: one repo in code/, a link named
# root that leads to code/, and a session status file that names this shell's own pid in the repo, by the resolved
# path as the kernel gives it. No process starts. The built binary reads them cold with the link as its only root.
# The repo index keeps the checkout as root/shop, WorkForest names its finding code/shop, and the graph compared the
# two as text: the worktree finding had no workstream, and `work` found none at the path. The same held for any home
# under /tmp or /var/folders, which lead to /private. Every run here is a read.

lk_dir="$(cd "$MINMACS_HOME" && pwd -P)/linked.$$"
mkdir -p "$lk_dir/code" "$lk_dir/claude/sessions" "$lk_dir/claude/projects" "$lk_dir/codex" "$lk_dir/clutter"
ln -s "$lk_dir/code" "$lk_dir/root"
lk_git() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
lk_git init -q "$lk_dir/code/shop"
( cd "$lk_dir/code/shop" && echo one >a.txt && lk_git add -A && lk_git commit -qm first )
printf '{"pid":%s,"sessionId":"linked-live-%s","cwd":"%s","startedAt":%s000,"kind":"interactive","status":"idle","statusUpdatedAt":%s000}\n' \
  "$$" "$$" "$lk_dir/code/shop" "$(date +%s)" "$(date +%s)" >"$lk_dir/claude/sessions/$$.json"
lk_cold() { # home words...
  lk_home="$lk_dir/home-$1"; shift; mkdir -p "$lk_home"
  MINMACS_HOME="$lk_home" MINMACS_ROOTS="$lk_dir/root" MINMACS_CLUTTER_ROOT="$lk_dir/clutter" MINMACS_COLD=1 GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$lk_dir/claude" CODEX_HOME="$lk_dir/codex" "$BIN" "$@" 2>/dev/null
}
lk_trees="' '.join(f['title'] for f in"

check "linked: under a root that is a link, the checkout's worktree finding is in its workstream" "shop" \
  "$(lk_cold all work --json | json "$lk_trees [f for w in j['workstreams'] for f in w['findings']] if f['kind'] == 'worktree')")"
check "linked: work finds that workstream at the path under the link" "shop shop" \
  "$(lk_cold kept work "$lk_dir/root/shop" --json | json "'%s %s' % (j['workstream']['name'], $lk_trees j['workstream']['findings'] if f['kind'] == 'worktree'))")"
check "linked: and at the resolved path" "shop shop" \
  "$(lk_cold real work "$lk_dir/code/shop" --json | json "'%s %s' % (j['workstream']['name'], $lk_trees j['workstream']['findings'] if f['kind'] == 'worktree'))")"

# ===== end of linked =====
