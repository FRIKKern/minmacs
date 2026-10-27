# For AI agents working in this repo

**MinMacs 2.0 is under construction on `main`.** Read [docs/2.0/PLAN.md](docs/2.0/PLAN.md), the [milestones](https://github.com/FRIKKern/minmacs/milestones) and [docs/DESIGN.md](docs/DESIGN.md) first. [docs/2.0/research/SYNTHESIS.md](docs/2.0/research/SYNTHESIS.md) section 1 is the Core API. Every piece of work belongs to an issue in a milestone.

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

Never pass `--install` in phase 0. The person's installed MinMacs 1.2 must keep running until phase 1 replaces it. Never launch the app from a test.

**Layout**
- `Sources/main.m`: the entry point. The menu bar app, or the CLI when a verb is given.
- `Sources/Core/{Runtime,Senses,Know,Graph,Store,Review,Act}`: the shared core. [Sources/README.md](Sources/README.md) says what each holds.
- `Sources/Experts/{MinMacs,LocoHost,WorkForest,NooNoo,Insomnia}`: the five experts, each a lens on the graph with its menu and CLI verbs.
- `Sources/UI`: the menu kit and the render tool. `Sources/CLI`: the verb registry and the URL router.
- `registry/`: the agent registry as data. `tools/validate_row.py` checks a row, and build.sh ships every row that passes. `tools/agents_probe.py` is the reference detector, with `tools/fakeagent.c`, `tools/fakehost.c` and the rows in `tools/fixtures/`.
- `test.sh`: the shared harness. `test/core.sh` always runs first and builds the copy every section tests. An expert adds its checks as `test/<expert>.sh`.

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
7. Every menu follows [docs/DESIGN.md](docs/DESIGN.md). After a menu change, run the render tool and look at the PNGs in `build/render/`. CI keeps them.

**Test rules**
1. Fixtures only. Tests run against servers, repos, worktrees, agents and files that the test made itself inside `$MINMACS_HOME`.
2. Never act on a real server, worktree, cache or app in a test. A test that stops, removes or quits names its fixture by port, path or pid, so it cannot reach anything else.
3. Scope every destructive test. A command that would act on everything it finds, such as an auto run, only runs with a scan root, port or path that points into `$MINMACS_HOME`.
4. Stop only what you started. A section adds the pids it starts to `procs`, and cleanup stops those and nothing else.
5. Never run a package manager to find a path. `brew`, `npm`, `pnpm` and `yarn` can install or change things. Read env vars and config files instead.
6. `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `GIT_CONFIG_GLOBAL` point into the temp folder, so the agent running the tests never feeds a fixture and the person's git config stays out.
