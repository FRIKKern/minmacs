# Core

The shared core of MinMacs 2.0. Issue #11 wrote it as headers. Each type's doc comment names its pattern from [SYNTHESIS.md](../../docs/2.0/research/SYNTHESIS.md) section 1 and the code it starts from. The `.m` files came in phase 1, each module on its own branch with stand-ins so it linked alone. The Core wiring work removed the stand-ins and made Core one running whole, below.

`#import "Core/MMCore.h"` brings in every header. build.sh passes `-ISources`, so imports start at `Core/`.

## Rules the headers set

- Every symbol starts with `MM`. test.sh checks this.
- Core headers import Foundation only, never AppKit or Cocoa. An expert describes its menu and cards as data in `MMExpert.h`, and the kit in `Sources/UI` draws them.
- A few Core `.m` files will need `NSWorkspace` and `NSRunningApplication` from AppKit, for app events, owning apps and quitting apps. They use those classes only and never draw.
- `MMRowMark` in `MMExpert.h` follows `MMMark` in `Sources/UI/MMMenuKit.h` member for member, so the kit casts one to the other. Change both together.
- Every action is checked on `-[MMGraph freshFactsFor:]`, never on the snapshot. `MMRunAction` does this for every expert.
- AppKit runs on main. Everything else runs on an `MMQueue`, labeled `no.guerrilla.minmacs.<expert>.<job>`. Core's own knowers use `core` as the expert.
- An expert reads `MMFacts` and `MMSnapshot` only. It never samples, scans or asks the model on its own.
- Core stores keep, go and unsure. Each expert keeps its own words through `MMVerdictWords`, per decision 9.

## Where each pattern lives

| Patterns | Header | What it holds |
|---|---|---|
| P1, P2, P3, P5 | `Runtime/MMRuntime.h` | `MMQueue`, `MMTimer`, `MMJob`, breadcrumbs |
| P4 | `Runtime/MMWorker.h` | The `MMWorker` protocol for walks out of process |
| P63 | `Runtime/MMCoreSocket.h` | `core.sock`, the instance lock and the same-uid check. The CLI side lives in `Sources/CLI` |
| P6 to P14, P66 | `Senses/MMSenses.h` | `MMProcKey`, `MMProc`, `MMSample`, `MMSocket`, `MMPower`, `MMSignal`, `MMSenses`, the test `MMPowerSource` |
| P15 | `Senses/MMFolders.h` | `MMFolderWatch` on FSEvents |
| P16 | `Know/MMSizer.h` | `MMSize` and `MMSizer`, three tiers. PLAN.md lists the Sizer under Know |
| P17, P18 | `Know/MMRegistry.h` | `MMAgentRow`, `MMAgent`, `MMRegistry` and the ranked working signal |
| P19 to P22, P64 | `Know/MMSessions.h` | `MMSession`, `MMSessions`, `MMAgentEvents`, `MMHookIngest` |
| none | `Know/MMWhere.h` | `MMPlace`, `MMWhereIs`, `MMGoTo`, from LocoHost's Where |
| P23 to P26 | `Know/MMGit.h` | `MMRun`, `MMGit`, `MMWorktree`, `MMGitFacts`, `MMRepoIndex` |
| P27 | `Know/MMFactCache.h` | `MMFactCache` for git facts, sizes and review fingerprints |
| P28 to P30 | `Know/MMClutter.h` | `MMClutterKind`, `MMClutterItem`, `MMClutterCatalog`, `MMCachePathOf` |
| P31 to P33 | `Graph/MMGraph.h` | `MMOwner`, `MMCost`, `MMEvidence`, `MMProposal`, `MMFinding`, `MMFacts`, `MMWorkstream`, `MMSnapshot`, `MMGraph` and its fresh facts |
| P34 to P37 | `Store/MMStore.h` | The support folder, prefs on `no.guerrilla.minmacs`, `MMRules`, `MMStateFile` |
| P38 | `Store/MMLog.h` | The SQLite log for undo, restore, review history and trends, per decision 5 |
| P39 to P47 | `Review/MMReview.h` | `MMUsage`, `MMModel`, `MMVerdictWords`, `MMVerdict`, `MMReview`, `MMRule`, `MMBudget`, `MMReviewRequest`, `MMReviewBroker` with Investigate |
| P52, P53 | `Act/MMUndo.h` | `MMUndoRecord`, `MMUndo` with the Trash, git bundles and Wrap Up records, `MMToolCommand` with its dry run |
| P48 to P51, P54, P55 | `Act/MMAct.h` | Modes, `MMExpertPolicy`, `MMMustKeep`, `MMPlan`, `MMKeep`, `MMAction`, `MMStop`, `MMAwake`, `MMNotify` |
| P56 to P62 | `MMExpert.h` | The `MMExpert` protocol, `MMRowMark`, and the menu, card and verb specs it returns. The kit, render tool, formatters, verb registry and URL router themselves live in `Sources/UI` and `Sources/CLI` |
| P65 | none | build.sh, test.sh and the CI workflow. `MMCore.h` notes it |

## Runtime and Senses, issue #14

- The worker of P4 is a `minmacs _walk` child of the same binary. The XPC kind waits for the settling check on macOS 14. The child calls `+[MMSizer quick:]` and `+exact:` directly, and both walk in process. It finds worktrees itself by reading `.git` files, with no git spawn. A test tool that uses the worker answers `_walk` itself, as `test/wire/wire.m` does.
- One pass measured 6.1 to 7.5 ms CPU median and 6.6 to 9.4 ms p95 on the research Mac, over 60 to 100 passes with 836 to 929 pids. The spread follows the load from other builds. `test/senses.sh` fails above 12 ms median or 25 ms p95.
- A zombie, a process that exited and waits for its parent to reap it, is left out of the sample, and `MMProcAlive` says it is gone. Every array a sample hands out is immutable.
- `-[MMSenses stop]` ends the timer, the pushed sources and the notification observers. `MMCoreStop` calls it.

## Know in phase 1

Issue #15 adds `MMRegistry.m`, `MMSessions.m`, `MMWhere.m`, `MMFactCache.m` and `MMRun.m` under `Know/`. Core wiring adds `MMSizer.m` and `MMRepoIndex.m`. `MMClutter` stays a header until phase 3.

- `MMRun` and `MMRunTask` do all pipe work on the calling thread with poll. Past the limit the child gets SIGTERM, then SIGKILL a second later, and the pipes are closed half a second after that, even when a grandchild holds them. The review broker and Act's tool commands run through `MMRunTask`.
- `MMWhereIs` drops a cached place once its pid and start time are gone, on every call, and empties the cache past 256 answers.
- The cmux events reader is behind the pref `core.cmuxEvents` or `MINMACS_CMUX_EVENTS=1`. `MINMACS_CMUX` and `MINMACS_TMUX` name the CLIs, which the checks use for fakes.

### The Sizer, TESTS.md question 11

- `quick:` walks with `getattrlistbulk`. Private bytes are freed. A full clone family's shared bytes count once, only when every holder its refcount names is in the walk. A hard-linked inode counts only when every link is in the walk. This is an estimate: a partial clone shares blocks with a family it left, and no flag shows that, so the pair of a base and its partial clone counts low.
- `exact:` maps every inode that may share blocks with `F_LOG2PHYS_EXT` and sweeps the device in order. A stretch is freed when it is private, or when two or more inodes of the set hold it and none of them shares outside. An inode shares outside when it has a hard link outside the roots, or when its clone family's refcount names a holder outside. Past 30 seconds or 200,000 files it gives the estimate, since question 14 found the union too slow for large trees.
- Neither tier can see two full clones in the set that also share blocks with a partial clone outside it. The statfs delta in the undo record, `freedOnVolume:by:`, stays the measured number.

### The repo index

- `MMRepoIndex` walks its roots in the worker. The roots are `$MINMACS_ROOTS` when set. With `MINMACS_HOME` set and no `MINMACS_ROOTS` there are none, so a test never walks the person's folders. Otherwise they are the `roots` list in `core/rules.json`, which starts with WorkForest's roots and the Cursor and Conductor folders.
- `MMCoreStart` watches the roots with FSEvents. Only a change to a `.git` folder, or to a folder near a root outside every known checkout, starts a walk, and walks are at least 10 seconds apart. A full walk also runs every 10 minutes.
- `worktreeAt:` reads `.git` files above the path, with no spawn. `factsFor:wait:` returns nil until WorkForest brings git facts in phase 2.

## Store

- With `MINMACS_HOME` set, `MMPref` and `MMSetPref` read and write `$MINMACS_HOME/Preferences/no.guerrilla.minmacs.plist` as a file under an flock, never through CFPreferences, so no test writes the real `no.guerrilla.minmacs` domain.
- `MMLog` runs on `MMQueue(@"core", @"log")`. The review broker and the undo engine write to it directly. There is no JSON lines fallback.

## Core as one whole

- One support folder function, `MMSupportDir` in Store, and one queue maker, `MMQueue` in Runtime. No Core class is looked up by name. `test/wire.sh` checks all three with grep.
- `MMRegisterExpert` adds an expert to the graph and to the broker, with its rules and its request maker. `MMExperts` and `MMExpertNamed` read the list.
- The fact source of the graph lives in `MMCore.m`. A rebuild reads the latest sample and power facts, the agents the registry finds in that sample, the session index, which it refreshes, and the repo index. It samples on its own only after a watched process exited, because the last sample still lists it. Each new snapshot hands the keys of its agents and of every process a finding names to `watchExits:`, once per key. An exit rebuilds in about 30 ms on the test Mac.
- `-[MMGraph freshFactsFor:]` takes a new sample and reads the sessions again. It returns nil on main.
- `MMGraph observe:` and `stopObserving:` take a lock, so any queue may call them. The blocks still run on main.
- `MMCoreStart` starts Store, Senses, Know, the graph with its fact source, a scheduled review wake per expert every hour, the first a minute after launch, and core.sock. With `MINMACS_HOME` unset it also runs the one migration from MinMacs 1.2 and LocoHost. `MMCoreStop` stops the timers, the FSEvents watch, Senses, the cmux reader and the socket.
- core.sock follows NN `server.go:82-160`: an flock on `core.lock`, the socket made with a 0177 umask and set to 0600, and `getpeereid` on every connection. A peer with another uid is closed without a reply. A request is one JSON line with a `verb`. Core answers `ping` and `status`, and `MMCoreServe` adds more, which `Sources/CLI` is to do for the verbs that run in the app. A socket file left by a crash is replaced by the next process that takes the lock.
## The shell and the CLI, issue #20

- `MMSpecs.m` holds the menu, card and verb specs as plain data.
- `Sources/Shell/MMShell.m` is the app: it calls `MMCoreStart`, adds the `cli` and `reopen` verbs to core.sock with `MMCoreServe`, makes one status item per expert and opens Settings. `Sources/main.m` registers each class named in `MMBuiltInExpertClasses` that is linked in: `MMMinMacsExpert`, `MMLocoHostExpert`, `MMWorkForestExpert`, `MMNooNooExpert` and `MMInsomniaExpert`. An expert lands by adding its class, with no change to the shell.
- `Sources/CLI` holds the verb registry, Core's verbs, `MMArgs` and the URL router. A verb prints through `MMArgs`, never with printf, so its output reaches the terminal from the app too.

## How the parts meet

1. Senses takes one sample every 5 seconds and pushes exits, app events and power changes.
2. The graph builder gathers an `MMFacts` from Senses and Know, asks each expert for its findings, and publishes an `MMSnapshot` to main.
3. The broker reviews findings whose fingerprint moved, after rules, within the `MMBudget`.
4. Act plans from the snapshot and the review under the expert's mode. It runs each action through `MMRunAction`, which checks fresh, writes the undo record, then acts.
5. UI draws each expert's `MMMenuSpec` and `MMCardSpec`. The CLI runs each expert's `MMVerbSpec`.

## Checks

`./test.sh` ends with the headers section in `test/headers/check.sh`. It checks that:

- `test/headers/check.m` imports every header here
- they compile with no warnings for arm64 and x86_64 on macOS 14, with and without `MM_TESTS`
- each header compiles on its own
- no header imports AppKit or Cocoa
- Core and the headers in `Sources/UI` and `Sources/CLI` compile together, so no name is declared twice
- every pattern P1 to P66 is named
- every symbol starts with `MM`

`check.m` calls through the `MMExpert` protocol and never links, so it shows the methods can be called. It does not show they can be implemented. `build.sh` compiles the `.m` files that exist.
