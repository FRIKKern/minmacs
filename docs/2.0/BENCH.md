# The idle tick

Issue #52. What MinMacs 2.0 costs at rest with all five experts, after the tick work. docs/2.0/MEASUREMENTS.md keeps the numbers of issue #23 and the method they share. Every number here comes from a command named below. Each run writes its raw JSON, `report.md` and `gate.txt` under `build/`, which git ignores.

## Result

`tools/bench/run.sh 1800 30 200 build/bench/w4-idle-30m`, built with `BUILD_DIR=build/w4-idle`. Thirty minutes from 01:32:25 UTC on 2026-10-28, after 30 seconds of warm-up.

| Budget | Phase 6 | Before, issue #23 | This run | Ceiling now |
|---|---|---|---|---|
| Idle CPU | 0.3 % | 1.489 %, two experts | 0.291 %, five experts | 0.6 % |
| CPU a tick, mean from one sample to the next | 15 ms | 46.69 ms, pass and rebuild at the median | 14.545 ms | 30 ms |
| Idle footprint | 45 MB | 12.00 MB | 10.70 MB, peak 12.47 MB | 20 MB |
| Wakeups a second | under 1 | 0.423 | 0.223, idle wakeups 0.000 | 0.5 |

All four targets are met. The idle CPU is 0.291 %, or 5.238 seconds of CPU in 1800 seconds. It sits 0.009 points under the budget on a busy Mac, so the margin is thin. See "What is left".

## How it was measured

- The Mac: MacBookPro18,1, 10 cores, macOS 27.0.1. Other agents built and tested in other worktrees through the window. The load average was 10.46, 14.17 and 21.71 at the start and 3.64, 4.50 and 6.73 at the end.
- `tools/bench/bench idle` runs `MMCoreStart` with the five built-in experts in one process: MinMacs, LocoHost, WorkForest, Noo-Noo and Insomnia. It loads AppKit with no status item and runs main at user-interactive QoS, as the app does. Every mode is Idle in a fresh `MINMACS_HOME`. Senses reads the real process table. The model, cmux and tmux CLIs are `/usr/bin/false`. Claude Code's, Codex's and pi's folders point into that home.
- `run.sh` now sets `MINMACS_NO_BACKOFF=1`, so the pass kept its 5 seconds through the whole window. The numbers above are those of a Mac in use, not of one the person left. `MM_BENCH_BACKOFF=1` lets the pass back off as the app does.
- CPU and footprint come from `getrusage` and `task_info` at both ends of the window, wakeups from `TASK_POWER_INFO`. The tick is the whole process's CPU from one sample signal to the next, 360 of them. The parts come from `-[MMSenses counts]` and `-[MMGraph costs]`, thread CPU time per part and per expert, read at both ends of the window.

## Where a tick goes

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

Each pass carried the args of 815 processes and the cwd of 27. It read the sockets of 125 processes and carried those of 501. The session index read its folders 28 times, once a minute, and skipped 366 refreshes. The graph skipped 2 builds whose facts did not change. LocoHost never handed back its last findings in this window, since the fixture servers of other agents' tests started and ended in almost every tick.

Alone, on one thread after the window, 20 runs each, the pass took 3.417 ms at the median and a build 4.03 ms: 0.497 for the facts and 3.537 for the snapshot. The window costs more than that because the pass runs at utility QoS, often on the efficiency cores, under the load of other builds.

## How it was profiled

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

## What changed

**Senses.** A sample takes from the last one what holds for the same process: args, responsible pid and app lookups for the same pid, start, parent and name, and the cwd for a pass in which the process used no CPU time, otherwise for 30 seconds from its read. An exec changes the name, so its args are read again. A process that used no CPU time keeps its sockets for 45 to 60 seconds. One that ran but holds the same socket fds has only its TCP fds read again. `MMRunningApps()` reads each app once. An exit drops the process from the last sample with no pass. The pass backs off to 10 seconds on battery, 15 when the person is away 5 minutes, and 30 for both.

**Graph.** A build after a new sample is skipped when the facts digest matches: each of our processes at a CPU band and 16 MB of memory, sockets, power, agents and the identity of Know's objects. It builds at least every 30 seconds, and always for any other reason. An expert that answers `inputDigestFrom:` gets its last findings back when its inputs did not change. Exits within 0.3 seconds share one build.

**Know.** The session index reads only the folders FSEvents named, and all of them every 10 minutes. The registry reads its presence paths every 30 seconds, not on every match.

**Experts.** LocoHost has an input digest, asks Where once a minute per server and reads its undo records when `MMLogStamp()` moved. MinMacs keeps the app each process rolls up into and reads its undo records the same way.

**Store and Act, outside this issue's paths.** One stat replaces `createDirectoryAtPath` and attribute reads. A rules file is checked at most once a second unless this process wrote one. The test prefs and the keeps file are parsed again only when they changed. `MMLogStamp()` is new in `MMLog.h`.

## What is left

- The margin is 0.009 points. A window with more process churn costs more: a 90-second run at load 56 measured 0.324 %, and one with 10 exits in 90 seconds 0.448 %. Each new process costs an args read and a registry match, and each exit of a listed process a build.
- The skip and the reuse rarely fire on this Mac, because other agents start and end processes and fixture servers every few seconds. On a calm Mac they would carry most ticks. That was not measured here.
- The pass is now the larger half. 3.35 ms of it is `proc_pid_rusage` for about 650 of our processes and the objects for 865. `RUSAGE_INFO_V2` costs about 60 % of V6 but has no energy, so the energy rank keeps V6.
- The bench is headless. The app's footprint with status items and menus is higher than 10.7 MB and is not measured here.

## Rerun

```sh
tools/bench/run.sh 1800 30 200          # thirty minutes, then menus and the gate
MM_BENCH_BACKOFF=1 tools/bench/run.sh   # with the backoff the app uses
./test.sh idle                          # the checks of issue #52
./test.sh bench                         # the short run and the gate
```
