# For AI agents working in this repo

**MinMacs 2.0 is built on `main` and is not released yet.** Core runs as one whole, with all five experts. Read [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md), [docs/2.0/PLAN.md](docs/2.0/PLAN.md) with its decisions in section 11, the [milestones](https://github.com/FRIKKern/minmacs/milestones) and [docs/DESIGN.md](docs/DESIGN.md) first. [docs/2.0/research/SYNTHESIS.md](docs/2.0/research/SYNTHESIS.md) section 1 is the Core API, and [Sources/Core/README.md](Sources/Core/README.md) says how each part runs. Every piece of work belongs to an issue in a milestone.

**MinMacs 1.2 lives on the `legacy` branch.** Fixes to 1.2 go there, through the Legacy 1.x milestone. `install.sh` on `main` installs from `legacy` by default. Read 1.2 code with `git show legacy:Sources/Agents.m`.

**Build and verify**

```sh
./build.sh                       # universal build into build/MinMacs.app; installs nothing
BUILD_DIR=/tmp/mm-a ./build.sh   # a separate output folder, so parallel builds do not collide
./build.sh --install             # also replaces ~/Applications/MinMacs.app and ~/.local/bin/minmacs
./test.sh                        # fixtures only, in a temporary MINMACS_HOME
./test.sh locohost               # core, then one section from test/
build/MinMacs.app/Contents/MacOS/MinMacs version
```

Never pass `--install` unless the person asks for it. It replaces the app the person runs. Never launch the app from a test, and never call the real `claude` or `codex` CLI from one: the review and Investigate tests have fakes in `test/review` and `test/investigate`.

The full `./test.sh` takes about 17 minutes. Issue #58: on this Mac it is sometimes killed with SIGKILL partway, with no summary line, by a sender not yet found. Then run the sections in groups, such as `./test.sh act bench fixes git graph headers idle insomnia`, and report each group's numbers.

**Layout**
- `Sources/main.m`: the entry point. It registers each class `MMBuiltInExpertClasses` in `Sources/Shell/MMShell.m` names that is linked in, then `Sources/Shell` runs the menu bar app, or the CLI when a verb is given.
- `Sources/Shell`: the app delegate, `MMCoreStart`, `core.sock`, the one icon and the menu window's feed, controller and Fix Everything runner, the login item, URLs and the main-thread watchdog. With the pref `core.window` off: the status items, One Icon and Settings with a pane per expert.
- `Sources/Core/{Runtime,Senses,Know,Graph,Store,Review,Act}`: the shared core. [Sources/README.md](Sources/README.md) says what each holds.
- `Sources/Experts/{MinMacs,LocoHost,WorkForest,NooNoo,Insomnia}`: the five experts, each a class that conforms to `MMExpert` in `Sources/Core/MMExpert.h` with `+shared`. Each folder has a README. An expert gives its findings, rules, review request, menu, cards and verbs as data.
- `Sources/UI`: `Window/`, the menu window's view model and views. The menu kit that draws every `MMMenuSpec` and `MMCardSpec`, the formatters and the Settings window of before. `tools/render.sh` renders every expert's menus and cards from the fixture subjects in `tools/render.m` into `build/render/`.
- `Sources/CLI`: the verb registry, Core's verbs, `MMArgs` and the URL router. A verb is an `MMVerbSpec` and prints only through `MMArgs`. [docs/CLI.md](docs/CLI.md) is generated from `minmacs help --json`.
- `docs/`: [HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md), [REVIEW.md](docs/REVIEW.md), [PRIVACY.md](docs/PRIVACY.md), [CLI.md](docs/CLI.md), [DESIGN.md](docs/DESIGN.md), and `docs/img/`, the README's renders. `docs/2.0/` holds the plan, the research, the settling tests in TESTS.md, and the numbers in MEASUREMENTS.md and BENCH.md.
- `tools/bench`: the bench and its budgets. `test/bench.sh` runs the short bench and the regression gate.
- `registry/`: the agent registry as data. `tools/validate_row.py` checks a row, and build.sh ships every row that passes. `tools/agents_probe.py` is the reference detector, with `tools/fakeagent.c`, `tools/fakehost.c` and the rows in `tools/fixtures/`.
- `test.sh`: the shared harness. `test/core.sh` always runs first and builds the copy every section tests. A piece of work adds its checks as `test/<key>.sh`, with its fixtures and tools in `test/<key>/`. `test/docs.sh` checks that docs/CLI.md and docs/PRIVACY.md match the code.

**Build rules**
- Objective-C, built with clang alone. No Swift, no packages, no Xcode project.
- macOS 14 is the floor. build.sh passes `-mmacosx-version-min=14.0`, and Info.plist says the same.
- Every Core symbol uses the prefix `MM`.
- build.sh compiles every `.m` under `Sources/`, so a new file needs no build change. Source paths must not hold spaces.
- A compiler warning fails the build. Keep it at zero.
- The version lives in Info.plist only. build.sh passes it to the code as `MM_VERSION`.

**Invariants that must hold after any change**
1. Nothing MinMacs removes is deleted at once. Everything it removes keeps a way back: a worktree through git, with its ignored files in a recovery folder and a git bundle for commits on no remote; clutter and untracked config files in the Trash; a tool's own cleanup behind an APFS recovery copy. There is no removal choice: `MMRemovalDecide` in `Sources/Core/Act/MMRemoval.h` is asked by every removal path, and its answer always keeps a way back, whoever asks and whatever the old pref `core.removal` holds. Core's start clears that pref. Every action is checked fresh right before it runs, passes MustKeep and writes its record first. What cannot be verified is kept, git never runs with `--force`, and a record says deleted only once the thing is gone. The staging below settles what a Wrap Up of an older MinMacs, under its old Smart or Delete, left staged; only a check's own seam, compiled with `MM_TESTS`, makes a decision that deletes. A Wrap Up deletes nothing until its last part went through: what a part wants deleted is renamed into a staging folder of MinMacs's own on the same volume, and is deleted only after the last part. It goes back to its exact old path, never over something that sits there now, when a later part refuses. When MinMacs stops in between, it goes back the next time MinMacs starts or runs a Wrap Up, once the process that owned the Wrap Up is gone, and so does what a part had sent to the Trash. What a Wrap Up that went through could not delete is never put back into the worktree git took: at the next start its delete is tried once more, once ever, behind the same wall and identity check, unless the person asked for an Undo of it, and what still waits is listed by `minmacs removal --waiting`, where the person deletes it or puts it back. Nothing is ever deleted for a record that cannot be read, and what its parts moved aside still goes back when their lists read. A staged item is moved back or deleted only from the staging folder MinMacs made for its Wrap Up, `MMRemovalStagedItemWhyNot`, only to the old path that folder's own list holds for it, and never for a part whose Wrap Up has no record. That list names an item before the rename moves it, so an item whose record MinMacs never wrote is found from the folder alone and settled through the same check. An item comes back from the Trash only when MinMacs's own list of what it sent there, written before the move, names that very file, `MMRemovalTrashListWhyNot`, issue #74. A put-back nobody asked for, `MMRemovalPutBack`, only moves files: it never runs a command, opens an app or calls a restorer because a record says so. An item that cannot be staged where the wall would let it be deleted stays where it is. Only `MMRemovalApply` deletes, behind one wall, `MMRemovalWallWhyNot`: a path a fresh finding named, never a volume's root, the home folder, a folder at its top, or MinMacs's own folder. MinMacs never empties the Trash and never deletes from it.
2. An expert never samples, scans or asks the model on its own. It reads the shared graph.
3. AppKit runs on the main thread only. Each knower has one labeled serial queue, `no.guerrilla.minmacs.<expert>.<job>`.
4. No tick runs `lsof`, `nettop`, `ps` or `pmset`.
5. SIGTERM first, and SIGKILL only on a second request. The second request may come from a person, the CLI or an agent such as BarkBot: no person needs to be there. From the CLI with nobody at the terminal it needs `--yes`, since a SIGKILL keeps no way back. Pid and start time are checked before both. Never signal pid 1 or MinMacs itself.
6. No hooks are installed, no permission is asked for at launch, and nothing waits for a person, decision D3. These Macs run unattended. A failure is a row of the log's `notice` table, `MMNotice` in `Sources/Core/Act/MMNotice.h`, with at most one notification, never an alert. A confirm guards only a press a person plainly made in the window or a menu, `MMPersonPresses`, through `MMAskPerson` in `Sources/UI/MMConfirm.m`, the one `NSAlert`. Never for the CLI, an agent, the migration or anything started on its own: an action that keeps a way back then runs, and one that does not, such as Investigate's cost, does not. A link can come from any web page, so a link that stops, removes or cleans, such as `workforest://clean-up`, `locohost://close-idle` or `run-now`, shows the same confirm while a person is here, and runs unasked, by `url`, only while unattended. The CLI never reads stdin when stdin is not a TTY, when `MINMACS_UNATTENDED=1`, or after `minmacs unattended on`. The welcome is skipped while unattended. What macOS asks for itself stays: the administrator password for the lid rule, only on an explicit lid on with a person here; unattended, lid on without the rule is refused at once with a notice. `minmacs device --json` lists in `provision` what a Mac still needs a person for once. `./test.sh unattended` holds this.
7. The menu window and every menu follow [docs/DESIGN.md](docs/DESIGN.md). After a change to either, run `tools/render.sh` and look at the PNGs in `build/render/`: the window's in `window/`, in dark and Increase Contrast, the menus' in light, dark and Increase Contrast. CI keeps them.
8. Every action goes through `MMRunAction`, which checks fresh facts, runs MustKeep and writes the undo record before it acts.
9. What the review sends is listed in [docs/PRIVACY.md](docs/PRIVACY.md). A new key in an expert's review facts needs a row there, or `./test.sh docs` fails.

**Test rules**
1. Fixtures only. Tests run against servers, repos, worktrees, agents and files that the test made itself inside `$MINMACS_HOME`.
2. Never act on a real server, worktree, cache or app in a test. A test that stops, removes or quits names its fixture by port, path or pid, so it cannot reach anything else.
3. Scope every destructive test. A command that would act on everything it finds, such as an auto run, only runs with a scan root, port or path that points into `$MINMACS_HOME`.
4. Stop only what you started. A section adds the pids it starts to `procs`, and cleanup stops those and nothing else. A section that stops its own fixtures takes their pids back out of `procs`, so cleanup never signals a pid the system has given to another process.
5. A detached fixture server calls `setsid`, so it runs in a session of its own. A test tool never passes a pid it has not checked to `kill`, since 0 means its own process group.
6. Never run a package manager to find a path. `brew`, `npm`, `pnpm` and `yarn` can install or change things. Read env vars and config files instead.
7. `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `GIT_CONFIG_GLOBAL` point into the temp folder, so the agent running the tests never feeds a fixture and the person's git config stays out.
8. Other agents build and test on the same Mac at the same time. Give every fixture binary, process and folder a name unique to the run, such as one with `$$` in it, and never match processes by a shared name.
9. Probe ports and sockets with `"$PORT"`, the tool test.sh builds from test/port.c, never with `nc`. On the development Mac, Microsoft Defender's behavior monitoring read the test run as a reverse shell and killed test.sh with SIGKILL, issue #58, and each such run raises alerts on a managed Mac.
10. A test may run with no TTY, and then the CLI answers as `--yes` would wherever a change keeps a way back, D3. A check of the refusal a person at a terminal gets sets `MINMACS_UNATTENDED=0`, and a check that needs a TTY runs its command under `script -q /dev/null`. Every run that once asked has a time limit, `perl -e 'alarm shift; exec @ARGV' <seconds> ...`.
