# Measurements

Numbers measured on this Mac for MinMacs 2.0. Each section names the command that gave its numbers.

## Git

Issue #25: git facts in Know and FSEvents scanning. `./test.sh git` runs the bench as its last part and prints each number below as an `info` line. Other agents built and tested on this Mac at the same time, with load averages between 15 and 45, so wall times are high and CPU times are the steadier numbers.

**The fixture.** `test/git/benchfix.py` makes 10 repos with 300 commits each on main, and 9 linked worktrees per repo, so 100 checkouts in all. Per repo, 2 branches are merged by ancestry, 1 is squash-merged, 1 is cherry-picked and 5 are open. It took 30 to 40 seconds to build.

**The runs.** `test/git/gittool.m bench` does four things in one process:

1. A cold scan: a walk in the worker, then git facts for every worktree with no cache.
2. A warm full scan: the walk again, which reads every fingerprint from git's files.
3. One file changes in one worktree with FSEvents on, timed from the write until that worktree's facts show it.
4. One commit lands on one repo's default branch.

| Run | Wall | CPU | git runs | Notes |
|---|---|---|---|---|
| Cold scan, 100 worktrees | 53.4 s | 9.14 s | 940 | 460 patch ids computed, 70 squash checks |
| Warm full scan, 100 worktrees | 0.198 s | 0.046 s | 0 | 100 fingerprints read |
| One file changed | 0.085 s, FSEvents included | 0.013 s | 1 | the update pass took 79 ms |
| One default-branch commit | 3.96 s | 0.53 s | not counted | 10 histories run again, 7 squash checks, 1 new patch id |

Five runs of the section, the last inside the full ./test.sh, gave warm full scans of 0.198 to 0.573 s, and one-file changes of 0.085 to 0.154 s end to end. Both are under the one second of PLAN.md phase 2. The tool's peak RSS was 12 to 13 MB. The checks fail above one second.

**The squash check.** WorkForest 0.1 read `git log -p --no-merges -n 400` of the default branch and piped it to `git patch-id` whenever the default branch's tip moved (`Trees.m:104-129`). That is 400 patch ids per repo each time. Run over the 10 fixture repos, it took 0.47 s and 0.45 s of CPU. The fixture's diffs are small. TESTS.md question 7 measured 2,279,287,237 bytes of that log output for one real repo. MinMacs 2.0 keeps a patch id per commit forever. On this bench:

- the cold scan computed 460 patch ids, once
- a warm scan computed none
- a new default-branch commit computed 1
- a branch merged by ancestry or tree is never checked

**One git run.** `MMRun` waited for NSTask's running flag in 50 ms poll steps. A loop of 20 `git --version` runs through `MMGit` took 129.1 ms per run, against 6.4 ms for a bare NSTask. With a kqueue `NOTE_EXIT` in the poll it took 8.5 ms, against 5.9 ms. The cold scan fell from 110.9 s to 47.5 s of wall time with the same 940 git runs. The load changed between those two runs too.
