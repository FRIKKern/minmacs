# Changelog

All notable changes to MinMacs. Format follows [Keep a Changelog](https://keepachangelog.com/).

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
