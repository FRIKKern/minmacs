# Crush: evidence notes (2026-09-29)

Row: `registry/agents/crush.json`. Validator: ok. Confidence `documented`. Crush is not installed here and nothing was running, so no surface was classified live. Version researched: v0.97.0 (released 2026-09-29T10:48Z), repo `charmbracelet/crush`, commit 792cb84.

## What I checked

- README, `docs/hooks/README.md`, `docs/hooks/FUTURE.md`, `docs/config/`, `.goreleaser.yml`.
- Public source from a shallow clone in the scratchpad (not built, not run): `internal/cmd` (root, server, session), `internal/db`, `internal/config/load.go`, `internal/agent`, `internal/hooks`, `internal/herdr`, `internal/server`, `internal/ui/model/ui.go`, `internal/ui/notification`, `internal/shell`, `internal/event`.
- npm `@charmland/crush@0.97.0` tarball (unpacked, read, not installed), GitHub releases API asset list.
- Local: `which crush`, `ls ~/.config/crush ~/.local/share/crush`, `ps | grep`. All empty. Matching tested with made-up ps lines through the probe's own matcher: `crush`, `crush -s abc`, brew/go/npm paths match as tui; `crush run`, `crush session list`, `crush --version`, `node run-crush.js` match nothing; `crush server` matches daemon.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | Terminal UI only (plus `crush run` one-shot and an optional `crush server` daemon). No desktop app, no bundle id, no IDE extension | README, root.go |
| Process | One static Go binary named `crush` (macOS releases `crush_0.97.0_Darwin_{arm64,x86_64}.tar.gz`). Brew, `go install` (`~/go/bin/crush`), npm (`node_modules/@charmland/crush/bin/crush`, child of `node run-crush.js`) | README, goreleaser, npm lib.js |
| Process to session | argv has an id only for `-s/--session` on resume. Otherwise: cwd of the process, then the project's `.crush/crush.db`. Sessions in one project share the db | root.go, connect.go |
| Store | SQLite (WAL), `<project>/.crush/crush.db`, found by walking up from cwd, or `--data-dir`. Tables `sessions`, `messages`, `files`, `read_files`. UUID session ids. `~/.local/share/crush/projects.json` lists every project. `documented: false`: only `.crush/logs/crush.log` is promised | connect.go, load.go, projects.go, README l.910 |
| Turn in progress | In-memory only (`activeRequests`, `IsSessionBusy`). From outside a plain TUI the best signal is a fresh `crush.db-wal` mtime, because every text and reasoning delta is persisted. Client-server mode adds `GET /v1/workspaces/{id}/agent` -> `is_busy` | agent.go l.938-971, proto.go |
| Waiting on human | Notification titled "Crush is waiting..." (permission, questions, and also turn end). herdr `blocked` state. Server event stream in client-server mode. No file or process trace in the default mode | ui.go, herdr/client.go |
| Hooks | Only `PreToolUse`. `hooks` in `~/.config/crush/crush.json`, project `crush.json` / `.crush.json`, or `hook add` in `crushrc` | hooks docs, hooks.go |
| OpenTelemetry | No. PostHog metrics to `data.charm.land`, opt-out | event.go, root.go |

## Could not determine

- Real `ps` output on macOS for any surface. Executable paths for brew (`/opt/homebrew/Cellar/crush/<v>/bin/crush`) are inferred from the tap config; I could not fetch the formula (404 at the guessed URL).
- Whether `lsof -p <pid>` shows `crush.db` open. modernc.org/sqlite on darwin keeps the file open in the pool, so it should, but I did not observe it. If true it maps a process to its exact db even with `--data-dir`.
- CPU while busy vs idle. The `tree_cpu` floor of 3 is a guess. The TUI has an animated spinner, so an idle floor is plausible, not measured.
- The `-wal` write cadence in practice (15 s window is a guess). Long tool runs with no output are quiet on disk; `tool_children` covers external commands only.
- Whether an assistant message row with `finished_at IS NULL` reliably marks an in-progress turn, including after a crash or cancel. Not traced. A count query would not read content, but I did not run it (no db).
- Where the running `crush server` socket lands on macOS: `$TMPDIR/crush-<uid>.sock` by source, unverified. The server's client-server path is behind an env var and may change quickly.
- Whether in client-server mode the TUI's own CPU stays low while the server works (source says the agent runs server-side; not observed).

## Contradicts common belief, the hint, or the docs

- "Terminal agent, one process" is only the default. `CRUSH_CLIENT_SERVER=1` splits it into a thin client plus a detached `crush server` (reparented to launchd, `Setsid`). In that mode the busy work is not in the client's process tree at all.
- The README says native notifications are the auto choice for local sessions, and the config schema says the same. The code uses OSC 99/777 on darwin (native is skipped there as slow and icon-less). So a macOS notification comes from the terminal emulator, not from a `crush` process.
- The same "Crush is waiting..." title covers permission prompts, questions and turn completion. It does not by itself mean blocked on the human.
- Hooks are Claude Code compatible in shape, but there is no `Notification`, `Stop` or `SessionStart` event. Only `PreToolUse` exists, and it fires before the permission prompt, so it cannot detect a wait or an idle turn. `UserPromptSubmit` is designed in FUTURE.md, not shipped.
- The README says the data dir is `~/.local/share/crush` "JSON state only". That is global state (`crush.json`, `projects.json`). The sessions are not there: they are per project in `.crush/crush.db`.
- The hint "Charm's terminal agent" hides that there is no per-session file. Session-per-process mapping by folder is ambiguous whenever two crush processes share a project.
- The bash tool is an embedded Go shell. There is no shell child process, and builtins leave no children, so `tool_children` misses much of a turn.
- No `caffeinate` or power assertion, unlike Claude Code. Window title is static (`crush ~/path`). The OSC 9;4 progress bar while busy is limited to ghostty, iTerm2, rio and Windows Terminal, and only visible to the terminal.
- The npm launcher means two processes: `node .../run-crush.js` and the `crush` child. Only the child matches, and its parent is node, not a shell.
- With the probe's first-match rule, a `crush --cwd /x/server-app` line matches both tui and daemon (substring test on `server`); tui wins because it is listed first.

## Verification

Independent refutation pass, 2026-09-29. Re-checked against a fresh shallow clone of charmbracelet/crush at v0.97.0 (792cb84), the npm tarball `@charmland/crush@0.97.0` from registry.npmjs.org (unpacked, not installed), the GitHub releases API, and the probe's own `matches()` driven over made-up ps lines. `tools/validate_row.py` passed before and after. No agent was started; Crush is not installed here (`which crush`, `ls ~/.config/crush ~/.local/share/crush ~/go/bin/crush /opt/homebrew/bin/crush /usr/local/bin/crush`: all absent, no process). Confidence stays `documented` (maximum without a live instance); the numeric thresholds are unmeasured.

Legend: confirmed = source or docs say exactly this; corrected = claim was wrong or incomplete and the row now says the corrected thing; unsupported = no evidence, kept only as a labelled guess or removed.

| Claim | Result | Note |
|---|---|---|
| v0.97.0, commit 792cb84, released 2026-09-29 | confirmed | `git describe` v0.97.0; releases API published_at 2026-09-29T10:48:18Z |
| Not installed, nothing running | confirmed | commands above |
| Darwin arm64 and x86_64 archives, binary `crush`, brew/npm/go install routes | confirmed | releases API assets; README lines 30, 33, 166 |
| Homebrew Cellar path | unsupported | tap formula not fetchable (404 at three guessed paths); harmless, `names` matches by basename |
| npm downloads the binary at first run | corrected | package.json has `postinstall: node install.js`; run-crush.js only re-downloads if `bin/` is missing. Child spawn via `spawnSync(binDir/crush, argv.slice(2))` confirmed |
| Subcommand list | corrected | missing `models`, aliases `r` (run), `auth` (login), `signout` (logout), and `-H/--host`. Row's exclude_args therefore let `crush r ...`, `crush models`, `crush auth`, `crush signout` match as tui |
| Default mode is single process; client-server opt-in via CRUSH_CLIENT_SERVER | confirmed | root.go useClientServer, setupWorkspace |
| Server detached with Setsid, "parent becomes launchd" | corrected | Setsid plus `Process.Release` does not reparent; the parent is the spawning client until it exits. Server also self-exits 60 s after its last workspace is released (backend.go). Consequence: the probe's outermost-process rule hides the daemon while that client lives |
| Socket `crush-<uid>.sock` under XDG_RUNTIME_DIR or os.TempDir, /tmp fallback over 104 bytes | confirmed | server.go DefaultHost, socketDir |
| Daemon match `args_contain: ["server"]` | corrected | substring test with no exclude_args: `crush run "restart the server"` matched as daemon. Daemon now carries the same subcommand exclusions |
| Process `path_contains` entries | corrected | substring test: `/opt/homebrew/bin/crushtool`, `/usr/local/bin/crush-monitor`, `~/go/bin/crush-cli` all matched as tui. Removed; `names` already matches the basename of any path |
| tui label: in client-server mode "tree_cpu on the client reads idle" | unsupported | not observed, and the client owns the UI that draws the spinner. Reworded to "not verified" |
| Sessions in SQLite, WAL, `<data dir>/crush.db`, default `.crush` found by walking up; tables; UUID ids | confirmed | connect.go pragmas, load.go 586-594, migrations (plus mcp_* tables added 2026-09-28) |
| `-s` value is a session id | corrected | may be UUID, hash or hash prefix (resolveWorkspaceSessionID). Also `--session=<id>` form is not read by the probe |
| `-c/--cwd` leaves process cwd differing from project | n/a, checked | ResolveCwd calls `os.Chdir`, so lsof cwd is right; only `--data-dir` breaks the cwd mapping |
| db path not promised by docs; only `.crush/logs/crush.log` | confirmed | README lines ~908-909; `crush.db` absent from README and docs/. `documented: false` stands |
| Each streamed delta is persisted | corrected | true but debounced to one write per 33 ms (message.go defaultUpdateDebounce). Enough for a 15 s window while streaming |
| transcript_write `within_seconds: 15` | unsupported | a guess; long tool runs and slow first tokens write nothing. Labelled as such in the row. Also other db writes touch the -wal, so it says "project wrote", not "turn running" |
| Busy state in memory only, `is_busy` over the server API | confirmed | agent.go activeRequests; proto.go IsBusy; endpoints.go `/v1/workspaces/{id}/agent` and `/events` |
| tool_children: externals are children, builtins and Go coreutils run in-process | corrected | on macOS Go coreutils are off by default (`useGoCoreUtils = runtime.GOOS == "windows"`), so ls/cat/grep are real children. More importantly the signal misfires: stdio MCP servers and LSP servers are long-lived children, and bash background jobs outlive a turn; the probe counts any non-caffeinate child as working, so such a session would read as working forever. Signal removed from working_signals |
| tree_cpu floor 3, "guess, unmeasured" | unsupported (kept, labelled) | source does show a 20 fps spinner animation (anim.go fps = 20) while items are pending, so the mechanism is plausible; the 3% number is unmeasured |
| Data-dir lock `crush.lock` only for server workspaces | confirmed | connect.go "off by default so local-mode invocations do not regress"; datadirlock.go |
| projects.json at `~/.local/share/crush/projects.json` | confirmed | projects.go, GlobalConfigData; `Register()` from setupLocalWorkspace (root.go:302) |
| Only PreToolUse; config locations; Claude-shaped; env CRUSH/AGENT/AI_AGENT; exit 2 and 49 | confirmed | docs/hooks/README.md; hooks.go EventPreToolUse; crushrc paths in README lines 284-291. Docs URL returns 200 |
| UserPromptSubmit planned, not shipped | confirmed | FUTURE.md; no such constant |
| PreToolUse fires before the permission check, top-level calls only | confirmed | README step 5 and Scope paragraph |
| Notification title/messages for permission, questions, turn end; darwin auto is OSC | confirmed | ui.go 1082-1099, 5677-5681, 663-705 |
| Notification is a usable waiting signal | corrected | only sent when focus reporting is on and the window is not focused (`shouldSendNotification`), and not when notifications is `disabled`. Row now says so |
| herdr reports idle, working, blocked | confirmed | herdr/client.go; needs HERDR_ENV=1, HERDR_SOCKET_PATH, HERDR_PANE_ID |
| Window title static; OSC 9;4 progress only for ghostty, iterm2, rio, Windows Terminal | confirmed | ui.go 3656, 795-808, 3691 |
| No caffeinate or power assertion | confirmed | grep over *.go: no hits |
| No OpenTelemetry; PostHog to data.charm.land, opt-out | confirmed | grep: only indirect go.mod requires; event.go; shouldEnableMetrics (CRUSH_DISABLE_METRICS, DO_NOT_TRACK, options.disable_metrics) |

Residual doubts: no real `ps` line for any surface, no observed cpu or -wal cadence, whether the client's cpu stays low in client-server mode, and whether a different program named `crush` exists on a user's Mac. The `--session=<id>` form is a probe limitation, not a row error.
