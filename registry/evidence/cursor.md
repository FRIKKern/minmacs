# Cursor evidence notes (2026-09-29)

Installed here: Cursor.app 3.15.6 (bundle `com.todesktop.230313mzl4w4u92`), `cursor-agent` CLI 2025.12.17-996666f (old; docs now call it `agent`).
Nothing agent-related was running, so every "working" claim below comes from source, logs and docs, not from watching a live turn.

## Shape

```
Cursor.app/Contents/MacOS/Cursor  (one Electron main, ppid 1)
 |- Cursor Helper (Renderer/GPU/Plugin), shared-process, mcp-process, terminal pty-host
 |- agent runs in an "AgentExec" extension host (extensions/cursor-agent-host, cursor-agent-exec)
 '- Agents Window = another window of the same process, not a second app

~/.local/bin/cursor-agent -> .../cursor-agent/versions/<v>/cursor-agent (bash) --exec--> .../versions/<v>/node index.js
Cloud / background agents: Cursor VMs, no local process
```

## What I checked

- Read-only: `ps`, `plutil`, `pmset -g assertions`, `ls`, `sqlite3` opened `mode=ro&immutable=1`, `strings`, grep over the app's bundled JS. Printed key names and counts only, no message content.
- Docs fetched: hooks, third-party-hooks, cli/overview, agents-window, cloud-agent API, enterprise OpenTelemetry export.
- Probe: `tools/agents_probe.py --row registry/agents/cursor.json` gave one row: `Cursor ide pid 70991 idle cpu 1.0 kids 6`. That is correct (app open, no turn), but it says nothing about the working path.

## Probe run

```
harness  surface pid    state   cpu  kids why  project
Cursor   ide     70991  idle    1.0  6         /
1 agent sessions: 0 working, 1 idle
```
The CLI surface matched nothing (no CLI running). The `cloud` surface has no process spec by design.

## Best signal for "a turn is in progress"

IDE and Agents Window: Cursor's own wakelock. In the bundled `workbench.desktop.main.js`, `ComposerWakelockManager` starts an Electron `powerSaveBlocker('prevent-app-suspension')` at the start of every local chat turn and releases it on `generation-ended`. Real logs confirm it: `~/Library/Application Support/Cursor/logs/20260609T181642/` has 10 `Acquired ... reason="agent-loop"` and 10 `Released ... reason="generation-ended"` lines, with `composerId` on each. Not created for background/cloud agents.

## Waiting on the human

- Same manager releases the wakelock with `reason="user-approval-requested"` when the chat's `hasBlockingPendingActions` turns true, and retakes it with `agent-loop-resumed`. One release and one resume seen in the June log. So "wakelock absent while chat exists and last log line is user-approval-requested" means blocked on you.
- `hasBlockingPendingActions` is also a key in `composerHeaders.value` in `state.vscdb`. Not checked whether it is flushed live.
- Hooks: no Notification or idle event. `beforeShellExecution` / `beforeMCPExecution` can answer `ask`, but that is a decision hook, not a "waiting" notification.

## Could not determine

- The exact name/type `pmset -g assertions` shows for the Cursor wakelock (Electron `prevent-app-suspension` normally appears as a PreventUserIdle...Sleep assertion, name unverified). Needs a live turn.
- The exact `ps` line for a running CLI, and whether `store.db` mtime moves during a turn (so `transcript_write` is marked unverified).
- Whether newer `agent` CLI builds (this one is 3 months old) add a power assertion, `agent-transcripts`, or hooks behaviour. Only event-name strings for hooks were seen in this old bundle.
- Per-chat process mapping for the IDE: impossible from the process table; all chats share one process. Only log lines carrying `composerId` and hooks (`conversation_id`) identify a chat.
- Whether the wakelock is logged in current 3.15.6 sessions: no agent turn appears in the 2026-07-24 or 2026-09-29 log dirs, so the last confirmed log evidence is June (an older 3.x).
- `agent acp`, `agent -p` headless and cloud `IDLE/ACTIVE` were read from docs only. Cursor tunnel (`bin/cursor-tunnel`) and `cursorsandbox` helper (`Resources/app/resources/helpers/`) exist but were not tested as process markers.
- Project-level `.cursor/hooks.json` files across repos were not searched. `~/.cursor/hooks.json` does not exist.
- Third-party-hooks page came through an extractor, so the full Claude Code mapping table was not read.

## Contradicts common belief

- There is no `cursor-agent` process for the IDE agent. The IDE agent lives inside the Electron app (extension host); `cursor-agent` is only the terminal CLI, and its process is called `node`, not `cursor-agent`.
- The Agents Window is not a separate app or bundle (Cursor 3, 2026-04-02); it is a window of Cursor.app.
- Cursor does not export OpenTelemetry locally. The OTEL_* strings in the CLI bundle are just the OTel JS SDK. The real feature is Enterprise-only, server-side, metrics and logs, no traces, and does not include IDE/CLI message text.
- Cursor supports hooks (about 21 events, `~/.cursor/hooks.json`, and it reads Claude Code hook files), but has no equivalent of Claude Code's `Notification`, so "waiting for me" cannot come from hooks.
- Chats are not in a plain per-session file. IDE chats sit in one 1.2 GB SQLite (`state.vscdb`, 160 `composerData` rows; `status` held only none/completed/aborted and `generatingBubbleIds` was empty in every row at rest, so do not expect a live "running" status there). Only 2 of them also have `agent-transcripts/*.jsonl`. The CLI uses per-chat `store.db`, keyed by md5 of the cwd, not by session id alone.
- The probe cannot use `--resume=<id>` (docs form); it only reads `--resume <id>`. The probe's `tree_cpu` is the whole Electron tree for the IDE, so it is noisy there. The probe ignores `power_assertion`, `waiting_signals` and log lines, so the row's best signals need the Objective-C detector to implement them.
- `tool_children` and `child_process` were left out on purpose: the probe applies signals row-wide and Electron helpers are always children of the IDE process, so they would mark the IDE as always working.

## Verification

Adversarial re-check on 2026-09-29. Every claim in the row was re-run or re-fetched. Status: confirmed, corrected, or unsupported. Confidence stays `documented`: no agent turn was running, so the working signals are still not seen live.

Validator: `tools/validate_row.py registry/agents/cursor.json` printed `ok`. Probe: one row, `Cursor ide pid 70991 idle cpu 0.8 kids 6`. `ps` agrees: main Cursor at 0.5%, helpers 0.0-0.3%, no window helpers, no agent activity. The idle call is believable. It says nothing about the working path, because the probe ignores `power_assertion`, `waiting_signals` and log lines.

### Process patterns (false positives)

- IDE `path_contains /Cursor.app/Contents/MacOS/Cursor`: confirmed against `ps`. Helpers, crashpad, ShipIt and the system `CursorUIViewService` do not match, because helper argv[0] contains a space or lives under Frameworks.
- CORRECTED: `cursor <path>` (bin/cursor) runs `ELECTRON_RUN_AS_NODE=1 .../MacOS/Cursor .../out/cli.js`. That is the same executable, its parent is a shell, so it matched as a second "ide" session. Added `exclude_args` with the cli.js path. Exact-token match, so it covers `/Applications` installs only. Tested with the probe's own `matches()` on synthetic argv: main matches, launcher, helper and Claude Code do not.
- CLI `path_contains .../cursor-agent/versions/`: confirmed with a live sample. While `cursor-agent --version` ran, `ps` showed `<dir>/node --use-system-ca <dir>/index.js --version`. `rg` and `spawn-helper` live in the same dir but have a matching parent, so the probe's outermost rule drops them.
- CORRECTED: added `-v` and `-h` to CLI `exclude_args` (both in `--help`).
- UNSUPPORTED as a fix, left open: subcommands (login, logout, mcp, status, whoami, update, upgrade, create-chat, ls, resume) still show as brief idle sessions. Excluding them by token would hide a real session whose unquoted prompt contains "login" or "status".
- `tree_cpu` (floor 10): downgraded in `meaning`. The floor was never measured against a turn, and the IDE tree includes the integrated terminal, so builds or another agent in Cursor's terminal can false-positive.

### Claims

- Bundle id, executable, version 3.15.6, product.json fields: confirmed (`plutil`, `product.json`). Only one Cursor bundle in /Applications.
- Running IDE process and helpers: confirmed. Helper list is gpu, network, shared-process, mcp-process, audio, terminal pty-host.
- Agents Window is a window of the same app, GA with Cursor 3 on 2026-04-02: confirmed (docs re-fetched).
- CLI is a bash launcher exec'ing node on index.js; `--version` 2025.12.17-996666f: confirmed, plus live `ps` line. A real interactive session's `ps` line is still unobserved.
- CLI docs use `agent` and `--resume="chat-id"`: confirmed. This old build prints `--resume [chatId]` and has a `cursor-agent` name. Both spellings appear in the bundle.
- CLI store `~/.cursor/chats/<md5 cwd>/<chat id>/store.db`, tables blobs and meta, meta keys agentId, latestRootBlobId, name, mode, createdAt, lastUsedModel: confirmed. md5 of the cwd matches the folder. One chat, dated 2025-12-18.
- CLI takes no power assertion and never spawns caffeinate: confirmed for this one old build only (grep over all `*.js` printed nothing).
- Wakelock logic in the IDE bundle: confirmed. The constructor acquires `agent-loop` unless `hasBlockingPendingActions`. The watch releases with `user-approval-requested` and re-acquires with `agent-loop-resumed`. `dispose` releases with `generation-ended`. It is built only when `!createdFromBackgroundAgent?.bcId`. main `startWakelockForOwner` calls `powerSaveBlocker.start("prevent-app-suspension")`.
- Log counts: confirmed. 10 `agent-loop`, 1 `agent-loop-resumed`, 10 `generation-ended`, 1 `user-approval-requested` across the renderer logs in `20260609T181642`; main.log has 11 `Started wakelock` lines. Log format is `Acquired wakelock id=N reason="..." composerId=...` (an `id=` field sits before `reason`); patterns built from the row's `waiting_signals.pattern` text need to allow it. No such lines in the 2026-07-24 or 2026-09-29 log dirs.
- No Cursor assertion while idle: confirmed again (`pmset -g assertions` shows Chrome, caffeinate, Insomnia, none from Cursor). The assertion's type and name during a turn stay unobserved.
- `state.vscdb` (about 1.2 GB), tables, key-prefix counts: confirmed. CORRECTED: `status` is none (90), completed (49), aborted (7), and absent in 14 rows. `generatingBubbleIds` exists in 146 rows and is empty in all. `conversationState`, `subagentComposerIds`, `stopHookLoopCount` are only in some rows. `composerHeaders` has 14 rows, not one per composer (8 carry `hasBlockingPendingActions`, none true).
- Plain transcripts `~/.cursor/projects/<slug>/agent-transcripts/<id>/<id>.jsonl`, keys role and message.content: confirmed, 2 files, incomplete store.
- Hooks: 21 event names, config locations, priority, stop status values, `transcript_path`: confirmed against the docs.
- Notification hook not mapped: confirmed. CORRECTED: the full table is now read. `PermissionRequest` is not mapped either, and eight events are mapped.
- Cloud agent hooks: CORRECTED. Also unsupported in cloud: `workspaceOpen`. On self-hosted workers `sessionStart` and `sessionEnd` do fire.
- Cloud status ACTIVE/IDLE/ARCHIVED, ids `bc-<uuid>`: confirmed (docs, via extractor).
- OpenTelemetry: confirmed. Enterprise, server-side, OTLP/HTTP protobuf, `/v1/metrics` and `/v1/logs`, no traces, IDE and CLI conversation content not covered. OTEL strings in the CLI bundle are the JS library.
- No hooks configured here: confirmed for `~/.cursor/hooks.json`. Project-level files not searched.

### Still unsupported

- Any live "working" behaviour: the wakelock in `pmset`, CLI `store.db` mtime moving during a turn (`transcript_write` is unverified), CPU during a turn.
- Newer `agent` CLI builds: only the 2025.12.17 bundle was inspected.
