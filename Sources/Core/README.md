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
| P16 | `Know/MMTreeDisk.h` | `MMTreeDisk`: one walk per checkout for its size, freed bytes, caches and newest change, from WorkForest's WalkDisk |
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
| P51 to P53 | `Act/MMClutterAct.h` | `MMClutterAction`: clutter to the Trash, or a tool's command after an APFS recovery copy, with an audit |
| P52, P53 | `Act/MMUndo.h` | `MMUndoRecord`, `MMUndo` with the Trash, git bundles and Wrap Up records, `MMToolCommand` with its dry run |
| P52 | `Act/MMWorktreeAct.h` | `MMWorktreeIgnoredFiles`, `MMWorktreeRemove` with no `--force` and `git branch -d`, and `MMWorktreePrune` |
| P48 to P51, P54, P55 | `Act/MMAct.h` | Modes, `MMExpertPolicy`, `MMMustKeep`, `MMPlan`, `MMKeep`, `MMAction`, `MMStop`, `MMAwake`, `MMLidOverride`, `MMNotify` |
| P56 to P62 | `MMExpert.h` | The `MMExpert` protocol, `MMRowMark`, and the menu, card and verb specs it returns. The kit, render tool, formatters, verb registry and URL router themselves live in `Sources/UI` and `Sources/CLI` |
| P65 | none | build.sh, test.sh and the CI workflow. `MMCore.h` notes it |

## Runtime and Senses, issue #14

- The worker of P4 is a `minmacs _walk` child of the same binary. The XPC kind waits for the settling check on macOS 14. The child calls `+[MMSizer quick:]` and `+exact:` directly, and both walk in process. It finds worktrees itself by reading `.git` files, with no git spawn. A test tool that uses the worker answers `_walk` itself, as `test/wire/wire.m` does.
- One pass measured 6.1 to 7.5 ms CPU median and 6.6 to 9.4 ms p95 on the research Mac, over 60 to 100 passes with 836 to 929 pids. The spread follows the load from other builds. `test/senses.sh` fails above 12 ms median or 25 ms p95.
- A zombie, a process that exited and waits for its parent to reap it, is left out of the sample, and `MMProcAlive` says it is gone. Every array a sample hands out is immutable.
- `-[MMSenses stop]` ends the timer, the pushed sources and the notification observers. `MMCoreStop` calls it.
- `MMPower.online` says a default route exists, from one `NET_RT_FLAGS` sysctl per address family. It stands in for Insomnia's reachability check, and a change fires `MMSignalPower`. Issue #31 added it for Insomnia's offline guard.

## Know in phase 1

Issue #15 adds `MMRegistry.m`, `MMSessions.m`, `MMWhere.m`, `MMFactCache.m` and `MMRun.m` under `Know/`. Core wiring adds `MMSizer.m` and `MMRepoIndex.m`. Issue #25 adds `MMGit.m` and `MMGitFacts.m`.
Noo-Noo, issues #28 to #30, adds `MMClutter.m` and `Act/MMClutterAct.{h,m}`: the clutter catalog from `registry/clutter/*.json`, its walls, its scans on `core.clutter` at each row's own pace, the trend math, and removal to the Trash or through a tool's own command after a recovery copy. `Sources/Experts/NooNoo/README.md` describes them.

- `MMRun` and `MMRunTask` do all pipe work on the calling thread with poll. The child's exit and its status come from a kqueue `NOTE_EXIT` with `NOTE_EXITSTATUS` in the same poll, which does not reap it, so NSTask still does. A child that exited normally is not waited for through `waitUntilExit`, which noticed the exit 70 to 95 ms late. MEASUREMENTS.md, section Git, has the cost per run. Past the limit the child gets SIGTERM, then SIGKILL a second later, and the pipes are closed half a second after that, even when a grandchild holds them. The review broker and Act's tool commands run through `MMRunTask`.
- `MMWhereIs` drops a cached place once its pid and start time are gone, on every call, and empties the cache past 256 answers.
- The cmux events reader is behind the pref `core.cmuxEvents` or `MINMACS_CMUX_EVENTS=1`. `MINMACS_CMUX` and `MINMACS_TMUX` name the CLIs, which the checks use for fakes.

### The Sizer, TESTS.md question 11

- `quick:` walks with `getattrlistbulk`. Private bytes are freed. A full clone family's shared bytes count once, only when every holder its refcount names is in the walk. A hard-linked inode counts only when every link is in the walk. This is an estimate: a partial clone shares blocks with a family it left, and no flag shows that, so the pair of a base and its partial clone counts low.
- `exact:` maps every inode that may share blocks with `F_LOG2PHYS_EXT` and sweeps the device in order. A stretch is freed when it is private, or when two or more inodes of the set hold it and none of them shares outside. An inode shares outside when it has a hard link outside the roots, or when its clone family's refcount names a holder outside. Past 30 seconds or 200,000 files it gives the estimate, since question 14 found the union too slow for large trees.
- Neither tier can see two full clones in the set that also share blocks with a partial clone outside it. The statfs delta in the undo record, `freedOnVolume:by:`, stays the measured number.

### The repo index and git facts, issue #25

- `MMRepoIndex` walks its roots in the worker. The roots are `$MINMACS_ROOTS` when set. With `MINMACS_HOME` set and no `MINMACS_ROOTS` there are none, so a test never walks the person's folders. Otherwise they are the `roots` list in `core/rules.json`, which starts with WorkForest's roots and the Cursor and Conductor folders.
- `worktreeAt:` reads `.git` files above the path, with no spawn.
- `startWatching` opens one FSEvents stream per root, with the 0.5 second latency and `NoDefer` that research track B recommends. Each stream saves its own event id as `repos.<hash>.eventid` in the support folder, so a restart replays only what changed while MinMacs was not running. A replay that lands before the first walk is held until the walk ends.
- A change among a worktree's files drops that worktree's status layer and marks its size stale. A change in a git dir marks the worktrees that use it, and their fingerprints are read again. No other worktree is touched. A `.git/worktrees` change, or a folder near a root outside every known checkout, also starts a walk, at least 10 seconds apart. A full walk runs every 10 minutes and reads every fingerprint again.
- A change in a known repo's git dir starts no walk. The update pass reads the checkout's `.git` files again, with no spawn, and replaces the walked worktree when its branch or its lock moved. A linked worktree outside every root has no stream, so its status is read again on every walk.
- `factsFor:wait:` returns `MMGitFacts`: branch, head, the default branch, the upstream with ahead and behind, dirty and untracked counts, the stash count on the branch, commits not in the default branch, commits on no remote, the last commit time and the merge kind. Branch, head, the default branch, the upstream and the stash count come from git's own files: `HEAD`, loose refs, `packed-refs`, `config`, `refs/remotes/origin/HEAD` and `logs/refs/stash`. The rest come from `MMGit` on the `core.git` queue, or `core.git.fresh` for wait YES, never on main. `MMGit` sets `GIT_OPTIONAL_LOCKS=0`, `LC_ALL=C`, no prompts and a time limit, and passes `GIT_CONFIG_GLOBAL` through.
- The facts live in two layers in the persisted cache `git.json`. The status layer, from `git status`, is keyed by HEAD and the index file's stamp. The history layer is keyed by HEAD, the default branch's tip, the upstream's tip, `FETCH_HEAD` and `packed-refs`. wait NO reads memory only and queues an update when a change marked the worktree. wait YES runs `git status` now. A graph rebuild never reads git's files or runs git, and `MMRepoIndexFactsDidChangeNotification` asks for a rebuild when an update moved any facts.
- Merge kinds, for every worktree but the main checkout: ancestor when no commit is outside the default branch, tree when the trees are equal, patch when every branch commit's patch id is among the default branch's, squash when the branch's whole change since the merge base has the patch id of a default-branch commit. Patch and squash are checked only for branches not merged by ancestry or tree.
- The squash check fixes WorkForest 0.1's CPU spike in `Trees.m:104-129`, which read `git log -p -n 400` of the default branch on every scan. A patch id is kept per commit in `git.patchids.json` forever, and the whole-branch id per pair of merge base and head. Only commits the cache has not seen are computed, and only the default branch's commits since the merge base, at most 1,000, are candidates. git's diff streams through `/bin/sh` into `git patch-id --stable`, so it is never held in memory. A new default-branch commit computes one new patch id. The `merge-tree` and pull request kinds are not checked yet.
- `sizeFor:wait:` keeps the quick Sizer tier per worktree in `sizes.json`. A stale size is shown until its new walk ends, and walked again at most once a minute.
- `test/git.sh` checks all of this on fixtures and runs the bench of docs/2.0/MEASUREMENTS.md, section Git.

## WorkForest in phase 2, issue #24

- `MMTreeDisk` walks one checkout at a time on `MMQueue(@"core", @"disk")` and keeps the answers in `treedisk.json`. A walk is fresh for 15 minutes and while the checkout folder's own change time holds. A cached read never blocks, and a stale one walks again in the background and posts `MMTreeDiskDidChangeNotification`. The walk runs in process for now. It belongs in the worker of P4.
- An undo record with a `worktree` payload and no `bundle` restores by `git worktree add` at its commit. `unbundle:` needs the bundle file only when the repo lost the commit.
- `MMReviewRequest.ignoreCache` sends every finding to the model past the fingerprint cache, for `--fresh` and for tests that review the same facts twice. Rules still decide first.

## Store

- With `MINMACS_HOME` set, `MMPref` and `MMSetPref` read and write `$MINMACS_HOME/Preferences/no.guerrilla.minmacs.plist` as a file under an flock, never through CFPreferences, so no test writes the real `no.guerrilla.minmacs` domain.
- `MMLog` runs on `MMQueue(@"core", @"log")`. The review broker and the undo engine write to it directly. There is no JSON lines fallback.
- Opening a new log sets WAL mode and makes the tables in an IMMEDIATE transaction, retrying a lock SQLite refused without waiting, for up to 10 seconds. Two processes that open a new file at once both keep every row. An append retries the same way.
- `MMLogMainThreadQueries` and `MMKeepMainThreadReads` count reads on the main thread, so the checks hold menus to zero. On main, `+[MMKeep keptUntil:expert:]` answers from the last read and reads the file only when nothing was read yet, as in a CLI.
- A failed undo record restores only what it moved aside, such as trashed files. A failed stop or quit restores nothing, since its server or app still runs.

## Core as one whole

- One support folder function, `MMSupportDir` in Store, and one queue maker, `MMQueue` in Runtime. No Core class is looked up by name. `test/wire.sh` checks all three with grep.
- `MMRegisterExpert` adds an expert to the graph and to the broker, with its rules and its request maker. `MMExperts` and `MMExpertNamed` read the list.
- The fact source of the graph lives in `MMCore.m`. A rebuild reads the latest sample and power facts, the agents the registry finds in that sample, the session index, which it refreshes, and the repo index. It samples on its own only after a watched process exited, because the last sample still lists it. Each new snapshot hands the keys of its agents and of every process a finding names to `watchExits:`, once per key. An exit rebuilds in about 30 ms on the test Mac.
- `-[MMGraph freshFactsFor:]` takes a new sample and reads the sessions again. It returns nil on main.
- `MMGraph observe:` and `stopObserving:` take a lock, so any queue may call them. The blocks still run on main.
- `MMCoreStart` starts Store, Senses, Know, the graph with its fact source, a scheduled review wake per expert every hour, the first a minute after launch, and core.sock. With `MINMACS_HOME` unset it also runs the one migration from MinMacs 1.2 and LocoHost. `MMCoreStop` stops the timers, the FSEvents watch, Senses, the cmux reader and the socket.
- core.sock follows NN `server.go:82-160`: an flock on `core.lock`, the socket made with a 0177 umask and set to 0600, and `getpeereid` on every connection. A peer with another uid is closed without a reply. A request is one JSON line with a `verb`. Core answers `ping` and `status`, and `MMCoreServe` adds more, which the shell does for `cli` and `reopen`. A socket file left by a crash is replaced by the next process that takes the lock. `ping` is answered at once, outside the one-at-a-time line, so a long verb never makes the CLI think no app runs.

## The shell and the CLI, issue #20

- `MMSpecs.m` holds the menu, card and verb specs as plain data. `Sources/UI/MMSpecMenu` is the one converter that draws them with the kit, for the shell, the render tool and each expert's tests. One Icon shows four experts' sections and folds the rest under More, with no cards there.
- `Sources/Shell/MMShell.m` is the app: it calls `MMCoreStart`, adds the `cli` and `reopen` verbs to core.sock with `MMCoreServe`, makes one status item per expert and opens Settings. `Sources/main.m` registers each class named in `MMBuiltInExpertClasses` that is linked in: `MMMinMacsExpert`, `MMLocoHost`, `MMWorkForestExpert`, `MMNooNooExpert` and `MMInsomniaExpert`. An expert lands by adding its class, with no change to the shell.
- `Sources/CLI` holds the verb registry, Core's verbs, `MMArgs` and the URL router. A verb prints through `MMArgs`, never with printf, so its output reaches the terminal from the app too.

## The idle tick, issue #52

[docs/2.0/BENCH.md](../../docs/2.0/BENCH.md) has the numbers and how they were taken.

- A sample carries over from the one before, for a process with the same pid, start time, parent and name: its args, its responsible pid, its owning app and its app object. Its cwd carries over while it used no CPU time, for at most 30 seconds. An exec changes the name, so the args are read again.
- A process that used no CPU time since the last pass keeps its sockets, for 45 to 60 seconds. One that ran but holds the same socket fds has only its TCP fds read again, and none when it had no TCP socket. `-[MMSample unchanged:]` says which processes did not run.
- Another user's process with the same pid, start, parent and name keeps its whole `MMProc`, since Senses reads nothing more about it. So does an idle process of ours whose footprint did not move.
- `MMRunningApps()` reads each app from LaunchServices once. An app launch or quit walks the list again and reads only the new app. Every 5 minutes each app is read again.
- An exit drops the process from the last sample with `-[MMSenses sampleWithout:]`, which copies and reads nothing. The rebuild for an exit waits 0.3 seconds to gather the rest of a burst, and leaves it to the next pass when that is due within half a second after.
- The pass backs off to 10 seconds on battery, 15 once no key or pointer moved for 5 minutes, and 30 for both. The first pass after the person comes back or plugs in returns to 5 seconds. `MINMACS_NO_BACKOFF=1` keeps 5 seconds, and the bench sets it.
- The graph skips a build after a new sample when the facts digest matches the last build's: every one of our processes with its start, parent, name, a CPU band and its memory in 16 MB steps, the socket table, power, each agent's state and the identity of every session, worktree, git fact and clutter item. It builds at least every 30 seconds, and always for any reason but a new sample.
- An expert may answer `inputDigestFrom:`, an optional method of `MMExpert`. When its digest matches and only a new sample asked for the build, the graph hands back its last findings, for at most 30 seconds. LocoHost answers it.
- The session index watches Claude Code's project and status folders, Codex's home and pi's sessions with one FSEvents stream. A refresh reads only the folders FSEvents named, and returns at once when none changed, no live status file's process ended, and the last read is under a minute old. Every 10 minutes it lists every folder again. Fresh facts always read everything.
- `MMLogStamp()` changes with any write to the log, from any process. MinMacs and LocoHost read their undo records again only when it moved.
- Store stats the support folder before it makes it, checks a rules file at most once a second unless this process wrote one, and parses the test prefs and the keeps file again only when their inode, change time or size moved.
- `-[MMGraph costs]` and `-[MMSenses counts]` hold thread CPU time by part and by expert. Signposts in subsystem `no.guerrilla.minmacs`, category `tick`, mark the pass, each rebuild and each expert's findings.

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
