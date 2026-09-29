# OpenAI Codex: evidence notes (2026-09-29)

Installed here: codex-cli 0.154.0 (standalone, `~/.local/bin/codex`), desktop app `/Applications/ChatGPT.app` (bundle `com.openai.codex`, v26.825.51511, bundles codex 0.151.0-alpha.7.2), Cursor extension `openai.chatgpt-26.908.40401` (bundles codex 0.154.0-alpha.6.2). Latest upstream release: rust-v0.159.0.

## Shape

```
ChatGPT.app (Electron, com.openai.codex)
  '- Resources/codex app-server --analytics-default-enabled   <- the agent (many threads)
Cursor/VS Code ext  -> bin/macos-aarch64/codex app-server ...  <- the agent (many threads)
terminal            -> codex (TUI) --embedded app-server, or attached to:
shared daemon       -> codex app-server [--remote-control] --listen unix://
scripts / SDK       -> codex exec ...   (originator codex_sdk_ts, source exec)
cloud               -> no local process

all of them write  ~/.codex/sessions/Y/M/D/rollout-<ts>-<thread-uuid>.jsonl
                   ~/.codex/state_5.sqlite          threads index
                   ~/.codex/thread_history_1.sqlite thread_turns.status (live turn state)
                   ~/.codex/thread-writer-locks/<thread-uuid>.lock  (flock while owned)
```

## What I checked

- Real install, read-only: `--version`, `--help`, `features list`, `plutil`, `strings`, `ls`/`stat` of `~/.codex`, sqlite `.schema` and non-content columns (source, originator, status, timestamps), key names of one record per rollout type.
- Desktop app launch args: found in the installed `app.asar`: `codex [-c ...] app-server --analytics-default-enabled`, binary from `CODEX_CLI_PATH` or `Resources/codex`.
- Upstream docs (learn.chatgpt.com, which developers.openai.com/codex redirects to) for hooks, advanced config, config reference, app-server. Upstream source: `rollout/src/policy.rs`, `rollout/src/writer_lock.rs`, `utils/sleep-inhibitor`, `app-server-daemon`, `app-server-protocol/.../v2/{thread,turn}.rs`.
- Timestamp-only scan of one 16-turn rollout for write gaps inside turns.
- Row validated: `tools/validate_row.py registry/agents/codex.json` passes. Process rules tested on 13 synthetic argv lines.

## Could not determine

- **No live instance.** Nothing Codex was running (`ps`, `pmset -g assertions` clean), and I may not start one. `agents_probe.py --row` reports 0 sessions. So confidence is `documented`, not `verified-locally`. Real `ps` argv for the desktop app-server, the TUI and the extension host is inferred from source and the asar, not seen.
- Whether the desktop app uses the shared daemon or spawns its own stdio app-server (the asar path found spawns its own; the `ipc/ipc.sock` dated Sep 15 was not identified).
- Whether `~/.codex/thread-writer-locks/<id>.lock` + `lsof` gives the owning pid on a live thread. Source says flock; not exercised.
- Whether a TUI attached to the daemon still holds the writer lock itself (it should not: the daemon owns the thread).
- The `-c` prefix args (`lH`) the desktop app adds before `app-server`.
- App-server control socket path: only the strings `app-server-control` and `app-server-control.sock` in the binary; the exact location is inferred as `~/.codex/app-server-control/`.
- Homebrew/manual install executable name (`codex-aarch64-apple-darwin` is the release asset name, inner name unverified).
- Cloud task state: needs network and login, not queried.
- Whether MCP server children (e.g. `node_repl` from `config.toml`) run under the host process; therefore `tool_children` is left out of the row.
- Gap statistics come from one session; legacy 2025 rollouts (no `ordinal`, different layout) not measured.

## Against common belief

1. **`history.jsonl` is not the transcript.** Docs say "session transcripts ... under CODEX_HOME (for example history.jsonl)". Here `history.jsonl` is 3 KB with keys `session_id, ts, text` (prompt history). Real transcripts are `sessions/**/rollout-*.jsonl`, an undocumented layout (hooks docs: transcript format "isn't a stable interface", `transcript_path` may be null).
2. **JSONL is no longer the whole story.** Since `history_mode = paginated`, SQLite (`thread_history_1.sqlite`, 189 MB here) holds a projection of the rollout with byte offsets. The rollout is still written and is the source of truth; older 2025 threads are `legacy`.
3. **No caffeinate child, no default power assertion.** Unlike Claude Code, Codex uses an in-process IOKit assertion named "Codex is running an active turn", and only when the experimental `features.prevent_idle_sleep` is on (default off, off here). Do not look for a `caffeinate` child; do not read a missing assertion as idle.
4. **One process is not one session.** The agent loop lives in `codex app-server`, which hosts many threads. CPU and children of that process cannot be attributed to a thread. Only the rollout, the sqlite projection, or the writer lock is per thread.
5. **`inProgress` lies after a crash.** `thread_turns.status = inProgress` for an `exec`/SDK thread that started 08:58 today is still set with no process alive and no writer lock file. Same for a `task_started` with no `task_complete`. Pair it with liveness (lock held, file growing).
6. **Waiting is invisible in the transcript.** Approval requests, `request_user_input` and elicitations are explicitly not persisted to the rollout. Only hooks (`PermissionRequest`, no question hook), the app-server `thread/status/changed` (`waitingOnApproval`, `waitingOnUserInput`) or terminal bell/OSC 9 expose it.
7. **No `Notification` hook like Claude Code's.** Nearest is `PermissionRequest`. Hooks are also inert until the user reviews and trusts them in `/hooks`, and project-local hooks need a trusted project. The legacy `notify` is a single command for `agent-turn-complete` only, and on this Mac it is already used by the desktop app's Computer Use plugin.
8. **Telemetry defaults.** OTel export is opt-in (`[otel]`, user config only), but anonymous usage metrics go to OpenAI by default (`otel.metrics_exporter` defaults to `statsig`; opt out with `[analytics] enabled = false`).
9. **The desktop app shows as "ChatGPT".** Bundle `com.openai.codex`, executable `ChatGPT`, Electron helpers named `Codex (Renderer)` etc. The Electron host is not the agent; the bundled `Resources/codex app-server` child is.
10. **Long gaps are normal mid-turn.** In one session in-turn gaps between rollout records had p99 57 s and max 528 s, so a 20 s "recent write" window (right for Claude Code) misses about 7% of the time.
11. **SDK-spawned runs carry a different codex version** (0.155.0 in sessions written today vs. installed 0.154.0), so some other binary (an npm-vendored one) runs `codex exec` on this Mac. Match on name `codex`, not on the install path.

## Privacy

No message content was printed. Only file names, sizes, mtimes, sqlite schemas, non-content columns (ids, status, source, originator, timestamps) and JSON key names were read.

## Verification

Adversarial pass, 2026-09-29, by a second agent that did not write the row. Method: re-ran every local command, re-fetched every URL and source file from `raw.githubusercontent.com/openai/codex/main`, read the installed extension JS and desktop `app.asar`, and tested the process rules against synthetic argv lines with `tools/agents_probe.matches()`. Read-only; nothing started. `tools/validate_row.py` passes before and after. `tools/agents_probe.py --row` still reports 0 sessions: no Codex process is running, so the classification cannot be checked against `ps` and confidence stays `documented`, never `verified-locally`.

### Source claims

1. Installed codex-cli 0.154.0, symlink, Mach-O arm64: **confirmed** (`ls -la`, `file -L`, `--version`).
2. Desktop app bundle id, name, version 26.825.51511, bundled codex 0.151.0-alpha.7.2: **confirmed** (`plutil -p`, `Resources/codex --version`).
3. Desktop launches `codex ... app-server --analytics-default-enabled`: **confirmed** in `app.asar` (`LH()` returns `[...lH, ...env -c flags, "app-server", "--analytics-default-enabled"]`; `CODEX_CLI_PATH` lookup; config.toml sets it). The `...lH` prefix is still unresolved: **unsupported** for the exact desktop argv prefix, harmless to matching.
4. IDE extension bundles its own codex: **confirmed**, and **corrected**. The original said the launch argv was only "inferred". It is not: `out/extension.js` of openai.chatgpt-26.908.40401 logs "Spawning codex app-server" and spawns `["-c","features.code_mode_host=true","app-server","--analytics-default-enabled"]`. Also two extension versions are installed (26.602.71036 bundles 0.137.0-alpha.4, which also has `app-server`). Source entry and ide label updated.
5. No Codex process running: **confirmed again** (`ps -axo ... | grep -i -E 'codex|ChatGPT|app-server'` empty, `pmset -g assertions` shows only unrelated caffeinate). Live classification is therefore still **unsupported**.
6. Rollouts are `~/.codex/sessions/Y/M/D/rollout-<ts>-<uuid>.jsonl`, id in the name: **confirmed** (34 files; `per_session` glob resolved a real id to its file through `agents_probe.transcript_age`).
7. Record shape and event types: **confirmed** by key-name census (top-level `timestamp, ordinal, type, payload`; `task_started`, `task_complete`, `item_completed`, `token_count` keys as listed; `session_meta` payload has `id, cwd, originator, cli_version, source, thread_source, history_mode`). No values printed.
8. Turn boundaries persisted, approvals/`request_user_input`/elicitations not: **confirmed** in `rollout/src/policy.rs` (`TurnAborted|TurnStarted|TurnComplete => true`; `ExecApprovalRequest|RequestPermissions|RequestUserInput|ElicitationRequest|ApplyPatchApprovalRequest => false`). Also `Error` events are not persisted, so a failed turn may leave no marker: **new caveat**, not in the row.
9. `thread_turns.status` can be stale (crash leaves `inProgress`): **confirmed** with `mode=ro` (completed 23, inProgress 1; the one inProgress turn has no live process). `TurnStatus` is `Completed | Interrupted | Failed | InProgress` in `turn.rs`. The original used `immutable=1`, the notes say `mode=ro`; both work, `mode=ro` is the safe one on a live DB.
10. `threads` schema and source/originator values: **confirmed**. Counts drift: now `exec|codex_sdk_ts|paginated|0.155.0` is 8 (was 4), so `codex exec` runs are happening on this Mac between snapshots; none was alive when checked.
11. Writer lock via flock, `lsof` shows holder: source part **confirmed** (`writer_lock.rs`: `thread-writer-locks/<id>.lock`, `try_lock`, `WouldBlock` = "already has an active writer", stale files removed when `try_lock` succeeds). The `lsof` mapping is **unsupported**: never exercised, only `.coordination.lock` exists.
12. macOS sleep inhibitor: **confirmed** (`macos.rs` `ASSERTION_REASON`, `PreventUserIdleSystemSleep`; `strings` on the 0.154.0 binary; `codex features list` prints `prevent_idle_sleep experimental false`; config reference "experimental; off by default"). "Absence tells nothing" follows from the default and is sound.
13. Rollout in-turn gap statistics: numbers **reproduced exactly** (16 turns, 1732 gaps, p50 0.08s, p90 14.5s, p99 56.8s, max 528s, 127 gaps over 20s). **Corrected** the derived claim in `transcript_write.meaning`: it said a 30s window "misses roughly 7% of gaps". 7.3% is the 20s figure; at 30s it is 72 of 1732 = 4.2%. Row fixed. Still one session, and it counts gaps, not turns.
14. Hooks docs: **confirmed** on learn.chatgpt.com/docs/hooks (events PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, UserPromptSubmit, SubagentStop, Stop, Interrupt, SessionStart, SubagentStart, SessionEnd; four config locations; non-managed hooks need review and trust in `/hooks`; project hooks only in trusted projects; `PermissionRequest` "doesn't run for commands that don't need approval"; `transcript_path` "isn't a stable interface", nullable). `developers.openai.com/codex/hooks` does redirect there (200, final URL learn.chatgpt.com). "No Notification hook, no hook for `request_user_input`" is an absence claim: consistent with the event list and the binary's hook names, **inferred**, cannot be proven by a doc that lists what exists.
15. No hooks.json, no `[hooks]`, no `[otel]`, `notify` set: **confirmed** (`ls hooks.json` missing; config.toml section list has no hooks/otel; `notify` on line 5). Note `features.hooks` is `stable true` locally.
16. OTel opt-in, exporters, `statsig` metrics default, `[analytics] enabled=false`, `notify`/`otel` ignored in project config: **confirmed** in config-advanced and config-reference. All eleven event and metric names appear in config-advanced.
17. `thread/status/changed` with `activeFlags` waitingOnApproval/waitingOnUserInput: **confirmed** (app-server docs example; `ThreadStatus`/`ThreadActiveFlag` in `thread.rs`; strings in the binary). The socket path `~/.codex/app-server-control/app-server-control.sock` is **unsupported**: the binary has the strings `app-server-control`, `app-server-control.sock`, `app-server-startup.lock` only; the directory does not exist here. Row already says "inferred".
18. Shared daemon argv, pid files, TUI attach with embedded fallback: **confirmed** (`pid.rs` command_args and `pid-update-loop`; `lib.rs` `daemon.pid`, `app-server-daemon`; crate README: "If an implicitly discovered daemon cannot initialize the connection, the TUI starts an embedded server"). `codex agents --help` text confirmed.
19. Cloud has no local process, `codex cloud` subcommands: **confirmed** (`exec status list apply diff`; note `exec` there means "submit a new cloud task", it is not `codex exec`).
20. Release asset name `codex-aarch64-apple-darwin`: **corrected**. Latest release rust-v0.159.0 (published 2026-09-29T08:05Z) does ship `codex-aarch64-apple-darwin.tar.gz`, and the README says the archive holds one entry with the platform in its name that users "likely want to rename to codex". So the name is plausible for manual installs but the inner name is still unobserved. Every packaged path here uses `codex` (npm vendor, TS SDK resolver, standalone, extension, desktop). Added `codex-x86_64-apple-darwin` for Intel Macs on the same README evidence. A separate `codex-app-server-aarch64-apple-darwin` asset exists and is not matched: **unsupported** either way.
21. Synthetic process-rule test: **confirmed as far as it goes**, but it missed real false positives, below.

### Row claims not tied to a source

- `history.jsonl` is prompt history, keys `session_id, ts, text`: **confirmed** (key names only).
- `thread_history_1.sqlite` size 189 MB: **confirmed** (189,263,872 bytes).
- Shape diagram, "one process is not one session": **confirmed** by the daemon README and `thread/*` protocol; not observed live.
- "SDK runs carry a different codex version (0.155.0 vs installed 0.154.0)": **confirmed** from `threads.cli_version`; the TS SDK resolver (`sdk/typescript/src/exec.ts`) spawns the npm-vendored binary named `codex` with `exec --experimental-json [resume <id>]`.
- Tail of notes "Since 0.15x the agent loop lives in app-server": **unsupported** as a version claim; reworded to what the asar, the extension JS and the daemon README show.

### Process pattern false positives and negatives (proved with `agents_probe.matches`)

- **Corrected.** `gui` and `ide` had no `exclude_args`. `ChatGPT.app/Contents/Resources/codex app-server proxy` and `... app-server daemon pid-update-loop` (and the same under the extension path) matched as agent sessions. Added `daemon proxy generate-ts generate-json-schema`. Retested: no match.
- **Corrected.** `codex review` (headless turn per `codex review --help`) matched nothing. Added a `review` surface. Side effect that is a gain: `codex please review this` (interactive prompt containing the word) used to vanish from the TUI surface and now matches this one.
- **Corrected.** The exec surface had no `session_id_args`; `codex exec ... resume <uuid>` now yields the uuid, so the transcript-age signal works for SDK resumes. Label rewritten: it claimed `codex review` was covered and it was not.
- **Left, documented in notes.** `codex e` alias unmatched. A TUI started with a prompt containing an excluded word (`codex fix the update logic`) is missed, because exclusion is on whitespace-split argv words. `args_contain` is substring, so a prompt mentioning `exec` or `app-server` can land on another surface of the same kind. `path_contains` is a prefix match. A different product whose binary is just `codex` would match the TUI surface: no path check is possible with `names`. `codex agents` is a session browser and counts as a TUI session.
- Correct as designed: the Electron host `.../MacOS/ChatGPT`, `node .../codex.js`, `codex doctor`, `codex exec-server`, `codex-code-mode-host` do not match.

### Confidence

`documented`, unchanged, and not higher. Evidence is vendor docs, vendor source and installed vendor code; the extension argv is now confirmed from the vendor's own JS, the desktop argv from its asar. Still never seen in `ps`: every process pattern, the writer-lock-plus-`lsof` mapping, the power assertion, and the daemon. The first live Codex run on this Mac should be checked with `tools/agents_probe.py --row registry/agents/codex.json` and `lsof` on `~/.codex/thread-writer-locks/`.
