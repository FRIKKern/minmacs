# Core

The shared core of MinMacs 2.0. Issue #11 wrote it as headers. Each type's doc comment names its pattern from [SYNTHESIS.md](../../docs/2.0/research/SYNTHESIS.md) section 1 and the code it starts from. The `.m` files come in phase 1. Issue #14 added Runtime and Senses. `test/senses.sh` checks them, and Runtime's README note below says what is still a stub.

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

- The worker of P4 is a `minmacs _walk` child of the same binary. The XPC kind waits for the settling check on macOS 14. The child calls `+[MMSizer quick:]` and `+exact:` through the Objective-C runtime, so those two must walk in process. It finds worktrees itself by reading `.git` files, with no git spawn.
- `MMCoreSocket` is a stub. `+serve:` refuses with a note and `+ask:` returns nil, so the CLI runs Core cold. `MMCoreSocketPath` is real.
- Runtime and Senses read the support folder through `MMRuntimeSupportDir`, which follows the same rule as `MMSupportDir`. It can call `MMSupportDir` once Store lands.
- One pass measured 6.1 to 7.5 ms CPU median and 6.6 to 9.4 ms p95 on the research Mac, over 60 to 100 passes with 836 to 929 pids. The spread follows the load from other builds. `test/senses.sh` fails above 12 ms median or 25 ms p95.

## Know in phase 1

Issue #15 adds `MMRegistry.m`, `MMSessions.m`, `MMWhere.m`, `MMFactCache.m` and `MMRun.m` under `Know/`. `MMGit`, `MMSizer` and `MMClutter` stay headers until phases 2 and 3.

- Know links before Runtime and Store land. `MMFactCache.m` holds Know's own `MMKnowSupportDir` and `MMKnowQueue`, which follow `MMSupportDir` and `MMQueue`. Swap them for the real ones once those land.
- Know reads `MMSample`, `MMProc` and `MMPower` by message only, so it links without Senses. `test/know/fakesample.m` stands in for Senses in `./test.sh know`.
- The cmux events reader is behind the pref `core.cmuxEvents` or `MINMACS_CMUX_EVENTS=1`. `MINMACS_CMUX` and `MINMACS_TMUX` name the CLIs, which the checks use for fakes.

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
