# Conductor: evidence notes (2026-09-29)

Row: `registry/agents/conductor.json`. Validator: ok. Probe on this Mac: nothing running, nothing installed (`ls /Applications`, `ls ~/Library/Application Support`, `ps`, `defaults read` all empty for Conductor). Confidence is `inferred`: the app is closed source, so every process and database fact comes from third-party readers of a live install, not from the vendor and not from this Mac.

## What I checked

- Vendor: `conductor.build` home page, `llms.txt` and `llms-full.txt` (the whole docs site as one file, read by grep and by section), the docs pages for harnesses, Claude Code, Codex, agent behavior, security and permissions, privacy, environment variables, settings reference, FAQ, troubleshooting, Big Terminal Mode, checkpoints, agent modes, and the Conductor API. Changelog index plus 0.7.0, 0.9.0, 0.18.0, 0.36.3, 0.44.0, 0.50.0, 0.52.0, 0.63.0, 0.69.0, 0.77.0.
- Homebrew cask JSON for `conductor` (app name, version 0.87.6, zap paths).
- Public third-party source that reads a live install:
  - `hyldmo/conductor-remote` (`FINDINGS.md`, `ARCHITECTURE.md`, `AGENTS.md`, `src/notifications/notify.ts`, `src/reads/{sessions,types}.ts`, its test for `TurnWatcher`). It records recon on Conductor 0.76 to 0.84 and says everything was verified against the installed build.
  - `condcli` 0.1.1 from npm (unpacked in scratch, not installed): `src/db.ts` has the table and column names.
  - `octane0411/open-vibe-island` issue 669: process ancestry and environment of a live Conductor-hosted agent.
- My own probe test: ran `tools/agents_probe.py` `matches()` and `session_id()` on synthetic `ps` lines (app, sidecar in both path forms, agent in both forms, the app's own CLI, a terminal claude, a Zed ACP child, Microsoft's `conductor` CLI). Only the intended ones match. No real process exists to test against.
- No app download, no install, no session store read. No message content seen.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | Mac app (Tauri v2), local sidecar plus agent subprocesses, Cloud workspaces (microVM sandboxes). An iOS app is listed "SOON" on the home page; a public HTTP API and MCP server drive cloud workspaces only | home page, docs `api`, FINDINGS |
| Bundle id | `com.conductor.app` (also the Application Support folder name) | cask zap, FINDINGS, open-vibe-island |
| App and exe | `/Applications/Conductor.app`, Mach-O `Contents/MacOS/conductor` (lowercase). `Contents/Resources/bin/` holds helpers, including a `conductor` CLI for the cloud API | cask, FINDINGS |
| Process tree | `Conductor.app/.../MacOS/conductor` -> `conductor-runtime sidecar` (~/Library/Application Support/com.conductor.app/bin/.internal/) -> `claude` or `codex` per chat, headless, no tty. Sidecar socket `$TMPDIR/conductor-sidecar-v2-<sidecarPid>.sock` | FINDINGS, open-vibe-island |
| Bundled agents | `claude` and `codex` in `~/Library/Application Support/com.conductor.app/bin`; a system install can replace them; Cursor sessions use the Cursor API with no local executable; OpenCode is a managed integration | FAQ, harnesses, troubleshooting |
| Process to session | The agent env has `CONDUCTOR_SESSION_ID` (documented) equal to the agent's `--session-id` (third-party); also `CONDUCTOR_WORKSPACE_ID`, `CONDUCTOR_WORKSPACE_PATH`, `__CFBundleIdentifier=com.conductor.app`. `sessions.id` in the DB equals the Claude Code session id. cwd is `~/conductor/workspaces/<repo>/<city>` | env-vars doc, open-vibe-island, FINDINGS |
| Store | `~/Library/Application Support/com.conductor.app/conductor.db`, SQLite WAL, one shared file, plus `~/conductor` for worktrees. Vendor names the directory, not the file, so `documented=false`. Claude's own transcripts still go to `~/.claude/projects` and Codex's to `~/.codex` (the FAQ says so) | privacy, FAQ, FINDINGS |
| Turn in progress | Exact: `sessions.status = 'working'` in `conductor.db`. Optional: the opt-in "Caffeinate while agents are running" setting. Otherwise CPU of the tree, which is per app, not per chat | notify.ts, changelog 0.50.0 |
| Waiting on the human | `sessions.status` of `needs_user_input` (question) or `needs_plan_response` (plan approval), in newer code. Tool-permission prompts: sidebar text only, no DB value found | notify.ts and test, changelog 0.44.0 |
| Hooks | None of its own. Claude Code hooks pass through (0.9.0 says global hooks are configurable in Conductor). `scripts.setup/run/archive` are workspace scripts, not turn hooks | changelog, settings reference |
| OpenTelemetry | Not from Conductor: PostHog analytics and crash logs. Env vars set in Conductor reach the agents, so a harness's own OTel could work (untested) | privacy, env-vars doc |

## Could not determine

- The real `ps` argv of the app, the sidecar and the agents. No install, so the sidecar's exact command line (full path or retitled), the agent's full flag set (`--session-id` versus `--resume` on restart, equals form or separate) and whether Codex carries any id in argv are all inferred. The row has two forms of each path rule because of the space in `Application Support`.
- Whether the `caffeinate` opt-in is a `caffeinate` child or an in-process assertion, its assertion name, and whether it ever drops while a permission prompt waits. Not in any doc; the binary could answer it with `strings`, and I did not download it.
- What `sessions.status` shows during a tool-permission prompt. The relay author's older note says a permission wait looks like `working -> idle`; the newer code names two `needs_*` states but not permissions. Not measured.
- Whether the `needs_*` statuses are current. They appear in the newest third-party code and its test, but the same repo's `AGENTS.md` and a type comment still say only `working`, `idle`, `error`.
- How the DB looks during a turn: whether the `-wal` file is written often enough to serve as a 30 s signal. The relay polls status every 2.5 s, which says nothing about write cadence. The 30 s window and the 5% CPU floor are guesses.
- Whether Claude Code hooks (`Notification`, `Stop`) fire under Conductor's headless SDK mode, and whether a `caffeinate` child from Claude Code appears there. Same open question as the T3 Code row.
- Bundle ids of alpha or beta channels. The `conductor-alpha://` scheme suggests they exist; nothing lists their ids.
- Whether Codex and OpenCode chats also get `sessions.id` equal to a harness session id. Only Claude was stated.
- Conductor Cloud: the local Mac shows nothing to `ps`.

## Contradicts common belief or the hint

- The hint says "runs many Claude Code and Codex agents". Today it also runs Cursor Agent (through the Cursor API, no local process at all) and OpenCode, and a cloud tier.
- It is not "an Electron or terminal app running claude in ptys". It is a Tauri app whose agents are headless children of a separate `conductor-runtime sidecar`, with no tty. Only Big Terminal Mode and the integrated terminal use a pty, and those run ordinary user commands.
- One process is not one chat. The app and the sidecar hold every chat, so CPU, children and pid cannot say which chat works. Only the SQLite `sessions` row is per chat.
- The row's biggest trap is double counting. A Conductor-run `claude` matches the claude-code row by its name (`claude`) exactly like a terminal one, so a detector lists the same chat twice unless it drops a match whose ancestor is `conductor-runtime` or the app. Same class as `t3-code` and `zed`.
- `agents_probe.py` splits `ps` on spaces, and the agent, the sidecar and the helpers all live under `Application Support`. The probe therefore sees `/Users/<user>/Library/Application` as argv[0]; the claude-code row's `names: ["claude"]` will not match a Conductor-run claude at all under the probe, only under a detector that keeps the full path. Under the probe only the app itself (path has no space) is visible.
- Idle in the DB is not finished. `status` reads `idle` while a chat waits on a background task or subagent (the app shows "Waiting for task"), so a "working to idle" edge can fire while work is still coming.
- `tool_children` would be wrong on the app: its direct children include integrated-terminal shells and run scripts. It would also be wrong on the sidecar, whose direct children are the long-lived agents. The row leaves it out.
- Default is full access: agents run unsandboxed as the user, and with tool approvals off nothing ever waits on a permission prompt (docs FAQ, Big Terminal Mode). A waiting state is then only a question or a plan.
- Name collisions: Microsoft's `conductor` (Python workflow CLI), Netflix Conductor, agent-deck's conductor and paneflow's Conductor share the word. The row keys on `/Conductor.app/Contents/MacOS/conductor` and the `com.conductor.app` path only.
- The docs say nothing about processes, hooks, the database or sleep prevention. Everything on those came from the changelog and from other people's tools reading a live install, so any of it can move with a release (the relay's own notes say so for the sidecar wire protocol, versioned `-v2-`).

## Verification

Adversarial re-check, 2026-09-29. Validator: `ok`. Confidence stays `inferred`: the app is closed source and not installed here (`ls /Applications | grep -i -E "conduct|herdr"` and `ps -axo pid=,args= | grep -i conductor` printed nothing), so no process, path or database fact was seen live. "documented" is not reachable for the process and DB rows, because they rest on one third-party repo. Sources were re-fetched and read; no message content was seen.

Claims, each confirmed, corrected or unsupported:

- Cask: `/Applications/Conductor.app`, version 0.87.6, zap paths for Application Support, Caches, WebKit, auto_updates true. Confirmed (`formulae.brew.sh/api/cask/conductor.json`). "WKWebView" from the WebKit dir: inferred, now labelled so.
- Tauri v2, bundle id `com.conductor.app`, frontend in the Mach-O, `Resources/bin` helpers (`conductor` API CLI, `checkpointer.sh`), `CFBundleURLSchemes=[conductor]`, recon on 0.76.0. Confirmed in conductor-remote `FINDINGS.md`.
- Sidecar `conductor-runtime sidecar`, child of the app, parent of live claude/codex, socket `$TMPDIR/conductor-sidecar-v2-<pid>.sock`, binary under `Application Support/com.conductor.app/bin/.internal/`. Confirmed in `FINDINGS.md` and `ARCHITECTURE.md`. Single source (one author); the exact `ps` argv was never seen.
- Ancestry and env (`CONDUCTOR_SESSION_ID` == `--session-id`, `CONDUCTOR_WORKSPACE_ID`, `__CFBundleIdentifier`), headless with no tty. Confirmed, but CORRECTED the citation: open-vibe-island #669 is a merged pull request (opened 2026-08-26, merged 2026-09-02), not "an issue closed 2026-08-26". The sidecar path appears elided there.
- Store `conductor.db`, SQLite WAL, `sessions` and `session_messages` columns, `sessions.id` == Claude session id. Confirmed (`FINDINGS.md` "State DB" and line 79; condcli 0.1.1 `src/db.ts` has the columns; its `PRAGMA journal_mode = WAL` is condcli's own, so WAL rests on `FINDINGS.md` alone). Directory documented by the vendor, file not: `documented=false` correct.
- Status values `working`/`idle`/`error`: confirmed. `needs_user_input`/`needs_plan_response`: confirmed to exist in `notify.ts` (`turnEnded`) and its test, contradicted by `AGENTS.md` line 1197 ("only ever holds working/idle/error"); left flagged unconfirmed. CORRECTED: the row tied `needs_user_input` to the `AskUserQuestion` tool. No source says that (AGENTS.md only names it as a Conductor MCP tool). Now marked inferred.
- Permission wait has no status value, read as working -> idle: confirmed (`notify.ts` "no permission-request table", `AGENTS.md`). Sidebar "needs permission": confirmed in 0.44.0; "session needs input": confirmed in docs troubleshooting.
- `idle` while waiting on background tasks: confirmed (`bt.ts` header, `types.ts` comment; vendor 0.77.0 says chats show a waiting indicator and timer). The literal string "Waiting for task" is from `bt.ts`, not from the vendor.
- Caffeinate setting, prevents sleep while an agent is working, off below 10% battery, added in 0.50.0 (1 May 2026): confirmed. CORRECTED: "Off by default" is not stated anywhere; the changelog says "new experimental settings". Now inferred opt-in. Mechanism and assertion name: still unknown.
- Bundled Claude Code and Codex in `~/Library/Application Support/com.conductor.app/bin`, `Settings -> Storage`, `claude_code_executable_path`/`codex_executable_path`: confirmed (FAQ, troubleshooting, settings reference). The binaries' file names are not stated.
- Local history in Application Support; `CONDUCTOR_SESSION_ID` only in agent processes; `~/conductor/workspaces/<repo>/<workspace>`: confirmed. PostHog analytics: confirmed. Agents run with the user's permissions, model requests go from the Mac to the provider: confirmed.
- Big Terminal Mode presets use `--dangerously-skip-permissions` when approvals are off: confirmed. UNSUPPORTED (this file's earlier "Contradicts" section): "Default is full access". The docs never state the default of `tool_approvals_enabled`, so whether a permission wait can occur by default is unknown.
- Hooks: 0.9.0 says "Global hooks and memory are now configurable in Conductor": confirmed. REMOVED as unsupported: "the /hooks slash command opens the UI" (not in the 0.9.0 page, the docs or any source). That Claude Code reads `~/.claude/settings.json` under Conductor is inferred from that one line. `scripts.setup/run/archive` in `.conductor/settings.toml` and `~/.conductor/settings.toml`: confirmed in the settings docs.
- Anthropic Agent SDK 2.1.50 in 0.36.3: confirmed. Codex app-server use by the relay: confirmed in `FINDINGS.md`.
- Vendor "Melty, Inc.": CORRECTED to "Melty Labs, Inc." (Terms; the changelog footer says Melty Labs). "Free app": the docs say "Conductor is free to use" and list a Free plan, with Pro/Teams above it; reworded "free plan".
- Cloud "Firecracker microVM ... hosted on Vercel": CORRECTED. Conductor's docs say an isolated microVM in a Vercel sandbox. "Firecracker" is Vercel's own wording (`vercel.com/docs/vercel-sandbox`), not Conductor's. Added as a source.
- `GET /v0/sessions/{id}/status` returns idle, working or errored: confirmed. iOS app "SOON" on the home page: confirmed.
- Name collisions with "agent-deck" and "paneflow" conductors: unsupported (no source read); harmless, since the rules key on the `Conductor.app` and `com.conductor.app` paths. Microsoft and Netflix Conductor: not fetched, same reasoning.

Process patterns, tested with `agents_probe.matches()` on synthetic argv (full-path and space-split forms):

- App rule `/Conductor.app/Contents/MacOS/conductor`: matches only the app. Does not match `Contents/Resources/bin/conductor`, `/usr/local/bin/conductor`, `/opt/homebrew/bin/conductor`. It would also match a hypothetical `.../MacOS/conductor-helper` (substring); a Tauri app has no such helper, so left.
- Sidecar rules: match `conductor-runtime sidecar` in full and split forms. Do not match `conductor-runtime actions` or `--version`. No other product was found using `conductor-runtime`.
- Agent rules: FALSE POSITIVE FOUND, not repairable from evidence. They match every process under `.../com.conductor.app/bin/` except argv tokens `sidecar` and `actions`. Synthetic `bin/rg` and `.internal/conductor-runtime <other>` both matched as agents. Narrowing to `bin/claude` and `bin/codex` needs the real file names, which I could not see. Recorded in the surface label and notes. A system `claude` chosen in Settings -> Storage is missed by path (already stated); ancestry covers it.
- Double counting with `claude-code`: its `tui` rule is `names: ["claude"]` plus `/claude/versions/`. A bundled `claude` named `claude` matches it in a detector that keeps the full path (checked against the row, not a live process). Drop the `claude-code` match when an ancestor is `conductor-runtime` or the app.
- Real-world caveat: the sidecar's real `ps` argv form (retitled or full path) was never seen.
