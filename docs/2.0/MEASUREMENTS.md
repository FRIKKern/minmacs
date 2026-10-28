# Measurements

Issues #23 and #51. What MinMacs 2.0 costs at rest on the research Mac, against the old apps that ran over the same window, and how long its menus take to build. Every number here comes from `tools/bench/run.sh`. Each run writes its raw JSON, `report.md` and `gate.txt` to its output folder under `build/`, which git ignores.

**The Mac.** MacBookPro18,1, 10 cores, macOS 27.0.1. Other agents built and tested in other worktrees during every run. The load average was 16 to 79 over the window below, and up to 120 during the short runs.

## How it is measured

- `tools/bench/bench idle` starts `MMCoreStart` with every built-in expert in one process. It loads AppKit with no status item, window or Dock icon, and runs main at user-interactive QoS, as the app does. On `main` at 308814e two experts link: MinMacs and LocoHost.
- Every mode is set to Idle in a fresh `MINMACS_HOME`. Senses samples the real process table and power facts. The model, cmux and tmux CLIs are `/usr/bin/false`, and `CLAUDE_CONFIG_DIR` and `CODEX_HOME` point into that home. So the bench reads no real session file, and the review wake at one minute fails at once.
- After a warm-up, the bench reads itself with `getrusage` for CPU, `task_info` `TASK_VM_INFO` for footprint and resident size, and `TASK_POWER_INFO` for wakeups, at the start and end of the window. `proc_pid_rusage` on itself gives the same CPU to three places.
- The old apps are found by the path of their executable inside the bundle. MinMacs counts only when its bundle says version 1. They are read with `proc_pid_rusage` and `ps` at the same start and end. Nothing signals them.
- Tick times come two ways. In the window, main reads the process CPU clock at each sample signal and at each new snapshot. After the window, each part runs alone on one thread, timed with the thread CPU clock, each on a new sample, since a sample keeps the args and cwd it read.
- `tools/bench/bench menus` builds each expert's menu from a fixture snapshot, 200 times, with a new snapshot generation each time so no per-snapshot cache answers. Menu open is what `menuNeedsUpdate:` does on main: `menuFor:`, every row's card, and the NSMenu. Card hover is one card's spec and view, then its layout and drawing into a bitmap. LocoHost's fixture is 12 servers, MinMacs's is 20 apps and 2 agents.

## 2.0 against the old apps, issue #23

Ten minutes from 21:03:19 UTC on 2026-10-27, after 30 seconds of warm-up. `tools/bench/run.sh 600 30 200`.

| App | CPU % | CPU s a minute | Footprint MB | Resident MB | Peak footprint MB | Wakeups a second |
|---|---|---|---|---|---|---|
| MinMacs 2.0, MinMacs and LocoHost, headless | 1.489 | 0.893 | 12.00 | 32.94 | 12.47 | 0.423 |
| LocoHost 0.1.0 | 0.886 | 0.532 | 39.63 | 40.12 | 82.33 | 1.212 |
| WorkForest 0.1.0 | 10.561 | 6.337 | 173.67 | 58.38 | 5056.07 | 1.437 |
| Insomnia 1.3.0 | 0.061 | 0.037 | 46.31 | 27.81 | 52.08 | 0.195 |
| The three old apps together | 11.508 | 6.906 | 259.61 | 126.31 | | 2.844 |

MinMacs 1.2 did not run, so it has no row. Idle wakeups, the ones that woke the package from idle, were 0 for every row.

`ps` at the window's ends:

| App | RSS KB start | RSS KB end | CPU time start | CPU time end | Running for |
|---|---|---|---|---|---|
| LocoHost | 161920 | 41088 | 4:25.69 | 4:31.04 | 6h41m |
| WorkForest | 26576 | 59776 | 15:10.19 | 16:13.56 | 6h36m |
| Insomnia | 29056 | 28480 | 23:42.55 | 23:42.92 | 22d13h |

What the numbers show:
- 2.0 with two experts used more CPU than LocoHost alone over this window: 1.49 % against 0.89 %. Short runs of 30 seconds gave 0.89 % to 1.33 %. It is over the phase 1 target of 0.5 % and the phase 6 budget of 0.3 %.
- WorkForest scanned in this window. It used 63 seconds of CPU, which is most of the old apps' total.
- 2.0's footprint was 12 MB, against LocoHost's 40 MB and Insomnia's 46 MB. This bench draws no status item or menu, so the app's footprint will be higher. This number is not the app's.
- 2.0 woke 0.42 times a second, under the budget of 1, and under LocoHost's 1.21.

## The tick

The same run, in CPU ms. 174 samples and 192 snapshots in the window, 852 pids, 4.987 seconds between samples at the median.

| Part | Median | p95 | Max |
|---|---|---|---|
| In the window: from the last snapshot to the next sample signal | 7.60 | 14.85 | 20.57 |
| In the window: rebuild, from the sample signal to the snapshot on main | 39.09 | 54.34 | 66.29 |
| In the window: rebuild wall time | 55.78 | 151.51 | 687.65 |
| Alone: Senses pass | 6.31 | 6.81 | 7.16 |
| Alone: the facts of a rebuild | 12.62 | 13.46 | 14.92 |
| Alone: the snapshot from those facts | 13.40 | 15.31 | 19.27 |
| Alone, own sample: registry `agentsIn:power:` | 9.21 | 9.87 | 11.61 |
| Alone, own sample: `MMSessions refresh` with no session files | 3.33 | 3.68 | 3.69 |
| Alone, own sample: LocoHost `findingsFrom:` | 9.00 | 10.14 | 10.46 |
| Alone, own sample: MinMacs `findingsFrom:` | 3.78 | 4.02 | 4.05 |

**Slow spot, reported and not fixed here.** A tick costs about 46 ms of CPU: 6 ms for the pass and 39 ms for the rebuild. At one tick every 5 seconds that alone is 0.9 % of a core. The rebuild costs six times the pass. About half of it is reading process arguments: the registry's `agentsIn:` takes 9.2 ms on a new sample and LocoHost's findings 9.0 ms, together 18 of the 39 ms. Each falls to under 1 ms when the sample already holds the args. A 10-second run of `bench idle --tick-runs 10` timed each part twice on one sample: the registry took 9.64 ms and then 0.24 ms at the median, LocoHost's findings 10.81 ms and then 0.70 ms. MinMacs's findings took 3.65 ms and then 3.42 ms, so its cost is not the args. Every rebuild runs both on every sample, even when no process started or ended. A budget of 0.3 % leaves 15 ms a tick, so with the pass at 6 ms the rebuild must come under about 9 ms.

## Menus

200 builds each, wall ms on main. Same run.

| Expert | Fixture | Rows | Spec median | Menu open median | Menu open p95 | Card hover median | Card hover p95 |
|---|---|---|---|---|---|---|---|
| LocoHost | 12 servers | 12 | 1.80 | 26.40 | 28.43 | 6.61 | 7.29 |
| MinMacs | 20 apps, 2 agents | 14 | 0.44 | 22.02 | 23.78 | 4.82 | 5.73 |
| One Icon, both | | | | 12.66 | 14.04 | | |

**Slow spot, reported and not fixed here.** Menu open is within 30 ms at p95, by less than 2 ms for LocoHost. A 40-build run in `./test.sh bench` under load gave 31.8 ms at p95 for LocoHost, over the budget. The spec takes 2 ms or less. The rest is the card under every row, which `MMMenuFromSpec` builds before the menu opens, at about 2 ms each. Menu open grows with the number of rows that have a card. Card hover is well under 16 ms.

## The regression gate, issue #51

`tools/bench/budgets.json` holds the phase 6 budgets of PLAN.md section 9. Each also has a ceiling: the line today's code must stay under. `test/bench.sh` runs a 30-second idle window and 40 menu builds per expert, about 50 seconds, then `tools/bench/gate.py`.

| Budget | Phase 6 | Ceiling | This run |
|---|---|---|---|
| Idle CPU | 0.3 % | 5 % | 1.489 %, over the budget |
| CPU a tick, pass and rebuild at the median | 15 ms | 80 ms | 46.69 ms, over the budget |
| Idle footprint | 45 MB | 45 MB | 12.00 MB, headless |
| Wakeups a second | under 1 | under 1 | 0.423 |
| Menu open at p95, worst expert | 30 ms | 60 ms | 28.43 ms, LocoHost |
| Card hover at p95, worst expert | 16 ms | 32 ms | 7.29 ms, LocoHost |
| Warm scan of 300 worktrees | 2 s | | not measured, WorkForest is not merged |
| Icons after launch | 300 ms | | not measured, the bench makes no status item |

A value over the phase 6 budget and under its ceiling prints as `over` and passes, so `./test.sh` passes while idle CPU waits for phase 6. Over the ceiling fails. `MM_BENCH_STRICT=1` fails on the phase 6 budgets themselves. Idle CPU over 30 seconds moves with how many processes start and end on the Mac, since each exit of a watched process adds a sample and a rebuild. One full `./test.sh` run measured 2.81 % in that window, against 0.89 % to 1.33 % in runs of the section alone. So the idle CPU ceiling is loose at 5 %, and the CPU a tick carries the tight one. Its budget of 15 ms is 0.3 % of a core over the 5-second tick, and its ceiling of 80 ms sits about 1.7 times above today's 46.69 ms. That full `./test.sh` run measured 61.76 ms a tick, so the ceiling has little room under heavy load. The menu ceilings sit at twice the budget, because the menu numbers are wall time and other builds on this Mac move them.

## Review

Issues #32, #33, #34 and #36. What the review broker sends to the model in one day, against what LocoHost 0.1 and WorkForest 0.1 sent. Every number here comes from the last part of `./test.sh review`, which prints each one as an `info` line. No real model ran. The fake claude in `test/review` answered every call and counted its tokens.

**How cost is counted.** Decision 10 measures review cost as uncached tokens and list cost.

- The broker records every call's usage with `-[MMBudget record:expert:]`, as a `usage` row in the SQLite log, with input, both cache writes, cache reads, output and thinking.
- Uncached is input plus both cache writes plus output. Cache reads are left out. The 0.1 apps added cache reads at full weight. The tables give that sum too, as "as counted before".

**The fixture.** `test/review/dayfix.py` writes one day of findings for all five experts, as the graph holds them at each of 24 hourly reviews. The day is made, not recorded on a real Mac. Its counts follow research F:

- 91 linked worktrees in 10 repos at the start, 58 percent merged in some way. 12 of them get work in the day and 20 more are made in the day, so 32 trees get work. 8 of those merge after their last work, and 10 old merged trees are removed.
- LocoHost's 5 servers: 2 shared services, 2 dev servers in one worktree, one of which restarts at hour 10, and one dev server left in an old merged worktree.
- 20 apps for MinMacs, 30 clutter items for Noo-Noo and 3 agents for Insomnia.

The test checks the SHA-256 of the written file, so a change to the day is a deliberate one.

**The counting.** `test/review/fakecount.py` counts the same way for both runs:

- A token is 4 bytes of UTF-8. Research F assumes 3 to 4 bytes. All the totals rest on this guess.
- The system prompt and the schema are the cached prefix. A call reads them from cache when the same prefix was used within the TTL on the replay's clock, and writes them otherwise.
- The input on stdin is written to the cache, as research F saw in its test calls.
- Visible output is the bytes of the answer. Thinking is 4 times that at the default effort and 2 times at `--effort low`. The first factor follows research F's 76 to 85 percent. The second is F's guess A4. Neither is measured.

**The two runs.** `test/review/day.m` builds each expert's request with the expert's own code, so both runs start from the same facts per finding.

- The 1.x replay: LocoHost every hour and WorkForest every two hours, the 0.1 cadence. Every finding goes to the model, pretty-printed, with the 0.1 prompt and its prose schema from `test/review/legacy.json`. WorkForest goes in batches of 25 with one summary call, as in WorkForest 0.1. MinMacs 1.2, Noo-Noo and Insomnia asked no model on a schedule, so they send nothing here.
- The broker replay: every expert every hour, as `MMCoreStart` wakes them, through `MMReviewBroker` with each expert's rules.

### Tokens a day, issue #36

| Run | Uncached tokens | As counted before | List cost |
|---|---|---|---|
| 1.x replay | 1,842,725 | 1,879,463 | $0.7787 |
| Broker, cache off with `--fresh` | 734,945 | 774,065 | $0.2564 |
| Broker | 56,846 | 58,476 | $0.0173 |

| Expert | 1.x uncached | Broker uncached | Broker calls | Findings sent |
|---|---|---|---|---|
| WorkForest | 1,630,277 | 39,915 | 12 | 75 of 2,313 |
| LocoHost | 212,448 | 16,931 | 11 | 19 of 120 |
| MinMacs, Noo-Noo, Insomnia | 0 | 0 | 0 | 0 |

What the numbers show:

- The broker's day is 3.1 % of the 1.x replay on the same fixture. The target was a fifth or less, and the check fails above a fifth.
- 56,846 is 2.1 % of the 2.7M baseline of PLAN.md section 4. The check fails above 540,000.
- The 1.x replay counts 1.88M, below the 2.7M of PLAN.md and the 3.26M of research F. Per tree it gives 1,445 tokens as counted before, against the 2,671 research F measured. The fake adds nothing for what Claude Code itself sends, and the bytes-per-token figure is a guess. So the share is the steadier number, not the totals.
- Output was 74 % of the 1.x replay's uncached tokens, and 80 % of that output is thinking by the fake's rule.
- The same replay on the person's login, within the 2M Haiku tokens of decision 16, has not run. It would replace the fake's counting with the CLI's.

### Rules first, issue #32

Of 3,705 findings over the day, 528 never reach the broker. Insomnia asks for no review, and MinMacs and Noo-Noo ask only about findings with a proposal. The broker decided the other 3,177:

| Decided by | Findings | Share |
|---|---|---|
| Rules | 1,591 | 50.1 % |
| The fingerprint cache | 1,492 | 47.0 % |
| The model | 94 | 3.0 % |

By expert and rule:

| Expert | Rule | Findings |
|---|---|---|
| WorkForest | `workforest.holds-work` | 617 |
| WorkForest | `core.work-keeps` | 176 |
| WorkForest | `workforest.locked-or-protected` | 4 |
| LocoHost | `locohost.not-a-dev-server` | 48 |
| LocoHost | `locohost.in-use-now` | 2 |
| MinMacs | `minmacs.lists` | 168, all of its findings |
| Noo-Noo | `noonoo.owner-state` | 576, all of its findings |

- `core.work-keeps` is new in Core. A finding with a work keep, such as a session active today, is kept with its first keep reason and never sent. Before it, those 176 went to the model.
- A rule decides again on every review. Its verdict is never carried by the cache, so a keep that ends is sent to the model at the next review.
- The test checks every id each call sent against the verdicts of that tick. None was decided by a rule or the cache.

### The fingerprint cache, issue #33

- With the cache off, the broker sent 1,586 findings and 734,945 uncached tokens. With it on, 94 findings and 56,846 tokens. The cache removed 92.3 % of what the rules left.
- A verdict is carried only while three keys hold: the expert's fingerprint, the instance key and Core's context from `MMReviewContext`. The context is the HEAD of the finding's worktree, the activity bucket of the newest session there and a size bucket of what the finding frees. The buckets are those of the graph's workstream fingerprint.
- The instance key rule of LocoHost now holds in `-[MMReview verdictFor:]` for every expert. The server that restarts at hour 10 was sent again at that tick.
- No finding was sent because the context alone moved. The fingerprints of WorkForest and LocoHost already hold HEAD and activity buckets. The context keeps the same rule for the experts whose fingerprints do not.

### One fact block per workstream, issue #34

Measured on the 75 inputs the 1.x replay sent, encoded four ways by `test/review/daybytes.py`:

| Encoding | Bytes | Against pretty |
|---|---|---|
| Pretty-printed, as the 0.1 apps sent | 1,408,944 | 100 % |
| Compact with sorted keys | 928,658 | 66 % |
| Compact, null, false, zero and empty values dropped | 718,587 | 51 % |
| And values every finding of a call shares sent once, in `all` | 649,923 | 46 % |

- Research F's 30 % cut came from one sample that was not saved, so it is unverified. On these 75 inputs, pretty to dropped cuts 49 %.
- `ws` holds the values in `MMReviewRequest.sharedKeys` that every finding of one block shares. LocoHost lists the agent session, branch, project and worktree. WorkForest lists the agent session, repo and default branch. In the broker replay, ws saved 70 uncached tokens over the day: 56,916 without it, 56,846 with it. Only LocoHost's two servers in one worktree share a block. A WorkForest block holds one tree, so it gets no ws.
- Every system prompt ends with one fixed note on how blocks, ws and all read, so the prompt stays one cached prefix.

### Verdicts before and after

The verdicts were compared where both runs reviewed the same finding at the same tick: 1,274 pairs. The fake model decides from the facts it is sent, by the evidence lists of the 0.1 prompts, so a difference comes from what the broker sends or decides.

| 1.x verdict | Broker verdict | Pairs | Decided by |
|---|---|---|---|
| Same | Same | 1,224 | |
| unsure | active | 24 | `workforest.holds-work`, for commits on no remote |
| stale | unsure | 23 | the cache |
| unsure | in_use | 3 | the cache |

- The broker never said go where the 1.x review said keep or unsure. The test checks that.
- The 26 differences from the cache are verdicts carried while a time fact drifted inside one fingerprint bucket. WorkForest's quiet bucket runs from one to seven days, and the fake calls a merged tree stale after three. Each such verdict is asked again when a bucket moves.

## Rerun

```sh
tools/bench/run.sh                 # ten minutes, then menus and the gate; results in build/bench/<date>
tools/bench/run.sh 60 10 50        # one minute
./test.sh bench                    # the short run and the gate
```

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
