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
- `Sources/Shell`: the app delegate, `MMCoreStart`, `core.sock`, the status items, One Icon, Settings with a pane per expert, the login item, URLs and the main-thread watchdog.
- `Sources/Core/{Runtime,Senses,Know,Graph,Store,Review,Act}`: the shared core. [Sources/README.md](Sources/README.md) says what each holds.
- `Sources/Experts/{MinMacs,LocoHost,WorkForest,NooNoo,Insomnia}`: the five experts, each a class that conforms to `MMExpert` in `Sources/Core/MMExpert.h` with `+shared`. Each folder has a README. An expert gives its findings, rules, review request, menu, cards and verbs as data.
- `Sources/UI`: the menu kit that draws every `MMMenuSpec` and `MMCardSpec`, the formatters and Settings. `tools/render.sh` renders every expert's menus and cards from the fixture subjects in `tools/render.m` into `build/render/`.
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
1. Nothing is lost. Every action is checked fresh right before it runs. It goes to the Trash, to a recovery folder, or through the owning tool's own command. What cannot be verified is kept. MinMacs never empties the Trash.
2. An expert never samples, scans or asks the model on its own. It reads the shared graph.
3. AppKit runs on the main thread only. Each knower has one labeled serial queue, `no.guerrilla.minmacs.<expert>.<job>`.
4. No tick runs `lsof`, `nettop`, `ps` or `pmset`.
5. SIGTERM first, and SIGKILL only on a second request. Pid and start time are checked before both. Never signal pid 1 or MinMacs itself.
6. No hooks are installed, and no permission is asked for at launch.
7. Every menu follows [docs/DESIGN.md](docs/DESIGN.md). After a menu change, run `tools/render.sh` and look at the PNGs in `build/render/` in light, dark and Increase Contrast. CI keeps them.
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
