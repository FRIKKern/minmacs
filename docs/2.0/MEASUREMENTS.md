# Measurements

Numbers measured on this Mac for MinMacs 2.0. Each section names the command that gave its numbers.

## Git

Issue #25: git facts in Know and FSEvents scanning. `./test.sh git` runs the bench as its last part and prints each number below as an `info` line. Other agents built and tested on this Mac at the same time, with load averages between 9 and 20 during the review runs, so wall times vary and CPU times are the steadier numbers.

**The fixture.** `test/git/benchfix.py` makes 10 repos with 300 commits each on main, and 9 linked worktrees per repo, so 100 checkouts in all. Per repo, 2 branches are merged by ancestry, 1 is squash-merged, 1 is cherry-picked and 5 are open. It took 30 to 40 seconds to build.

**The runs.** `test/git/gittool.m bench` does four things in one process:

1. A cold scan: a walk in the worker, then git facts for every worktree with no cache.
2. A warm full scan: the walk again, which reads every fingerprint from git's files.
3. One file changes in one worktree with FSEvents on, timed from the write until that worktree's facts show it.
4. One commit lands on one repo's default branch.

The table is the review's run inside the full `./test.sh`, after the `MMRun` fix below. The column "Before the MMRun fix" is the git section alone, run before that fix.

| Run | Wall | CPU | git runs | Before the MMRun fix | Notes |
|---|---|---|---|---|---|
| Cold scan, 100 worktrees | 12.85 s | 8.86 s | 940 | 55.76 s, 9.30 s CPU | 460 patch ids computed, 70 squash checks |
| Warm full scan, 100 worktrees | 0.201 s | 0.071 s | 0 | 0.200 s | 100 fingerprints read |
| One file changed | 0.031 s, FSEvents included | 0.013 s | 1 | 0.095 s | the update pass took 13 ms, 78 ms before |
| One default-branch commit | 0.740 s | 0.538 s | not counted | 4.240 s | 10 histories run again, 7 squash checks, 1 new patch id. The check marks the repo's git dir through `invalidate`, not through FSEvents |

Both warm numbers are under the one second of PLAN.md phase 2, and the checks fail above one second. The tool's peak RSS was 12 to 13 MB. The fixture took 31.7 to 33.4 s to build.

**The squash check.** WorkForest 0.1 read `git log -p --no-merges -n 400` of the default branch and piped it to `git patch-id` whenever the default branch's tip moved (`Trees.m:104-129`). That is 400 patch ids per repo each time. Run over the 10 fixture repos, it took 0.50 to 0.53 s and 0.44 to 0.46 s of CPU. The fixture's diffs are small. TESTS.md question 7 measured 2,279,287,237 bytes of that log output for one real repo. MinMacs 2.0 keeps a patch id per commit forever. On this bench:

- the cold scan computed 460 patch ids, once
- a warm scan computed none
- a new default-branch commit computed 1
- a branch merged by ancestry or tree is never checked

**One git run.** A scratch tool ran `git --version` 20 times through `MMRun`, then 20 times through a bare NSTask, three to six times for each build. The 2.0 code before issue #25 waited for NSTask's running flag in 50 ms poll steps and took 121 to 134 ms per run. The first kqueue `NOTE_EXIT` change took 35 to 74 ms, because `waitUntilExit` still noticed the exit 70 to 95 ms late on most runs. With the status taken from `NOTE_EXITSTATUS` and no `waitUntilExit` after a normal exit, it took 8.3 to 11.0 ms. A bare NSTask took 6.0 to 37.2 ms across all of these runs. 50 pairs of a git run and an `exit 3` run gave the right status every time and left no zombie child.
