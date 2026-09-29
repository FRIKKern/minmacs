# Rovo Dev CLI: evidence notes (2026-09-29)

Not installed on this Mac. Nothing below was seen on a running instance. Confidence in the row is `documented`, and the working signals are inferred.

## What I checked

- Atlassian support docs (fetched 2026-09-29): use-rovo-dev-cli, install-and-run, rovo-dev-cli-commands, manage-sessions, manage-rovo-dev-cli-settings, use-server-mode, use-tools. ACLI macOS install page on developer.atlassian.com.
- Atlassian blogs: event hooks (2026-01-26), notifications with Peon Ping (2026-04-15).
- Public source: `github.com/atlassian/atlascode` (the VS Code extension, open source). Read `src/rovo-dev/rovoDevProcessManager.ts`, `client/rovoDevApiClient.ts`, `client/rovoDevApiClientInterfaces.ts`, `client/responseParser.ts`, `rovoDevUtils.ts`. Fetched with curl into the scratchpad, not installed.
- `PeonPing/peon-ping` `adapters/rovodev.sh` and `install.sh` (open source, header says copyright Atlassian US, Inc.): the only public source of the `eventHooks` YAML shape and full event list.
- Local: `which -a acli atlassian_cli_rovodev rovodev` (none), `ps` grep for rovo/acli (nothing), `ls ~/.rovodev ~/.config/acli` (absent). `tools/agents_probe.py --row` finds 0 sessions, as expected.
- Local, useful: the Atlassian VS Code extension is already installed at `~/.vscode/extensions/atlassian.atlascode-3.8.18` (and 3.8.3). Its `package.json` pins `rovoDev.version` 0.11.24, and the bundled `extension.js` contains the binary path (`atlascode-rovodev-bin/<ver>/atlassian_cli_rovodev`) and the spawn args (`serve <port> --xid rovodev-ide-vscode --site-url <url>`). The binary was never downloaded (no `atlascode-rovodev-bin` directory anywhere under Application Support).
- Only the README of the third-party reverse-engineering repo `ghuntley/atlassian-rovo-source-code-z80-dump` was read, for the "Go binary with embedded Python agent" claim. I did not use its extracted proprietary source.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | (1) terminal: `acli rovodev run`, one-shot `run <instruction>`, `run --web` (web UI instead of TUI). (2) server: `acli rovodev serve <port>`. (3) VS Code extension (Atlassian for VS Code), which runs its own server. (4) Cloud: Jira, Bitbucket, GitHub Action (`atlassian-labs/rovo-dev-action`). No standalone Mac app. | docs, extension source |
| Executable | CLI is `acli` (Go, installed at `/usr/local/bin/acli` or via Homebrew tap `atlassian/homebrew-acli`); `rovodev` is a subcommand. Standalone plugin binary is `atlassian_cli_rovodev`, which the extension keeps at `<workspaceStorage>/atlassian.atlascode/atlascode-rovodev-bin/<version>/`. | docs, extension source, local bundle |
| Bundle ids | None for the CLI. IDE host: VS Code `com.microsoft.VSCode` (well known, not verified here, VS Code is not installed); Cursor on this Mac is `com.todesktop.230313mzl4w4u92` (mdls). The agent process itself has no bundle. | mdls, inferred |
| Process to session | `--restore <uuid>` (value optional). `/status` shows Session ID. Server mode: port in argv, then `GET /healthcheck` returns `x-session-id`, `GET /v3/status` returns `cliVersion.sessionId`. Sessions are per workspace, `metadata.json` records the workspace, so cwd matching is possible. | docs, extension source |
| Store | `~/.rovodev/sessions/` (`sessions.persistenceDir` can move it): `session_context.json` (whole conversation), `metadata.json` (title, workspace, fork parent). One JSON document per session, not JSONL. | docs |
| Turn in progress | Best exact signal is in-process: server mode SSE `/v3/stream_chat` is open and events flow until a `close` event, and `POST /v3/cancel` cancels it. From the outside there is no verified signal. Row lists tool_children, transcript_write, tree_cpu as inferred fallbacks. | extension source, inferred |
| Waiting on human | Hook `on_tool_permission`; server mode `on_call_tools_start` with `permission_required` (paused only when `pause_on_call_tools_start=true`). Default `toolPermissions.default` is `ask`, so this is a common state. `--yolo` or `/yolo` removes it. | blog, docs, source |
| Hooks | Yes. `eventHooks.events[].name` + `commands[].command` in `~/.rovodev/config.yml`, or `/hooks` interactively. Events: `on_complete`, `on_error`, `on_tool_permission` (Atlassian confirmed); `on_user_prompt`, `on_tool_start`, `on_tool_end`, `on_session_start`, `on_session_end` (third-party adapter only). | blog, peon-ping |
| OpenTelemetry | No documented export. | absence in docs |

## Could not determine

- What `ps` shows for a live CLI: `acli`, `atlassian_cli_rovodev`, a Python child, or a mix. Does `acli` exec or spawn the plugin? Where does ACLI store the plugin binary it downloads (not in any doc I found)? The row lists both names and relies on `args_contain: rovodev` to avoid matching every `acli jira ...` command.
- Whether `session_context.json` is rewritten per step or only at turn end, so `transcript_write` may be late. Whether the per-session directory nesting is exactly `sessions/<uuid>/`.
- Whether the TUI runs a child per bash tool call (so `tool_children` is precise) and whether MCP server children make it noisy: healthcheck shows filesystem-tools, atlassian and bitbucket MCP servers as standing components.
- Whether Rovo Dev holds a power assertion or spawns `caffeinate`. Nothing in docs or source; not checked on a live binary.
- Whether the hook events `on_user_prompt`, `on_tool_start`, `on_tool_end`, `on_session_start`, `on_session_end` really fire in current releases (the blog said more events were coming). Whether `ROVODEV_SESSION_ID` is exported to hook commands: the adapter uses it with a `$$` fallback, unverified.
- JetBrains or other IDE plugin behaviour. Only VS Code was checked.
- Version drift: docs mention 0.11.26 in the server example, the installed extension pins 0.11.24, the CLI also has a `--respect-configured-permissions` flag the older bundle lacks.

## Contradicts common belief or the hint

- There is no `rovodev` executable in the normal install. It is `acli rovodev ...`. The server-mode doc writes `rovodev serve 8123` as shorthand; the real spawn in the extension source is `atlassian_cli_rovodev serve ...`, and third-party wrappers use `acli rovodev serve --disable-session-token`.
- "Work from public source" mostly does not apply: the CLI is closed source. Public code is only the VS Code extension, the GitHub Action, and adapters like peon-ping. A reverse-engineered dump of the proprietary Python exists on GitHub; I did not use it.
- Event hooks are real but absent from the official settings page, and a community answer says `/hooks` is undocumented. The blog is the only official statement.
- `healthcheck.status = "pending user review"` sounds like a permission wait but is about MCP server terms (confirmed in the installed bundle: it lists servers whose status equals that string, and the client's `acceptMcpTerms` calls `/accept-mcp-terms`). It does not mean a turn is blocked on a tool prompt.
- Session file is a single JSON, not JSONL, so mtime moves only when the whole file is saved, unlike Claude Code's append-only transcript.
- The VS Code extension does not shell out to the user's `acli`; it downloads and runs its own copy of the agent, pinned per extension version, so a Mac can run Rovo Dev with no `acli` installed.

## Verification

Adversarial re-check on 2026-09-29 by a second reader. Every URL in `sources` was refetched, the extension bundles were re-read, and the process patterns were exercised through `tools/agents_probe.py` `matches()` on synthetic `ps` lines (no Rovo Dev process exists here). `tools/validate_row.py` prints `ok` before and after. Confidence stays `documented`: nothing was seen on a live instance, and the working signals remain inferred.

### Confirmed

- Rovo Dev CLI is an ACLI extension, run with `acli rovodev run`, auth with `acli rovodev auth login` (install page, dateModified 2026-04-10).
- ACLI on macOS is one binary named `acli`: Homebrew tap `atlassian/homebrew-acli` or curl to `/usr/local/bin/acli` (developer.atlassian.com install-macos).
- Commands page lists run, run [instruction], run --web, run --restore [session ID] (value optional), run --yolo, run --worktree, run --config-file, serve [port], config, mcp, /status, /sessions, /hooks.
- Sessions page: `~/.rovodev/sessions/` holds `session_context.json` and `metadata.json`; sessions are per workspace; `--restore <UUID>`; UUID from `/status`.
- Settings page: `~/.rovodev/config.yml`, `sessions.persistenceDir`, `logging.path` default `~/.rovodev/logs/rovodev.log`, `mcp.mcpConfigPath` default `~/.rovodev/mcp_config.json`, `toolPermissions.default: ask`.
- Extension source (main): binary `atlassian_cli_rovodev` under `<storageUri>/atlascode-rovodev-bin/<version>/`, zip from `https://acli.atlassian.com/plugins/rovodev/<platform>/<arch>/<version>/rovodev.zip`, ports 40000-41000, spawn args `serve <port> --xid rovodev-ide-vscode --site-url https://<host> --respect-configured-permissions`, cwd = workspace, env `ROVODEV_SERVE_SESSION_TOKEN`. The current installed bundle (atlascode 4.0.32 in `~/.cursor/extensions`) matches this.
- `pending user review` in `/healthcheck` refers to MCP servers awaiting terms acceptance (`POST /accept-mcp-terms`), present in both installed bundles.
- Server-mode docs: `/healthcheck`, `/v3/stream_chat`, `/v3/cancel`, `/v3/resume_tool_calls`, `pause_on_call_tools_start=true`, `/v3/sessions/*`.
- Event hooks blog (2026-01-26): hooks exist, `/hooks`, permission-wait motivation, `on_tool_permission` quick start, event hooks log under `eventHooks` in `/config`, more events coming.
- peon-ping adapter: full event list, stdin JSON with `transcript_path` and `attributes.tool_input`, transcript deleted once the hook exits, `ROVODEV_SESSION_ID` with `$$` fallback, copyright header 'Atlassian US, Inc.'. Atlassian's 2026-04-15 blog announces the Peon Ping integration.
- ghuntley README: Mach-O arm64 Go binary with an embedded ZIP containing `atlassian_cli_rovodev` package references (repo created 2025-06-14).
- Rovo Dev not installed here: `which -a acli atlassian_cli_rovodev rovodev` found nothing, `ps` shows nothing, `~/.rovodev` and `~/.config/acli` absent.
- Community answer that `/hooks` had no official documentation exists.
- No telemetry, OTEL or eventHooks text on any of the fetched official docs pages.

### Corrected

- **IDE process pattern never matched on macOS.** The binary lives under `~/Library/Application Support/<host>/User/workspaceStorage/...`. The probe splits `ps` args on single spaces, so argv[0] is cut at `/Users/<u>/Library/Application` and neither `path_contains: /atlascode-rovodev-bin/` nor the names matched. Original row: 0 matches on a synthetic IDE line. Fixed by adding `/Library/Application` to `path_contains` and tightening `args_contain` to `atlascode-rovodev-bin` and `serve`. A reader with the full path also matches on `/atlascode-rovodev-bin/`. Synthetic lines under other `Application Support` folders with `serve` do not match.
- **`acli rovodev run <instruction>` was read as a server.** `args_contain` is a substring test, so `server`, `observe` or `preserve` in an instruction satisfied `serve`, and the daemon surface came before tui. Fixed by ordering surfaces ide, tui, daemon, cloud (tui excludes only an exact `serve` argument). Residual: an instruction containing the exact word `serve` still reads as a server.
- **Installed bundle claim was partly wrong.** The row said the installed bundle matched the source and pinned 0.11.24. That is only the stale build in `~/.vscode/extensions` (3.8.18), which opens a hidden VS Code terminal, has no `--respect-configured-permissions` and no session token. The current build is atlascode 4.0.32 in `~/.cursor/extensions`, pinned to Rovo Dev `202607.24.1`, spawning like the public source. Source entry rewritten. Cursor bundle id `com.todesktop.230313mzl4w4u92` (mdls) added to `bundle_ids`.
- **`session_store.documented` was true, now false.** The docs name the directory and the two file names, not the per-session subdirectory, so the glob is inferred.
- **`telemetry.otel: false` removed.** Absence in docs is not proof, and the third-party README lists LogFire (OpenTelemetry-based) among the embedded agent's dependencies. The row now says unknown.
- **Server-mode source entry split.** `/v3/status`, the `x-session-id` header, the `entitlement check failed` status and the event kinds are in the extension source, not the docs page. They were filed under official-docs. The `/healthcheck` status list also lacked `entitlement check failed`.
- **Hook event names.** The blog names only `on_tool_permission`; `on_complete` and `on_error` are third-party names for behaviours the blog describes. Source entry and notes now say so. `/hooks` is now listed on the official commands page, so the 'undocumented command' remark applies only to the config schema.
- **'Textual-based TUI' softened.** Only the docs' `theme: textual-dark` example supports it; the ghuntley README lists Rich and Typer, not Textual.
- **Missing sources added** for the gnhf and opencode-rovodev-auth wrappers (`acli rovodev serve <port> --disable-session-token`; gnhf uses an ephemeral port, not 40000-41000), the bundle ids, and the process-pattern test. `acli` is also the name of Acquia CLI (docs.acquia.com); `args_contain: rovodev` keeps it out and this is noted in the row.

### Unsupported (left as inferred, said so in the row)

- What `ps` shows for a live CLI turn: `acli`, `atlassian_cli_rovodev`, or both, and whether MCP helper processes are children that get deduplicated.
- All three working signals: `tool_children`, `transcript_write` (write cadence of `session_context.json` unknown) and `tree_cpu` (floor of 5 is a guess).
- That the hook transcript shape (`message_history`, `parts`, `part_kind`) equals `session_context.json`; peon-ping reads the hook's temporary transcript copy.
- `com.microsoft.VSCode` as the VS Code bundle id (well known, no VS Code app here).
- 'One server per workspace' is inferred from `cwd = workspacePath` and the per-instance port pick.
- The hook events other than `on_tool_permission` firing in current releases, and `ROVODEV_SESSION_ID` being exported to hook commands.
- Any Rovo Dev behaviour in JetBrains or other IDEs.
