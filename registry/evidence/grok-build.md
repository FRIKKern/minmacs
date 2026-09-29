# Grok Build evidence notes (2026-09-29)

Not installed here: no `grok`, no `~/.grok`, no Grok app, nothing running, no power assertion. No live turn was seen, so row confidence is `documented`, not `verified-locally`. Unlike most harnesses, xAI publishes the source (`github.com/xai-org/grok-build`, Rust, Apache-2.0), so most claims below were read in code, not inferred from docs.

Version drift: the source tree (shallow clone at `97f190f`, monorepo `SOURCE_REV f589e31c`) is crate version 1.0.45. The public changelog's latest is v1.0.41 (2026-09-22). The released binary may lag the source.

## Shape

```
terminal:  grok  (one native Mach-O, ~170 MB)   ~/.grok/downloads/grok-macos-<arch>
             |                                   ~/.grok/bin/grok, ~/.grok/bin/agent  (symlinks)
             |- agent runs on a thread INSIDE this process (acp-agent-worker)
             |- bash tool: fresh login shell per command = DIRECT child
             |- MCP / LSP servers, background commands = long-lived direct children
             |- holds IOKit NoIdleSleepAssertion "grok: agent turn in progress" while any agent is busy
             '- writes ~/.grok/active_sessions.json  {session_id, pid, cwd, opened_at}

leader mode (default off in source):
  TUI --spawns--> grok agent leader --no-exit-on-disconnect ...   (detached group, ~/.grok/leader.sock)
                    '- owns the agent and tool shells for all attached TUIs

embedded clients:  VS Code extension, Grok Desktop (grok-desktop), Zed, Xcode ... -> grok agent stdio
servers:           grok agent serve --bind 127.0.0.1:2419 --secret <token>   |   grok agent headless

sessions: ~/.grok/sessions/<url-encoded cwd>/<uuidv7>/{summary.json, updates.jsonl, chat_history.jsonl, events.jsonl, ...}
config:   ~/.grok/config.toml, pager.toml, hooks/*.json, managed_config.toml, requirements.toml   (GROK_HOME overrides ~/.grok)
```

## What I checked

- Official docs (docs.x.ai/build via `llms.txt` index): overview, CLI reference, sessions, hooks, dashboard, settings, changelog (x.ai/build/changelog, searched for desktop, leader, sleep, ACP, macOS, not read end to end).
- Vendor installer `https://x.ai/cli/install.sh`, read not run: paths, symlinks, channels.
- Public source, read only (shallow clone into the scratchpad, nothing built or run): pager sleep inhibitor, `AgentState`, permission handling, notification title and config, leader spawn and mode resolution, agent-thread spawn, shell tool spawn, session storage layout, `events.jsonl` writer and tracker, interrupted-turn recovery, active-sessions registry, hook dispatch, OTel crates, telemetry env. The repo also ships the user guide (`crates/codegen/xai-grok-pager/docs/user-guide/*.md`, 27 files), which is more detailed than docs.x.ai.
- Local: `command -v grok agent` (nothing), `ls -d ~/.grok` (no such directory), `ps -axo pid=,args= | grep -i [g]rok` (only the checking shell), `pmset -g assertions | grep -i grok` (nothing), `mdfind` for a bundle id containing grok (nothing), `tools/validate_row.py registry/agents/grok-build.json` (ok), `tools/agents_probe.py --row registry/agents/grok-build.json` (0 sessions, correct for nothing running).
- Process rules run through the probe's own `matches()` and `session_id()` on about 30 synthetic argv lines (no process started). Matched the intended surface: bare `grok`; `grok --resume <uuid>`, `-r <uuid> --yolo`, `-s <uuid>` (all return the uuid); `grok -p ...`; `grok dashboard`; `grok --sandbox workspace -w`; full paths `~/.grok/bin/grok`, `~/.grok/downloads/grok-macos-aarch64`, `~/.grok/bin/agent` (tui); `grok agent leader ...` (daemon); `grok agent --always-approve stdio` (ide); `grok agent serve ...` and `grok agent headless` (daemon). Matched nothing: `grok update --check`, `grok update --trigger auto_background` (the TUI's auto-updater child), `--version`, `login`, `mcp`, `sessions`, `leader list`, `wrap docker exec ...`, `inspect`, `completions`, bare `agent`, `agent -p hi`, `grok-pattern`, `node grok.js`, Cursor's `.../agent`. One false hit is unfixable from the command line: an unrelated `/usr/bin/grok -f pattern.txt` (the log-parsing tool) matches as a TUI.

## Could not determine

- **Any live behaviour.** No assertion, session file, hook payload or `events.jsonl` line was seen. The 30 s transcript window and the 3% CPU floor are guesses.
- **Whether leader mode is on for a stock install.** In source it is off unless `--leader`, config `use_leader`, or the remote setting `leader_mode` (release builds only) turns it on. The remote value is fetched from xAI and cannot be read here. If it is on, the shell children move under `grok agent leader` and `tool_children` goes quiet.
- **Grok Desktop's bundle id, install path and executable name.** The source names `grok-desktop` as a client of `grok agent stdio` and the docs list it in the terminal matrix, but nothing published says where it installs. The row has a `gui` surface with no process rule and no bundle id, on purpose. Unofficial desktop apps exist (RongleCat/grok-app, `com.grokapp.grok-app` inferred from its data folder; "Grok Build Desktop (Community)"); neither is xAI's.
- **The VS Code extension's id and path.** The source only says a VS Code extension is an ACP client. No extension docs found.
- **What `grok agent headless` looks like on the wire.** It is named in `AgentMode` and in the agent-mode docs; no page describes it.
- **Whether `--sandbox` wraps tool shells in `sandbox-exec`** (the sandbox crate has a Seatbelt backend that spawns `/usr/bin/sandbox-exec`). If it does, the direct child is not a shell.
- **Which shell path the default bash tool takes.** Two spawners were read (`static_shell.rs` snapshot replay, `local_terminal.rs`); both use a fresh login shell per command, but the wiring between them was not traced.
- **When streamed text is flushed to `updates.jsonl`.** Chunks are merged before writing; the flush trigger was not found.
- **Whether a turn parked on background tasks keeps the agent state non-idle** (and so keeps the assertion). The changelog mentions "parked" turns; the code path was not traced.
- **Record content of a real session.** No files exist here; key names of `events.jsonl` and `active_sessions.json` come from the Rust structs.

## Against common belief

1. **The sleep assertion does not drop while waiting on you.** Cursor, Zed and Qwen Code release theirs at a permission prompt. Grok's `NoIdleSleepAssertion` is tied to `AgentState`, and a permission request does not change it (`permissions.rs` queues the prompt and only fires the notification). So "assertion held" means working or waiting. Separate them with `events.jsonl` (`permission_requested` without `permission_resolved`), a `Notification` hook of type `permission_prompt`, or the `⚠ Action Required` title. Inferred by reading code, unobserved.
2. **The assertion is not `caffeinate`.** There is no child process for it; the codebase has no `caffeinate` spawn. It is an in-process IOKit assertion named `grok: agent turn in progress`, so `child_process` cannot see it and the probe's `power_assertion` signal is needed. It is process-wide: one TUI with a dashboard of several agents holds one assertion for all of them. `grok agent stdio` and `grok -p` never take it (only the pager has the code). The comment in the config template says "display sleep", but the type is idle sleep.
3. **The agent is not a child process.** It is a thread in the TUI, so shell tool calls are direct children of `grok` (a good `tool_children` signal), unlike Codex or Droid where an agent child hosts them. Leader mode inverts that.
4. **Grok reads Claude Code's hooks by default.** `~/.claude/settings.json`, `settings.local.json` and project `.claude/settings.json` are scanned, and so is Cursor's `hooks.json`. A hook installed to monitor Claude Code also fires inside Grok, with camelCase payload keys (`sessionId`, `promptId`, `hookEventName`) next to a snake_case `hook_event_name` that carries Claude's PascalCase value. It can be turned off with `[compat.<vendor>] hooks = false`. `grok import` also reads Claude Code sessions.
5. **A bare `agent` is not safe to match.** The installer symlinks `agent` next to `grok`, but Cursor's CLI also installs an `agent`. Command-line matching cannot tell them apart, so the row matches `agent` only by its `~/.grok/bin/agent` path. `grok` itself is also the name of an old log-pattern tool.
6. **One TUI process holds many sessions, and a fresh launch has no id in argv.** Dashboard, `/fork` and `/new` open several top-level sessions in one process. Only `--resume`, `-r` and `-s` put an id on the command line (`-s` needs a valid UUID, and does not resume). `~/.grok/active_sessions.json` (undocumented, source only) is the pid to session map. A crash leaves stale entries until the next register.
7. **Two hook events are easy to get wrong.** `Stop` is a blocking gate that fires again for each continuation, so a busy/idle tracker on `Stop` alone shows false idle. `Stop` does not fire on Ctrl+C; `StopCancelled` does (Grok-specific, not in Claude Code), and `StopFailure` covers API errors. The docs' own recipe is `UserPromptSubmit` for busy, `Stop` + `StopFailure` + `StopCancelled` + the `idle_prompt` Notification to settle, keyed on `promptId`, ignoring events with `subagentType`. `idle_prompt` fires about a minute after the session settles, so it is a backstop, not a permission signal. `Esc` never cancels a turn.
8. **`events.jsonl` is a real open-turn record, and the vendor uses it that way.** `turn_started` with no later `turn_ended` is how Grok itself finds an interrupted turn at load. It is not in the documented storage layout. Keep it open only while the pid is alive, since a crash leaves it open.
9. **Two OpenTelemetry streams, and neither is the usual one.** The external stream is logs and metrics only (no traces), alpha, off by default, and needs `GROK_EXTERNAL_OTEL=1` plus an `OTEL_*_EXPORTER`; setting `OTEL_EXPORTER_OTLP_*` alone does nothing. It keeps working under ZDR. Flush is 5 s for logs and 60 s for metrics, so it is a reporting feed. The internal stream sends traces to xAI with xAI credentials; older builds let `OTEL_EXPORTER_OTLP_*` redirect it, now deprecated.
10. **Status line is an exact busy flag if you configure it.** A `command` status line receives `prompt_id` and `turn.started_at_ms` only while a turn runs, and its `transcript_path` is the session's `updates.jsonl`. It needs a script writing somewhere a monitor can read.
11. **The docs name a different product with a similar name.** "Grok Bot" (docs.x.ai/grok-bot, computer use, mobile) and the consumer Grok app are not Grok Build and were left out. The source also holds hidden, server-gated pieces (`grok workspace`, Computer Hub, relay sync, `xai-workspace-server`) with no local signal.

## Verification

Second-pass review 2026-09-29, written by a reviewer who did not write the row. Method: `tools/validate_row.py` (ok before and after); re-read the vendor source (`github.com/xai-org/grok-build`, HEAD still `97f190f`, crate 1.0.45) and grepped it for each claim; re-fetched `x.ai/cli/install.sh`, `x.ai/build`, `x.ai/build/changelog`, the docs.x.ai pages, the two third-party pages and the Homebrew formula API; re-ran the local checks; ran the row's process rules through `tools/agents_probe.py` `matches()` and `session_id()` on 35 synthetic argv lines against every registry row (nothing executed). Confidence stays `documented`: this harness is not installed here, so nothing was seen live.

### Confirmed

- Not installed and not running here: `command -v grok agent` empty, `ls -d ~/.grok` no such directory, `ps` grep matched only the checking shell, `pmset -g assertions | grep -i grok` empty, `mdfind` for a grok bundle id empty, no `grok` in /Applications or ~/.local/bin.
- Homepage `https://x.ai/build` loads ("Grok Build | SpaceXAI"); vendor name SpaceXAI (xAI) matches the site and `authors = ["xAI"]` in Cargo.toml.
- Crate `xai-grok-pager-bin` version 1.0.45, `[[bin]] name = "xai-grok-pager"`; changelog latest v1.0.41, Sep 22 2026.
- Sleep assertion: `notifications/sleep.rs` (CFString "NoIdleSleepAssertion", reason "grok: agent turn in progress", level 255; Linux `systemd-inhibit --what=idle --who=grok`), `ctx.rs:143` `any_busy = ... !is_idle()`, called from `router.rs:1635`, `sleep_prevention: true` by default. The only construction sites are in the pager's `NotificationService`, so `grok agent stdio` and `grok -p` do not take it.
- `AgentState` has exactly Idle, TurnRunning, TurnCancelling, CommandRunning, CommandCancelling; a permission request does not change it (`permissions.rs` only raises the ApprovalRequired notification and queues the prompt), so the assertion is held while waiting on the human.
- No `caffeinate` anywhere in the tree.
- Agent runs on thread `acp-agent-worker` inside the TUI (`spawn.rs:371`); leader mode precedence in `resolve_leader_mode` (`--no-leader`, `--leader`, eligibility, config, remote `leader_mode` only under `release-dist`, default off; a sandbox profile vetoes it); `spawn_leader_subprocess` runs `<exe> agent leader --no-exit-on-disconnect ...` with `process_group(0)`, stdout null, stderr to `<grok_home>/leader.log`; the exe resolves to `~/.grok/bin/grok` for a managed install.
- Changelog shows leader mode exists in released builds (stale-leader cleanup "when leader mode is disabled via config or remote settings").
- `events.jsonl`: `type` tag snake_case, `ts` RFC 3339 ms, events turn_started, phase_changed (waiting_for_model, streaming_text, streaming_reasoning, tool_execution, permission_prompt), first_token, tool_started, tool_completed, permission_requested (preceded by phase_changed permission_prompt in `tracker.rs:181`), permission_resolved (decision allow/deny/cancelled/followup, wait_ms), turn_ended (completed, cancelled, error, interrupted). `interrupted_turn.rs` reads the last 256 KiB (`EVENTS_TAIL_BYTES`). v1.0.41 changelog has the matching crash-marker line.
- `active_sessions.json`: struct fields session_id, pid, cwd, opened_at; pretty-printed array; `register` prunes dead pids; `try_unregister` on clean exit; headless registers only when `GROK_TRACK_HEADLESS` is set (`headless.rs:1078`, any value).
- Session directory layout, `usage.json`, `.cwd`, blake3 hex16 slug over 255 bytes, UUIDv7 via `Uuid::now_v7()`, `GROK_HOME` override; `updates.jsonl` is "the durable source of truth" (`storage/mod.rs:254`).
- Hook events: 15 in the shipped guide, matching the row's list. Notification types permission_prompt (also for DiffReview), idle_prompt, task_complete, agent_error, elicitation_dialog exist in source; payload key `notificationType`. Claude and Cursor hook files read by default; payload has camelCase keys plus snake_case `hook_event_name` carrying the PascalCase value; timeouts 5 s and 600 s.
- Title: spinner U+280B..U+2827 (8 glyphs), `⚠ Action Required`, Thinking/Responding/Running, `[ui.notifications.title] enabled = true`, default items action-required, spinner, activity, session-name, grok; `progress_bar = true`; notification defaults events turn_complete and approval_required, condition unfocused, `idle_threshold_secs = 3`; hook events turn_complete, approval_required, session_ready, task_complete, agent_error.
- Status line JSON: session_id, prompt_id (only during a turn), turn.started_at_ms (absent between turns), transcript_path = updates.jsonl.
- OpenTelemetry: `GROK_EXTERNAL_OTEL` master switch, logs and metrics only, http/protobuf or grpc, `service.name grok-cli`, meter scope `ai.xai.grok_code`, metric names as listed, log interval 5 s and metric interval 60 s (`external/config.rs:187-190`).
- Installer: `~/.grok/downloads/grok-<platform>`, `~/.grok/bin/grok` and `agent`, `GROK_BIN_DIR`, `GROK_CHANNEL` stable|alpha|enterprise, config in `~/.grok/config.toml`.
- Exclude list covers every subcommand in `cli.rs` `enum Command` except the hidden `workspace`, which the row leaves out on purpose; `--sandbox <PROFILE>` exists.
- Grok Desktop: named as an ACP client in `xai-acp-lib/src/stdin_reader.rs`, `auth_provider.rs` and `oidc/protocol.rs` (referrer "grok-desktop"); the changelog mentions grok-desktop with `grok agent stdio`; no bundle id anywhere. The row's gui surface with no process rule is right.
- Third-party clients: RongleCat/grok-app README ("not an official xAI product", `grok agent stdio`, `com.grokapp.grok-app`), Product Compass page ("runs xAI's real CLI unmodified", "Community").
- Process rules on synthetic argv: bare `grok`, `--resume`, `-r`, `-s`, `--resume=<id>`, `dashboard`, `-p ...`, full paths, `--sandbox workspace` match the TUI; `grok agent stdio` is ide; `agent serve`, `agent headless`, `<~/.grok/bin/grok> agent leader` are daemon; `update`, `--version`, `mcp`, `leader list`, `wrap`, `login`, bare `agent`, `node .../grok`, `grep grok`, `sandbox-exec ... grok` match nothing; no other registry row matched any grok line. Cursor's row does not match `agent` either.

### Corrected

- **`hold_awake` has a caller.** The row said `xai-system-power::hold_awake()` had none. `xai-grok-login/src/manager/refresh_chain.rs:200` calls it as `hold_awake("grok: OIDC token refresh")` on a dark-wake token refresh, type `PreventSystemSleep`. It does not break the turn signal (the row matches the full turn name) but any process can hold this assertion briefly. Source entry rewritten; note added to the `power_assertion` meaning.
- **Installer symlink condition.** The row said the `~/.local/bin` or `/usr/local/bin` symlinks are made "when one is on PATH". The installer makes them only when `~/.grok/bin` is not on PATH, then adds `~/.grok/bin` to the shell rc (`install.sh` 419-424). Source entry and TUI label fixed.
- **Hosted docs versus the shipped guide.** Three source entries cited docs.x.ai for facts the hosted pages do not contain. The hosted hooks page is 2.6 KB: 14 events (no StopCancelled), no idle_prompt or permission_prompt, no promptId, no 600 s timeout, and it calls PreToolUse "the only blocking event" while the shipped guide lets UserPromptSubmit, Stop and SubagentStop block. The hosted status-line page has no prompt_id, turn.started_at_ms or transcript_path. The hosted sessions page has no updates.jsonl, GROK_HOME or UUIDv7. The hosted headless page has no `--prompt-json` or `--prompt-file`. All of those hold in `crates/codegen/xai-grok-pager/docs/user-guide/*.md` at 97f190f, so the claims stand, but the evidence now names which page says what, and a separate source entry covers the shipped hooks guide.
- **`updates.jsonl` "authoritative"** comes from `storage/mod.rs:254` (source), not from the docs.
- **Surface order (repaired).** `args_contain` is a substring test over every argument, and the row listed the agent-mode surfaces before the TUI, so `grok --cwd /work/webserver-agent` (contains agent and serve) was labelled daemon. The TUI surface is now first; its exact-argument veto on `agent` already rejects real `grok agent ...` processes. Still wrong by design: a prompt containing the bare word `agent` (`grok -p why does the agent stdio hang`) is vetoed by the TUI and falls to ide.
- **`--load <id>` (repaired).** Hidden alias of `--resume` (`cli.rs:556`), was missing from `session_id_args`; added.
- **Helper children.** The TUI re-executes its own binary as `__mermaid-render` and `__mic-capture` (`mermaid_worker.rs:56`, `xai-grok-voice/src/lib.rs:55`, argv[0] the resolved `~/.grok/downloads/grok-macos-<arch>`). They match the TUI surface; the probe drops a match whose parent also matches, so they fold into the TUI. Recorded in the label.
- **Source ahead of release.** Crate 1.0.45 against changelog 1.0.41. `events.jsonl` recovery and leader mode are corroborated by the changelog; `idle_prompt`, `active_sessions.json` and the exact turn assertion name are not mentioned there, so treat them as source-only for the build a user runs.

### Unsupported or still open

- **`grok` is an old log-pattern tool** (evidence note 5, no source in the row). Now supported: Homebrew formula `grok`, jordansissel/grok, deprecated and disabled. A name-only match on a hand-installed copy stays an accepted false positive.
- **`tool_children` for the TUI.** The tool runs `<shell> -lc <command>`. A shell given one simple command may exec it, leaving a direct child that is not named like a shell. Not observed; added to the signal's meaning as inferred. Which of the two spawners the default bash tool uses is still untraced.
- **`--sandbox` and `sandbox-exec`.** Only the Linux path re-execs the binary (bwrap); on macOS the Seatbelt backend wraps tool commands. Whether the direct child is then `sandbox-exec` is unchecked.
- **Assertion type as pmset prints it.** The source creates "NoIdleSleepAssertion" (the deprecated NoIdleSleep type); nobody has seen the `pmset -g assertions` line. Matching by name avoids depending on it.
- **All timing values** (30 s transcript window, 3% CPU floor, the idle_prompt minute in practice) are unmeasured. The `grok agent headless` argv shape, Grok Desktop's bundle id, and the VS Code extension's path are still unknown.
