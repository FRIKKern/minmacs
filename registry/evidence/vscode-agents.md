# VS Code extension agents: evidence notes (2026-09-29)

Row: `registry/agents/vscode-agents.json`. Validator: ok. Confidence: `documented`.
Nothing in this family is installed or running here (no VS Code app, no Cline, Kilo, Roo, `code`, `kilo`), so no live turn was seen and no probe run can say anything. Everything below is official docs, public source, or a small amount of local layout evidence.

```
VS Code app (com.microsoft.VSCode)  "Visual Studio Code.app/Contents/MacOS/<Electron|Code>"   one process, ppid 1
 |- Code Helper (Plugin)  = EXTENSION HOST  (utility, allowLoadingUnsignedLibraries)
 |     |- Copilot "Local" harness   (GitHub.copilot-chat, in-process)
 |     |- Cline 4.x                 (SDK ClineCore, backendMode local, in-process)
 |     |- Roo Code 3.x              (in-process, sunset)
 |     |- Kilo Code client -- spawns --> <ext dir>/bin/kilo serve --port 0   (own process, loopback HTTP+SSE)
 |     |                       and, only if Keep Awake is on, /usr/bin/caffeinate -i -w <ext host pid>
 |- Code Helper (utility "agent-host") = AGENT HOST  (Copilot / Claude / Codex harnesses, outlives windows)
 |- Code Helper: shared process, pty host, file watcher (same helper app, same argv shape as the agent host)
 |- Code Helper (Renderer), (GPU)
Cloud target: provider infrastructure, nothing local.
```

## What I checked

- Read first: `registry/schema.json`, `registry/agents/claude-code.json`, `tools/agents_probe.py`, `tools/validate_row.py`, plus the cursor, windsurf, opencode, codex, hermes rows for house style.
- Docs fetched (code.visualstudio.com): agent-host, agent-harnesses (concepts and run), agent-customization/hooks, agents/reference/ai-settings, agents/guides/monitoring-agents, agents/run/agents-window. Docs in the cline repo (hub-spoke, plugins, OpenTelemetry pages). Kilo docs (plugins, keep-awake). Homebrew cask JSON for VS Code, Insiders, VSCodium. VS Marketplace extensionquery for versions.
- Public source, read by raw file: `microsoft/vscode` (`src/vs/platform/agentHost/*` incl. `AGENTS.md`, `OTEL.md`, `LOCAL_ENDPOINT.md`, the starter, `extensions/copilot/src/...`, `chatSessionStore.ts`), `microsoft/agent-host-protocol` (session-channel spec), `cline/cline` (`apps/vscode/src/sdk/*`, `sdk/packages/{core,shared}`), `Kilo-Org/kilocode` (`packages/kilo-vscode`, `packages/opencode`, `packages/core`), `RooCodeInc/Roo-Code`.
- Local, read-only: `ls`/`test -e` of every candidate path, `ps -axo` of the running Cursor.app (same VS Code base) for Electron process shape, `pmset -g assertions` (no VS Code agent assertion; only caffeinate from Claude Code and Insomnia), and the leftover `~/Library/Application Support/Code` from an uninstalled VS Code (April 2025): one `chatSessions/<uuid>.json` record, key names only printed.
- Probe: `matches()` run on synthetic ps lines. `kilo serve` matches the daemon surface, `kilo --version` and a terminal `kilo` do not. The VS Code main process does NOT match (see below). With full executable paths substituted, the main, Insiders and extension-host specs match correctly, and a plain `Code Helper` utility (shared process) and the renderer do not.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Bundle ids | `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`, `com.vscodium`, `com.visualstudio.code.oss` (OSS build) | Homebrew cask, upstream product.json |
| Main process | `/Applications/Visual Studio Code.app/Contents/MacOS/<exe>`; exe name (Code vs Electron) not verified | inferred; path used instead |
| Extension host | `Code Helper (Plugin)` utility, argv `--type=utility --utility-sub-type=node.mojom.NodeService` | source (`allowLoadingUnsignedLibraries: true`), `Cursor Helper (Plugin).app` exists locally |
| Agent Host | utility process type `agentHost` / name `agent-host`, plain `Code Helper` helper; argv gives nothing. Find it by endpoint entry file `<userData>/agent-host/local-endpoint/entries/*.json` (key `pid`) or socket `vscode-ah-<hash>/<instance>.sock` | source |
| Kilo | `<extensionPath>/bin/kilo serve --port 0`, child of extension host | source |
| Cline, Roo, Copilot Local | no process of their own | source |
| Process to session | Cline: `sessions.db` row `pid` = extension host pid (many sessions share it). Kilo: server hosts all sessions; `KILO_PARENT_PID` env = ext host. Agent Host: AHP session URIs. Copilot Local, Roo: none. No harness puts a session id in argv | source |
| Session stores | six, listed in the row (`session_store.stores`). All `documented: false` | source |
| Turn in progress, best per surface | Cline `sessions.status='running'`; Kilo `GET /session/status` busy/retry; Agent Host AHP `InProgress`; Copilot Local transcript `assistant.turn_start` without `turn_end` | source |
| Waiting on human | Agent Host AHP `InputNeeded`; Kilo `GET /permission`, `/question`; Copilot OS notification setting only; Roo IPC events (opt-in); Cline nothing observable | source, docs |
| Hooks | Cline (6 events wired), Copilot Local (8 events), Kilo plugins. Roo none. Agent Host uses the provider's own hooks, no shared schema | docs, source |
| OTel | Copilot yes (Local and Agent Host, opt-in), Cline yes (opt-in env/remote config), Kilo yes (standard `OTEL_EXPORTER_OTLP_*`), Roo no | docs, source |

## Could not determine

- Any real `ps` line for the extension host, agent host or `kilo serve`; the process title on stock VS Code (Cursor sets `VSCODE_PROCESS_TITLE`, upstream main does not).
- Whether the VS Code main executable is `Electron` or `Code`.
- The `pmset -g assertions` name of the Electron `prevent-app-suspension` blocker, and the default of the experiment flag that gates it.
- Cline: which of `~/.cline/data/db/sessions.db` (code) and `~/.cline/data/sessions/sessions.db` (docs) is real; whether `status` stays `running` during an approval (source says the approval is awaited inside the turn); how promptly the persisted status follows the turn.
- Copilot on the Agent Host: end-of-turn record names in `events.jsonl`, write cadence, and whether an external client can read AHP without disturbing the session.
- Whether Copilot Chat's Marketplace version matches the repo (`extensions/copilot/package.json` says 0.69.0, engines `^1.141.0`; the Marketplace query printed 0.48.1 dated 2026-05-15; Homebrew's stable VS Code is 1.139.1). Not resolved.
- Kilo's session DB layout at rest, and whether `kilo.db` moves during a turn (not needed given the HTTP status).
- Legacy Kilo (pre-7, Roo fork) task storage; not looked at.
- Cline Desktop, CLI and JetBrains use the same SDK and `sessions.db` (source `desktop`, `cli`, `jetbrains`); they are not part of this row and have no row yet.

## Contradicts common belief

- "Copilot agent mode lives in the extension host" is out of date. Since the Agent Host (docs dated 2026-09-16), Copilot, Claude and Codex sessions run in a separate utility process that can outlive the window. Only the **Local** session target still runs in the extension host. A monitor that watches the extension host will miss Agent Host sessions completely.
- "Cline keeps tasks in VS Code globalStorage as `tasks/<id>/api_conversation_history.json`" is the pre-SDK layout. Cline 4.x (2026-09-24) runs the SDK in-process and stores sessions in `~/.cline/data/db/sessions.db`, shared with the Cline CLI and desktop app, keyed by `source` and `pid`. It does not use the hub daemon in VS Code (`backendMode: "local"`).
- Cline docs and code disagree on that path (`data/sessions/sessions.db` vs `data/db/sessions.db`). The row follows the code.
- Cline's `Enable Hooks` README says the box must be ticked; the code default is on. The SDK's `~/.cline/hooks` is deliberately switched off in VS Code; only `~/Documents/Cline/Hooks` and `.clinerules/hooks` run. The classic `Notification` hook exists but is not wired.
- Roo Code is not a live project: extension, cloud and router were sunset on 2026-05-15 and the repo is archived. Its own issue list points users to Cline and Kilo.
- Kilo Code 7 is not a Roo fork any more. It is an opencode fork: a bundled Bun binary serving HTTP, not an in-process extension. That makes it the one agent here with its own process and a real status endpoint. Its OTel is the plain `OTEL_EXPORTER_OTLP_*` standard, unlike Cline's `CLINE_OTEL_*`.
- Kilo's caffeinate (`-i -w <pid>`) is opt-in (Keep Awake, default off) and hangs off the extension host, not off `kilo serve`. Copilot's power blocker is per model request, experiment-gated, and lingers 2 minutes, so it is not a clean turn signal.
- VS Code has no Notification hook. "Waiting for me" reaches you as an OS notification (`chat.notifyWindowOnConfirmation`) and, on the Agent Host, as AHP `InputNeeded`.
- `~/Library/Application Support/Code` can exist without the app (it does here), so its presence is not evidence VS Code is installed or agents ran.

## Findings about the reference probe (not edited)

- `tools/agents_probe.py` splits `ps` args on spaces, so `/Applications/Visual Studio Code.app/...` becomes argv[0] `/Applications/Visual`. No `path_contains` with a space can ever match, and this affects every `.app` with a space in its name. Fix idea: read the executable path with `ps -o comm=` or `proc_pidpath`.
- The probe's `tool_children` counts every descendant, so it would be true for any Electron IDE tree; it is not used in this row.
- Most signals here are state reads (SQLite column, HTTP, AHP) that the probe has no way to express; the row lists them under the closest enum value (`transcript_write`, `socket_activity`) and says so in each `meaning`. Only `child_process` caffeinate and `tree_cpu` are evaluable by the probe today.

## Privacy

No session content was read or printed. From the one old local `chatSessions` record only the top-level key names were printed. One `ps eww` call on the running Cursor accidentally printed that process's environment; it was not recorded anywhere. It does confirm that a same-user process environment (where Kilo keeps `KILO_SERVER_PASSWORD`) is readable, which is why the Kilo status query is marked intrusive.

## Verification

Adversarial re-check on 2026-09-29 by a second reviewer who did not write the row. `tools/validate_row.py registry/agents/vscode-agents.json` printed `ok` before and after the repairs. Docs pages were re-fetched (VS Code agent-host, agent-harnesses, hooks, ai-settings, monitoring-agents, Electron utilityProcess), source files were re-read from raw GitHub (`microsoft/vscode`, `microsoft/agent-host-protocol`, `cline/cline`, `RooCodeInc/Roo-Code`, `Kilo-Org/kilocode`), the VS Marketplace and Homebrew were re-queried, and the local claims were re-run. Confidence stays `documented`: no VS Code, Cline, Kilo or Roo is installed here, so nothing above `documented` is reachable. Status words: confirmed, corrected, unsupported (inferred or not shown by the cited source).

### Process patterns (false-positive check)

| Claim | Status | Basis |
|---|---|---|
| Main process spec matches only the IDE main binary (helpers live under Contents/Frameworks) | corrected | The `code` shell command runs `ELECTRON_RUN_AS_NODE=1 Contents/MacOS/<name> .../cli.js` (resources/darwin/bin/code.sh), so CLI runs also match. Caveat added to the label. Cannot be excluded: `exclude_args` needs an exact argv element. |
| Reference probe cannot match a path with spaces | confirmed | Synthetic run through `matches()`: `/Applications/Visual Studio Code.app/Contents/MacOS/Electron` and the extension-host line match no surface. |
| Extension host spec `Code Helper (Plugin)` + `--utility-sub-type=node.mojom.NodeService` identifies the extension host | corrected | Electron docs: the (Plugin) helper is used exactly when `allowLoadingUnsignedLibraries` is set. Extension host sets it; so does the on-device dictation runtime (`localTranscriptionService.ts`) and any utility-process worker that asks for it. The spec is not exclusive. Also "one process per window group" was unsupported; it is one extension host per window. Label rewritten. |
| Extension host spec covers Insiders and VSCodium | unsupported | Helper names for those builds were not verified. They are not in the spec and the label says so. Not a false positive, a coverage gap. |
| Agent Host has no distinguishable ps line | confirmed (inferred half kept) | Starter sets no `allowLoadingUnsignedLibraries`, so it uses the plain helper. Upstream `bootstrap-fork.ts` sets no process title; the local Cursor does (its bundle has `VSCODE_PROCESS_TITLE`), so the stock argv shape stays inferred. |
| Kilo daemon spec `path_contains /kilocode.kilo-code-` + args `serve` | corrected | `args_contain` is a substring test: `.../bin/kilo run reserve` matched. Added `--port`; synthetic run now matches `kilo serve --port 0` only. The path test also matches the same extension in Cursor's extensions dir, which is still Kilo. |
| `kilo serve --port 0` is spawned detached from `<extensionPath>/bin/kilo` with KILO_PARENT_PID, KILO_CLIENT, KILO_SERVER_PASSWORD | confirmed | `server-manager.ts` lines 82-173. Whether `bin/kilo` re-executes itself was not checked. |
| `caffeinate` child means Kilo is working | corrected | `-w` is the extension host pid (`caffeination/service.ts`: `driver.start(process.pid, ...)`). The VS Code tree also holds terminals, where Claude Code or any user command can spawn its own caffeinate (pmset here showed a caffeinate command-line assertion; its parent was not checked). Meaning rewritten: valid only as a direct child of the extension host with `-w` equal to its pid. The probe cannot enforce that. |
| `tree_cpu` floor 10 percent | unsupported | A guess, and the row says so. A terminal build under the tree also trips it. |

### Sources, one by one

| Claim (row source entry) | Status | Basis |
|---|---|---|
| Agent Host exists, runs Copilot/Claude/Codex, Local stays in extension host, older versions ran agents in extension host | confirmed | Docs agent-host and agent-harnesses, both 9/16/2026. Qualification added: Claude provider default on (experimental), Codex default off (ai-settings; `agentHostMain.ts`). |
| Agent Host outlives windows | confirmed, narrowed | Docs: not tied to a window, a turn continues with no client. It is still a child of the main process. |
| Agent Host is UtilityProcess type agentHost, name agent-host, entry agentHostMain, no allowLoadingUnsignedLibraries | confirmed | `electronAgentHostStarter.ts` lines 174-191; extension host `extensionHostStarter.ts` lines 116-121 sets the flag. |
| Endpoint entry file with pid, type, instanceId, token; socket `<tmpdir>/vscode-ah-<hash>/<instance>.sock` | confirmed | `LOCAL_ENDPOINT.md`. |
| AHP status Idle/InProgress/InputNeeded/Error and `inputNeeded` roll-up (approval, question, client execution, authentication) | confirmed | `session-channel.md` lines 67-92. |
| Agent Host registry at `<userData>/agent-host/agent-host.db` | corrected | Source puts it at `<userData>/User/globalStorage/agent-host.db` (`agentHostBootstrap.ts`, `agentHostServices.ts`, `environmentService.ts`). Per-session data is under `<userData>/agentSessionData/<sessionId>/`. Tables `sessions_v2`, `session_chat_catalogs`, `session_chats` confirmed. The OTel DB path `<userData>/agent-host/otel/agent-host-traces.db` is separate and confirmed (`OTEL.md`). |
| Copilot SDK conversations at `COPILOT_HOME/session-state/<id>/events.jsonl` | confirmed | `copilotAgent.ts` line 2948, `copilotHome.ts` (`COPILOT_HOME` or `~/.copilot`). |
| Local chat store `workspaceStorage/<id>/chatSessions`, `emptyWindowChatSessions`, `.jsonl` default | confirmed | `chatSessionStore.ts` lines 72-76, 738-740. `chat.useLogSessionStorage` is not a registered setting anywhere in the repo, only read with `!== false`, so it is on unless a user adds it as false. |
| Old local data confirms `chatSessions/<uuid>.json` layout and key names | confirmed | Re-ran: one file, 513 bytes, Apr 14 2025; sorted key names identical to the row; `requests` length 0. No content printed. |
| Nothing in this family is installed or running | confirmed | `test -e`/`ls` on the app bundles, `~/.cline`, `~/Documents/Cline`, `~/.copilot`, `~/.local/share/kilo`, `~/.config/kilo`, `~/.kilocode`, `~/.roo` all absent; `ps` grep for kilo|cline|roo-cline|copilot empty; `which code kilo cline` not found. |
| Electron IDE process shape from local Cursor (main ppid 1, Helper children, `Cursor Helper: shared-process` titles, Helper (Plugin) app present, 0.0 percent idle) | confirmed | Re-ran `ps`; same pids (70991 main; 71902, 71915, 72098 titled helpers), `Cursor Helper (Plugin).app` in Frameworks. No extension-host process was running in Cursor at check time, so the `--utility-sub-type=node.mojom.NodeService` argv of an extension host is still not observed. |
| Bundle ids and app/data-dir names | confirmed | Homebrew casks: `Visual Studio Code.app` (quit `com.microsoft.VSCode`, data `Code`), `Visual Studio Code - Insiders.app` (`com.microsoft.VSCodeInsiders`, `Code - Insiders`), `VSCodium.app` (`com.vscodium` only from zap paths, data `VSCodium`). `com.visualstudio.code.oss` from upstream `product.json`. No process path is listed for the OSS build (`Code - OSS.app`), unverified. |
| Copilot Chat writes transcripts under extension `storageUri/transcripts`, `assistant.turn_start`/`turn_end` records, 20 retained | confirmed | `sessionTranscriptService.ts` (also no transcript dir when `storageUri` is undefined, i.e. empty windows). |
| Power save blocker per model request, 2 min release, experiment gated | corrected | Confirmed: `RELEASE_DELAY_MS = 2 * 60 * 1000`, `chatMLFetcher.ts` line 959-960. Added: the setting `chat.advanced.chatRequestPowerSaveBlocker` is experiment-based with source default `true`; needs proposed API `environmentPower` (declared in package.json); skipped for `ChatLocation.Other`. Row text no longer says the default is unknown. pmset assertion name remains unverified. |
| Copilot Chat version 0.69.0 vs Marketplace 0.48.1 | unsupported (unresolved) | Re-queried: Marketplace latest is 0.48.1 dated 2026-05-15, repo says 0.69.0. Later builds appear to ship inside VS Code. Which build a machine runs is unknown, so transcript and blocker behaviour is per current source, not per a shipped build. |
| Local hooks events, file locations, `chat.useHooks` default on, `chat.hookFilesLocations`, `chat.useClaudeHooks` | confirmed | Docs hooks page, 9/16/2026. |
| Claude Code `Notification` hook "not mapped" in VS Code | unsupported | The docs list eight Local events with no Notification and say only that Claude-format files are parsed with matchers ignored. Row and source entry reworded to say the mapping is undocumented. |
| `chat.notifyWindowOnConfirmation` / `...OnResponseReceived` default windowNotFocused, values off/windowNotFocused/always | confirmed | AI settings page, 9/17/2026. |
| `chat.agentHost.otel.*` settings on the AI settings page | corrected | Not on that page. They are in `OTEL.md` (default false for `dbSpanExporter`). Source entry reworded. |
| Copilot OTel opt-in, exporters otlp-http/otlp-grpc/console/file, local SQLite store | corrected | Confirmed against monitoring-agents. Added: OTel also turns on when `OTEL_EXPORTER_OTLP_ENDPOINT` is set or `dbSpanExporter.enabled` is true. Telemetry text updated. |
| Cline 4.x is `saoudrizwan.claude-dev` 4.1.21, published 2026-09-24, SDK in-process, `backendMode: "local"` | confirmed | `apps/vscode/package.json`, `vscode-session-host.ts` line 185; Marketplace query: 4.1.21, 2026-09-24T16:26Z. |
| Cline `sessions.db` location, columns, status values, pid = process.pid, `source` vscode, reconciler for dead pids | confirmed | `sqlite-session-store.ts`, `paths.ts` (`~/.cline/data/db`), `records.ts`, `common.ts`, `local-runtime-host.ts` lines 520, 1850, 2249, 2279-2323, `persistence-service.ts` (`isPidAlive`, `reconcileDeadRunningSession`). VS Code host defaults `source` to `"vscode"` (`vscode-session-host.ts` line 168). `storage-context.ts` uses the same `~/.cline/data` default. |
| Cline docs vs code disagree on the sessions.db path | confirmed | `hub-spoke.mdx` line 106-107 says `~/.cline/data/sessions/sessions.db`; code says `data/db`. `sdk/ARCHITECTURE.md` mentions `cron.db` at `.cline/data/db/`; the "alongside sessions.db" wording is in `paths.ts` for the connector DB, so that support is indirect. Still unresolved by observation. |
| Cline hooks: six events wired, five deferred, `~/Documents/Cline/Hooks`, `.clinerules/hooks`, SDK hooks filtered out, default on | confirmed | `hooks-adapter.ts` header, `disk.ts`, `hooks-utils.ts` (`userSetting ?? true`), `vscode-session-host.ts` lines 169-178. |
| Cline turn phases exist only as webview state | corrected | `TurnStateTracker` lives in the extension and pushes `TurnState` to the webview. No source shows persistence. Reworded as inferred from absence. |
| Cline OTel opt-in via `CLINE_OTEL_*`, metrics and logs, gRPC/HTTP | confirmed | `otel-config.ts` lines 158-165, `opentelemetry.mdx`, `opentelemetry_override.mdx`. |
| Roo sunset 2026-05-15, archived, last release v3.54.0 | confirmed | `gh api`: archived true, pushed 2026-05-15T18:08Z, release v3.54.0 2026-05-15T17:52Z; Marketplace 3.54.0; PR #12160 text. |
| Roo task store, events, 2 s timeout, IPC only with `ROO_CODE_IPC_SOCKET_PATH`, no telemetry or hooks | confirmed | Re-read `storage.ts`, `globalFileNames.ts`, `TaskHistoryStore.ts`, `events.ts`, `Task.ts` line 1347, `extension.ts` lines 237-293; repo tree (3573 paths) has no path containing telemetry, posthog or otel. Note `src/package.json` in main says 3.53.0 while the release tag and Marketplace say 3.54.0. |
| Kilo 7.8.1 is an opencode fork, spawn shape, Basic auth user `kilo` | confirmed | `server-manager.ts`, `serve.ts`, `auth.ts`; Marketplace `kilocode.Kilo-Code` 7.8.1 darwin-arm64, 2026-09-25. |
| Kilo status idle/busy/retry/offline; endpoints; DB path | corrected | Endpoints `/session/status`, `/permission`, `/question` and `kilo.db` under `~/.local/share/kilo` confirmed. The schema also has `scheduled`; added. |
| Kilo Keep Awake off by default, `/usr/bin/caffeinate -i -w <pid>`, busy or retry or wakeup | confirmed | `keep-awake.md`, `caffeination.ts` lines 72-105, `feed.ts`. Interpretation of the signal corrected, see above. |
| Kilo plugins, events, OTLP env vars, PostHog | confirmed | `plugins.md` lines 67-115, 374-449; `otlp.ts` (`/v1/traces`, `/v1/logs`); `kilo-telemetry/package.json` (posthog-node). |
| Probe splits args on spaces and drops the VS Code main process | confirmed | `agents_probe.py` `processes()`; synthetic run. |

### What remains inferred or unobserved

- No real `ps` line for the extension host, agent host or `kilo serve`; no `pmset` assertion name for Electron's blocker.
- Main executable name inside `Contents/MacOS` (Electron or Code); path matching makes it moot.
- Cline `running` during a pending approval and how promptly the row flips.
- Copilot Agent Host `events.jsonl` end-of-turn record names and write cadence.
- Insiders, VSCodium and Code - OSS helper and main paths.
- Whether `<extension>/bin/kilo` is a single binary or a launcher that re-executes.

### Files changed by this review

`registry/agents/vscode-agents.json` (path fix, process-spec repairs, signal meanings, source entries, notes) and this file. Nothing else was edited, committed or installed.
