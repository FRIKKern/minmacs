# Emdash: evidence notes (2026-09-29)

Row: `registry/agents/emdash.json`. Validator: ok. Confidence is `documented`, not `verified-locally`: Emdash is not installed here (`ls /Applications | grep -i emdash`, `ps`, `ls ~/Library/Application Support`, `ls ~/.emdash`, `which emdash`: all empty). `tools/agents_probe.py --row` finds 0 sessions, as expected. Nothing was run, installed or messaged.

## Shape

```
Emdash (main, Electron)  /Applications/Emdash.app/Contents/MacOS/Emdash          bundle com.emdash.stable
 |- Emdash Helper (GPU | Renderer | ...)   under Contents/Frameworks, --type=...
 |- Emdash .../app.asar/out/main/tui-agents-runtime.js   worker, same exe, ELECTRON_RUN_AS_NODE
 |    '- claude / codex / amp / ...       DIRECT child, plain argv, PTY (no shell unless shell setup or tmux)
 |- Emdash .../app.asar/out/main/acp-runtime.js          worker for chat (ACP) sessions
 |    '- Emdash .../app.asar[.unpacked]/out/main/adapters/claude-acp.mjs   Claude/Codex adapter (exact path unobserved), then the user's CLI
 |- Emdash .../git-runtime.js, files-runtime.js, conversations-runtime.js, ...   up to 16 workers in all
 '- (no caffeinate, no notification helper, no sleep assertion)
```

Emdash is a host. It has no model loop. "Working" means a hosted agent is working.

## What I checked

- Repo `generalaction/emdash` at `873a3e2` (merge of v1.2.7, 2026-09-27, latest release). Shallow clone into the scratchpad plus raw files: `AGENTS.md`, `CONTEXT.md`, `agents/architecture/{acp-runtime,workspace-server}.md`, `agents/integrations/providers.md`, `agents/risky-areas/pty.md`; app identity, electron-builder config, worker manifest and spawner, the tui-agents runtime (`runtime.ts`, `agent-state.ts`, hook server and pipeline), PTY spawn and tmux code, the Claude and Codex provider plugins, the hook command builders, the agent-status service and ACP transition, the app DB schema and DB path code.
- Docs: `emdash.com/docs/{providers,telemetry,project-config}` (emdash.sh redirects there), Homebrew cask JSON, GitHub releases API, Claude Code hooks doc (for the Stop-on-interrupt rule).
- Source greps for sleep assertions (`powerSaveBlocker`, `caffeinate`, `IOPMAssertion`): none found. Notification helpers (`afplay`, `osascript`, `terminal-notifier`) and telemetry (`opentelemetry`, `OTEL_`, `otlp`): see Verification, the first pass overstated both.
- Probe check: ran the row's `matches()` over synthetic command lines. Stable main and workers match; Electron helpers, the canary helpers, `claude` and `Emdashboard.app` do not; the canary main matches only through the split-on-space entry.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Executable | `/Applications/Emdash.app/Contents/MacOS/Emdash`; canary `Emdash Canary.app/.../Emdash Canary` (space in the name) | `executableName: PRODUCT_NAME` in electron-builder config |
| Bundle ids | `com.emdash.stable`, `com.emdash.canary` | `app-identity.ts`, cask `quit: com.emdash.stable` |
| Process to session | None in Emdash's own argv. Key is the conversation id. Claude is launched `claude --session-id <conversation id>` (or `--resume <id>`); the transcript is `~/.claude/projects/*/<conversation id>.jsonl`. Agent env has `EMDASH_PTY_ID`, `TERM_PROGRAM=emdash` (env only, not argv) | `standard-command.ts`, `runtime.ts` |
| Store | `~/Library/Application Support/emdash/emdash4.db` (SQLite, WAL), table `conversations`, column `agent_status`. Canary: `emdash-canary`. Undocumented. No transcripts; those stay in each agent's own store | `schema.ts`, `default-path.ts`, `drizzle` client |
| Turn in progress | `agent_status = 'working'` (read-only query). Terminal sessions: hook `UserPromptSubmit` sets it, `Stop` ends it. ACP sessions: `isGenerating` from the session state | `agent-state.ts`, `agent-status-transition.ts` |
| Waiting on the human | `agent_status = 'awaiting-input'`: hook `notification` of type `permission_prompt`, `idle_prompt` or `elicitation_dialog`; ACP pending permission | same |
| Hooks | None of its own. It installs marker-tagged entries in the agent's user-global config (Claude: `~/.claude/settings.json`, events SessionStart, UserPromptSubmit, Notification, Stop) that POST to a loopback server in the tui-agents worker. 20 of 37 providers | `hooks.ts`, `providers.md`, docs |
| OpenTelemetry | No. PostHog, opt-out `TELEMETRY_ENABLED=false` | grep, telemetry doc |

## Could not determine

- Real `ps` output for any Emdash process: not installed. The Mach-O name comes from `executableName`; helper names from electron-builder defaults; the literal `app.asar` in worker argv from `app.getAppPath()` (inferred).
- Idle and busy CPU, so the 10 percent floor is a guess.
- How soon `emdash4.db` reflects a turn, and whether the `-wal` mtime is a usable raise signal. Status writes happen on transitions only.
- What `agent_status` holds if the app is killed mid-turn: the code resets it only at the next launch, so the file can read `working` with nothing running.
- Which transport (terminal or chat) new conversations default to. It is a per-provider preference (`useChatUi`).
- The exact argv the Claude ACP adapter gives the `claude` binary it starts (Agent SDK, not read).
- Whether `$SHELL -c` wrapping is common: it happens only with a shell setup or tmux, both opt-in.

## Contradicts common belief or the hint

- "Orchestrator that runs agents in parallel" is right, but on the process table it is one tree, not one process per task. The main app and every worker share one executable name, so a name-only match counts about a dozen "Emdash" processes. The probe's outermost-match rule folds them.
- The agents are grandchildren of the app, not children. Child-process rules on the app pid see only helpers and workers, which live as long as the app, so they read permanently working.
- Emdash holds no sleep assertion, unlike Cursor, Warp and Zed. Only the hosted Claude Code brings its own `caffeinate`, as a child of `claude`.
- Hooks are not per worktree. They are written once into the user's global agent config and stay there, harmless outside Emdash. Every Claude Code session on the Mac then carries Emdash entries in `~/.claude/settings.json`.
- `awaiting-input` is not the same as "blocked on a permission". For Claude Code it also covers the idle-waiting notification, and the permission-versus-idle detail is not saved in the database.
- Emdash never reads the terminal to infer state (unlike Herdr). No hook, no status, except that Enter marks a hookless provider `working`.
- A terminal session can stay `working` after an interrupt: Claude Code's Stop hook does not run on a user interrupt and Emdash does not subscribe to StopFailure. Inferred for Emdash; documented for Claude Code.
- tmux is off by default. When on, agents live in a tmux server and outlive the app, so they are no longer under Emdash in the process tree.
- Agents on SSH hosts run on the remote box (a Linux workspace-server daemon) and are invisible from this Mac.
- The docs now live at `emdash.com`; the README, the cask and the desktop `homepage` field still say `emdash.sh` (it redirects).

## Verification

Second-pass review, 2026-09-29, by an agent that did not write the row. Method: shallow clone of `generalaction/emdash` at `873a3e2` (5,194 tracked files, merge of v1.2.7), re-read of every cited file, fresh fetches of the release page, Homebrew cask JSON, `emdash.com/docs/telemetry`, `emdash.com/docs/project-config` and `code.claude.com/docs/en/hooks.md`, and `agents_probe.matches()` run over 12 synthetic command lines. Validator: `ok` before and after. Confidence stays `documented`: Emdash is not installed here (`ls /Applications | grep -i emdash`, `ps -axo pid,ppid,args | grep -i emdash`, `ls ~/Library/Application Support | grep -i emdash`, `ls ~/.emdash`, `which emdash`: all empty, re-run today).

| # | Claim | Result |
|---|---|---|
| 1 | v1.2.7 latest, published 2026-09-27; Homebrew cask `emdash` 1.2.7 with `Emdash.app`; dmg assets | confirmed. Release page datetime 2026-09-27T09:29:15Z; assets emdash-arm64/x64 dmg and zip; cask version 1.2.7, `quit: com.emdash.stable`. The GitHub API was rate limited, so the release page was used. `electron-builder.config.ts` lists only arm64 mac targets, yet an x64 dmg is published: CI evidently overrides it, immaterial here |
| 2 | Bundle ids `com.emdash.stable` / `com.emdash.canary`, product names, userData dirs `emdash`, `emdash-canary`, `emdash-dev`, `executableName = PRODUCT_NAME` | confirmed (`app-identity.ts`, `app-identity.canary.ts`, both builder configs). Mach-O name `Emdash` / `Emdash Canary` follows from `executableName` but was never observed |
| 3 | Workers are `fork()`ed from the main process, so argv[1] = `<app.getAppPath()>/out/main/<artifact>.js`, artifacts `tui-agents-runtime`, `acp-runtime` | confirmed (`child-process-spawner.ts`, `worker-paths.ts`, `workers.ts`, `worker.ts` of tui-agents and acp). ELECTRON_RUN_AS_NODE on fork is Electron behaviour, not in Emdash source: inferred |
| 4 | "About a dozen" workers | corrected: `desktopWorkers` lists 16 ids (acp, agent-config, automations, conversations, file-search, files, fs-watch, git, host-settings, mementos, pull-requests, resource-usage, scripts, terminals, tui-agents, workspace-registry). Row now says up to 16 |
| 5 | Terminal agents are direct children of the tui-agents worker, exec'd plainly without shell setup or tmux; wrapped in `$SHELL -c` otherwise | confirmed (`resolvePosixSpawn` in `services/pty/api/local-spawn.ts`: argv command with no `shellSetup` and no `tmux` goes to `planExecutableLaunch`, else a shell line) |
| 6 | tmux off by default, per host and per project; names `<label>-<10 hex>`; option `@emdash_identity` | confirmed (`settings?.tmux ?? false`, `tmux-identity.ts`: `TMUX_HASH_LENGTH = 10`, `TMUX_IDENTITY_OPTION`; docs text "Keeps task terminals and agent sessions running across app restarts") |
| 7 | Agent env: `TERM_PROGRAM=emdash`, `TERM`, `COLORTERM`, `EMDASH_HOOK_*`, `EMDASH_PTY_ID`, plus `EMDASH_TASK_ID/NAME/PATH`, `EMDASH_ROOT_PATH`, `EMDASH_DEFAULT_BRANCH`, `EMDASH_PORT` | confirmed. The first set is in `runtime.ts` (~533, 837); the task set comes from `getTaskEnvVars` via `task-session-launch-context.ts` into `providerVars`. `EMDASH_DEFAULT_BRANCH` is omitted when the repo has no default branch |
| 8 | Claude launched with `--session-id <conversation id>`, `--resume <provider session id>`, `--model`, `--dangerously-skip-permissions` | confirmed (`claude/index.ts` buildCommand, `standard-command.ts`; `sessionId: config.input.conversationId` in `runtime.ts`). Nothing verified about what `claude` looks like in `ps` (a full path is likely; its own row handles that) |
| 9 | Status mapping start/stop/error/notification, attention types, Enter marks a hookless provider working | confirmed (`agent-state.ts`). Nuance: Enter marks working for any provider whose hooks lack a `start` event, not only hookless ones. ACP mapping confirmed (`agent-status-transition.ts`: pending permission, `isGenerating`, `lastStopReason`, cancelled resets) |
| 10 | Claude notification classified by message text into permission_prompt or idle_prompt | confirmed (`claude/hooks.ts`) |
| 11 | `agent_status` in `conversations` of `emdash4.db`, WAL, device-local cache; DB in userData; canary `emdash-canary` | confirmed (`schema.ts` comment "Device-local cache converging from the live session model", `default-path.ts`, `path.ts`, `apply-identity.ts`, `drizzleClient.ts` `journal_mode = WAL`). `default-path.ts` pins `emdash` for CLI tooling only; the app uses `app.getPath('userData')` |
| 12 | Stale `working`/`awaiting-input` reset at boot, "local pty conversations" | corrected: two resets run, for `type = 'pty'` and `type = 'acp'`, both only where `location = 'local'`. Rows of remote SSH hosts are never reset. Row now says so and its query adds `AND location = 'local'` (column `location`: 'local' or 'remote') |
| 13 | Other userData files: `conversations.db`, `mementos.db`, `pull-requests.db`, `host-settings.json`, `acp-session-intents.json`, `tui-session-intents.json`, `acp-attachments/` | confirmed (`desktop-workers.ts` 244-332, `session-intent-stores.ts`) |
| 14 | Hook server on 127.0.0.1, `listen(0)`, POST `/hook`, headers `X-Emdash-Token`, `X-Emdash-Pty-Id`, `X-Emdash-Event-Type`; curl command shape and guard | confirmed (`hook-server.ts`, `helpers/hooks.ts`) |
| 15 | Claude gets SessionStart, UserPromptSubmit, Notification, Stop in user-global settings.json under `$CLAUDE_CONFIG_DIR` or `~/.claude` | confirmed (`claude/hooks.ts`, `providers.md` "install into user-global provider configuration") |
| 16 | "37 providers, 23 ACP-capable" | confirmed (`providers.md`; 37 plugin directories) |
| 17 | "Hooks are installed for 20 of 37 providers" | corrected: 24 of 37. The row's list missed Antigravity, CodeBuddy, Muse Code and Prime Agent; 13 providers have none (autohand, charm, cline, codebuff, continue, cursor, freebuff, hermes, jules, junie, letta, rovo, zero). Counted from `hooks:` blocks and cross-checked with the root table in `providers.md` (24 names) |
| 18 | Claude Code `Stop` does not run on user interrupt; API errors fire `StopFailure`; Emdash does not subscribe to StopFailure | confirmed. Hooks doc, `### Stop`: "Does not run if the stoppage occurred due to a user interrupt. API errors fire StopFailure instead." Emdash subscribes to four events only. The stuck-`working` consequence for Emdash stays inferred |
| 19 | ACP adapters are children of the acp worker: Emdash executable in Node mode, argv `adapters/<name>-acp.mjs` | confirmed for the executable, env and file name. Corrected for the path: the row wrote `app.asar.unpacked/...`, but `resolveAdapterAsset` returns the first `existsSync` candidate built from `import.meta.url`, and no code rewrites it to `app.asar.unpacked`. `asarUnpack` only decides where bytes live. The path is probably under `app.asar`; unobserved. The row now says so. It does not change matching, which keys on the executable |
| 20 | Remote SSH hosts run a Linux workspace-server under `~/.emdash/workspace-server/` | confirmed (`agents/architecture/workspace-server.md`) |
| 21 | Emdash holds no sleep assertion | confirmed: no match for `powerSaveBlocker`, `caffeinate`, `prevent-app-suspension`, `prevent-display-sleep`, `IOPMAssertion` |
| 22 | "Spawns no notification helper; none of afplay or osascript found in source" | corrected: `osascript` does occur (`main/core/app/service.ts:420` opens Terminal/iTerm for SSH tasks; `utils.ts:107` lists fonts, `:243` looks up bundle ids). None is a notification. Notifications use Electron `Notification` (`system-notification-sink.ts`) plus an in-renderer sound player (`needs_attention`). `afplay` and `terminal-notifier` appear nowhere. The conclusion holds, the evidence line was wrong |
| 23 | "No OpenTelemetry; grep for opentelemetry, OTEL_, otlp matched nothing" | corrected: it matches `pnpm-lock.yaml` (optional peer dependency `@opentelemetry/api`). No source file or package.json uses it. Conclusion holds |
| 24 | PostHog only, on by default, off with `TELEMETRY_ENABLED=false`, `0` or `no`; events `agent_run_started`, `agent_run_finished`; `app_started`, `perf_vitals` | confirmed (`emdash.com/docs/telemetry`; `telemetry.ts` declares `app_started`, `perf_vitals`) |
| 25 | Not installed here, nothing running | confirmed, commands re-run today: all empty or "No such file" |
| 26 | Process patterns | confirmed by running `agents_probe.matches()`: stable main [stable], stable worker [stable, tui-agents], canary main and canary worker [canary]; no match for stable or canary Electron helpers, `claude --session-id`, `/Applications/Emdashboard.app/...`, `/Applications/Emdash Notes.app/...`, `vim /Applications/Emdash.app/Contents/MacOS/Emdash`, `/opt/homebrew/bin/emdash`. Matching reads argv[0] only (`p["exe"]`), so an app in a path with a space is not seen: registry README section 3 case 11, not fixable in this row. The canary entry would also match any executable under `/Applications/Emdash*` carrying an argument containing `Canary.app/Contents/MacOS/Emdash`: no such program known. The tui-agents and acp surfaces are subsumed by the app surface and never decide anything under the outermost-match rule; harmless |
| 27 | Child signals, no `child_process`/`tool_children`/`power_assertion` on the Emdash pid | confirmed reasoning: direct children of main are helpers and workers, and the hosted agents are grandchildren; sound under the direct-children-only rule |
| 28 | `tree_cpu` floor 10 | unsupported by measurement, labelled "unmeasured guess" in the row; matches README section 4 for Electron apps |
| 29 | Hosted-agent transcript path `~/.claude/projects/*/<conversation id>.jsonl` | inferred from claim 8 (session id equals conversation id) plus Claude Code's own layout; not observed, and `/resume` inside the TUI changes the id |

Nothing in the row was refuted outright. Four factual errors were repaired (worker count, hook-provider count, adapter path, OTel and osascript grep statements) and one boundary added (`location = 'local'` in the suggested query). Remaining doubts: real `ps` output, idle CPU, database latency, and whether Electron's `fork` sets `ELECTRON_RUN_AS_NODE` (documented Electron behaviour, not seen in Emdash source).
