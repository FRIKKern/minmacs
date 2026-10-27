# Research H: one-process architecture for five experts

Tracks GitHub issue FRIKKern/minmacs#8.

## Summary

- **Baseline.** Over 131 seconds of read-only sampling on 2026-10-27, LocoHost used 0.79% of one core and WorkForest used 4.47%. Insomnia used 0.29%. Their idle footprints add up to 127.5 MB. MinMacs 1.2 was not running, so it has no baseline yet.
- **The real cost is WorkForest's scan.** One scan landed in the window. It used 5.41 s of CPU in about 16 s and up to 23 threads. RSS peaked at 2,166,432 KB. vmmap reports a lifetime peak footprint of 3.6 GB for a process that idles at 50.2 MB (unverified: the 50.2 MB reading was not saved, and a later `vmmap --summary` read 2.6 GB).
- **Likely cause, a guess.** The scan runs `fts_read` loops and git reads on the global concurrent queues. Those queues never wrap a block in an autorelease pool, and WorkForest's scan code has no `@autoreleasepool` of its own.
- **Main thread today.** LocoHost and MinMacs 1.2 sample the whole process table on the main thread from an NSTimer. LocoHost samples again on the main thread before it shows its menu. Insomnia runs `pmset -g` on the main thread.
- **Proposal.** Use one process with one AppKit main thread that only reads an immutable graph snapshot. Each knower gets its own labeled serial queue with a time budget. Heavy disk walks run out of process, as a child of the same binary. The CLI asks the running app over a Unix socket and runs the core itself when no app answers.

## 1. Machine and method

- **Machine.** Apple M1 Pro, 10 cores, 32 GB, macOS 27.0.1. Source: `sysctl -n hw.ncpu hw.memsize machdep.cpu.brand_string` and `sw_vers`.
- **Process count.** 867 processes, 665 of them owned by this user (unverified: a point-in-time count, and a rerun about 35 minutes later read 829 and 615). Source: `ps -axo pid= | wc -l` and `ps -U $(id -u) -o pid= | wc -l`.
- **Apps measured.** Each one is ad-hoc signed with no team ID. Source: `codesign -dv` on each bundle.

| App | PID | Running for | Binary built |
|---|---|---|---|
| LocoHost | 25473 | 33 min 15 s | 2026-10-27 15:29 |
| WorkForest | 42942 | 28 min 19 s | 2026-10-27 15:25 |
| Insomnia | 63088 | 22 days 6 h 56 min | 2026-10-05 10:08 |

- **Sources for the table.** `ps -o etime`, and `stat -f %Sm` on each `Contents/MacOS` binary.
- **Sampling.** `ps -o pid,%cpu,rss,time` ran every 5 s, 25 times. `top -l 25 -s 5 -pid … -stats pid,command,cpu,mem,purg,cmprs,th,wq,idlew,power` ran over the same window. The window ran from 15:05:09Z to 15:07:20Z, which is 131 s. After the window, `vmmap --summary <pid>` gave the physical footprint and its peak. The raw output is in the session scratchpad and was not committed.
- **Average CPU.** Average CPU is the change in cumulative CPU time from `ps -o time`, divided by the 131 s wall time. That figure includes work on background queues. It excludes child processes such as git, claude and codex.

## 2. Measured baseline

| App | CPU in window | CPU outside bursts | CPU since launch | Footprint after window | Peak footprint | top MEM | Threads |
|---|---|---|---|---|---|---|---|
| LocoHost | 1.03 s, 0.79% | top average 0.74% | 25.93 s in 1,995 s, 1.30% | 30.3 MB (unverified) | 56.1 MB | 43 to 47 MB | 3 to 6 |
| WorkForest | 5.85 s, 4.47% | 0.33 s in 94 s, 0.35% | 65.00 s in 1,699 s, 3.83% | 50.2 MB (unverified) | 3.6 GB | 138 MB idle, 2,185 MB after scan | 3 to 4 idle, 23 in scan |
| Insomnia | 0.38 s, 0.29% | same | 1,397.68 s in 22.2 days, 0.073% | 47.0 MB | 52.1 MB | 47 MB | 3 to 4 |

- **Sources.** The CPU columns come from `ps -o time` at the start and the end. LocoHost went from 0:25.93 to 0:26.96, WorkForest from 1:05.00 to 1:10.85, and Insomnia from 23:17.68 to 23:18.06. The footprint columns come from `vmmap --summary`. The MEM and thread columns come from `top`.
- **WorkForest's scan in detail.** At 16:06:43 local time its CPU time read 1:05.33. At 16:06:59 it read 1:10.74, which is 5.41 s of CPU. RSS was 58,688 KB at 16:06:43 and 2,166,432 KB at 16:06:48. top showed 59.0% and then 35.6% CPU, with 23 threads and then 19. Compressed memory rose from 106 MB to 1,358 MB. Source: `ps_loop.txt` and `top.txt` samples 19 to 21. vmmap later read 50.2 MB, so the memory was released after the window ended (unverified: no saved vmmap output, top MEM stayed at 2,185 MB to the end of the window, and a later `vmmap --summary 42942` read 2.6 GB).
- **Why scans repeat.** The scan repeats every 5 minutes, per `kScanEvery = 5 * 60` (workforest/Sources/main.m:20) and the 60 s tick (main.m:371, 380-382). If each scan costs what this one did, scans alone average about 1.8% of a core. That figure is a guess from a single scan.
- **LocoHost per tick.** LocoHost ticks every 5 s (locohost/Sources/main.m:862). That makes about 26 ticks in 131 s, or at most about 40 ms of CPU per tick. The 40 ms covers the sample, git and intel reads, Where and probes together. It is an upper bound derived from the numbers above, not a measured sample time.
- **Fixed cost of a menu bar app.** Insomnia is the smallest app at 742 lines (insomnia/Sources/main.m), and it idles at 47.0 MB. LocoHost idles at 30.3 MB. A guess from these two: an AppKit menu bar process costs 30 to 47 MB before it does any work. That is the part that five experts in one process would pay only once.

**What 2.0 must beat.** The idle sum is 127.5 MB and about 1.4% of a core across the three apps, from 0.74% plus 0.35% plus 0.29% in the table above, plus a WorkForest peak of several GB every few minutes. MinMacs 1.2 is not installed. `ls ~/Applications` shows no MinMacs and `which minmacs` finds nothing. Insomnia's agent poll therefore reads 0 on this Mac (insomnia/Sources/main.m:166-167).

## 3. How the four Objective-C apps run today

| Concern | MinMacs 1.2 (legacy) | LocoHost | WorkForest | Insomnia |
|---|---|---|---|---|
| Tick | NSTimer 4 s on main (main.m:416) | NSTimer 5 s on main (main.m:862) | NSTimer 60 s on main, scan every 5 min (main.m:371, 20) | NSTimer 60 s guard, 15 s agent poll (main.m:272, 504) |
| Process walk | `proc_listpids` on main in `refresh:` (Scanner.m:106, main.m:424) | `proc_listpids`, rusage and sockets on main in `tick` (Ports.m:439-470, main.m:897) | own `proc_listpids` in `ProcessesIn` on a global queue (Trees.m:365-370) | none, it runs `minmacs agents --json` (main.m:163-185) |
| Menu open | built on main | `[self.scanner sample]` on main, then `performClick:` (main.m:1220-1221, 1357-1359) | `buildMenu` from cached trees (main.m:746-758) | built on main |
| Background work | none found | global utility queue for review (main.m:935), serial queues for git, intel and where (Ports.m:304, Intel.m:388, Where.m:217) | global utility queue, `dispatch_apply`, 6-way semaphore (Trees.m:665, 682-683) | global utility queue for the agent poll (main.m:516) |
| Shared state | none found | `@synchronized (cache)`, `dispatch_sync` on the Where queue (Where.m:225-229) | `@synchronized (self)` on the scanner, held by 6 workers and by main-thread getters (Trees.m:634-636, 687-725) | none found |
| Calls another app | none | none | spawns `~/.local/bin/locohost list --json`, 20 s timeout (Trees.m:396-406) | spawns `minmacs agents --json`, 10 s timeout (main.m:166-180) |
| Subprocess on main | none checked | none checked | `/usr/bin/open` (main.m:967) | `pmset -g` in the lid sync on the 60 s timer (main.m:272, 648, 681) |

What this table shows:

1. **Sampling blocks the main thread.** Every LocoHost tick runs a full process and socket pass on the main thread, because an NSTimer from `scheduledTimerWithTimeInterval:` runs on the run loop that created it, in the default mode. Foundation `NSTimer.h:27` states this for the block variant. The target and selector variant the apps use, at `NSTimer.h:18`, carries no comment in the header.
2. **Ticks stop while a menu is open.** Apple's run loop guide says "If a timer is not in the mode currently being monitored by the run loop, it does not fire until you run the run loop in one of the timer's supported modes." It says Cocoa uses the event tracking mode "during mouse-dragging loops and other sorts of user interface tracking loops" ([Run Loops](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html)). LocoHost and WorkForest open their menus with `performClick:` inside `handleClick:` (locohost main.m:1357-1359, workforest main.m:747-750), and their timers sit in the default mode. It follows that their ticks pause while a menu is open. This is an inference from the docs and the code, not a measurement.
3. **The scan and the main thread share one lock.** WorkForest's six scan workers take `@synchronized (self)` on the scanner (Trees.m:694, 697, 701, 708, 725), and the scan thread takes it before it hands each tree to a worker (Trees.m:687). The main thread takes the same lock through the `trees`, `scannedAt` and `scanning` getters (Trees.m:634-636), which `updateButton` and `buildMenu` call. Each hold is short. Still, a menu open during a scan waits on scan workers.
4. **Cross-app facts cost a full cold run.** Each WorkForest scan spawns the LocoHost CLI. That CLI samples, sleeps 1 s and samples again (locohost main.m:559), and then may probe over HTTP. LocoHost's own app had those facts already.
5. **Global queues have no autorelease pools.** The SDK says the global concurrent queues have `DISPATCH_AUTORELEASE_FREQUENCY_NEVER`, which "never set up an individual autorelease pool around the execution of a block" (`usr/include/dispatch/queue.h:846-849`, 881). WorkForest has one `@autoreleasepool`, in `main` (workforest main.m:1008). Its scan blocks create autoreleased objects inside loops, for example `@(e->fts_name)` for each folder in `WalkDisk` (Trees.m:296-330). It is a guess that this explains the 2.1 GB RSS spike. Phase 1 should confirm it with `heap` or Instruments on a fixture.

## 4. Proposed process shape

```
MinMacs.app  (one process, LSUIElement, ad-hoc signed today)
|
+-- main thread: AppKit only
|     5 NSStatusItems, menus, hover cards
|     reads Graph.current, an immutable snapshot, never a lock
|     work per event: under 2 ms; menu build: under 16 ms (targets)
|
+-- core.senses      serial queue, QoS utility, dispatch timer 5 s, leeway 1 s
|     one pass: proc_listpids, proc_pid_rusage, PROC_PIDFDSOCKETINFO,
|     thermal, power; memory pressure as a dispatch source
|     budget: 50 ms CPU per pass (target, today about 40 ms upper bound)
|
+-- core.know.<name> one serial queue per knower, QoS utility
|     git (6-way gate as today), sessions, where, registry
|     each job has a deadline; subprocesses get terminate after it
|
+-- core.graph       serial queue: merges facts, builds snapshot N+1,
|     publishes it to main with dispatch_async
|
+-- core.review      serial queue, QoS background: claude or codex as NSTask
+-- core.act         serial queue: checks fresh, writes undo record, acts
+-- core.ipc         dispatch source on a Unix socket for the CLI
|
+-- child: "minmacs _walk <json>"   same binary, posix_spawn or NSTask
      fts or getattrlistbulk walks for WorkForest and Noo-Noo sizing
      exits after each batch, so its memory goes back to the OS
```

### 4.1 Threading model

- **Main does no I/O.** The main thread never calls `proc_*`, the file system, NSTask or the network. This rule removes the main-thread sample in LocoHost (main.m:897, 1221), MinMacs 1.2 (main.m:424) and Insomnia's `pmset -g` (main.m:681).
- **Ticks come from dispatch timers.** A `DISPATCH_SOURCE_TYPE_TIMER` on `core.senses` replaces the NSTimers. A dispatch source fires on its queue and not on a run loop, so an open menu does not pause it. Leeway plays the role of NSTimer's `tolerance`, for which Apple advises "at least 10% of the interval" (Foundation `NSTimer.h:47-48`).
- **Each knower gets its own labeled serial queue.** Each queue is created with `dispatch_queue_attr_make_with_autorelease_frequency(…, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM)`, which pushes and pops a pool around every block submitted asynchronously (`dispatch/queue.h:840-843`). The header says it has no effect on `dispatch_sync` (`dispatch/queue.h:878-879`). Loops that walk files or parse git output also get an inner `@autoreleasepool` per entry batch.
- **QoS classes.** Use utility for the senses pass and the knowers. Use background for the review, disk walks and trends. Apple's guide describes utility as "a balance between responsiveness, performance, and energy efficiency" and background as "Focuses on energy efficiency". It advises "Optimally, run your app at a QoS level of utility or lower at least 90% of the time when user activity is not occurring" ([Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheTaskLevel.html)).
- **Events first.** Memory pressure already uses `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` (locohost main.m:856, `dispatch/source.h:136-146`). Power uses `IOPSNotificationCreateRunLoopSource`, and thermal uses `NSProcessInfoThermalStateDidChangeNotification` (insomnia main.m:270-275). The senses pass carries these as facts. Experts no longer subscribe on their own.

### 4.2 Time budgets per expert

The budgets are targets for phase 1 to measure, not measurements. The "today" column cites the code.

| Expert | Work | Queue | Cadence | Budget per run | Today |
|---|---|---|---|---|---|
| Core senses | process, socket and power pass for all five | core.senses | 5 s | 50 ms CPU | about 40 ms upper bound per LocoHost tick, section 2 |
| MinMacs | agent registry match, app plan | core.know.agents | each senses pass | 10 ms | ran on main every 4 s (legacy main.m:416-424) |
| LocoHost | intel, git per cwd, Where, HTTP probe | core.know.git, .where, URLSession | 5 min cache, Where every 30 s | 3 s per subprocess, as Where.m:22 | same, Intel.m:388-405, main.m:897-899 |
| WorkForest | discover, facts, status, sizes | core.know.git with a 6-way gate, walks in the child | FSEvents, full pass at most every 5 min | warm pass under 1 s, per PLAN.md §3 | 5.41 s CPU per scan, section 2 |
| Noo-Noo | sizing, clutter kinds, trends | walks in the child | FSEvents, sizes after 6 h, as `kSizeFresh` in Trees.m:10 | 60 s per walk batch, the child is killed after it | Go daemon, not measured here |
| Insomnia | assertions, lid, guards | core.act | on graph change and power events | 10 ms, plus `pmset` off main with a 10 s timeout | `pmset -g` on main (main.m:681) |
| Review | rules, then a model batch | core.review | events at least 10 min apart (locohost main.m:30) | the subprocess timeout | per app today |

**Enforcing a budget.**
- Each job carries a deadline. A subprocess past its deadline gets `terminate`, as Where.m:20-22, Trees.m:406 and insomnia main.m:176-178 already do.
- Code inside the process cannot be stopped from outside. If a knower job runs past its budget, the core lets it finish, skips its next turn and logs the overrun with the expert's name.
- That limit is the reason long walks run in a child process.

### 4.3 Crash isolation

| Option | What it isolates | Cost | Works ad-hoc signed? | Source |
|---|---|---|---|---|
| In-process only | nothing. An exception in one expert ends all five icons | none | yes | |
| Child of the same binary, `minmacs _walk` | crashes and memory of walks. Exit returns all its memory | one spawn per batch, JSON over a pipe | yes. WorkForest and Insomnia already spawn sibling CLIs (Trees.m:396-406, insomnia main.m:166-180) | |
| XPC service in `Contents/XPCServices` | crashes and memory. launchd relaunches it and kills it when idle | a second executable and Info.plist, a C or NSXPC protocol | unproven here. Sparkle ships ad-hoc signed XPC services but says this is "not ideal for distribution" | [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/) |
| LaunchAgent helper through `SMAppService agentServiceWithPlistName:` | everything. It survives an app crash | a registered job and a login items entry | needs testing | SMAppService.h:94 |

- **Apple on XPC services.** XPC services exist so that "if it crashes, the rest of the application is not affected". launchd "launches them on demand, restarts them if they crash, and terminates them (by sending SIGKILL) when they are idle" ([Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)).
- **C API availability.** The C session API `xpc_session_create_xpc_service` is available from macOS 13 (`usr/include/xpc/session.h:84-118`). That matches `LSMinimumSystemVersion 13.0` in locohost/Info.plist and workforest/Info.plist. `xpc_listener_create` needs macOS 14 (`xpc/listener.h:124`).
- **Recommendation.** Keep the core in-process. Move disk walks to a child of the same binary first, because that path is proven on this Mac today. Keep git, claude, codex and pmset as NSTask children with timeouts, as now. An XPC service can replace the child later. That swap needs a phase 0 test that launchd starts an embedded `.xpc` from an ad-hoc signed bundle.
- **Crash reports per expert (PLAN.md §10).** Every queue is labeled `no.guerrilla.minmacs.<expert>.<job>`. It is a guess that macOS crash reports name the queue of the crashed thread, and phase 0 should check one `.ips` file. In addition, the core writes the running job name to a small breadcrumb file before each job and clears it after. On the next launch, a leftover breadcrumb names the expert that was running.
- **No `@try` around experts.** A catch does not cover signals such as `EXC_BAD_ACCESS`. Under ARC, a caught exception leaks by default. This is a guess from clang's ARC documentation, not tested here.

### 4.4 Memory budget

These are targets, set against the measurements in section 2.

| Part | Target | Basis |
|---|---|---|
| AppKit process with five status items | 35 MB | LocoHost idles at 30.3 MB and Insomnia at 47.0 MB |
| Graph snapshot, two generations live | 5 MB | guess. LocoHost's `activity.json` is 33 KB and WorkForest's `facts.json` 57 KB plus `sizes.json` 21 KB (`ls -la` of the support folders) |
| Caches: patch-ids, sizes, registry | 5 MB | `patch-ids.json` is 141 KB |
| Steady idle total | 50 MB or less | against 127.5 MB for three apps today |
| Peak inside the app | 100 MB | every heavy loop drains its pool |
| Peak in a walk child | 300 MB, then exit | against a 3.6 GB WorkForest peak |

**Under memory pressure.** The core drops caches at `DISPATCH_MEMORYPRESSURE_WARN` and skips walks at `CRITICAL`. LocoHost listens for both flags today (main.m:856).

### 4.5 Sharing the graph without locks on the main thread

```
core.know.*  ---facts--->  core.graph (serial)
                              builds Snapshot N+1, all NSArray/NSDictionary immutable copies
                              dispatch_async(main) { Graph.current = N+1; experts redraw }
main thread   reads Graph.current only; it is the only writer of that pointer
core.ipc and core.act  read  Graph.latest, an atomic property set on core.graph
```

- **One writer for main.** Only core.graph builds snapshots, and only main assigns `current`. The main thread therefore reads without a lock.
- **Snapshots never change.** A snapshot is immutable after publish, so readers on other queues need only a safe pointer read. An `atomic` Objective-C property or a pointer behind `os_unfair_lock` gives that read. The lock holds for a pointer copy, never for a loop (`usr/include/os/lock.h:104-115`).
- **The generation number.** Each snapshot carries `generation` and `builtAt`. A menu shows how old its facts are. An action checks fresh against live state, not against the snapshot, per PLAN.md §1.5.
- **What is removed.** `@synchronized (self)` shared by scan workers and main-thread getters goes away (Trees.m:634-636). So do the `dispatch_sync` reads from the menu (Where.m:229) and resampling on menu open (locohost main.m:1221). A click may ask core.senses for a fresh pass, but the menu opens from the current snapshot at once.

### 4.6 CLI and app

```
minmacs <verb> [--json]          also invoked as locohost, workforest, noo-noo or insomnia
   |
   +-- connect ~/Library/Application Support/MinMacs/core.sock, timeout 200 ms
   |     answers: send {"verb", "args", "argv0"}, print the JSON reply, exit
   |              mutating verbs run in the app on core.act, so one writer owns undo and state
   |
   +-- no answer: run the core in this process once, cold, as every CLI does today
                  take core.lock with flock before writing state
```

- **Why a Unix socket.**
  - An NSXPC mach service needs a name "advertised in a launchd.plist" (Foundation `NSXPCConnection.h:55, 133`). A plain app launched from Finder has no such name.
  - A Unix socket needs nothing from launchd.
  - Noo-Noo already has this pattern, an exclusive `flock` on `<socket>.lock` before it touches the socket. It removes a stale socket only when nothing answers on it (noo-noo internal/ipc/server.go:82-160).
  - `sun_path` holds 104 bytes (`usr/include/sys/un.h:79`). The socket path `~/Library/Application Support/MinMacs/core.sock` expands to 63 bytes on this Mac (`printf '%s' … | wc -c`).
  - The server checks the caller with `getpeereid` (`usr/include/unistd.h:673`) and accepts only the same uid. The folder is mode 0700 and the socket 0600.
- **What the socket saves.** A warm answer from the app skips the cold sample with its 1 s sleep (locohost main.m:559). It also replaces the sibling spawns in WorkForest and Insomnia, which go away inside one process anyway.
- **Aliases.** The CLI dispatches on the base name of `argv[0]`. The family already ships CLIs as symlinks to the app binary: `~/.local/bin/locohost` and `~/.local/bin/workforest` (`ls -la`). All four apps enter CLI mode when `argv[1]` does not start with `-` (locohost main.m:1499, workforest main.m:1009, legacy main.m:739).
- **Works alone.** With every icon hidden, PLAN.md §1.6 asks that the core still run for agents on the CLI. The app keeps running without status items and answers on the socket. If the app is not running at all, the CLI falls back to a cold, in-process core.

## Recommendations

1. **PLAN.md §3 The shared core.** Add a "Threads" paragraph. AppKit runs on main only, with one labeled serial queue per knower and dispatch timers in place of NSTimers. Queues use `DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM`. Shared pattern: core scheduler.
2. **PLAN.md §3 Graph.** Write down the snapshot rule. core.graph is the only builder, main is the only writer of `current`, snapshots are immutable and carry a generation number, and no expert takes a lock that a worker also holds. Shared pattern: graph snapshot.
3. **PLAN.md §10 Risks, "One process for all".** Name the walk child, `minmacs _walk`, as the first isolation step. Keep an XPC service as a later option once ad-hoc launch is proven. Add the breadcrumb file for per-expert crash reports. Shared pattern: isolated worker.
4. **PLAN.md §9 Phase 1, "Done when".** Replace "below MinMacs 1.2's" with numbers MinMacs 1.2 can also be held to. These are idle footprint at or under 50 MB, idle CPU at or under 0.5% averaged over 10 minutes, and a peak footprint in the app at or under 100 MB. Measure them with `ps -o time` and `vmmap --summary` as in section 1. MinMacs 1.2 has no baseline on this Mac. Shared pattern: performance budget.
5. **PLAN.md §9 Phase 2.** Add "a full scan's peak memory is at or under 300 MB in the walk child, and the app's footprint returns to idle". Today one scan spikes RSS to 2.1 GB and the lifetime peak is 3.6 GB. Shared pattern: performance budget.
6. **PLAN.md §7 CLI.** State the transport. A Unix socket in the support folder with a flock instance lock and a same-uid check, and a cold in-process fallback when no app answers. Mutating verbs go through the app when it runs. Shared pattern: CLI bridge.
7. **PLAN.md §9 Phase 0.** Add three checks to "Decide".
   - Whether launchd starts an embedded `.xpc` from an ad-hoc signed bundle.
   - Whether `.ips` crash reports name the dispatch queue.
   - Whether the autorelease pool explains the WorkForest spike, measured with `heap` on a fixture.

   Shared pattern: isolated worker.
8. **PLAN.md §2 What each app brings.** Under "Leave behind", add main-thread sampling for MinMacs and LocoHost and the NSTimer ticks that stop while a menu is open. For WorkForest, add `@synchronized (self)` shared with the scan and spawning `locohost list --json`. Shared pattern: core scheduler.

## Open questions

1. Does launchd start an XPC service embedded in an ad-hoc signed app on macOS 13 to 27? No source here settles it. Sparkle ships ad-hoc signed XPC services by default and says this "works for common development workflows, but is not ideal for distribution".
2. Is the WorkForest memory spike caused by missing autorelease pools, by git output buffers read with `readDataToEndOfFile` (Trees.m:186, 405), or by both? One scan is not enough to tell.
3. Do `.ips` crash reports on macOS 27 include the dispatch queue label of the crashed thread?
4. What are MinMacs 1.2's idle CPU and memory on this Mac? It is not installed, so phase 1's "below MinMacs 1.2's" has no number yet.
5. Can an open NSMenu update its items when a new snapshot arrives? If not, should the menu show the snapshot from the moment it opened? This needs a test with the render harness from docs/DESIGN.md.
6. What do Noo-Noo's walks cost in CPU and memory, as Go today and as Objective-C after the port? Noo-Noo's daemon was not running and was not measured.
7. Should the app run as a login item through `SMAppService.mainAppService`, as WorkForest offers today (main.m:984-985)? The CLI would then almost always find a warm app.

## Verification

Checked on 2026-10-27 by re-reading each cited file and line, re-fetching each URL and re-running the read-only commands. Counts: 62 confirmed, 8 corrected, 3 unsupported.

**Confirmed.**
- Machine and apps. `sysctl`, `sw_vers` and `codesign -dv` match: M1 Pro, 10 cores, 34,359,738,368 bytes, macOS 27.0.1, all three apps `Signature=adhoc` and `TeamIdentifier=not set`. `ps -o lstart` puts the three PIDs' launch times consistent with the etime column at 16:05:01 local. `stat` matches the three build times.
- Raw samples. `scratchpad/h-baseline/ps_start.txt`, `ps_end.txt`, `ps_loop.txt` and `top.txt` hold every CPU time, the 15:05:09Z to 15:07:20Z window, the scan samples at 16:06:43 to 16:06:59, the RSS of 2,166,432 KB, top CPU 59.0% and 35.6%, 23 and 19 threads, and compressed memory 106 MB to 1,358 MB. The top average for LocoHost is 0.74% when the first sample, which top always reports as 0.0, is left out. The arithmetic for every percentage, the 1.8% scan estimate and the 40 ms tick bound checks out.
- Peaks. A rerun of `vmmap --summary` reads peaks of 56.1 MB, 3.6 GB and 52.1 MB, and Insomnia's footprint at 47.0 MB.
- Code. Every line cited in locohost (main.m:30, 559, 856, 862, 897, 935, 1220-1221, 1357-1359, 1499; Ports.m:304, 439-470; Intel.m:388-405; Where.m:20-22, 217, 225-229), workforest (main.m:19-20, 371, 380-382, 746-758, 967, 984-985, 1008-1009; Trees.m:10, 186, 296-330, 365-370, 396-406, 634-636, 665, 682-683) and insomnia (main.m:163-185, 270-275, 504, 516, 648, 681) shows what the text says. Insomnia's main.m has 742 lines. The MinMacs 1.2 lines (main.m:416, 424, 739; Scanner.m:106) match on `legacy`, and `main` has the same `Sources`. A grep of MinMacs 1.2 finds no background queue. WorkForest has one `@autoreleasepool` across all its sources.
- Noo-Noo. internal/ipc/server.go:82-160 shows the flock on `<socket>.lock` before the socket and the stale-socket check.
- SDK headers. `dispatch/queue.h:846-849, 881`, `dispatch/source.h:136-146`, `NSTimer.h:47-48`, `NSXPCConnection.h:55, 133`, `xpc/session.h:114-118` for macOS 13, `xpc/listener.h:124` for macOS 14, `os/lock.h:104-115`, `sys/un.h:79` for 104 bytes, `unistd.h:673` for `getpeereid`, and `SMAppService.h:94`.
- Web. The Energy Efficiency Guide quotes, both XPC Services quotes and the Sparkle ad-hoc page match.
- Files and setup. `LSMinimumSystemVersion` is 13.0 in both Info.plist files. `~/.local/bin/locohost` and `workforest` are symlinks into the app bundles. `which minmacs` finds nothing and `~/Applications` holds no MinMacs. The support files read 34,156, 58,603, 21,837 and 141,756 bytes now, in line with the sizes given. PLAN.md §1 principles 5 and 6, §3 "under one second", §9 phase 1 "below MinMacs 1.2's" and §10 "One process for all" match. docs/DESIGN.md:36 describes the render harness.

**Corrected.**
1. Idle CPU sum. The table gives 0.74% plus 0.35% plus 0.29%, which is about 1.4%, not 1.1%.
2. NSTimer.h:27 documents the block variant, not the target and selector variant the apps call.
3. The run loop quote was cut mid-sentence, and the guide names mouse-dragging and other tracking loops, not tracking loops in general.
4. Trees.m:687 runs on the scan thread, not in a worker. The worker lines are 694, 697, 701, 708 and 725.
5. `DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM` covers blocks submitted asynchronously only, per `queue.h:840-843` and 878-879.
6. The socket path is 63 bytes, not about 62.
7. Sparkle says ad-hoc XPC services are "not ideal for distribution". It does not say they are only for development.
8. WorkForest's idle thread count in top is 3 to 4, not 3.

**Unsupported.**
1. The process count of 867 and 665. It is a point-in-time count with no saved output, and a rerun read 829 and 615.
2. LocoHost's footprint of 30.3 MB after the window. No vmmap output was saved, and a rerun read 37.8 MB.
3. WorkForest's footprint of 50.2 MB after the window and the claim that the scan memory was released. No vmmap output was saved. top MEM stayed at 2,185 MB to the end of the window, and a rerun read a 2.6 GB footprint. The idle sum of 127.5 MB and the memory targets that use 30.3 MB and 50.2 MB rest on these two readings.

Claims the text already marks as guesses or inferences were left as they are and are not counted.
