# Zed agent: evidence notes (2026-09-29)

Not installed here (no app, no CLI, no `~/Library/Application Support/Zed`, nothing running). Every claim comes from official docs and the public source (`zed-industries/zed`, main, fetched 2026-09-29). Confidence is `documented`, not `verified-locally`.

## Shape

```
Zed.app/Contents/MacOS/zed        one process (ppid launchd), dev.zed.Zed
  |- hosts ALL Zed Agent threads   (native agent, in-process, no child)
  |- hosts ALL external-agent threads' UI
  |- child: <node> .../Zed/external_agents/registry/npx/<id>/node_modules/.../<bin> [args]   (claude-acp, codex-acp, gemini --acp, pi-acp ...)
  |- child: .../Zed/external_agents/registry/<id>/v_<ver>_<hash>_<hash>/<cmd> [acp]          (opencode, cursor, amp ...)
  |    '- the agent's own children (Claude SDK's native `claude`, native `codex`, tools)
  '- child: login shell on a pty    (Terminal Threads; any CLI inside)

Zed.app/Contents/MacOS/cli        the `zed` terminal command; not the app
```

## What I checked

- Docs: agent-panel, external-agents, terminal-threads, agent-settings, parallel-agents, telemetry, macos, uninstall, tasks (Hooks), llms.txt index.
- Source (raw files via `gh api`): `crates/acp_thread/src/acp_thread.rs`, `crates/gpui_macos/src/{platform,dispatcher}.rs`, `crates/agent/src/{db,agent}.rs`, `crates/agent_ui/src/{conversation_view,thread_metadata_store,terminal_thread_metadata_store}.rs`, `crates/project/src/agent_server_store.rs`, `crates/agent_servers/src/custom.rs`, `crates/paths/src/paths.rs`, `crates/db/src/db.rs`, `crates/zed/Cargo.toml`, `script/bundle-mac`, `assets/settings/default.json`.
- ACP registry JSON (`cdn.agentclientprotocol.com/registry/v1/latest/registry.json`) and npm metadata for the Claude and Codex ACP wrappers.
- Local, read-only: `ls`, `mdfind`, `ps`, `pmset -g assertions`, `which`. All empty for Zed.
- `tools/validate_row.py registry/agents/zed.json` passes. `tools/agents_probe.py --row` finds 0 sessions (expected).
- No session-store content read (none exists here).

## Best signal for "a turn is in progress"

Zed holds an OS idle-sleep assertion for exactly the running, unblocked turns. In `acp_thread.rs`, `update_idle_sleep_prevention` takes `cx.prevent_idle_sleep("Agent thread in progress")` when `running_turn` is set, `agent.prevent_idle_sleep` is true and `!is_waiting_for_confirmation()`, and drops it otherwise. The docs say the same. On macOS that is `NSProcessInfo beginActivityWithOptions(UserInitiated)`, so expect `PreventUserIdleSystemSleep` named "Agent thread in progress", owned by the `zed` pid.

- `AcpThread` is the thread type for the Zed Agent AND external ACP agents, so one signal covers both.
- One assertion per running thread, all the same pid: it counts working threads, it cannot name them.
- Off when the user sets `agent.prevent_idle_sleep: false` (default true). Then there is no reliable external signal.
- Terminal Threads take nothing; they are plain ptys.

## Waiting on the human

Same code path: `is_waiting_for_confirmation` (pending tool authorization or pending elicitation, looking back to the last user message) makes Zed drop the assertion. So "thread exists, no assertion" = idle OR waiting, and an outside observer cannot tell which. In-app only: popup windows "Waiting for tool confirmation" / "Waiting for input" + Dock attention (`agent.notify_when_agent_waiting`, default `primary_screen`), sound on done (`play_sound_when_agent_done`, default `never`). No hook, no log line, no file. `dev: open acp logs` is in-app.

## Sessions

- Zed Agent: `~/Library/Application Support/Zed/threads/threads.db` (SQLite; `threads` table, `data` = zstd-compressed JSON, columns include `folder_paths`). Source only, undocumented, not seen on disk. Native agent re-saves on every thread change, so the file moves during a turn (unverified). One shared file, so no per-session path.
- Index of all threads incl. external ones: `sidebar_threads(session_id, agent_id, title, folder_paths, archived ...)` in `~/Library/Application Support/Zed/db/0-<stable|preview|nightly|dev>/db.sqlite`. Also `sidebar_terminal_threads`. The `0-<channel>` folder name is inferred from `db_path()` + `dev_name()`.
- External agents: Zed stores no transcript. The agent does (Claude `~/.claude/projects`, Codex `~/.codex/sessions`, ...). Zed can import them over ACP (not Cursor, not Gemini CLI).
- Process to session: impossible from argv. Session ids go over stdio JSON-RPC. Zed process to project only via window title / `lsof` cwd, which is the project root at most.

## Hooks and telemetry

- No agent lifecycle hooks. The one documented hook is the `create_worktree` task hook. Nothing for turn start/stop, tool use or notification. Terminal Threads only get the terminal bell/title trick (docs give Claude Code `preferredNotifChannel: terminal_bell`, Amp `AMP_FORCE_BEL`, an OpenCode plugin, a Pi extension; Codex `tui.terminal_title`).
- No OpenTelemetry. Zed telemetry goes to Zed (Sentry, Snowflake). `zed: open telemetry log` audits it.

## Could not determine

- Whether `pmset -g assertions` prints the reason string as the name and which exact `PreventUserIdleSystemSleep` label appears. Composition of `NSActivityUserInitiated` is Apple's; the pmset text is inferred.
- Real `ps` lines for external agents. Which `node` runs npx agents (Zed-managed vs system) is not visible in the fetched source. The ACP row therefore keys on `Zed/external_agents/registry/` in args, not on the node path.
- Whether the threads.db mtime really moves while streaming (WAL vs main file).
- Whether external agents' own hooks (Claude Code settings.json) fire when run through the ACP wrapper.
- Whether an ACP agent's OTel env can be set via `agent_servers.<id>.env` and works (docs show `env`, not tested).
- Windows/Linux behaviour: irrelevant, not checked.

## Against common belief

- "Zed agent" is not a process. There is no `zed-agent` binary; the native agent runs inside the editor. A Zed with many agent threads is still one pid.
- Zed's docs say the assertion exists only while generating and not while waiting. So a blocked-on-you thread looks idle to the OS. Do not treat "sleep inhibited" as "session open".
- External agents in Zed are not the CLIs you know: they are ACP wrappers (`claude-agent-acp`, `codex-acp`). But underneath they run the vendor's native binary (Claude Agent SDK ships a platform `claude` binary as an optionalDependency). Existing rows keyed on process name `claude` or `codex` will likely count those as standalone TUI sessions. That is npm metadata plus inference, not observed.
- Zed keeps no transcript of external-agent sessions, despite showing them in the sidebar.
- The terminal `zed` command is `Contents/MacOS/cli`, a different executable from the app's `Contents/MacOS/zed`.
- Zed gives no lifecycle hooks and no OTel, unlike Claude Code, Codex and Cursor.

## Verification

Adversarial re-check on 2026-09-29 by a second pass that did not write the row. Docs pages and the source files in `zed-industries/zed` main were re-fetched (`zed.dev/docs/<page>.md`, `raw.githubusercontent.com`), the ACP registry and npm metadata were re-queried, and the row was run through `tools/validate_row.py` (ok, before and after edits) and offline through `tools/agents_probe.py` `matches()` with synthetic `ps` lines. Confidence stays `documented`: Zed is not installed here, so nothing was observed running. The sections above are left as written; where they differ, this section wins.

Confirmed
- Idle-sleep assertion: `update_idle_sleep_prevention` in `acp_thread.rs` takes `cx.prevent_idle_sleep("Agent thread in progress")` only if `prevent_idle_sleep` is on, `running_turn` is set and `!is_waiting_for_confirmation()`; called on turn changes and on `ElicitationResponded`-type events (lines 3548, 3557). Docs say the same (agent-panel, "Keeping the System Awake").
- `agent.prevent_idle_sleep` default `true` (`assets/settings/default.json`).
- macOS: `prevent_idle_sleep` uses `NSActivityOptions::UserInitiated`; `prevent_app_nap` uses `UserInitiatedAllowingIdleSystemSleep` (`gpui_macos/src/platform.rs`, `dispatcher.rs`).
- `AcpThread` is the thread type behind the native agent too (`crates/agent/src/agent.rs` holds `Entity<AcpThread>` per session), so one signal covers Zed Agent and external agents.
- `is_waiting_for_confirmation` (pending tool authorization or pending elicitation since the last user message) drops the assertion.
- Bundle ids `dev.zed.Zed`, `-Preview`, `-Nightly`, `-Dev`; names `Zed`, `Zed Preview`, `Zed Nightly`, `Zed Dev`; `Contents/MacOS/zed` and `Contents/MacOS/cli` (`crates/zed/Cargo.toml`, `script/bundle-mac`).
- Paths: `~/.config/zed`, `~/Library/Application Support/Zed` (same for every channel, `APP_NAME` is a const), `~/Library/Logs/Zed`, `external_agents_dir = data_dir/external_agents`, `database_dir = data_dir/db`, `db/0-<stable|preview|nightly|dev>/db.sqlite`.
- npx agents install to `external_agents/registry/npx/<id>` and run as `<node_binary> <executable> [args]`; binary agents extract to `external_agents/registry/<id>/v_<version>_<hash>_<hash>`.
- `threads.db` schema, zstd JSON, and `agent.rs` `cx.observe(&thread_handle, ... save_thread)` re-saving on every thread change (source only; the mtime behaviour is still unobserved).
- `sidebar_threads` and `sidebar_terminal_threads` tables exist as described.
- ACP registry entries and versions: claude-acp 0.84.0, codex-acp 2.0.0, gemini 0.61.0 with `--acp`, opencode 1.18.33 `./opencode acp`, cursor `./dist-package/cursor-agent acp`, pi-acp 0.0.34, amp-acp 0.9.0 `./amp-acp`. npm: claude-agent-acp bin `claude-agent-acp` -> `dist/index.js`, dep `@anthropic-ai/claude-agent-sdk` 0.3.284; codex-acp dep `@openai/codex` ^0.158.0.
- Notification strings, defaults (`primary_screen`, `never`), and no hook/event settings in agent-settings; only `create_worktree` in tasks docs.
- Telemetry: Sentry, Snowflake, Hex, Amplitude; `telemetry.diagnostics`/`metrics`; "open telemetry log". No `opentelemetry` in any Cargo.toml (GitHub code search: 0 files).
- Terminal Threads: bell and title are the only agent-facing signals; Claude Code `preferredNotifChannel: terminal_bell` is in the docs.
- Cursor and Gemini CLI thread import unsupported (parallel-agents note).
- Not installed here (re-run: `python3 tools/agents_probe.py --row registry/agents/zed.json` -> 0 sessions).

Corrected
- Preview, Nightly and Dev process patterns could never match in `agents_probe.py`. It splits `ps` args on spaces, so `/Applications/Zed Preview.app/Contents/MacOS/zed` has exe `/Applications/Zed`. Added a second `ide` surface (`path_contains /Applications/Zed`, `args_contain Contents/MacOS/zed`); offline test: matches Preview, Nightly and `~/Applications` installs, does not match `Contents/MacOS/cli`, `Contents/MacOS/git`, or unrelated apps. The first entry is kept for detectors that read the full path.
- "the claude-code row would match the SDK's `claude` by name": true only for a detector that reads the real executable path. Under the probe the exe is `/Users/<u>/Library/Application`, neither claude-code surface matches, and the Zed ACP surface matches it and is then dropped by parent-dedup. Notes rewritten. The native `claude` binary itself is confirmed (`package/claude` is the first entry in the `claude-agent-sdk-darwin-arm64-0.3.284.tgz` listing), and is now a source entry.
- "external agents own their own transcripts; Zed does not store them" was cited to docs that do not say it (the "boundary table" in external-agents has no transcript row). What is supported: the sidebar index has no content column, only the native agent writes `threads.db`, and import goes through the agent over ACP. Kept as `source-code` inference with that stated.
- "only place that maps an ACP session id to a Zed thread" narrowed to external-agent threads (native threads are also keyed in `threads`).
- Notifications are skipped while the thread is visible in an active window (`show_notification`: `should_notify = !agent_status_visible`). Added to the claim.
- Working signal `power_assertion` is not implemented by `agents_probe.py` (`classify()` has no branch; `transcript_write` needs `per_session`). Under the probe every Zed row is idle. Stated in notes; the row is data for a detector that reads assertions.

Unsupported (left in, marked as such)
- The `pmset -g assertions` type label for an NSProcessInfo activity. Apple's flag composition says idle system sleep is disabled, but on this Mac Chrome's assertion prints as `NoIdleSleepAssertion` while caffeinate and Insomnia print as `PreventUserIdleSystemSleep`, so the label is unconfirmed. Key on owner pid plus the name `Agent thread in progress`.
- `threads.db` mtime moving during a turn (source says it re-saves; WAL vs main file unobserved).
- Which `node` runs npx agents (Zed-managed or system). Both forms match the ACP surface offline.
- Whether external agents' own hooks fire under the ACP wrapper.
- Whether `agent_servers.<id>.env` carries OTel settings.
- Real `ps` lines for any Zed process; none exist on this Mac.

Process-pattern false positives (offline, `matches()`)
- Zed app surface: only `Contents/MacOS/zed` under a `Zed*.app`. `cli` and `git` helpers do not match; a re-exec of the same binary (for example a `--crash-handler` style child, whether Zed does this was not checked) would match but is dropped by the probe's parent-dedup.
- ACP surface: matches only when an arg contains `Zed/external_agents/registry/`. Unrelated `node`, Claude desktop processes under `~/Library/Application Support/Claude`, and a `grep` naming the path do not match. Only a `node` (or an `Application Support` process) that has the path in its args would, e.g. someone running `node` on a file there by hand; negligible.
- Gap, not false positive: custom and legacy extension agents live outside `external_agents/registry/` and are not seen by the ACP surface.
