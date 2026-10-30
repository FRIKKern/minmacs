# Bench

Issues #52 to #56. MEASUREMENTS.md keeps #23 and #51.

## The idle tick

Issue #52. What MinMacs 2.0 costs at rest with all five experts, after the tick work. docs/2.0/MEASUREMENTS.md keeps the numbers of issue #23 and the method they share. Every number here comes from a command named below. Each run writes its raw JSON, `report.md` and `gate.txt` under `build/`, which git ignores.

### Result

`tools/bench/run.sh 1800 30 200 build/bench/w4-idle-30m`, built with `BUILD_DIR=build/w4-idle`. Thirty minutes from 01:32:25 UTC on 2026-10-28, after 30 seconds of warm-up.

| Budget | Phase 6 | Before, issue #23 | This run | Ceiling now |
|---|---|---|---|---|
| Idle CPU | 0.3 % | 1.489 %, two experts | 0.291 %, five experts | 0.6 % |
| CPU a tick, mean from one sample to the next | 15 ms | 46.69 ms, pass and rebuild at the median | 14.545 ms | 30 ms |
| Idle footprint | 45 MB | 12.00 MB | 10.70 MB, peak 12.47 MB | 20 MB |
| Wakeups a second | under 1 | 0.423 | 0.223, idle wakeups 0.000 | 0.5 |

All four targets are met. The idle CPU is 0.291 %, or 5.238 seconds of CPU in 1800 seconds. It sits 0.009 points under the budget on a busy Mac, so the margin is thin. See "What is left".

### How it was measured

- The Mac: MacBookPro18,1, 10 cores, macOS 27.0.1. Other agents built and tested in other worktrees through the window. The load average was 10.46, 14.17 and 21.71 at the start and 3.64, 4.50 and 6.73 at the end.
- `tools/bench/bench idle` runs `MMCoreStart` with the five built-in experts in one process: MinMacs, LocoHost, WorkForest, Noo-Noo and Insomnia. It loads AppKit with no status item and runs main at user-interactive QoS, as the app does. Every mode is Idle in a fresh `MINMACS_HOME`. Senses reads the real process table. The model, cmux and tmux CLIs are `/usr/bin/false`. Claude Code's, Codex's and pi's folders point into that home.
- `run.sh` now sets `MINMACS_NO_BACKOFF=1`, so the pass kept its 5 seconds through the whole window. The numbers above are those of a Mac in use, not of one the person left. `MM_BENCH_BACKOFF=1` lets the pass back off as the app does.
- CPU and footprint come from `getrusage` and `task_info` at both ends of the window, wakeups from `TASK_POWER_INFO`. The tick is the whole process's CPU from one sample signal to the next, 360 of them. The parts come from `-[MMSenses counts]` and `-[MMGraph costs]`, thread CPU time per part and per expert, read at both ends of the window.

### Where a tick goes

360 passes at 5.000 seconds at the median, 392 snapshots, 865 pids. The 32 extra snapshots came from 39 exits of watched processes: 24 Python, 14 postgres and 1 stubborn app, all fixtures of other agents' tests that LocoHost and MinMacs list. Each row is CPU ms at the mean.

| Part | CPU ms |
|---|---|
| Pass: rusage and the process objects | 3.350 |
| Pass: sockets | 1.362 |
| Pass: what the sample carried from the last one | 0.708 |
| Pass: the process table | 0.512 |
| Pass: power facts | 0.317 |
| The whole pass | 6.249 |
| Build: the facts, registry and sessions | 0.906 |
| Build: LocoHost's findings | 2.387 |
| Build: MinMacs's findings | 1.614 |
| Build: Noo-Noo's findings | 0.171 |
| Build: Insomnia's findings | 0.046 |
| Build: WorkForest's findings | 0.006 |
| Build: the facts digest and LocoHost's input digest | 0.348 |
| Build: the snapshot, findings and owners included | 4.689 |
| Main: publish | 0.349 |

Wave 7 reads the whole Mac's network in the pass, after the power facts, and times it apart as `partsCPUms.net`. A 60-second `bench idle` run had 12 passes at 0.179 ms CPU for the network, 0.382 ms for the power facts and 7.436 ms for the whole pass. The load average was 77.58 while other agents built, so the whole pass reads high. `test/bench.sh` checks that the network part is above 0 and under 2 ms.

Each pass carried the args of 815 processes and the cwd of 27. It read the sockets of 125 processes and carried those of 501. The session index read its folders 28 times, once a minute, and skipped 366 refreshes. The graph skipped 2 builds whose facts did not change. LocoHost never handed back its last findings in this window, since the fixture servers of other agents' tests started and ended in almost every tick.

Alone, on one thread after the window, 20 runs each, the pass took 3.417 ms at the median and a build 4.03 ms: 0.497 for the facts and 3.537 for the snapshot. The window costs more than that because the pass runs at utility QoS, often on the efficiency cores, under the load of other builds.

### How it was profiled

- `sample` on the bench process during 60 to 100 second windows, at 1 ms, and on `bench idle --tick-runs 200`, which times each part 200 times on one thread. A build of the bench with `-g` gave line numbers.
- Signposts in subsystem `no.guerrilla.minmacs`, category `tick`: `pass`, `rebuild` and `findings` per expert. They cost nothing until something records them.

The first profile, five experts on `main` at f04a47b, 60 seconds, 1.064 % CPU: 11.1 ms from snapshot to sample signal and 39.0 ms per rebuild. It showed:

1. Process args read again on every sample: the registry's `agentsIn:` took 8.0 ms on a new sample and 0.2 ms on a sample that held them.
2. LaunchServices round trips from `NSRunningApplication`: MinMacs's app roll-up and LocoHost's owning app asked for each app's bundle id, bundle URL and activation policy on every rebuild.
3. Know's Where worked out every dev server's place in the background on every rebuild, with the cmux and tmux CLIs every 15 seconds.
4. The session index listed every session folder and read every file's attributes on every rebuild, 2.9 ms with no session file, and Codex's databases twice.
5. Store: the rules file's attributes on every rules lookup, `createDirectoryAtPath` on every support folder lookup, the test prefs and the keeps file parsed on every read.
6. The undo log queried on every rebuild by MinMacs and LocoHost.
7. A whole new pass after every exit of a watched process.

### What changed

**Senses.** A sample takes from the last one what holds for the same process: args, responsible pid and app lookups for the same pid, start, parent and name, and the cwd for a pass in which the process used no CPU time, otherwise for 30 seconds from its read. An exec changes the name, so its args are read again. A process that used no CPU time keeps its sockets for 45 to 60 seconds. One that ran but holds the same socket fds has only its TCP fds read again. `MMRunningApps()` reads each app once. An exit drops the process from the last sample with no pass. The pass backs off to 10 seconds on battery, 15 when the person is away 5 minutes, and 30 for both.

**Graph.** A build after a new sample is skipped when the facts digest matches: each of our processes at a CPU band and 16 MB of memory, sockets, power, agents and the identity of Know's objects. It builds at least every 30 seconds, and always for any other reason. An expert that answers `inputDigestFrom:` gets its last findings back when its inputs did not change. Exits within 0.3 seconds share one build.

**Know.** The session index reads only the folders FSEvents named, and all of them every 10 minutes. The registry reads its presence paths every 30 seconds, not on every match.

**Experts.** LocoHost has an input digest, asks Where once a minute per server and reads its undo records when `MMLogStamp()` moved. MinMacs keeps the app each process rolls up into and reads its undo records the same way.

**Store and Act, outside this issue's paths.** One stat replaces `createDirectoryAtPath` and attribute reads. A rules file is checked at most once a second unless this process wrote one. The test prefs and the keeps file are parsed again only when they changed. `MMLogStamp()` is new in `MMLog.h`.

### What is left

- The margin is 0.009 points. A window with more process churn costs more: a 90-second run at load 56 measured 0.324 %, and one with 10 exits in 90 seconds 0.448 %. Each new process costs an args read and a registry match, and each exit of a listed process a build.
- The skip and the reuse rarely fire on this Mac, because other agents start and end processes and fixture servers every few seconds. On a calm Mac they would carry most ticks. That was not measured here.
- The pass is now the larger half. 3.35 ms of it is `proc_pid_rusage` for about 650 of our processes and the objects for 865. `RUSAGE_INFO_V2` costs about 60 % of V6 but has no energy, so the energy rank keeps V6.
- The bench is headless. The app's footprint with status items and menus is higher than 10.7 MB and is not measured here.
## Menus, the main thread and startup

Issues #53 and #55. What a menu open and a card hover cost on main, whether main ever stalls, and how long the app takes from `MMMain` to its icons and summaries. Every number here comes from `tools/bench/bench` on the research Mac, a MacBookPro18,1 with 10 cores on macOS 27.0.1. Other agents built and tested in other worktrees during every run. [MEASUREMENTS.md](MEASUREMENTS.md) has the idle cost and the tick.

### What changed

**Cards on hover.** `MMMenuFromSpec` built every row's card before the menu opened, about 2 ms a card, so menu open grew with the rows. `MMMenuFromSpecOnHover` in `Sources/UI/MMSpecMenu.h` gives each row with a card its submenu arrow and an empty submenu. The submenu's delegate builds the card in `menuNeedsUpdate:`, when the pointer or the keyboard opens it. The shell builds every menu this way through `MMShellMenu` and `MMShellOneIconMenu`. A card whose finding went away after the menu opened says so in one line. The render tool and the tests call `MMLoadCards`, which builds each waiting card as a hover would, and `MMRenderMenu` and `MMMenuProblems` call it too, so the checks see the cards the person sees.

**Menus read only the snapshot.** An expert may implement `-prepareFor:` in `Sources/Core/MMExpert.h`. The graph queue calls it once per snapshot, after the build and before main sees the snapshot, and main reads the result with `-[MMSnapshot preparedFor:]`. This is the one change outside this work's paths: an optional method in `MMExpert.h`, two methods in `MMGraph.h`, and one call in `-[MMGraph buildNow]`.

| Expert | What moved off main |
|---|---|
| LocoHost | `MMPlan`, which reads the rules, the prefs and watching-since through `MMMustKeep`, the mode, the idle minutes and the day of watching. The mode's plan after a review reads the prepared plan too. Protect writes the rules file on the act queue. |
| WorkForest | `MMPlan`, the keeps, the protect list, Recently Removed from the undo log and the day of watching. The mode's plan after a review reads the prepared plan. Keep and Protect write their files on the act queue. |
| Noo-Noo | The mode and the day of watching. |
| MinMacs | The mode and the day of watching, for the header and the summary. |
| Insomnia | The first look before Insomnia's first pass. After that pass the menu reads Insomnia's own state, as before. |

**Hang detection.** `Sources/Shell/MMWatchdog.h`. Two run loop observers on main mark where each pass starts and ends. A thread of its own sleeps until a pass starts, then wakes once at start plus 50 ms. If the same pass still runs, it reads main's run state, suspends main, walks its frame pointers, resumes it, and waits for the pass to end. Each stall goes to NSLog, to `stalls.log` in the support folder as a JSON line, and to `MMWatchdogStalls()`. A stall says how long the pass took, how much CPU main used in it, whether main was waiting or running at the 50 ms mark, and main's stack at that mark. It is on in a debug build, `DEBUG=1 ./build.sh`, which defines `MM_DEBUG`, and wherever `MINMACS_WATCHDOG=1` is set. `MMMain` starts it then. When main sleeps, the watchdog thread sleeps too.

**Startup.** An expert whose icon was hidden at the last run gets no status item, no menu and no per-snapshot update until its field appears or Settings shows it. On a first launch every item is made, and an expert whose field is empty hides its icon at the first snapshot, as DESIGN.md "First launch" asks. On the next launch that expert waits. `MMStartupTimes()` gives the marks in ms since `MMStartupBegin`, which `MMMain` calls first.

### How it is measured

- `bench menus --iterations 200` builds a new fixture snapshot of a new generation for each turn, on a queue of its own, and runs the prepare step there. Then main times `MMShellMenu`, which is what `menuNeedsUpdate:` of the status item's menu runs. A hover is the card submenu's `menuNeedsUpdate:`, then the card's layout and its drawing into a bitmap.
- Every expert has a fixture now: LocoHost 12 servers, MinMacs 20 apps and 2 agents, WorkForest 16 worktrees in 2 repos, Noo-Noo 12 clutter items, Insomnia 2 agents.
- `bench hangs --rounds 10` starts Core with every built-in expert, every mode Idle, and the watchdog at 50 ms. Each menu open and each card hover runs in a pass of main of its own, 3 ms after the one before: on a new fixture snapshot, on Core's live snapshot, and the One Icon menu.
- `bench startup` runs `MMShellStartHeadless`: the launch the app runs after its instance check, without NSStatusItem and without NSApp's run loop. Each item makes its icon image and label, and nothing in the menu bar. It runs twice in one `MINMACS_HOME`, a first launch and then a later one.

### Menu open and card hover

200 builds each, wall ms on main. Both runs on the same fixtures, one after the other, at load averages of 30 to 41. "Before" is main at f04a47b, where menu open built every row's card. "Before" had no fixture for WorkForest, Noo-Noo and Insomnia, so those three had no rows.

| Expert | Rows | Menu open p95 before | Menu open median after | Menu open p95 after | Card hover median after | Card hover p95 after |
|---|---|---|---|---|---|---|
| LocoHost | 12 | 37.02 | 1.32 | 1.52 | 6.86 | 7.65 |
| MinMacs | 14 | 26.09 | 1.64 | 1.88 | 5.11 | 6.11 |
| WorkForest | 14 | 1.47, no rows | 1.35 | 1.62 | 5.95 | 7.29 |
| Noo-Noo | 11 | 1.01, no rows | 1.39 | 1.74 | 3.99 | 6.15 |
| Insomnia | 1 | 0.87, no rows | 0.91 | 1.04 | 5.65 | 6.22 |
| One Icon, every expert | | 15.61 | 2.94 | 3.28 | | |

Menu open is under 30 ms at p95 for every expert, and card hover under 16 ms. The `menus` run also shows:
- No card was built while a menu opened, and every hover built its card.
- After every card is hovered, each expert's menu holds the same items, titles and card sizes as the menu built with every card up front.
- Main ran no log query and read no keeps file while the menus opened and the cards were built.

**What the graph queue does now.** The prepare step, from the same `menus` run, at the median: LocoHost 0.73 ms, MinMacs 0.28 ms, Noo-Noo 0.28 ms, Insomnia 0.07 ms. WorkForest took 18.0 ms. That figure is the bench's alone. The fixture's findings come from a stand-in expert, so `MMMustKeep` reads each worktree again from the fixture facts. In the app, WorkForest made the findings from those same facts, and it reads them from each finding. On this Mac's real process table with an empty `MINMACS_HOME`, `bench idle --tick-runs 10` timed the prepare step at 1.48 ms of CPU a tick at the median. In the app, main did this work on every snapshot before, through `badgeFor:` and `accessibilityStateFor:`.

### Main never waits

`tools/bench/run.sh 60 10 200`, from 23:50 UTC on 2026-10-27, at load averages of 17 to 20.

- The watchdog caught the 120 ms stall made on purpose, as "waits", in `MMBenchStallOnPurpose`.
- Then 110 menu opens, 50 of them on Core's live snapshot, and 900 card hovers ran in 14180 passes of main. No pass took over 50 ms.

### Startup

Same run, headless, in ms from where `MMMain` starts.

| Launch | Core started | Items made | First snapshot | Every summary | Made at launch | Left for later |
|---|---|---|---|---|---|---|
| First | 3.99 | 15.16 | 90.55 | 116.40 | MinMacs, LocoHost, WorkForest, Noo-Noo, Insomnia | none |
| Later | 2.62 | 9.52 | 80.14 | 80.47 | MinMacs, LocoHost | WorkForest, Noo-Noo, Insomnia |

In that empty `MINMACS_HOME`, WorkForest, Noo-Noo and Insomnia had empty fields, so the later launch left them for later. The items are made within 300 ms and every summary within 5 seconds on both launches.

**Not measured here.** The bench never launches the app, so these numbers leave out what happens before `MMMain` and around it: dyld, `NSApplication`'s launch until `applicationDidFinishLaunching:`, and the status bar's own cost for each `NSStatusItem`. The headless items make the icon image and the label, which is the work the shell does for each item. The first snapshot waits on Core's first Senses pass and rebuild.

### The gate

`tools/bench/budgets.json` gains three budgets that `gate.py` reads from the startup and watchdog runs, and skips when a run has none:

| Budget | Phase 6 | Ceiling | This run |
|---|---|---|---|
| Menu open at p95, worst expert | 30 ms | 60 ms | 1.78 ms, MinMacs |
| Card hover at p95, worst expert | 16 ms | 32 ms | 7.65 ms, LocoHost |
| Icons after launch, headless | 300 ms | 300 ms | 15.16 ms, first launch |
| Every summary after launch, headless | 5000 ms | 5000 ms | 116.40 ms, first launch |
| Main-thread stalls over 50 ms | 0 | 0 | 0 |

`test/bench.sh` checks each of these, every linked expert's rows and cards, the deferred items of the later launch, and the watchdog's own catch.

## Scans and review at scale

Issue #54. What 300 worktrees, a 20 GB clutter tree and a review of 100 findings cost, and how fast Core is back at rest. Every number here comes from `bench scale` on the research Mac, a MacBookPro18,1 with 10 cores, while other agents built and tested in other worktrees. The load average is given with each run, since wall times move with it.

### The fixtures

- `test/git/benchfix.py "$roots" 30 300 8`: 30 repos of 300 commits, each with 9 linked worktrees, 300 checkouts in all. Per repo, 2 branches are merged by ancestry, 1 squash-merged, 1 cherry-picked and 5 open. It builds 8 repos at a time in 19 to 44 seconds.
- `tools/bench/clutterfix.py`: 40 Xcode DerivedData folders, each with 8 APFS clones of one 60 MiB base file and one 1 GB sparse file, 2,000 small files in each of the pip, go and npm caches, and a `node_modules` of 300 files in each main checkout. du sees 20.19 GB. One run took 9.3 seconds and moved free space from 56.86 to 56.73 GB, another from 54.91 to 54.62 GB. It makes nothing when the volume has under 50 GB free. Other agents' builds took free space under that line later in the day, so the clutter numbers below come from the earlier runs.
- The review: WorkForest's own request for 100 linked worktrees, through `test/review/fakeclaude.py` with its byte-count token rule, `fakecount.py`. The bench copies the findings without their work keeps, since every fixture worktree is minutes old and WorkForest's rules would keep all 100.

### Before and after

`bench scale` from `main` at 8533429 and from this branch, built with the same `bench.m`, one after the other in a fresh home each time. "Before" is 2 runs at load averages of 21 to 33, "after" 2 runs at 21 to 26, from 11:29 to 11:42 local time on 2026-10-28. Both values are given.

| Measure | Target | Before | After |
|---|---|---|---|
| Cold scan: launch until a snapshot holds every checkout's git facts | 30 s | 58.6 and 78.0 s | 12.9 and 18.1 s |
| Cold scan: CPU of this process, and of its git children | | 17.8 and 39.5 s, 24.6 s | 5.8 and 6.7 s, 18.7 and 19.4 s |
| Warm walk, later launch, median of 5 | 2 s | 3.93 and 4.53 s | 0.32 and 0.52 s |
| Warm walk, first launch, median of 5 | 2 s | 2.24 and 4.34 s | 1.63 and 2.64 s |
| Warm walk: git runs | 0 | 133 to 305 | 0 to 24 |
| Warm walk: CPU at the median, later launch | | 2.25 and 3.36 s | 0.15 s |
| A rebuild over 300 checkouts: CPU of the snapshot part | | 2,425 and 2,462 ms | 116 and 122 ms |
| Worker child peak | 300 MB | 4.83 MB | 7.09 MB |
| Core peak, first launch | | 64.5 and 92.0 MB | 41.2 and 43.1 MB |
| CPU over the quiet window after, first launch | | 35.1 and 82.2 % | 0.67 and 6.49 % |
| Footprint right after launch, then at the end | | 62.5 then 80.2 MB, 51.0 then 43.1 MB | 30.2 then 43.1 MB, 25.4 then 35.1 MB |

Earlier pairs show the spread. Three rounds from 09:34 to 09:52 local time at load averages of 23 to 79, with an earlier state of this branch: cold 49.6 to 55.2 s before and 12.4 to 16.4 s after, the clutter scan 4.2 and 5.7 s before. One run of this branch at a load average of 81 took 74 s cold and 7.1 s for the first launch's warm median. The gate's cold ceiling is 60 s for that reason, and its budget stays 30 s.

The first launch's warm walks run while its 300 disk walks still go. The later launch is the walk the 10-minute timer runs in an app whose launch work is done, so the gate reads that one.

### Clutter and review

| Measure | Before, 2 runs | After, 2 runs |
|---|---|---|
| Clutter scan, first | 4.20 and 5.65 s | 1.56 and 2.22 s |
| Clutter scan, again | 2.29 and 5.11 s | 1.56 and 1.70 s |
| Clutter scan CPU | 4.67 and 5.43 s | 0.98 and 1.16 s |
| Items, files, what du sees, what deleting frees | 73, 15,400, 20.19 GB, 0.06 GB | the same |

The Sizer counts the clones at what deleting them frees, 0.06 GB, against the 20.19 GB du sees. The clutter scan's worker peak was 6.39 MB.

The review sent 100 worktrees in 4 batches of 25, 3 at a time, then one summary call: 5 calls, 0.31 to 0.88 seconds through the fake, 36,167 to 36,203 uncached tokens by the fake's count, about 362 a finding. The same review again sent nothing: the fingerprint cache decided all 100 in 0.03 seconds. The token count did not move between before and after, since nothing in the broker changed. `test/bench.sh` runs it with a longer path and counts 32,714.

### What was slow, and what changed

Profiles with `sample` on `bench scale`, 6 to 15 seconds each.

1. **Wrap Up plans, 2.4 s of every rebuild.** WorkForest's prepare step plans Wrap Up for each merged worktree, 120 of them. Each plan resolved every worktree path and three paths of every finding with `realpath`: about 155,000 calls a build. `Sources/Core/Act/MMWrapUp.m` now resolves each path once per snapshot, for at most 2 seconds, and only a check on fresh facts, which passes no snapshot, calls `realpath` every time. A subject that is not a finished workstream skips the scan of every finding, since no plan reads them. `PathIn` makes no string. The snapshot part fell from 2,754 to 467 ms, then with the rest below to 116 to 147 ms.
2. **The protect list, once per worktree.** `+[MMRules rulesFor:defaults:]` took the rules file's lock and parsed it on every call, 300 times a build. `Sources/Core/Store/MMStore.m` hands back the same rules while the file's stamp and the defaults hold. A changed or missing file merges its defaults again, as before.
3. **The worktree of every finding.** `-[MMBuild treeAt:]` in `Sources/Core/Graph/MMGraph.m` walked all 300 worktrees with a path test that made a string. It now looks up the path and each folder above it.
4. **git one worktree at a time.** The update pass ran 2,162 to 2,267 git children in turn. `Sources/Core/Know/MMRepoIndex.m` now works on up to 4 repos at once, half the cores at most, on the labeled queues `core.git.1` to `core.git.4`, and on each repo's worktrees in turn, so a repo's patch ids are computed once.
5. **Small file reads.** A warm walk read about 15 small files per worktree through Foundation, which cost most of its time. `MMReadLine` in `MMGitFacts.m` reads them with `open` and `read`, and `stat` replaces `NSFileManager` on the walk. The worker sends back each worktree's git dirs, so the index no longer reads them again, and the branch and lock check reuses what the fingerprint read had.
6. **Rebuilds back to back.** WorkForest asks for a rebuild after each of its 300 disk walks at launch. A build now waits until 4 times the last build's CPU time has passed since it ended, at most 2 seconds. A build under 12.5 ms of CPU waits for nothing. A cold launch of this branch built 46 snapshots in 24.9 s before this change, and 14 and 20 after it in the final runs.
7. **git in the person's repos.** The bench reads the real process table, so LocoHost and MinMacs saw servers in the person's repos, and the index ran git there. After one run the bench's git cache held 308 entries for 300 fixture checkouts, among them 4 of the person's checkouts. The warm walks before ran 133 to 381 git children; after, 0 to 24. With `MINMACS_HOME` set, the index now reads git facts and sizes only inside `MINMACS_HOME` and its roots. A first version blocked only the person's home folder. In one `./test.sh bench` run during the review, the git cache then held 303 entries, 3 of them outside the fixture roots and outside the home folder, and the later launch's warm median was 4.34 s. With the stricter rule the next run held 300, the later launch ran 0 git children, and its warm median was 0.46 s. The scale bench also holds the scheduled reviews with a day over budget, so no finding from the real process table reaches the fake CLI. `test/bench.sh` checks that every path in the git cache lies in the fixture roots.

### Back to idle

The worker child closes 27.4 to 29.9 seconds after its last request, as its 30-second idle time says. The bench reads it as the child of the bench that runs the bench's binary as `_walk`. Core's footprint at the end of the final runs was 35.1 and 43.1 MB, against 25.4 and 30.2 MB right after launch. A run with the clutter scan ended at 128.6 MB, against 59.1 MB after launch. `malloc_zone_pressure_relief` freed 0 MB at the end of one probe run, so that memory is in use, not free pages malloc keeps. Over the quiet window after, the process used 0.67 to 6.49 % of a core in the final runs, mostly the rebuilds a 5-second tick still runs over 300 worktrees, about 120 ms of snapshot CPU and 60 to 75 ms of WorkForest's findings each.

### The gate

`tools/bench/budgets.json` has three budgets that read a scale run, and `gate.py` knows each result by its kind:

| Budget | Phase 6 | Ceiling | Reads |
|---|---|---|---|
| Warm scan of 300 worktrees | 2 s | 4 s | the later launch's median |
| Cold scan of 300 worktrees | 30 s | 60 s | the launch with no caches |
| Worker child peak memory | 300 MB | 300 MB | the highest of any phase |

`test/bench.sh` runs both launches, about two and a half minutes, and passes them to the gate with the rest. `tools/bench/scale.sh` is the longer run, with 10 warm walks and a 10-second quiet window.

### What is left

- WorkForest's findings take 60 to 75 ms of CPU a build with 300 worktrees, and Noo-Noo reads a file in its findings on every build. Both are expert code outside this issue's paths.
- A cold scan still runs about 2,200 git children, 7 per worktree. The CPU of those children, 18 to 25 s, did not change.
- Each warm walk reads every fingerprint again, about 10 small files per worktree. FSEvents already names what changed, so the walk could skip a worktree whose git dir it saw no change in.
- The clutter rows were measured once each way, at load averages of 22 to 48, before free space fell under 50 GB.
- `./test.sh bench` at 13:50 local time, at load averages of 99 to 131: cold 24.9 s, the later launch's warm median 1.79 s, under its 2 s ceiling with little to spare. That later launch ran 63 git children, where calmer runs ran none, since git answers from the first launch that failed are asked again. The check allows a tenth of the cold scan's git runs.
- The next `./test.sh bench`, at 14:00 local time with load averages up to 148, failed the warm gate: the later launch's median was 2.57 s, its max 9.62 s, with 120 git children. The same run had one main-thread stall over 50 ms in the menu checks. The warm walk's wall time follows the load, while its CPU stays near 0.15 to 0.35 s.
- The review of this branch set the warm ceiling to 4 s, twice the 2 s budget, as the cold ceiling is twice its budget. A median between 2 and 4 s prints as over and passes, and `MM_BENCH_STRICT=1` still fails it.
- That run's stall was main inside `CrumbSetUp` in `MMRuntime.m`, 129.7 ms with 0 ms CPU: `MMCoreStart` read the last run's breadcrumbs on main, which lists and reads the `running` folder. It now reads them on the `core.store` queue.
- A later `./test.sh` at a load average near 50 had one 67.7 ms stall with 0 ms CPU in `+[MMCoreSocket serve:error:]`, which `MMCoreStart` calls on main. `bench hangs` now reports the stalls of Core's start and first snapshot as `startStalls` and gates only those of the menu opens and card hovers, as the check's name says. The socket's bind on main is left for its own issue.
- The idle CPU budget failed in some `./test.sh bench` runs today, at 0.652 to 0.875 %, against a 0.6 % ceiling. `main` at 8533429 does the same: two 30-second idle runs of each, one after the other at load averages of 11 to 16, gave 0.403 and 0.874 % for `main` and 0.682 and 0.408 % for this branch.

## Soak

Issue #56. Whether MinMacs 2.0 holds up over hours: no leak, no growth, no crash and no hang, with all five experts on and the world around them changing. Every number here comes from `tools/soak/run.sh` on the research Mac, a MacBookPro18,1 with 10 cores on macOS 27.0.1, while other agents built and tested in other worktrees.

### What runs

- `tools/soak/soak` is Core headless with the five built-in experts in one process, as `tools/bench/bench idle` runs it, with every mode Idle and the main-thread watchdog at 50 ms. Once a minute it opens every expert's menu and the One Icon menu on Core's live snapshot and hovers every card, each open and each hover in a pass of main of its own. It writes a status line a minute and a summary when SIGTERM stops it. It answers `_walk`, so Core's worker gets its real walker child, as in the app.
- Beside it, every churn step, 20 seconds by default, inside a fresh `MINMACS_HOME`: a worktree with a commit is made in a fixture repo under `MINMACS_ROOTS`, and the oldest past four is removed. A Python HTTP server starts in the newest worktree on a free port from 40000, and the oldest past three stops. A fake agent starts with a Claude Code session file and a transcript, and the oldest past three stops, its files removed. Every live transcript gets a line.
- Every fixture name carries the run's tag. A fixture is stopped by its pid, only after `ps` shows the tag in its command line. Servers and agents call `setsid` and end by themselves after a few minutes, even if the script dies. The script stops the run when more than 20 processes carry the tag.
- Only the fixture registry row is loaded, and the fake agent has no working signal, so Insomnia holds no power assertion. The model, cmux and tmux CLIs are `/usr/bin/false`. The soak refuses to run without `MINMACS_HOME`, `MINMACS_ROOTS` and the agent folders inside it.
- Each sample reads the process with `tools/soak/procstat`: footprint, peak footprint, resident size and CPU time from `proc_pid_rusage`, threads and open fds from `proc_pidinfo`. Then `leaks(1)` reads its heap. At the end the script looks for crash, hang and spin reports of the run's processes in both DiagnosticReports folders.
- `tools/soak/report.py` writes `report.md` and the verdict.

### What passes

| Check | How it is read |
|---|---|
| No leak | Every `leaks(1)` run worked and found no leaked block in a tree that names a MinMacs class or a function of the soak binary. Trees that only system frameworks made are counted apart and must not grow from the first sample to the last. |
| Footprint growth under 5 MB a day | The least-squares slope of the footprint over the samples, judged on a run of 6 hours or more |
| No crash | The soak lived to the stop, exited 0 on SIGTERM, and no crash, hang or spin report names a process of the run |
| No hang | No pass of main over 50 ms. Passes while `leaks(1)` held the process suspended are listed apart, and so are passes in which main was ready but got under a tenth of the time on a core, which is the Mac's load and not a wait of MinMacs |
| Nothing acted | Every mode stayed Idle, the undo log is empty, no awake hold was taken and no fixture is left running |

### What the first runs found

**A retain cycle that kept every snapshot.** LocoHost's and WorkForest's menu views keep an `act` block, and the block held the snapshot strongly. The snapshot holds those views through `prepareFor:`. So no snapshot was ever freed. In a one-minute run before the fix, `leaks(1)` found 1888 leaked blocks at 8 seconds and 18936 at 71 seconds, and the footprint went from 10.59 MB to 24.22 MB. The block now holds the snapshot weakly and falls back to `MMGraph.shared.current`. That is two lines in `Sources/Experts/LocoHost/MMLocoHost.m` and `Sources/Experts/WorkForest/MMWorkForest.m`, outside this issue's paths. After it, MinMacs code leaks nothing in every run below.

**Core's worker runs its own binary again as `_walk`.** The first soak binary did not answer that verb, so each walker child started a whole soak with its own child. One minute made 287 copies, all stopped by pid. The soak now hands `_walk` to `MMWorkerChildMain`. `tools/bench/bench` prints its usage for `_walk` and exits 2, so the bench's worker never gets a walker. That is outside this issue and left as it is.

**Three system leaks.** Every run has three leaked `NSXPCConnection` trees for `LNDaemonApplicationInterface`, made by AppIntents' `-[LNProcessInstanceRegistryClient makeXPCConnection]` on a dispatch queue, 417 blocks in all. A run with `MallocStackLogging=1` showed no MinMacs frame in their allocation stack. They appear in the first seconds and do not grow.

### One hour

`tools/soak/run.sh 3600 600 20 build/w5-soak/hour`, built with `BUILD_DIR=build/w5-soak-hour` from 84beb0c. One hour from 08:15:48 UTC on 2026-10-28, at load averages of 16.93, 32.45 and 43.38 at the start. A sample every 10 minutes in place of every hour, so one hour has a curve.

| Sample | Elapsed s | Footprint MB | Peak MB | CPU % since last | Threads | Fds | MinMacs leaks | System leak trees |
|---|---|---|---|---|---|---|---|---|
| 1 | 133 | 16.70 | 17.19 | | 8 | 28 | 0 | 3 |
| 2 | 735 | 18.24 | 18.83 | 1.861 | 8 | 25 | 0 | 3 |
| 3 | 1327 | 18.66 | 19.20 | 2.686 | 9 | 28 | 0 | 3 |
| 4 | 1937 | 18.72 | 20.16 | 2.870 | 8 | 29 | 0 | 3 |
| 5 | 2525 | 19.52 | 21.45 | 3.528 | 7 | 25 | 0 | 3 |
| 6 | 3128 | 19.80 | 21.45 | 3.235 | 8 | 25 | 0 | 3 |
| 7 | 3600 | 19.91 | 21.45 | 3.091 | 6 | 25 | 0 | 3 |

- 159 churn steps: 159 worktrees made and 155 removed, 159 servers and 159 agents started and stopped. The soak published 2319 snapshots and ran 60 menu rounds, 360 menu opens and 3085 card hovers. At most LocoHost listed 29 servers, MinMacs 22 items, WorkForest 6 worktrees, and the graph held 3 agents and 3 sessions. The churn keeps at most 4 servers alive, so most of the 29 were this Mac's own servers. LocoHost is Idle, so it only read them. Since that run the summary also has `peakFixtureFindings`, the findings about a folder inside `MINMACS_HOME`, and `test/soak.sh` asks that LocoHost and WorkForest each saw one.
- No leak in MinMacs code at any sample. Threads stayed between 6 and 9 and fds between 25 and 29.
- The soak lived to the stop and exited 0 on SIGTERM. No crash, hang or spin report names its processes. Every mode stayed Idle, with no undo record, no awake hold and no fixture left.
- The watchdog saw 46419 passes of main. Two took over 50 ms, at 08:21:49 and 08:21:50 UTC: 234.4 ms and 96.9 ms, both with main ready to run and 0 ms of CPU, in AppKit while a card's label and color were made. No `leaks(1)` ran then. Main waited for a core while this worktree's tests ran beside it, besides the other agents' work. The report as `run.sh` wrote it at the end counted both and exited 1. The report rule for main waiting for a core came after, and `report.py` on the same folder now lists them apart and exits 0.
- CPU from the first sample to the last was 2.869 %. It is not the idle cost: it holds the churn, a menu round a minute and the `leaks(1)` runs. BENCH.md "The idle tick" has the idle cost.
- The footprint grew 3.20 MB from the first sample to the last, 72 MB a day by least squares. The growth slowed: 1.54 MB in the first 10 minutes after warm-up, 0.39 MB in the last 18. One hour cannot say whether it levels off, so the 24-hour run judges it. In a second, 25-minute run, `heap(1)` 3 and 18 minutes in showed the malloc heap at 6.09 MB and 6.52 MB while the footprint went from 16.3 MB to 19.3 MB. The largest malloc growth was 260 KB of `CFString` storage in 163 strings. Most of the footprint growth is outside the malloc heap. That is the first place to look if the 24-hour slope stays over 5 MB a day.

### The 24-hour run

On a Mac that stays on, plugged in, with the lid open. The soak itself holds no power assertion, so the Mac's own sleep settings apply. Start it in a terminal that stays open:

```sh
BUILD_DIR=build/soak-24h tools/soak/run.sh 86400 3600 20 build/soak/24h
```

It samples every hour, 25 samples with the warm-up one, and writes `report.md` at the end. It passes when every check in "What passes" says pass and footprint growth is judged under 5 MB a day. The run leaves `build/soak/24h` for the record, and `samples.jsonl` has the raw numbers.

### The week of real use

The soak runs fixtures only. The week of real use runs the app on the person's Mac, so it is started by the person, never by an agent or a test:

1. Build with `DEBUG=1 BUILD_DIR=build/week ./build.sh`, so the watchdog writes every stall to `stalls.log` in the support folder. Install it the way the release is installed, when phase 1 allows that.
2. Use the Mac as every day, with the modes as the person sets them, for seven days.
3. Once a day, read the app with `tools/soak/procstat <pid>` and run `leaks <pid>`. Keep the lines.
4. At the end, check `~/Library/Logs/DiagnosticReports` for MinMacs crash, hang and spin reports, and `stalls.log` for passes over 50 ms.

It passes on the same rules: no leak in MinMacs code, footprint growth under 5 MB a day by least squares over the daily reads, no crash report, and no stall that is not a `leaks(1)` read or main waiting for a core.

### On the GitHub runner

On the macos-26-arm64 runner the short soak's Senses holds each fixture server's process, with the soak's own uid, and reads no socket for it. The status line on 44c994d read `"inSample":1,"uid":501,"me":501,"sockets":0`, and no sample held a listener. On the same runner the minmacs CLI reads those servers in the locohost section, and on a Mac the soak reads them. Signing the soak binary with codesign did not change it. The cause is not found. On CI the check prints LocoHost's peak fixture findings and does not gate on them; on a Mac it gates.

## Rerun

```sh
tools/bench/run.sh 1800 30 200          # thirty minutes, then menus and the gate
MM_BENCH_BACKOFF=1 tools/bench/run.sh   # with the backoff the app uses
./test.sh idle                          # the checks of issue #52
tools/bench/scale.sh                    # 300 worktrees, the clutter tree and a review of 100, issue #54
./test.sh bench                         # the short run and the gate
tools/bench/run.sh 60 10 200          # one minute of idle, then menus, startup twice, the watchdog run and the gate
DEBUG=1 BUILD_DIR=build/debug ./build.sh   # a build whose main-thread watchdog is on
tools/soak/run.sh 3600 600 20           # one hour of soak, a sample every 10 minutes
./test.sh soak                          # the short soak and its report rules
```
