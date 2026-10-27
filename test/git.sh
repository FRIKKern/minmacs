# Issue #25: git facts and FSEvents scanning in Know. Sourced by test.sh.
# Fixtures only: git repos, a bare origin and linked worktrees, all inside $MINMACS_HOME/git. The tool walks only
# those roots. The only processes it starts are its own worker child and git, which end with it.
# test/git/gittool.m links all of Sources/Core.

G="$MINMACS_HOME/git"
mkdir -p "$G"
G=$(cd "$G" && pwd -P)
GT="$G/gittool"
clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources \
  $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/git/gittool.m -framework Cocoa -framework IOKit \
  -framework UserNotifications -lsqlite3 -o "$GT" >"$G/clang.log" 2>&1
check "git: the tool builds" 0 "$?"
check "git: Know has no warnings under -Wextra" 0 "$(grep -c 'warning:' "$G/clang.log")"

export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
gq() { git -c init.defaultBranch=main -c advice.detachedHead=false "$@" >/dev/null 2>&1; }
gc() { # dir file text message
  printf '%s\n' "$3" >>"$1/$2"; gq -C "$1" add "$2"; gq -C "$1" commit -q -m "$4"
}
# One field of one worktree's facts in the last facts output.
# The tool keeps paths standardized, so /private/var reads as /var.
gf() { printf '%s' "$GO" | python3 -c "
import json,sys; j=json.load(sys.stdin); k=sys.argv[1]
k=k if k in j['facts'] else k[len('/private'):]
v=j['facts'][k]; print(v if v is None else v[sys.argv[2]])" "$1" "$2"; }
gs() { printf '%s' "$GO" | json "j['stats'].get('$1', 0)"; }
gt_up() { git -C "$1" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo None; }

echo "-- one repo with a remote: the fixture"
GR="$G/solo/roots"; mkdir -p "$GR/wt"
S="$GR/solo"; W="$GR/wt"
gq init -q --bare "$G/solo/origin.git"
gq clone -q "$G/solo/origin.git" "$S"
for i in 1 2 3 4 5; do gc "$S" base.txt "line $i" "base $i"; done
gq -C "$S" push -q -u origin main
gq -C "$S" remote set-head origin main
gq -C "$S" worktree add -q -b ff "$W/ff" main~2
gq -C "$S" worktree add -q -b sq "$W/sq" main
gc "$W/sq" sq1.txt one "sq one"; gc "$W/sq" sq2.txt two "sq two"
gq -C "$S" worktree add -q -b cp "$W/cp" main
gc "$W/cp" cp.txt picked "cp"
gq -C "$S" merge -q --squash sq; gq -C "$S" commit -q -m "squash sq"
gq -C "$S" cherry-pick cp
gc "$S" after.txt after "after"
gq -C "$S" worktree add -q -b tr "$W/tr" main
gc "$W/tr" tr.txt same "tr"
gc "$S" tr.txt same "the same file, made apart"
gq -C "$S" push -q origin main
gq -C "$S" worktree add -q -b open "$W/open" main
gc "$W/open" o1.txt first "o1"
gq -C "$W/open" push -q -u origin open
gc "$W/open" o2.txt second "o2"
printf 'stashed\n' >>"$W/open/o1.txt"; gq -C "$W/open" stash
printf 'dirty\n' >>"$W/open/o1.txt"; printf 'u\n' >"$W/open/u1.txt"; printf 'u\n' >"$W/open/u2.txt"
gq -C "$S" worktree add -q -b gone "$W/gone" main
gc "$W/gone" gone.txt gone "gone"
gq -C "$W/gone" push -q -u origin gone
gq clone -q "$G/solo/origin.git" "$G/solo/other"
gq -C "$G/solo/other" checkout -q open
gc "$G/solo/other" other.txt other "from another clone"
gq -C "$G/solo/other" push -q origin open
gq -C "$G/solo/other" push -q origin :gone
gq -C "$S" fetch -q --prune origin
gq -C "$S" worktree add -q --detach "$W/det" main~1
gq -C "$S" pack-refs --all
check "git: the fixture has 8 checkouts" 8 "$(git -C "$S" worktree list | grep -c .)"

echo "-- git facts from git's files and git"
GO=$("$GT" facts "$GR")
check "git: every checkout has facts" 8 "$(printf '%s' "$GO" | json "len([v for v in j['facts'].values() if v])")"
ok=yes
for d in "$S" "$W/ff" "$W/sq" "$W/cp" "$W/tr" "$W/open" "$W/gone" "$W/det"; do
  [ "$(gf "$d" head)" = "$(git -C "$d" rev-parse HEAD)" ] || ok="no: $d head"
  b=$(git -C "$d" branch --show-current); [ -n "$b" ] || b=None
  [ "$(gf "$d" branch)" = "$b" ] || ok="no: $d branch"
done
check "git: head and branch match git, with every ref packed" yes "$ok"
check "git: the default branch comes from origin/HEAD" origin/main "$(gf "$S" defaultBranch)"
check "git: the upstream is read from config" "$(gt_up "$W/open")" "$(gf "$W/open" upstream)"
check "git: ahead and behind the upstream match rev-list" \
  "$(git -C "$W/open" rev-list --left-right --count '@{u}...HEAD' | awk '{print $2 "/" $1}')" "$(gf "$W/open" ahead)/$(gf "$W/open" behind)"
check "  which the fixture made 1 and 1" 1/1 "$(gf "$W/open" ahead)/$(gf "$W/open" behind)"
check "git: dirty and untracked counts" "1/2" "$(gf "$W/open" dirty)/$(gf "$W/open" untracked)"
check "git: the stash count is per branch, from logs/refs/stash" "1/0" "$(gf "$W/open" stashes)/$(gf "$W/ff" stashes)"
check "git: commits not in the default branch" "$(git -C "$W/open" rev-list --count origin/main..HEAD)" "$(gf "$W/open" notInDefault)"
check "git: unpushed counts commits on no remote" "1/False" "$(gf "$W/open" unpushed)/$(gf "$W/open" onRemote)"
check "git: a pushed branch is on a remote" "0/True" "$(gf "$W/ff" unpushed)/$(gf "$W/ff" onRemote)"
check "git: a deleted remote branch shows as gone" "True|origin/gone" "$(gf "$W/gone" upstreamGone)|$(gf "$W/gone" upstream)"
check "git: no upstream set is None" None "$(gf "$W/sq" upstream)"
check "git: the last commit time matches git" "$(git -C "$W/cp" show -s --format=%ct HEAD)" "$(gf "$W/cp" lastCommit | cut -d. -f1)"
check "git: merged by ancestry" "ancestor|ancestor" "$(gf "$W/ff" merged)|$(gf "$W/det" merged)"
check "git: merged by squash, through the patch id of the whole branch" squash "$(gf "$W/sq" merged)"
check "git: merged by cherry-pick, every commit's patch id on the default branch" patch "$(gf "$W/cp" merged)"
check "git: merged by tree" tree "$(gf "$W/tr" merged)"
check "git: open and gone branches are not merged, nor the main checkout" "none|none|none" \
  "$(gf "$W/open" merged)|$(gf "$W/gone" merged)|$(gf "$S" merged)"
check "git: the squash check runs only for branches not merged by ancestry or tree" 4 "$(gs squashChecks)"
check "git: patch ids were computed on the first scan" yes "$([ "$(gs patchIdsComputed)" -gt 0 ] && echo yes || echo no)"
check "  and kept in the support folder" yes "$([ -s "$MINMACS_HOME/git.patchids.json" ] && echo yes || echo no)"

GO=$("$GT" facts "$GR")
check "git: a second launch reads the fingerprints and runs no git" "8|0|0|0" \
  "$(gs fingerprintReads)|$(gs statusRuns)|$(gs historyRuns)|$(gs gitRuns)"
check "  and the facts it kept are the same" squash "$(gf "$W/sq" merged)"
gc "$W/open" o3.txt third "o3"
GO=$("$GT" facts "$GR")
check "git: a commit in one worktree runs git for that worktree alone" "1|1" "$(gs statusRuns)|$(gs historyRuns)"
check "  and moves its facts" "2/1/2" "$(gf "$W/open" ahead)/$(gf "$W/open" dirty)/$(gf "$W/open" untracked)"
check "  with no new patch id" 0 "$(gs patchIdsComputed)"

echo "-- fresh reads, never on main"
GO=$("$GT" fresh "$W/open")
check "git: wait YES runs git for the status now" "1|1" "$(printf '%s' "$GO" | json "'%d|%d' % (j['fresh']['dirty'], j['stats']['statusRuns'])")"
check "  wait YES on main returns nil" nil "$(printf '%s' "$GO" | json "j['waitOnMain']")"
check "  MMGit on main runs nothing" "nil|-1" "$(printf '%s' "$GO" | json "'%s|%d' % (j['gitOnMain'], j['gitOnMainStatus'])")"
check "git: git runs with GIT_OPTIONAL_LOCKS=0 and a timeout" yes \
  "$(grep -q '@"GIT_OPTIONAL_LOCKS": @"0"' Sources/Core/Know/MMGit.m && grep -q 'MMRun(git' Sources/Core/Know/MMGit.m && echo yes || echo no)"
check "git: no git spawn outside MMGit.m in Core" 0 \
  "$(grep -rnE 'launchedTaskWithLaunchPath|/usr/bin/git|NSTask new' Sources/Core/Know/MMGitFacts.m Sources/Core/Know/MMRepoIndex.m | grep -c .)"

echo "-- FSEvents marks one worktree"
gt_idn() { ls "$MINMACS_HOME" | grep -c '^repos\..*\.eventid$'; }
gt_ids=$(gt_idn)
GO=$("$GT" watch "$GR" "$W/open/base.txt" "$W/cp/cp.txt")
gw() { printf '%s' "$GO" | json "j['$1']"; }
check "git: a change to one file shows in that worktree's facts" "1|2" "$(gw dirtyBefore)|$(gw dirtyAfter)"
check "  within a second, FSEvents latency included" yes "$(printf '%s' "$GO" | json "'yes' if 0 <= j['seconds'] < 1 else j['seconds']")"
check "  git status ran for that worktree alone, and no history" "1|0" "$(gw statusRuns)|$(gw historyRuns)"
check "  another worktree keeps its facts" 0 "$(gw otherDirty)"
check "  the size of the changed worktree goes stale, the other's does not" 1 "$(gw sizeWalksQueued)"
check "  a stale size is still shown until the walk ends" yes "$(printf '%s' "$GO" | json "'yes' if j['staleSizeFiles'] == j['sizeFiles'] > 0 else j")"
check "git: git add in a worktree reads its fingerprint again and starts no walk" "1|0" "$(gw addStatusRuns)|$(gw addWalks)"
check "git: the root's stream saved its own event id" 1 "$(($(gt_idn) - gt_ids))"

echo "-- a restart reads only what changed"
"$GT" restart-a "$GR" >/dev/null
printf 'while no MinMacs ran\n' >>"$W/cp/cp.txt"
GO=$("$GT" restart-b "$GR" "$W/cp")
check "git: the replay from the saved event id marks the changed worktree" 1 "$(printf '%s' "$GO" | json "j['facts']['dirty']")"
check "  and git status runs for it alone" "1|0" "$(gs statusRuns)|$(gs historyRuns)"

echo "-- bench: about 100 worktrees"
GB="$G/bench/roots"; mkdir -p "$GB"
gb_t0=$(python3 -c 'import time; print(time.time())')
python3 test/git/benchfix.py "$GB" 10 300 >"$G/bench.json"
check "git: the bench fixture builds" 0 "$?"
echo "  info  fixture built in $(python3 -c "import time; print('%.1f s' % (time.time() - $gb_t0))")"
GO=$("$GT" bench "$GB" "$GB/wt/r0-5/f0.txt" "$GB/r3")
printf '%s\n' "$GO" >"$G/bench.out"
gbv() { printf '%s' "$GO" | json "$1"; }
check "git: the bench walks 100 worktrees and has facts for each" "100|100" "$(gbv "'%d|%d' % (j['worktrees'], j['withFacts'])")"
check "git: merge kinds across the bench" "ancestor=20 none=60 patch=10 squash=10" \
  "$(gbv "' '.join('%s=%d' % kv for kv in sorted(j['merged'].items()))")"
check "git: a warm full scan runs no git" 0 "$(gbv "j['warmFullGitRuns']")"
check "  and takes under a second" yes "$(gbv "'yes' if j['warmFullSeconds'] < 1 else j['warmFullSeconds']")"
check "git: after one file changes, git runs for one worktree" 1 "$(gbv "j['changeRan']")"
check "  and the warm scan takes under a second, FSEvents included" yes "$(gbv "'yes' if 0 <= j['changeSeconds'] < 1 else j['changeSeconds']")"
check "git: a new default-branch commit computes one new patch id" 1 "$(gbv "j['defaultMovedPatchIds']")"
check "  for the repo's 10 worktrees alone" 10 "$(gbv "j['defaultMovedHistories']")"
echo "  info  cold $(gbv "'%.2f s, %.2f s CPU, %d git runs, %d patch ids, %d squash checks' % (j['coldSeconds'], j['coldCPU'], j['coldStats']['gitRuns'], j['coldStats']['patchIdsComputed'], j['coldStats']['squashChecks'])")"
echo "  info  warm full $(gbv "'%.3f s, %.3f s CPU, %d checked' % (j['warmFullSeconds'], j['warmFullCPU'], j['warmFullChecked'])")"
echo "  info  one file $(gbv "'%.3f s end to end, pass %d ms, %d git runs, %.3f s CPU' % (j['changeSeconds'], j['changePassMs'], j['changeGitRuns'], j['changeCPU'])")"
echo "  info  default moved $(gbv "'%.3f s, %.3f s CPU, %d squash checks' % (j['defaultMovedSeconds'], j['defaultMovedCPU'], j['defaultMovedSquashChecks'])")"
echo "  info  peak RSS $(gbv "'%.0f MB' % j['peakRSSMB']")"
# What WorkForest 0.1 ran per repo whenever the default tip moved: patch ids of the newest 400 commits.
gb_wf=$(python3 - "$GB" <<'PYEOF'
import subprocess, sys, time, resource
t = time.time(); c0 = resource.getrusage(resource.RUSAGE_CHILDREN)
for k in range(10):
    d = "%s/r%d" % (sys.argv[1], k)
    subprocess.run("git -C %s log -p --no-merges --no-color -n 400 --format='commit %%H' main | git -C %s patch-id --stable >/dev/null" % (d, d),
                   shell=True, check=True)
c1 = resource.getrusage(resource.RUSAGE_CHILDREN)
print("%.2f s, %.2f s CPU" % (time.time() - t, (c1.ru_utime + c1.ru_stime) - (c0.ru_utime + c0.ru_stime)))
PYEOF
)
echo "  info  WorkForest's DefaultPatchIds over the 10 repos: $gb_wf"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
