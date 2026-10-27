# ===== Act: modes, MustKeep, plans, MMRunAction, undo, stop, keep-awake and the notifier, issue #18 =====
# Sourced by test.sh. It builds test/act/act.m with Sources/Core/Act and the doubles in test/act,
# makes a fixture repo with a worktree inside $MINMACS_HOME, and runs the checks.
# The test binary starts its own fixture processes, which exit on their own when it ends, and stops only those.
# It passes the real Trash only fixture files, and restores each one, so the Trash ends as it began.

act_dir="$MINMACS_HOME/act"
mkdir -p "$act_dir/fixtures"
act_cc="clang -fobjc-arc -mmacosx-version-min=14.0 -ISources -Itest/act -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
$act_cc $(find Sources/Core/Act -name '*.m' | LC_ALL=C sort) test/act/doubles.m test/act/act.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -o "$act_dir/acttest" >"$act_dir/build.log" 2>&1
act_r=$?
check "act: the test binary builds with no warnings" 0 "$act_r"
[ "$act_r" = 0 ] || tail -20 "$act_dir/build.log"
clang -Wall -Werror -o "$act_dir/fixture" test/act/fixture.c >>"$act_dir/build.log" 2>&1
check "act: the fixture process builds" 0 "$?"

# Nothing in Act deletes a file for good or empties the Trash.
check "act: no permanent delete in Sources/Core/Act" 0 \
  "$(grep -nE 'removeItemAt|unlink\(|rmdir\(|emptyTrash|rm -rf' Sources/Core/Act/*.m | grep -c .)"

# A fixture repo with a bare remote, and a worktree whose one commit is on no remote and whose .env.local is ignored.
act_git() { GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.com GIT_COMMITTER_NAME=fixture \
  GIT_COMMITTER_EMAIL=fixture@example.com git "$@" >/dev/null 2>&1; }
act_fx="$act_dir/fixtures"
act_git init -q --bare "$act_fx/remote.git"
act_git -c init.defaultBranch=main init -q "$act_fx/repo"
printf '.env.local\n' >"$act_fx/repo/.gitignore"
act_git -C "$act_fx/repo" add .gitignore
act_git -C "$act_fx/repo" commit -qm first
act_git -C "$act_fx/repo" remote add origin "$act_fx/remote.git"
act_git -C "$act_fx/repo" push -q origin main
act_git -C "$act_fx/repo" worktree add -q -b feature "$act_fx/wt"
printf 'work\n' >"$act_fx/wt/work.txt"
act_git -C "$act_fx/wt" add work.txt
act_git -C "$act_fx/wt" commit -qm "work on no remote"
printf 'secret=1\n' >"$act_fx/wt/.env.local"
check "act: the fixture worktree has one commit on no remote" 1 \
  "$(git -C "$act_fx/wt" rev-list --count HEAD --not --remotes 2>/dev/null)"

if [ "$act_r" = 0 ]; then
  ACT_REPO="$act_fx/repo" ACT_WORKTREE="$act_fx/wt" "$act_dir/acttest" "$act_dir/fixture" "$act_fx" \
    >"$act_dir/out.txt" 2>"$act_dir/err.txt"
  act_r=$?
  check "act: the checks ran to the end" "0 END" "$act_r $(tail -1 "$act_dir/out.txt")"
  [ "$act_r" = 0 ] || tail -10 "$act_dir/err.txt"
  act_tab=$(printf '\t')
  while IFS="$act_tab" read -r act_tag act_name act_want act_got; do
    [ "$act_tag" = CHECK ] && check "$act_name" "$act_want" "$act_got"
  done <"$act_dir/out.txt"
fi
