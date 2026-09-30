# Superset: evidence notes (2026-09-30)

Row: `registry/agents/superset.json`. Validator: ok. Confidence `documented`. Superset is not installed here (`ls /Applications | grep -i superset`, `ls ~/.superset`, `ls ~/Library/Application\ Support | grep -i superset`, `which superset`, `ps`: all empty), so nothing was seen running. `tools/agents_probe.py --row` finds 0 sessions, as expected. Nothing was installed, run or messaged.

## Shape

```
Superset (Electron main)   /Applications/Superset.app/Contents/MacOS/Superset      bundle com.superset.desktop
 |                         (canary: "Superset Canary.app", com.superset.desktop.canary)
 |- Superset Helper (GPU|Renderer|...)     Contents/Frameworks, --type=...        (no match, on purpose)
 '- SAME Mach-O, ELECTRON_RUN_AS_NODE=1, script in Contents/Resources/app.asar/dist/main/
     |- host-service.js       per-org local HTTP/tRPC server, owns host.db, chat.db, hook endpoint
     |   '- pty-daemon.js      detached, started via /bin/sh exec, owns every PTY, survives restarts
     |       '- zsh -l         one login shell per terminal (node-pty)
     |           '- claude / codex / grok / ...   plain interactive TUI, argv has NO Superset marker
     '- terminal-host.js + pty-subprocess.js       older v1 terminal stack, still built

Headless host (CLI bundle):  superset start -> superset-host -> <root>/lib/node <root>/lib/host-service.js
```

Superset is a host. It has no model loop for terminal agents; "working" means a hosted agent is working. (It also has a built-in chat panel with its own store, see below.)

## What I checked

- Repo `superset-sh/superset` at `6130042` (2026-09-30, desktop 1.33.0), shallow clone in the scratchpad: `apps/desktop` (electron-builder configs, host-service coordinator, terminal-host client, bundled CLI, renderer status hooks), `packages/host-service` (daemon supervisor, events, terminal-agents store and schema, notifications router, chat-v3 mount), `packages/pty-daemon`, `packages/agent-setup` (hook writers, wrappers, `notify-hook.template.sh`), `packages/shared` (agent catalog, `agent-status.ts`), `packages/chat` and `chat-runtime`, `packages/cli` (start, status, DISTRIBUTION.md, build-dist), `HOOKS_INVESTIGATION.md`, `apps/docs/content/docs/*`.
- Web: `superset.sh`, `docs.superset.sh`, Homebrew cask `Casks/s/superset.rb` (v1.32.0), tap formula `superset-sh/tap` (v1.33.0).
- Greps over the whole tree for sleep assertions (`powerSaveBlocker`, `caffeinate`, `IOPMAssertion`): no hit. For OpenTelemetry (`opentelemetry`, `OTEL_EXPORTER`, `otlp`): no source hit.
- Probe check: ran `matches()` over synthetic command lines. Main app, canary, the three Node-mode helpers and the standalone host match. Electron helpers, a plain `node`, the `superset` CLI, Apache Superset's `superset` script do not. `claude` and `grok` launched inside Superset match `claude-code` and `grok-build`, not this row.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Executable | `Superset.app/Contents/MacOS/Superset`; canary `Superset Canary` (space) | electron-builder productName; cask `app "Superset.app"`. Mach-O name is the electron-builder default, inferred |
| Bundle ids | `com.superset.desktop`, `com.superset.desktop.canary` | `electron-builder*.ts`, cask `quit:` |
| Process to session | None in argv. Environment only: `SUPERSET_TERMINAL_ID` (= `terminal_agent_bindings.terminal_id`), `SUPERSET_WORKSPACE_ID`, `SUPERSET_AGENT_ID`. Ancestor chain agent -> shell -> pty-daemon (Superset Mach-O). Agent session id lands in `agent_session_id` (equals the agent's own id, so it joins to `~/.claude/projects/*/<id>.jsonl`) | `terminal/env.ts`, `agent-wrappers-common.ts`, `schema.ts` |
| Store | `~/.superset/host/<orgId>/host.db` (SQLite, WAL). Undocumented. Also `chat.db` beside it (built-in chat), `~/.superset/local.db` (v1), `manifest.json` (0600, holds the host auth token). No agent transcripts: those stay in each agent's own store | `host-service-coordinator.ts` 1033, `db.ts`, `chat-runtime` schema |
| Turn in progress | `terminal_agent_bindings.last_event_type = 'Start'` and `ended_at IS NULL`. Written by hook events: UserPromptSubmit, and re-asserted on every PostToolUse | `map-event-type.ts`, `agent-status.ts`, `store.ts` |
| Waiting on the human | `last_event_type = 'PermissionRequest'` (Claude `PermissionRequest`, Codex approval and `request_user_input`, Grok `permission_prompt` / `elicitation_dialog`). Built-in chat: `chat_sessions_local.status = 'awaiting_input'` | same, `notify-hook.template.sh`, `envelope.ts` |
| Finished | `Stop` (UI word: `review`), `Failed` for API-error stops, `Detached` ends the binding | `agent-status.ts` |
| Hooks | None of its own. Consumer only: writes into `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.grok/hooks/superset-notify.json`, `~/.factory/settings.json`, `~/.cursor/hooks.json` and others at every app start, plus `~/.superset/hooks/notify.sh` and PATH shims in `~/.superset/bin/` | `agent-setup`, `HOOKS_INVESTIGATION.md` |
| OpenTelemetry | No. Sentry and PostHog | greps, `apps/desktop/package.json` |

## Could not determine

- Real `ps` output for any Superset process. Not installed. The Node-mode helper argv shape (app Mach-O as argv[0], script under `app.asar/dist/main/`) is read from `spawn()` calls and the electron-builder file list. On macOS the host-service goes through node-pty's `spawn-helper`; that its exec leaves the app binary as argv[0] is inferred.
- The Mach-O name and Electron helper names (electron-builder defaults, not read from a bundle). I did not download the DMG: that is more than a read-only check.
- Idle and busy CPU. The 10 percent floor and the 20 s WAL window are guesses.
- How long `host.db` lags a turn. Every hook event upserts, so the WAL should move on each tool call, but a long model call with no tool leaves it quiet (inferred from code, not measured).
- Whether the Homebrew `superset-host` symlink layout resolves `../lib/node`: the wrapper takes `dirname $0` without following symlinks. Only `--version` is tested in the formula.
- Where the packaged app finds the Claude binary for the built-in chat. The source says packaged builds are "an open IOU" and only dev resolves it. The chat panel is behind the `chat-v3` PostHog flag, so whether it is on for a given user is unknown.
- What a live hook payload looks like end to end (nothing ran).

## Contradicts common belief or the hint

- "Orchestrator that runs many agents" is true, but the process table shows one app tree, not one process per task. The app, host-service, pty-daemon and v1 helpers share ONE executable, so a name match counts about four "Superset" processes; the probe's outermost rule folds them, and the daemon surface scores 1 higher (args_contain) so a helper is labelled daemon, not gui.
- The agents are not children of Superset and carry no Superset flag. They are ordinary interactive TUIs, descendants through shell and pty-daemon. The existing `claude-code` and `grok-build` rows already see them, and their own caffeinate child or assertion is a real per-session signal here. This is the opposite of Conductor (headless children) and of the advice in README case 15 to drop a match under a registered host. I chose not to drop them.
- pty-daemon is started detached so it outlives host-service and can be orphaned to launchd: after a crash a Superset PTY host can sit outside the app's tree with terminals and agents still alive under it.
- Superset holds no sleep assertion and has no `caffeinate` child. "Workspaces keep running when your laptop sleeps" is about remote hosts, not a local wake lock.
- Status only works for agents launched inside a Superset terminal, but the hooks are registered globally, once, and stay after uninstall. Every Claude, Codex, Grok, Droid and Cursor session on the Mac has Superset entries; they no-op unless `SUPERSET_TERMINAL_ID` or `SUPERSET_TAB_ID` is set. `HOOKS_INVESTIGATION.md` says Droid, Codex, Mastra, Cursor, Gemini and Copilot were unguarded in an older build; the guard in the current hook template is at script level, so the leak there is closed.
- After a user interrupt (Esc, Ctrl+C) Claude Code fires no Stop hook, so `host.db` keeps `Start` until the desktop renderer clears it. Read with the app closed or in the background, the row can say working for a finished turn. Force-quit does the same (docs: "Clear Status").
- Waiting is not universal. The docs say some agents report only completion; for those a permission wait reads as working. Superset launches Claude with `--dangerously-skip-permissions` and Grok with `--always-approve`, so permission prompts are rare there and question dialogs are the usual wait.
- The `superset` CLI is not the harness. It is a client that exits per command, and `superset` is also Apache Superset's CLI, so it is left out of the row. Apache Superset (BI tool) is unrelated.
- Source-available under ELv2, not open source (the docs say so themselves).

## Grok Bot (asked for in the request)

Grok Bot is not a Superset surface and there is no Grok Bot code in the Superset repo. Superset's own compare pages (`apps/marketing/content/compare/superset-vs-grok-bot.mdx` and `grok-bot-alternative.mdx`, dated 2026-09-11 / 2026-09-24, vendor marketing, so treat as third-party) describe it as xAI's always-on "teammates" on one persistent cloud computer per account, announced 2026-08-11, in beta, US-only, running on Cursor-hosted Firecracker microVMs with Cursor choosing the model; desktop app on macOS, Windows and Linux plus iOS and Android. If that holds, it is a `cloud` surface with no local agent process, so a Mac detector can only see the desktop client and can report no turn state (README case 19). It needs its own row and evidence file; I was limited to the two Superset files and did not write it. Do not confuse it with Grok Build (`grok-build` row), the CLI that Superset launches as `grok --always-approve`; that one is a real local process and its sessions are server-side, which Superset itself says it cannot inspect.

## Verification

Adversarial re-check on 2026-09-30 by a second pass that did not write the row. Method: fresh shallow clone of `superset-sh/superset` at `6130042` (same commit the row cites), every source re-read against the claim it backs, docs and cask and formula re-fetched, local commands re-run, `matches()` from `tools/agents_probe.py` run over synthetic argv. Validator: `ok` before and after. Confidence stays `documented` (ceiling: the harness is not installed here). Row edits: `host: true` on all three surfaces, and the fixes marked "corrected" below.

### Claims

| Claim | Verdict | Note |
|---|---|---|
| appId `com.superset.desktop`, productName `Superset`; canary `com.superset.desktop.canary`, `Superset Canary` | confirmed | `electron-builder.ts` 27-28, `electron-builder.canary.ts` 16, 23-24, `package.json` productName |
| Mach-O is `Contents/MacOS/Superset` (canary `Superset Canary`) | unsupported, inferred | Electron-builder default for macOS. The only explicit `executableName` in the config is `"superset"` under `linux:` (line 157), so it does not apply. Never read from a bundle |
| Electron helpers are `Superset Helper*.app` under `Contents/Frameworks` | unsupported, inferred | Same default; not read from a bundle. The row's match is safe either way, because the app path requires `Contents/MacOS/` directly after the app name |
| Cask installs `Superset.app`, quits `com.superset.desktop`, version 1.32.0; tap formula 1.33.0 | confirmed | Re-fetched both files. Side fact: the formula declares `license "MIT"`, the repo is Elastic-2.0 (`LICENSE.md`, root `package.json`, `overview.mdx` says "source-available ... Elastic License 2.0"). Unexplained, harmless for detection |
| Not installed here | confirmed | Re-ran the five commands, all empty or "No such file or directory"; probe finds 0 sessions |
| Host-service spawn: app Mach-O in Node mode through node-pty `spawn-helper`, `dist/main/host-service.js`, `HOST_DB_PATH` | confirmed (line numbers corrected) | Spawn block is 899-925, not 904-913. That `spawn-helper` execs with argv[0] = the app binary is still inferred (helper is a compiled node-pty file, not in the repo) |
| pty-daemon: `/bin/sh -c 'ulimit ...; exec "$@"' sh <execPath> <script> --socket= --buffer-bytes=`, detached, survives host-service | confirmed | `DaemonSupervisor.ts` 1260-1285; script sits next to `host-service.js` (`singleton.ts` 28-30). It inherits `ELECTRON_RUN_AS_NODE=1` from host-service's env |
| v1 stack `terminal-host.js` + `pty-subprocess.js`, same binary | confirmed | `client.ts` 1305, 1373-1381; `electron.vite.config.ts` 128-145 |
| No argv marker links an agent to a Superset terminal; link is env only | confirmed for Claude, corrected for Codex | Claude is exec'd in place. Codex is not: `~/.superset/bin/codex` is a bash wrapper that stays as codex's parent and adds `--enable hooks --dangerously-bypass-hook-trust`. Weak hint, not a marker (presets and users pass it too). Added to notes |
| Env vars `SUPERSET_TERMINAL_ID`, `SUPERSET_WORKSPACE_ID`, `SUPERSET_HOME_DIR`, `SUPERSET_HOST_AGENT_HOOK_URL`, wrapper `SUPERSET_AGENT_ID` first-wins | confirmed | `env.ts` 257-290, `agent-wrappers-common.ts` |
| Events normalise to Start, Stop, PermissionRequest, Failed, Attached, Detached; UI Start=working, PermissionRequest=permission, Failed=failed, Stop=review | confirmed | `map-event-type.ts`, `agent-status.ts`, `trigger.ts` line 5 |
| `last_event_type` can hold `Detached` | corrected | `Detached` (and pty exit) goes through `endBinding`: it sets `ended_at` and `end_reason` and never writes `last_event_type`. `Attached` is stored only for a new binding; on a bound session it keeps the prior value. Row text fixed |
| Table `terminal_agent_bindings` columns, upsert on every event, WAL | confirmed | `schema.ts` 53-82 (also has `ended_at`, `end_reason`, `resumed_into_terminal_id`, `transcript_path`), `store.ts` 151-240, `db.ts` 36 |
| Interrupt fires no Claude Stop hook; renderer clears to Stop | confirmed | Header comment of `useTerminalInterruptClear.ts` says exactly this; `clearWorkspaceStatuses` in `store.ts` 399 |
| Hook script no-ops without `SUPERSET_TERMINAL_ID`/`SUPERSET_TAB_ID`, drops foreign harness events, maps Codex and Grok names, posts to the env URL then every manifest endpoint, unauthenticated | confirmed | `notify-hook.template.sh`; `env.ts` comment "the endpoint is unauthenticated by design" |
| Grok waits: only `permission_prompt` and `elicitation_dialog` forwarded | confirmed | Template and `agent-wrappers-grok.ts` 43-51 |
| Codex waits: `request_user_input` via PreToolUse, plus `exec_approval_request` and `apply_patch_approval_request` | confirmed, mechanism added | The approval ones do not come from hooks.json. A watcher inside the codex wrapper tails Codex's TUI session log and emits `PermissionRequest` on any `*_approval_request"` line, so only Codex started through `~/.superset/bin/codex` reports them |
| Claude hook list in `~/.claude/settings.json` | corrected | List was right for the notify hooks but missed a `PreToolUse` entry with matcher `Artifact` (artifact-guard script). Added |
| Hooks written "at every desktop start" | corrected | Also by the standalone host at start (`serve.ts` 63 `provisionAgentIntegrations`). Added |
| "Nothing removes them on uninstall" | unsupported, inferred | Code has `removeClaudeManagedHooks` and a per-agent toggle, and the cask `zap` list does not touch `~/.claude`, `~/.codex` or `~/.grok`. No uninstaller was inspected. Stays as an inference |
| Superset launches `claude --dangerously-skip-permissions` and `grok --always-approve` | confirmed | `builtin-terminal-agents.ts` 65, 186 |
| Docs: status from hooks and wrappers, Claude reports finished and waiting, some agents only finished, per-agent toggle, no-op outside Superset | confirmed | Re-fetched `docs.superset.sh/agent-status` and `/agent-integration` |
| Built-in chat: `chat.db`, `chat_sessions_local.status` values, claude-code and codex adapters, packaged Claude binary unresolved | confirmed | `mount.ts` 35-46, `envelope.ts` 5-13, `host-service-coordinator.ts` 1046-1051 ("Packaged builds are an open IOU") and `chatV3ClaudeBin()` returns `undefined` when packaged |
| Superset holds no sleep assertion | confirmed | Grep for `powerSaveBlocker`, `caffeinate`, `IOPMAssertion`, `prevent-app-suspension`, `prevent-display-sleep` over `apps` and `packages`: no hit |
| No OpenTelemetry; Sentry and PostHog | confirmed | Grep hit only two plan HTML files and two cursor SVGs; `@sentry/electron 7.16.0`, `posthog-js`, `posthog-node` in `apps/desktop/package.json` |
| Headless bundle layout, `superset-host` wrapper execs `lib/node lib/host-service.js`, Node 22 | confirmed | `DISTRIBUTION.md`, `build-dist.ts` 46, 393-398. `superset start` runs `dirname(process.execPath)/superset-host` (`spawn.ts`), so the symlink worry only applies to calling the Homebrew `superset-host` symlink by hand. Whether Bun's `process.execPath` is the real path is untested |
| Marketing quotes on `superset.sh` | confirmed | Re-scraped: "One workspace for Claude Code, Codex, and any coding agent", `~/.superset/worktrees/superset/cloud-ws`, "Local First: Repos, worktrees, terminal output, and agent sessions stay on your machine" |
| `SUPERSET_HOME_DIR` moves `~/.superset`; dev builds `~/.superset-<workspace>` | confirmed | `app-environment.ts` 6-9, `shared/constants.ts` 11-13 |
| `manifest.json` mode 0600 holds the auth token | confirmed | `host-service-manifest.ts` line 40 (`mode: 0o600`), `authToken` field |
| `host.db-wal` mtime as a raise signal (20 s) | corrected, still weak | Window is a guess. Added that the host also writes on a 5 minute pull-request sync timer and on workspace or terminal creation, so a fresh WAL can be a false raise. The `tree_cpu` 10 percent floor is a guess too, and includes every shell, dev server and build the user runs in a Superset terminal |
| `agents_probe` cannot evaluate the WAL signal | confirmed | `transcript_write` needs `session_store.per_session`; the row has only `glob` |
| Grok Bot: xAI's always-on teammates, announced 2026-08-11, Cursor-hosted, not a Superset surface | confirmed, sourced | The row had no source for it and cited vendor marketing in the evidence. Now backed by `x.ai/news/introducing-grok-bot` (dated Aug 11, 2026, beta, desktop and iOS), `docs.x.ai/grok-bot/overview` ("The computers Bots work on run in Cursor's cloud"; macOS Apple silicon and Intel, Windows, Linux, iPhone, iPad, Android) and `docs.x.ai/grok-bot/teams-and-enterprises` (Firecracker microVM per user). Repo grep for "grok bot": only the two compare pages |
| Grok Bot is US-only and Cursor picks the model | unsupported | Appears only in Superset's compare pages (a competitor). Dropped from the row notes. Not found in the xAI pages that were read |
| Grok Bot has no local process | corrected | Docs: a Bot runs commands on the user's own computer when a local-computer capability is enabled and approved. Its desktop app is a local process. Bundle id and process name not verified, so no row or surface was written; needs its own row |

### Process patterns (false-positive check)

Ran `matches()` on synthetic argv. Match: `/Applications/Superset.app/Contents/MacOS/Superset` (gui, 38), `Superset Canary` (gui, 52), the same binary with `.../app.asar/dist/main/host-service.js` (daemon 39, beats gui 38, so it is labelled daemon), headless `<root>/bin/../lib/node <root>/bin/../lib/host-service.js` (11). No match: `Superset Helper (Renderer)`, the bundled CLI under `Contents/Resources/resources/bin/superset`, `node server.js`, Apache Superset's `superset run -p 8088`, `/opt/x/lib/node other.js`, `claude "fix /lib/host-service.js"`, a `Grok Bot.app` path. The probe reads the real argv from the kernel, so the space in `Superset Canary` is not a problem. Residual: `path_contains "/lib/node"` is a substring, so `/opt/homebrew/lib/node_modules/x/bin/x` plus an argument containing `/lib/host-service.js` would match; nothing real does that. In dev (`bun dev`) the binary is `Electron.app/.../Electron`, not matched, by design. Outermost-process rule folds host-service and pty-daemon into the app while the app is their ancestor; an orphaned pty-daemon (parent launchd) shows as its own daemon entry, as the row says.

### Left unproven

- Real `ps` lines, Mach-O and helper names, and whether `spawn-helper` leaves argv[0] as the app binary.
- Any timing: WAL lag, 10 percent CPU floor, 20 s window.
- Whether a Homebrew-installed `superset-host` resolves `lib/node` when invoked through the symlink (`superset start` does not use the symlink).
- Grok Bot on this Mac: no app installed, so nothing was checked.
