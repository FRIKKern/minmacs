# goose: evidence notes (2026-09-29)

Row: `registry/agents/goose.json`. Validator: ok. Confidence `documented`. goose is not installed here and nothing was running, so no surface was classified live. Version researched: v1.52.0 (released 2026-09-23), repo `aaif-goose/goose`, branch `main`.

## What I checked

- README, docs (`documentation/docs/`: logs, hooks, environment-variables, config-files, installation, known-issues, terminal-integration) from a main-branch tarball unpacked to the scratchpad. Not built, not run.
- Public source: `crates/goose-cli` (cli.rs, session/mod.rs, term.rs), `crates/goose` (session_manager.rs, config/paths.rs, hooks/mod.rs, agents/agent.rs, agents/tool_execution.rs, otel/otlp.rs, acp/transport), `ui/desktop` (gooseServe.ts, main.ts, settings), `ui/goose-acp` and `ui/goose-binary` (npm launcher).
- The real desktop release zip `Goose-darwin-arm64.zip` (1.52.0), read with `unzip -p`, `unzip -l`, `plutil -p`, `file`, `strings -a` only. Not mounted, not installed, not launched, and the extracted binary was never executed.
- GitHub API for the latest release and asset list.
- Local: `which goose`, `ls /Applications`, `ls ~/.config/goose ~/.local/share/goose ~/.local/state/goose`, `ps -axo pid=,args=`, `mdfind` on bundle id. All empty.
- Matching tested with 11 made-up `ps` lines through the probe's own `matches()` and `session_id()`: desktop server matches gui; main Electron process matches nothing; `goose session`, `goose run` match tui; `goose session list` matches nothing; `goose serve` matches daemon; `goose acp` matches ide; `--session-id X` is extracted.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | CLI (`goose session`, `goose run`, `goose term`), desktop app (Electron), standalone `goose serve` (ACP over HTTP and WebSocket, default port 3284), `goose acp` (ACP over stdio, for other clients), plus scheduler, gateway, roam (not in the row) | cli.rs, README |
| Desktop process | `/Applications/Goose.app/Contents/MacOS/Goose`, bundle id `com.electron.goose`, helper `com.electron.goose.helper`, URL scheme `goose://`. It starts one `Contents/Resources/bin/goose serve --tls --platform desktop --enable-scheduler --host 127.0.0.1 --port N` per chat window, cwd = the window's working dir | Info.plist, gooseServe.ts, main.ts:1198 |
| CLI process | One native Rust binary `goose`. Installer puts it in `~/.local/bin`; brew formula `block-goose-cli`; npm `@aaif/goose-acp` runs a Node launcher that spawns `@aaif/goose-binary-darwin-arm64/bin/goose` | download_cli.sh, installation.md, goose.mjs |
| Process to session | CLI: `--session-id` or `--id` with `--resume`, otherwise nothing in argv. Desktop: none per session; one server hosts many, cwd only gives the window's initial dir. Session rows carry `working_dir` | cli.rs, session_manager.rs |
| Store | SQLite WAL `~/.local/share/goose/sessions/sessions.db` (+`-wal`, `-shm`), shared by CLI and desktop. Tables `sessions`, `messages`, `usage_ledger`. Ids `YYYYMMDD_N`. Pre-1.10 sessions were `.jsonl` and are left on disk. Documented | logs.md, session_manager.rs |
| Turn in progress | No API for it and no OS signal. Best available from outside: a child of the goose process (shell tool spawns `$SHELL -c`). With config: `UserPromptSubmit` to `Stop` hook pair, or OTLP spans | agent.rs, shell.rs, hooks.md |
| Waiting on human | Nothing external. Approve/SmartApprove mode blocks on a channel (terminal prompt or ACP `session/request_permission`). No Notification-style hook; `PreToolUse` fires after approval | tool_execution.rs:171-206 |
| Hooks | Plugin `hooks/hooks.json` under `~/.agents/plugins/<name>/` or `<project>/.agents/plugins/<name>/`, shell command actions, 12 events | hooks.md, hooks/mod.rs |
| OpenTelemetry | Yes, documented, default feature. `OTEL_EXPORTER_OTLP_ENDPOINT` or `otel_exporter_otlp_endpoint` in config.yaml. Traces, metrics, logs, http/protobuf | environment-variables.md, otlp.rs |

## Could not determine

- Real `ps` output for any surface. Path shapes for brew (`/opt/homebrew/Cellar/block-goose-cli/...`) come from the formula name in the docs, not from an install.
- Whether the shell tool child is a direct child of `goose` on macOS in practice, and its exact argv. Source says `$SHELL -c <command>`, wrapped in a login-shell env probe on first use (shell.rs:80-90, 219).
- CPU while idle or streaming, so the `tree_cpu` floor of 3 percent is a guess.
- Whether a tool confirmation request is persisted to `messages` before the user answers. The elicitation `ActionRequired` message is persisted (agent.rs:2945); the tool confirmation path I only saw yielded as an event.
- WAL write cadence during a long stream. Messages persist per completed message, so a long stream is probably quiet on disk.
- Whether etcetera resolves to `~/.local/share/goose` on macOS. The docs say so, but a source comment in paths.rs mentions `~/Library/Application Support/Block/goose/` as a backwards-compatible location. I did not read etcetera itself, so if a Mac has data there, check both.
- Real behavior of `goose acp` under an editor.
- The state-machine agent loop (`GOOSE_STATE_MACHINE=1`) is being migrated in; hooks and persistence may differ between the two paths. Not traced.
- Whether a stdio MCP extension makes `tool_children` fire while idle. Inferred from how extensions are launched, not observed.

## Contradicts common belief, the hint, or the docs

- The hint says Block's agent at github.com/block/goose. It now 301-redirects to `aaif-goose/goose`; goose is under the Linux Foundation's Agentic AI Foundation. Code still uses `Block` in legacy paths (Windows `%APPDATA%\Block\goose`), the brew names are `block-goose*`, and OTel `service.namespace` is `goose`.
- The desktop app's bundle id is the Electron default `com.electron.goose`, not a vendor id. A `com.block.goose` lookup finds nothing.
- The desktop app has a "Prevent Sleep" setting ("Keep your computer awake while goose is running a task"), default off. In both the main-branch source and the shipped 1.52.0 `app.asar` there is no `powerSaveBlocker.start`, only `.stop`. So it cannot be a power-assertion signal even if enabled. The CLI binary has no `IOPMAssertion` or `caffeinate` strings either. So `pmset -g assertions` should show nothing for goose (inferred, not observed).
- The main Electron process has Chromium helper children, so tool-children logic on it would always say working. The row matches the bundled `goose serve` instead (same trap as OpenCode).
- Sessions are not JSONL. Older guides and third-party posts show `~/.local/share/goose/sessions/*.jsonl`; that ended at v1.10.0. The database is shared, so it cannot serve as a per-session transcript, and the row has no `per_session` template. The reference probe therefore never evaluates the `transcript_write` signal for goose.
- Hooks follow the Open Plugins spec and are not in `config.yaml` or a `hooks.json` at the config root. They live inside plugins under `.agents/plugins/`. There is no Notification event, so unlike Claude Code the waiting state is invisible to hooks. `PreToolUse` does not fire while a permission prompt is open.
- The deprecated Node ACP TUI (`@aaif/goose`, `ui/text`) is gone from source; not in the row. The npm `goose` command is now a launcher for the Rust binary, so a `node`-named parent exists and only the native child should be matched.
- Default `GOOSE_MODE` is `auto`, so a default install never blocks on tool approval; waiting on the human is rare unless the user set `approve` or `smart_approve`, or an MCP server elicits input.
- `exclude_args` matches exact argv items, so `goose run -t list` would be wrongly excluded.
- 258 MB per platform binary contains everything (agent, server, MCP builtins). A builtin-extension registry of in-process duplex-stream servers exists (builtin_extension.rs) and the shell tool is a platform extension in-process, so I expect no fixed set of idle children. I did not trace whether any builtin is launched as a `goose mcp <name>` child instead.

## Verification

Independent refutation pass, 2026-09-29. Validator: `tools/validate_row.py registry/agents/goose.json` printed `ok` before and after. Method: re-fetched every cited doc and source file (tag v1.52.0 tarball plus raw main files), re-downloaded `Goose-darwin-arm64.zip` to the scratchpad and read it with `unzip -l/-p`, `plutil`, `file`, `strings -a` only (nothing mounted, installed or run), re-ran the local commands, and fed 30 made-up `ps` lines through the probe's own `matches()` and `session_id()`. Confidence stays `documented`: goose is not installed here, so it can never be `verified-locally` from this machine. Line numbers cited earlier are from main; at the v1.52.0 tag they differ by a few lines.

### Corrected

- **Process pattern false positive (the one real defect).** `names: ["goose"]` also matches pressly/goose, a Go database-migration CLI installed by `brew install goose` or `go install`. Before the fix the probe classified `goose up`, `goose sqlite3 ./foo.db up`, `goose postgres URL status`, `goose -dir migrations create x sql`, `~/go/bin/goose ... up` and `/opt/homebrew/Cellar/goose/3.26.0/bin/goose up` as an idle goose TUI. Evidence: pressly README and `cmd/goose/main.go` usage text (drivers, commands, flags); the Homebrew formula `block-goose-cli.rb` declares `conflicts_with "goose", because: both install goose binaries`. Repair: tui `exclude_args` now also lists pressly's 12 commands, 12 drivers and `-dir`/`--dir`; re-test shows all six lines above match nothing and every real goose line still matches its surface. Limit: still an exact-argv test, so a real session with an argument equal to one of those words (`goose run -t status`) is missed.
- **Plugin enable/disable text in `hooks.config`.** The row said `enabledPlugins`/`disabledPlugins` settings files or a `plugins` map in config.yaml, with no source. Docs only document `disabledPlugins` in `~/.config/goose/settings.json` and `<project>/.config/goose/settings.json`. Source (`crates/goose/src/plugins/discovery.rs`) confirms `enabledPlugins`, `settings.local.json`, and a `plugins` map in config.yaml keyed by plugin path with `enabled`. Row text now says which parts are documented and which are source-only, and a source entry was added.
- **`acp_request` meaning.** The secret key is required by default, but `goose serve --dangerously-unauthenticated` exists (cli.rs). Row text now says so.
- **Prevent Sleep string** in the power-assertion source: the v1.52.0 i18n text ends `(screen can still lock)`. Wording fixed in the source entry; the conclusion is unchanged.
- **Open question resolved.** The `Could not determine` item on etcetera is answered: etcetera's `choose_app_strategy` uses Xdg on macOS (Apple strategy is only `choose_native_strategy`, docs comment and `create_strategies!(Apple, Xdg)` in `src/app_strategy.rs`). So `~/.local/share/goose` is right for a default install; `XDG_DATA_HOME` or `GOOSE_PATH_ROOT` would move it.

### Confirmed

- Repo move: `curl -sI https://github.com/block/goose` printed `HTTP/2 301`, `location: https://github.com/aaif-goose/goose`. `releases/latest` redirects to `tag/v1.52.0`, release page `datetime="2026-09-23T14:59:14Z"`, assets include `Goose-darwin-arm64.zip` and `goose-aarch64-apple-darwin.tar.gz`. README line 29 names the Agentic AI Foundation at the Linux Foundation. (The unauthenticated GitHub API returned 403, rate limited, so the release was read from the HTML page instead.)
- Desktop bundle: Info.plist gave CFBundleExecutable `Goose`, CFBundleIdentifier `com.electron.goose`, version `1.52.0`, URL scheme `goose`; `Contents/Resources/bin/goose` is 258932912 bytes, `file` says Mach-O 64-bit executable arm64. The same directory holds only shell launchers (`node`, `npx`, `uvx`, `jbang`), so the gui path pattern matches nothing but the server binary. Helper `com.electron.goose.helper` not re-checked beyond the plist.
- Desktop server argv and cwd: `gooseServe.ts` args array is `serve`, `--tls`, `--platform desktop`, `--enable-scheduler`, `--host 127.0.0.1`, `--port N`; spawn options `cwd: workingDir`; `GOOSE_SERVER__SECRET_KEY` set in env; `main.ts` calls `startGooseServe({dir: workingDir, tls: true, ...})` in `createChat`; packaged binary resolved to `<resources>/bin/goose`.
- CLI: `[[bin]] name = "goose"`; top-level commands match the exclude list (configure, info, doctor, mcp, acp, roam, serve, recipe, skills, plugin, schedule/sched, gateway/gw, update, term, local-models/lm, completion, review); session subcommands list/remove/export/import/diagnostics/rename; `session` has visible alias `s`; `--session-id` alias `id`, and cli.rs errors `--session-id can only be used with --resume`. Bare `goose` runs the default session.
- Installs: `DEFAULT_BIN_DIR="$HOME/.local/bin"`; installation.md has `brew install block-goose-cli` and `brew install --cask block-goose`; formulae.brew.sh shows formula `block-goose-cli` 1.52.0 and cask `block-goose` with `Goose.app`; npm `@aaif/goose-acp` 1.52.0 has bin `goose` -> `bin/goose.mjs` and optional deps `@aaif/goose-binary-darwin-arm64` etc.; the launcher `spawn(binaryPath, process.argv.slice(2))`, so the child argv[0] is the native path.
- Session store: `DB_NAME="sessions.db"`, `SESSIONS_FOLDER="sessions"`, `journal_mode Wal`, tables `sessions` and `messages` with the columns named, id built as `%Y%m%d` + `_` + counter; logs.md gives the macOS path and the pre-1.10 `.jsonl` note.
- Hooks: 12 events in `HookEvent` and in the docs table; `sh -c`, JSON on stdin, default timeout 30 s, only `command` type; locations user/project/installed. `PreToolUse` is emitted in `dispatch_tool_call`, which `tool_execution.rs` calls only after `confirmation_rx.await` returns AllowOnce/AlwaysAllow. `SessionStart`, `UserPromptSubmit`, `Stop` emitted in agent.rs.
- Waiting: elicitation `ActionRequired` is persisted (`session_manager.add_message` in the `ToolStreamItem::ActionRequired` arm); the tool-confirmation `ActionRequired` is only yielded as an event in `handle_approval_tool_requests`.
- Builtin and platform extensions connect through `builtin::connect` (in-process); only `ExtensionConfig::Stdio` spawns a child, so `tool_children` has no idle children in a default install.
- OpenTelemetry: env-var table and config keys in the docs, `otel` in the goose-cli default features, resource attributes service.name/service.namespace/host.name/user.name in `otlp.rs`. Binary `strings -a` counts re-run: OTEL_EXPORTER_OTLP_ENDPOINT 3, UserPromptSubmit 2, PostToolUseFailure 2, hooks.json 2, sessions.db 2, GOOSE_SERVER__SECRET_KEY 2, enabledPlugins 1, disabledPlugins 1.
- No power assertion: `IOPMAssertion` 0 and `caffeinate` 0 in the CLI binary; `app.asar` has `powerSaveBlocker.stop(` 3 times, no `.start(`, no `prevent-app-suspension`, no `caffeinate`; source has no `.start` either; `enableWakelock` defaults false.
- Local observation: `which goose` printed `goose not found`; `ls /Applications | grep -i goose`, `ls ~/.config/goose ~/.local/share/goose ~/.local/state/goose` all empty or `No such file or directory`; `ps` shows no goose process; `mdfind` finds nothing for `com.electron.goose` or `com.block.goose`; no goose binary in `~/go/bin`.
- Doc URLs (homepage, hooks, logs, environment-variables) all return 200. `session/request_permission` is a real ACP method (agentclientprotocol.com tool-calls page) and the desktop registers `requestPermission` in `gooseAcpClient.ts`.

### Unsupported (kept, and labeled as such in the row)

- `tool_children`: shell tool spawns `$SHELL -c <command>` is read from `shell.rs` (`["-c", command_line]`), never observed. Blind during model streaming.
- `transcript_write` (30 s): coarse, unmeasured; the probe never evaluates it because the row has no `per_session`.
- `tree_cpu` floor 3 percent: a guess, uncalibrated.
- Homebrew Cellar path `/Cellar/block-goose-cli/`: inferred from the formula name; a PATH launch shows bare `goose` in argv[0] and is caught by `names`, not by the path.
- `goose acp` surface: from the CLI definition only, no editor observed.
- Not detected, by design of the exclude list: `goose term run <prompt>` (the `@goose` alias) runs an agent turn in a short-lived process. Path pattern `/.local/bin/goose` is a substring on argv[0] and also matches `/.local/bin/goose-<anything>`. `args_contain` `serve`/`acp` are substring tests; a session named `preserve` still lands on tui first (surface order), and one named exactly `serve` would be classed as daemon.
- Whether the shipped release binary exposes the same feature set as the default cargo features is supported only by the `strings` hits above, not by a build config.
