# OpenClaw evidence notes (2026-09-29)

Confidence: documented. The gateway is installed but not running, so the probe classified nothing live.

## What I checked

- Install: `openclaw --version` gives 2026.4.29 (a448042). Binary is a symlink /opt/homebrew/bin/openclaw -> .../lib/node_modules/openclaw/openclaw.mjs. Upstream is newer (update-check.json says 2026.7.1-2). Everything below is for 2026.4.29.
- The npm package ships its own docs (/opt/homebrew/lib/node_modules/openclaw/docs), so official-docs claims were read locally and cite docs.openclaw.ai paths. Also read `dist/` for process title, session lock, claude-cli spawn args.
- Gateway: `launchctl print gui/501/ai.openclaw.gateway` says not running, runs = 0. `ps`, `lsof -iTCP:18789` find nothing. No OpenClaw.app in /Applications.
- State dir ~/.openclaw: sessions in agents/main/sessions (1 session, last written May 4), config openclaw.json (key names only, token redacted), logs/gateway.log (only structural lines grepped).
- Probe: `tools/agents_probe.py --row registry/agents/openclaw.json` prints an empty table, "0 agent sessions: 0 working, 0 idle". Validator: `ok`.

## Surfaces and how to recognise them

| Surface | Process (title) | Notes |
|---|---|---|
| Gateway daemon | `node .../openclaw/dist/index.js gateway --port 18789` (full args, never retitled; corrected in Verification, the earlier `openclaw-gateway` claim was wrong for the daemon) | launchd label `ai.openclaw.gateway`, plist ~/Library/LaunchAgents, WS+HTTP 127.0.0.1:18789 |
| TUI / one-shot | `openclaw-tui`, `openclaw-agent` (terminal and chat are aliases of tui, so no `-terminal`/`-chat` title exists) | clients; `--local` runs the loop in-process |
| ACP bridge | `openclaw-acp` | IDE launches it over stdio |
| Node host | `openclaw-node` | headless, for remote gateways |
| macOS app | bundle id `ai.openclaw.mac` (`.debug` for dev builds) | menu bar, not installed here, never runs turns |
| Channels | not processes | Telegram, Discord, Slack, WhatsApp, iMessage and more live inside the gateway |

Title rule (src/cli/program/preaction.ts, dist/program-BrS1V7cf.js:46): `process.title = "<cli>-<top-level command>"`, applied only when the full commander program is built. The gateway run fast path skips it (see Verification).

## Session mapping and stores

- One gateway serves all sessions, so there is no process-to-session mapping. Report the gateway's state, list sessions from the store.
- ~/.openclaw/agents/<agent>/sessions/sessions.json (dict keyed by session key, e.g. `agent:main:main`; row has status, startedAt, endedAt, updatedAt, runtimeMs, abortedLastRun, sessionFile, claudeCliSessionId), `<sessionId>.jsonl` (pi-style tree: header, then `message` records with id/parentId), `<sessionId>.trajectory.jsonl` (events session.started, prompt.submitted, model.completed, session.ended), `.trajectory-path.json`. Documented for sessions.json and jsonl; trajectory documented at /tools/trajectory.
- Only key names of one record per file were printed. No content read.
- Status values seen in source: running, done, failed, timeout. The one stored row says failed (May 4).

## Working signal, most precise first

1. `<session>.jsonl.lock` exists with a live pid in its JSON (dist/session-write-lock-*.js: created at run start, removed at end, stale if pid dead/recycled). Not observable now. Cannot be expressed in the schema's signal enum, so it is in the row's transcript_write meaning text.
2. Gateway lifecycle events `start|end|error` per run over the WS (needs a WS client and the token). Or OTel `openclaw.session.state` if enabled.
3. jsonl or trajectory.jsonl mtime within ~20 s (row: transcript_write).
4. With the claude-cli runtime (this install): caffeinate under the gateway's `claude` child (row: child_process). Inferred from the claude-code row, not observed.
5. Gateway tree CPU (weak).

## Waiting on the human

- Only `exec.approval.requested` / `exec.approval.resolved` (and `plugin.approval.*`) gateway events. The human answers on a chat channel, the Control UI or the macOS app. Nothing on disk or in ps. Here `tools.exec.ask=off`, `security=full`, so it never prompts.

## Hooks

- Internal hooks: HOOK.md + handler.ts, enabled through `hooks.internal` in ~/.openclaw/openclaw.json; events are command:*, session:compact:*, session:patch, agent:bootstrap, gateway:startup/shutdown/pre-restart, message:*. Typed plugin hooks (before_tool_call, agent_end, session_start/end, gateway_start/stop) are code-registered by plugins. No Notification-style hook exists.

## OpenTelemetry

- Yes, via the bundled `diagnostics-otel` plugin, OTLP/HTTP protobuf only (grpc ignored), off by default, content capture opt-in. Not enabled here.

## Could not determine

- What a real gateway's `ps` shows. Resolved by source reading in Verification: the launchd gateway is not retitled. Still never observed live.
- Whether caffeinate really appears under the gateway's claude child; the gateway never ran during my checks.
- The `ai.openclaw.node` launchd label and the exact `.app` executable path (docs give bundle id and `dist/OpenClaw.app` only). The row has no process spec for the app for this reason.
- Behaviour of newer releases (2026.7.x).
- Whether the session lock is held across the whole turn in all runtimes (docs say so; code read is partial).

## Contradicts common belief

- "OpenClaw is an app": there is no required GUI. The unit is one launchd Node daemon; the menu bar app is optional and does not spawn it.
- Loaded is not running: this Mac has the LaunchAgent loaded with runs = 0 (RunAtLoad and KeepAlive both false), so "installed" and "present in launchctl" do not mean a gateway exists.
- Working does not need a human: heartbeat (30 m / 1 h) and cron start turns unattended, so transcript activity with no client attached is normal.
- OpenClaw can be Claude Code underneath: with `agentRuntime.id=claude-cli` the gateway keeps a real `claude` process per session (flags `--input-format stream-json --output-format stream-json --permission-prompt-tool stdio --replay-user-messages`). The claude-code row will match those too. Detectors should drop a `claude` whose parent is an openclaw gateway, otherwise the same work is counted twice and, for an idle live session, shown as an idle Claude Code agent. The `claude` child also idles for ~10 min after a turn, so its existence is not a working signal.
- Any `openclaw gateway status|health|call|install` also retitles itself `openclaw-gateway` for its short life. Confirm a real gateway by the 18789 listener or the launchd job.
- ~/.openclaw/wake, wake-venv and logs/wake*.log on this Mac are a local Python voice-wake add-on, not part of upstream OpenClaw. Ignored.

## Verification

Verifier pass, 2026-09-29. Method: `tools/validate_row.py`, re-ran every local command, read the shipped package source (`/opt/homebrew/lib/node_modules/openclaw/dist`), fetched the live docs at docs.openclaw.ai, and ran synthetic processes through `tools/agents_probe.py --row`. No real OpenClaw process exists on this Mac, so nothing is verified-locally. Confidence stays `documented`, scoped to the installed 2026.4.29.

Validator: `ok registry/agents/openclaw.json` before and after the repair. Probe on the real machine: `0 agent sessions: 0 working, 0 idle`, matches the row.

### Confirmed

- Install: `openclaw --version` prints `OpenClaw 2026.4.29 (a448042)`; `/opt/homebrew/bin/openclaw -> ../lib/node_modules/openclaw/openclaw.mjs`; `update-check.json` lastAvailableVersion 2026.7.1-2.
- LaunchAgent `ai.openclaw.gateway`: `launchctl print` says state = not running, runs = 0, arguments wrapper, node v22.22.2, `dist/index.js`, `gateway --port 18789`. Plist has KeepAlive 0 and RunAtLoad 0. The wrapper script ends in `exec "$@"`, so the job is the node process itself. `lsof -iTCP:18789` empty, no OpenClaw.app in /Applications.
- Bundle ids `ai.openclaw.mac` and `.debug`, `dist/OpenClaw.app`: present in local docs platforms/mac/permissions.md and signing.md. The live macOS page no longer names them.
- macOS app is a menu bar companion (live page, "OpenClaw menu bar companion") and the local 2026.4.29 doc says it does not spawn the gateway as a child.
- Node `process.title` replaces the ps args on macOS: reproduced with nvm node 22.22.2, ps printed `openclaw-gateway` only.
- claude-cli runtime: `agents.defaults.agentRuntime.id = claude-cli`, model `anthropic/claude-opus-4-7`. Backend command is `claude`; live args include `--input-format stream-json --output-format stream-json --permission-prompt-tool stdio --replay-user-messages` (claude-live-session-DMjCNM6M.js:383). gateway.log shows live session start, turn, then close `reason=idle` ten minutes later.
- One record per file, key names: sessions.json rows carry status, startedAt, endedAt, updatedAt, runtimeMs, abortedLastRun, sessionFile, claudeCliSessionId, cliSessionBindings. Header keys cwd,id,timestamp,type,version.
- Hooks: every internal and plugin event name in the row was found in the local docs. `openclaw hooks --help` lists check/disable/enable/info/install/list/update. Config key `hooks.internal`, dirs and HOOK.md + handler.ts confirmed.
- Waiting: `exec.approval.requested` and `.resolved`, `exec.approval.list`, `plugin.approval.*` in docs/gateway/protocol.md and tools/exec-approvals.md. `exec-approvals.json` defaults are ask=off, security=full; openclaw.json tools.exec ask=off.
- OpenTelemetry: `diagnostics-otel` plugin, OTLP/HTTP protobuf, off by default; live model-calls-and-metrics page names `openclaw.tokens`, `openclaw.run.duration_ms`, `openclaw.queue.depth`, `openclaw.session.state`. Not enabled here: openclaw.json has no diagnostics key and plugins.entries lists only anthropic.
- Agent loop: serialized per-session runs, lifecycle end/error, `agent.wait` (live agent-loop page).
- `tui --session <key>`, `--local`, `acp` (ACP over stdio for IDEs), `node run|status|install|start|stop`: from `--help` and docs/cli/acp.md, cli/node.md.
- Session write lock file `<session>.jsonl.lock` with pid, createdAt, starttime, stale if pid dead: source read in dist/session-write-lock-Cij7epjy.js. No lock file present now.
- Probe result 0 sessions: reproduced.

### Corrected

- Process title of the gateway (the main error). The row said the daemon shows as `openclaw-gateway`. Source says otherwise: `setProcessTitleForCommand` is registered only inside `buildProgram` (program-BrS1V7cf.js:108), and `runCli` tries `tryRunGatewayRunFastPath` first (cli/run-main.js:341). That path builds a bare commander `Command` with only `gateway` and `run`, no preAction hook. I ran the installed `consumeGatewayRunOptionToken`: `['--port','18789']` returns 2, `['status']` returns 0, so `gateway --port 18789` takes the fast path and `gateway status` does not. Result on 2026.4.29: the launchd daemon keeps its full args (`node .../dist/index.js gateway --port 18789`), and `openclaw-gateway` appears only on short-lived `gateway status|health|call|install` runs. Row repaired: the daemon surface now matches `node` with args containing `openclaw/dist/index.js`, `gateway`, `--port`; the `openclaw-gateway` name is removed, since it matched only false positives. Not observed on a live gateway.
- A gateway started from a terminal (`openclaw gateway`) goes through dist/entry.js, which sets `process.title = "openclaw"` (entry.js:274) and skips respawn for a foreground gateway, so it shows as a bare `openclaw`. That title is also the parent wrapper of every respawned client (entry.js respawns a node child with `--disable-warning=ExperimentalWarning`), so it cannot be matched. gateway.log shows the gateway ran on this Mac on 2026-06-03 and 2026-07-24 01:17 to 01:31 while launchd says runs = 0, so that terminal form is real here. Recorded in notes and sources.
- `openclaw-terminal` and `openclaw-chat` never occur. `program.command("tui").alias("terminal").alias("chat")` (tui-cli-DcNLae-q.js:7), and the title uses `command.name()`. I ran commander from the installed package: preAction sees `tui` for all three. Removed from names.
- claude child flags. The row said the gateway spawns `claude` with `--session-id/--resume`. `stripLiveProcessArgs` removes `--session-id` always, and `--resume <id>` comes from resumeArgs. The live child carries `--resume` only when resuming. Wording fixed.
- Heartbeat cadence. Docs say 30m, or 1h for Anthropic OAuth/token auth including Claude CLI reuse. This Mac's gateway.log has 3474 `trigger=heartbeat` execs and 2 `trigger=user`, at about 30 minute spacing (12:15, 12:45, 13:15 on 2026-05-02) under claude-cli. Row now states the observed 30m.
- Session store. Row said the store is jsonl and cited docs.openclaw.ai/concepts/session. The live page now says runtime rows and transcripts live in `~/.openclaw/agents/<agentId>/agent/openclaw-agent.sqlite` and sessions.json is a legacy migration source. The installed 2026.4.29 still writes jsonl (ls shows it), so the glob is kept, `documented` set to false, and the version limit written into the row.
- Trajectory sidecar and lock. Live docs (tools/trajectory, concepts/agent-loop) say trajectory events now go to SQLite and the session lock became an `activeWriterRunId` claim. On newer releases the `transcript_write` signal and `.lock` file will not exist. Meaning text updated to say so.
- Record shape wording: header type is `session`, message lines also include `thinking_level_change`, trajectory keys and event types are more than the row listed (context.compiled, model.fallback_step, trace.metadata, trace.artifacts). Source entry rewritten.
- "No hook for waiting on the human": a plugin `before_tool_call` hook can return `requireApproval`, which pauses the run (docs/plugins/hooks.md:94,161). Wording softened; still no Notification-style hook.
- `openclaw-node` also fits short-lived `node status|install|start|stop`; `openclaw-agent` is a one-turn client. Labels say so.
- The un-retitled `node` surface used substring `gateway` and `node_modules/openclaw/`. It matched `node .../openclaw/dist/index.js agents list --gateway-url ws://x` and `node /proj/node_modules/some-app/server.js --gateway /proj/node_modules/openclaw/thing`. Now requires `openclaw/dist/index.js`, `gateway` and `--port`.

### Unsupported (kept, marked as inferred or limited)

- Caffeinate under the gateway's `claude` child. The claude-code row's evidence is for interactive sessions; nothing shows a `claude -p --input-format stream-json` child holds an inhibitor. No live gateway. Meaning text says "should" and "never observed".
- The macOS app's `.app` process path and any `ai.openclaw.node` launchd label. Still unknown, no process spec for the app.
- Behaviour of 2026.7.x and later (process titles, fast path, store). Only the docs were fetched; the package was not.
- Whether tree_cpu is useful: the gateway burns CPU on channel I/O and heartbeats. Left as the weak fallback.

### Synthetic probe check (throwaway node processes, not OpenClaw)

Run against the repaired row with `tools/agents_probe.py --row registry/agents/openclaw.json`:

| Fake process (ps args) | Result |
|---|---|
| `node <scratch>/openclaw/dist/index.js gateway --port 18789` | matched, daemon, idle |
| `openclaw-tui` (title set) | matched, tui, idle |
| `openclaw-gateway` (title set) | not matched (intended) |
| `openclaw-terminal` (title set) | not matched (intended) |
| `openclaw` (title set) | not matched (intended) |
| `node <scratch>/openclaw/dist/index.js agents list --gateway-url ws://x` | not matched (false positive removed) |

Before the repair the fake `openclaw-gateway` process was classified as an idle daemon, which shows the name alone is spoofable and matches short-lived CLI calls.

### Classification believable against ps?

On this Mac ps shows no OpenClaw process at all, so the probe's empty result is correct. Whether a live daemon classifies as working is unproven: with the claude-cli runtime a turn would show as a `claude` child of the gateway (probe reads descendants, so a caffeinate grandchild would count), and CPU is the fallback. Neither was seen.
