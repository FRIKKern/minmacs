# ===== Fixes after wave 3: the test Trash, git in MMUndo, the by words, the log off main, the old event id file,
# WorkForest's keep and protect, and Insomnia's hold =====
# Sourced by test.sh. test/fixes/fixes.m links every .m under Sources but main.m. Its fixtures live in
# $MINMACS_HOME/fixes<pid>: files to trash, a git repo with a worktree, a logging git wrapper and a support folder.
# Nothing here touches the person's Trash, git config or files, and it starts no process that outlives a check.

fx_dir="$(cd "$MINMACS_HOME" && pwd -P)/fixes$$"
mkdir -p "$fx_dir/bin"
fx_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' | LC_ALL=C sort)
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -ISources -DMM_VERSION='"2.0.0"' \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $fx_src test/fixes/fixes.m -o "$fx_dir/bin/fixes" >"$fx_dir/clang.log" 2>&1
fx_r=$?
check "fixes: the test tool builds" 0 "$fx_r"
check "fixes: no warnings under -Wextra" 0 "$(grep -c 'warning:' "$fx_dir/clang.log")"
[ "$fx_r" = 0 ] || tail -20 "$fx_dir/clang.log"
fx_tab=$(printf '\t')
fx_run() { while IFS="$fx_tab" read -r fx_tag fx_n fx_w fx_g; do [ "$fx_tag" = CHECK ] && check "$fx_n" "$fx_w" "$fx_g"; done; }

echo "-- the Trash of a test home, and git through MMGitPath and MMRun"
check "fixes: MMUndo names no git binary of its own" 0 "$(grep -c '/usr/bin/git' Sources/Core/Act/MMUndo.m)"
check "fixes: MMUndo runs git through MMGitPath and MMRun" "1 1" \
  "$(grep -c 'NSString \*git = MMGitPath();' Sources/Core/Act/MMUndo.m) $(grep -c 'MMRun(git, ' Sources/Core/Act/MMUndo.m)"
fx_git() { GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.com GIT_COMMITTER_NAME=fixture \
  GIT_COMMITTER_EMAIL=fixture@example.com git "$@" >/dev/null 2>&1; }
fx_repo="$fx_dir/repo"; fx_wt="$fx_dir/wt"
fx_git -c init.defaultBranch=main init -q "$fx_repo"
printf 'x\n' >"$fx_repo/a.txt"; fx_git -C "$fx_repo" add a.txt; fx_git -C "$fx_repo" commit -qm first
fx_git -C "$fx_repo" worktree add -q -b fixes-feature "$fx_wt"
printf 'y\n' >"$fx_wt/b.txt"; fx_git -C "$fx_wt" add b.txt; fx_git -C "$fx_wt" commit -qm "on no remote"
# The wrapper logs each call with the prompt setting MMRun gave it, then runs the git on PATH.
fx_realgit=$(command -v git)
cat >"$fx_dir/bin/fixes-git" <<EOF
#!/bin/sh
printf '%s GIT_TERMINAL_PROMPT=%s\n' "\$*" "\$GIT_TERMINAL_PROMPT" >>"$fx_dir/git.log"
exec "$fx_realgit" "\$@"
EOF
chmod +x "$fx_dir/bin/fixes-git"
if [ "$fx_r" = 0 ]; then
  mkdir -p "$fx_dir/undo"
  MINMACS_HOME="$fx_dir/undo" MINMACS_GIT="$fx_dir/bin/fixes-git" FIXES_GIT_LOG="$fx_dir/git.log" \
    "$fx_dir/bin/fixes" undo "$fx_repo" "$fx_wt" >"$fx_dir/undo.out" 2>"$fx_dir/undo.err"
  check "fixes: the undo checks ran to the end" "0 END" "$? $(tail -1 "$fx_dir/undo.out")"
  fx_run <"$fx_dir/undo.out"
fi

echo "-- every by word MMRunAction gets is one MMAct.h lists"
# The words in MMAct.h's comment on MMRunAction, and every literal or mode name passed as by at a call site.
check "fixes: MMRunAction's callers pass only the by words MMAct.h lists" "" "$(python3 - <<'PY'
import re, glob
h = open('Sources/Core/Act/MMAct.h').read()
if '/// by says who asked' not in h:
    print('MMAct.h has no list of by words'); raise SystemExit
doc = h[h.index('/// by says who asked'):h.index('MMUndoRecord *MMRunAction(')]
listed = set(re.findall(r'"([a-z]+)"', doc))
used = set()
for f in glob.glob('Sources/**/*.m', recursive=True):
    t = open(f).read()
    for m in re.finditer(r'MMRunAction\(', t):
        call = t[m.end():m.end() + 400]
        if call.startswith('id<MMAction>'):
            continue
        used.update(re.findall(r'@"([a-z]+)"', call.split(';')[0])[:1])
        if 'MMModeName(' in call.split(';')[0]:
            used.update(['proactive', 'eager'])
    # A caller that passes by on, such as -set:value:by: or -hold:reason:by:rid:, gets its word as by:@"word".
    used.update(re.findall(r'\bby:@"([^"]*)"', t))
print(' '.join(sorted(used - listed)))
PY
)"
check "fixes: guard is one of them" yes "$(grep -q '"guard" from an expert' Sources/Core/Act/MMAct.h && grep -q '"guard"' Sources/Core/Act/MMUndo.h && echo yes || echo no)"

echo "-- the log opens off main, and the old event id file goes"
if [ "$fx_r" = 0 ]; then
  mkdir -p "$fx_dir/start/roots" "$fx_dir/start/claude" "$fx_dir/start/codex"
  MINMACS_HOME="$fx_dir/start" MINMACS_ROOTS="$fx_dir/start/roots" CLAUDE_CONFIG_DIR="$fx_dir/start/claude" CODEX_HOME="$fx_dir/start/codex" \
    "$fx_dir/bin/fixes" start >"$fx_dir/start.out" 2>"$fx_dir/start.err"
  check "fixes: the start checks ran to the end" "0 END" "$? $(tail -1 "$fx_dir/start.out")"
  fx_run <"$fx_dir/start.out"
fi
check "fixes: MMCoreStart opens the log off main before anything else" 1 \
  "$(awk '/^void MMCoreStart/,/^}/' Sources/Core/MMCore.m | grep -c '^    MMLogOpenOffMain();')"

echo "-- WorkForest's keep and protect change state, so they need the app"
fx_tree="$fx_dir/cli-tree"; mkdir -p "$fx_tree" "$fx_dir/cli"
fx_wf() { MINMACS_HOME="$fx_dir/cli" MINMACS_COLD=1 MINMACS_ROOTS="$fx_dir/cli" "$BIN" "$@"; }
fx_wf trees keep "$fx_tree" >/dev/null 2>&1
check "fixes: trees keep without the app exits 3" 3 "$?"
fx_wf trees protect "$fx_tree" >/dev/null 2>&1
check "fixes: trees protect without the app exits 3" 3 "$?"
check "fixes: and neither wrote a keep or a protect rule" 0 \
  "$(cat "$fx_dir/cli/workforest/"*.json 2>/dev/null | grep -c "$fx_tree")"
check "fixes: trees keep --dry-run says what it would do" "would keep $fx_tree for 7 days" "$(fx_wf trees keep "$fx_tree" --dry-run 2>/dev/null)"
check "fixes: trees protect --dry-run says what it would do" "would protect $fx_tree" "$(fx_wf trees protect "$fx_tree" --dry-run 2>/dev/null)"
check "fixes: the dry runs wrote nothing either" 0 "$(cat "$fx_dir/cli/workforest/"*.json 2>/dev/null | grep -c "$fx_tree")"

echo "-- Insomnia's hold has a record"
check "fixes: insomnia hold runs through MMRunAction" "0 1" \
  "$(grep -c 'holdAwake' Sources/Experts/Insomnia/MMINCLI.m) $(grep -c 'MMRunAction(a, _policy, nil, by, a.why' Sources/Experts/Insomnia/MMInsomniaExpert.m)"
# ===== end of fixes =====
