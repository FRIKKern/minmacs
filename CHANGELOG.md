# Changelog

All notable changes to MinMacs. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [2.0.0] - unreleased

MinMacs 2.0 joins five apps in one: MinMacs 1.2, LocoHost 0.1, WorkForest 0.1, Noo-Noo 0.7 and Insomnia 1.3. Each became an expert with its own icon and menu in the menu bar. All five read one shared core, which samples the Mac once and keeps one record of what it did. The app is Objective-C built with clang, with macOS 14 as the floor.

### Added
- **One core for five experts.** Senses takes one sample of processes, sockets and power every 5 seconds. Know holds agents, sessions, git facts and worktrees. The graph builds each expert's findings from those facts. An expert never samples, scans or asks the model on its own.
- **Five icons, or one.** Each expert has its own icon by default. One Icon in Settings puts them in one menu (decision 3).
- **One undo log.** Every action is checked fresh right before it runs, writes an undo record, and goes to the Trash, a recovery folder or the owning tool's own command. History, undo and disk trends live in one SQLite log.
- **Modes per expert.** Idle, Proactive and Eager. What each mode may do is listed in each expert's README under Sources/Experts.
- **One review broker.** Each expert's rules decide first, then a fingerprint cache, then the model. On the recorded fixture day the broker sent 56,846 uncached tokens, 3.1 % of the 1,842,725 that the 1.x apps sent for the same day (docs/2.0/MEASUREMENTS.md).
- **Investigate.** A run on request for one finding or workstream, with the cost and model shown first. The model gets only MinMacs's own scoped Read, Grep and Glob tools.
- **Wrap Up.** One undoable step for a finished workstream: a merged worktree whose agent sessions ended. It stops its servers and helpers, moves its caches and config files to the Trash, saves its ignored files and removes the worktree.
- **Cross-links.** A server's card links to the worktree it runs in, a worktree's card lists the servers inside it, and clutter links to its owner.
- **Cards on hover.** A row's card is built when the pointer reaches it.
- **Settings.** Each expert's icon and mode, the review model, One Icon, Open at Login, and a pane for Insomnia's guards. An expert with prefs of its own gets a pane.
- **Open at Login** is turned on at first launch, said in one line, with a switch in Settings (decision 18).
- **One CLI.** `minmacs <verb>` runs through the running app when there is one, and on a cold core when not. A verb that changes things needs the app unless it is given `--dry-run`. Every verb takes `--json`.
- **Release tooling.** `release.sh` builds the zip, its checksum, the release notes and the Homebrew cask, and publishes nothing. `install.sh` installs a local build or a release zip, and both scripts take `--prefix`. packaging/README.md has the steps after a release build.

### Changed from MinMacs 1.2
- The MinMacs expert holds 1.2's apps, agents, Quit, Force Quit, browser tab trimming and Restore. Apps come from the shared sample, and helpers roll up to their app.
- Proactive never quits an app. Eager quits a close-list app only under memory pressure or heat. No mode trims tabs on its own.
- 1.x verbs such as `plan` and `agents` map to their 2.0 verbs.
- The 1.2.1 rule fixes for #43, #44 and #45 hold in 2.0: an exact bundle id wins over a pattern, every list matches wildcards the same way, and new defaults merge on every load.
- macOS 14 is the floor. 1.2 ran on macOS 13.

### Changed from LocoHost
- The LocoHost expert lists every localhost server, where it runs and who uses it, and stops what nobody needs. SIGTERM goes first, and SIGKILL only on a second request.
- A server keep sticks to its project folder and package.json script, and falls back to folder and port (decision 8).
- The binary run as `locohost` takes LocoHost 1.x commands: `list`, `who`, `explain`, `stopped`, `restart` and the rest. `install.sh` and the cask link that name.
- `locohost://review` and `locohost://close-idle` still work.
- The HTTP title probe is gone, so page titles are not shown or sent.

### Changed from WorkForest
- Worktrees and git facts come from Core's repo index, which FSEvents keeps current, instead of WorkForest's own scans.
- Removal runs `git worktree remove` with no `--force`, saves ignored files such as `.env` first, and takes a git bundle when HEAD is on no remote. Undo recreates the worktree at its commit.
- A worktree whose HEAD is on no remote but is squash-merged is removed in Eager only, after a bundle is saved (decision 7). Cursor's and Conductor's worktrees are shown, never removed (decision 6).
- WorkForest 0.1's `removed.json` records are imported, so `restore <0.1 id>` still works. 0.1 syntax works under the `workforest` name.
- `fetch` is gone: MinMacs never fetches. The merged pull request check through `gh` is gone too.

### Changed from Noo-Noo
- Clutter is a catalog of rows as data in registry/clutter. Only a path a listed row names may be acted on, and system folders, the home folder and symlinks are always refused.
- Caches, build output and leftovers go to the Trash. A tool's own cache runs the tool's command after an APFS recovery copy, so undo can copy it back (decision 1).
- Finished projects come first: build output of merged or ended worktrees. Disk trends come from one point a day per row.
- No daemon or LaunchAgent. Scans run inside MinMacs, a row at most as often as the row says.
- Offloading comes after 2.0 (decision 14). Docker, Colima, OrbStack and Homebrew rows only report.

### Changed from Insomnia
- Awake While Agents Work is on from the first launch, and Keep Mac Awake starts off (decision 4). Each working agent holds the Mac awake by its pid, and the hold ends when that process exits.
- Lid mode keeps Insomnia's sudoers rule and its guards for battery, unplugged time, offline time and heat. MinMacs clears only a lid override it set.
- `minmacs insomnia hold <pid>` holds the Mac awake until that process exits.
- `insomnia://` is not registered yet, so `minmacs://insomnia/<command>` stands in.

### Measured
- Idle cost with all five experts, headless, over 30 minutes on a busy Mac: 0.291 % CPU, a footprint of 10.70 MB with a peak of 12.47 MB, and 0.223 wakeups a second (docs/2.0/BENCH.md). The app with its status items and menus is not measured in that number.

### Not in 2.0.0 yet
- Signing with a Developer ID and notarization, issue #40. The build is ad-hoc signed, so macOS blocks the first open until Open Anyway is chosen in System Settings, Privacy and Security.
- No hooks ship (decision 11).

## [1.2.1] - 2026-10-27

### Fixed
- **Keep or Close for one app keeps shared patterns.** Marking `com.adobe.Photoshop` Keep removed `com.adobe.*` from the close list, so every other Adobe app became unsorted. An exact bundle id now wins over any pattern, and a choice for one app changes only that app's entries. Unsorted for an app a pattern covers goes on a new `unsorted` list. Rules file version 3. (#43)
- **ignoreServing matches like keep and close.** A trailing `*` and `*text*` now work there too. `!<bundle id>` is an exception to a pattern. (#44)
- **New defaults arrive on every load.** They were merged only into files below version 2, and 1.2.0 wrote version 2. Your entries are never moved or removed. A default set to Unsorted, or with Close Even When Serving turned off, stays that way. (#45)
- **CI runs the tests.** `test.sh` runs on the macOS runner after `build.sh --no-install`, and a failed check fails the job. It tests `build/MinMacs.app`, uses fixture apps instead of TextEdit, and points `MINMACS_RULES_FILE` and `MINMACS_DEFAULTS_DOMAIN` at test copies, so it never touches your rules file or settings. Checks the machine cannot run are skipped with a reason. The comparison with real agent sessions needs `--live`. (#46)
- **README matches the code.** "Will quit", the Agents, browser and spared sections, the full CLI list. The unmeasured idle cost claim is gone. (#47)
- **Registry rows no longer declare `socket_activity`.** Neither detector evaluates it. It is gone from ten working signals and from the schema. `test.sh` fails when a row declares a signal either detector ignores. (#48)

## [1.2.0] - 2026-10-01

### Added
- **Blocked agents from cmux.** With *Agents ▸ Read cmux for Waiting State* on (default off; `minmacs agents --cmux` for one run), an agent waiting on a permission, a question or a plan approval shows as blocked with its reason. It reads `pid, sessionId, surfaceId, workspaceId, updatedAt` from `~/.cmuxterm/claude-hook-sessions.json` and `kind, createdAt, workstreamId` from the last 2 MB of `~/.cmuxterm/workstream.jsonl`, and nothing else: payloads are never read. New `Sources/Hosts.m`.
- Debug hook `minmacs.debug.cmuxDir` reads the two files from another directory. `minmacs agents` prints `blocked` and counts it.
- 16 tests for the cmux reader, all against fixture files.
- **Agent detector, shared names.** Registry rows can list `presence` paths; a match on a bare process name counts only when one exists, so `fx`, `copilot`, `warp`, `goose` and the like no longer report unrelated programs.
- **Agent detector, hosts.** An agent started by an orchestrator (Emdash, Conductor, T3 Code, Orca, Zed, OpenClaw, Vibe Kanban) is reported once, as the host, which reads working while the agent does. Rows mark this with `hosts_agents`.
- **Agent detector, unknown state.** Rows with `no_outside_signal` read `unknown` instead of idle. The CLI table and the menu show a hollow marker, and the totals line counts it on its own.
- `caffeinate -w <pid>` signals (`args_contain`) must name the matched process. Per-session transcript paths for `devin` and `deepagents`.

## [1.1.0] - 2026-09-29

### Added
- **Force quit.** Apps get a normal Quit and eight seconds; *When an App Won't Quit* then decides: Ask Me (default), Force Quit It, or Leave It Running. Per-app *Force Quit Now*. CLI `--force`. Helper processes that outlive their parent are killed too.
- **Browser trimming.** Browsers on the close list keep running; only tabs on the noise list are closed, never tabs on the work list. The menu lists the exact tabs, and picking one keeps its site. Restore reopens closed tabs. `minmacs trim`, `--only-host`, `--quit-browsers`, `minmacs classify`.
- **Serving detection.** A close-list app started with remote debugging, or listening on a loopback port, is spared and the reason is shown. `ignoreServing` list and *Close Even When Serving* for apps that listen for their own reasons.
- Rules file version 2: `tabs.noise`, `tabs.work`, `ignoreServing`. New defaults merge in additively on upgrade.
- Test fixture `tools/stubborn.m`; the suite grew from 8 to 21 checks, plus an opt-in live browser test.

### Changed
- Keep list: superwhisper, the ChatGPT app, noo-noo by its real bundle id. Close list: Messenger, Parsec.
- Tabs and apps are addressed by process id, so a second browser instance owned by an automation tool is never touched.

## [1.0.0] - 2026-09-29

### Added
- Menu bar plan: apps grouped into Will close, Unsorted, Kept, plus system background load, each with CPU and memory. Helpers attributed to their owning app the way Activity Monitor does.
- MinMacs Now: graceful quit of the close list with a confirmation listing exactly what goes. Restore relaunches them in the background.
- Per-app submenu to move between Close, Keep and Unsorted, or quit one app. Rules stored in `~/Library/Application Support/MinMacs/rules.json` with sensible defaults.
- CLI: `minmacs plan [--json]`, `run [--yes] [--only <bundle-id>]`, `restore`, `rules`.
- URL scheme: `minmacs://run|run-now|restore|login-on|login-off|quit`.
- Also Turn On Insomnia option. Launch at Login. Universal binary. `install.sh`, `uninstall.sh`.
