# Every Code (just-every/code) — evidence notes

Date: 2026-09-29. Confidence: `documented`. Not installed on this Mac, no live turn seen.
Version studied: v0.6.195 (released 2026-09-28), source commit fe8dac63d319 (sparse clone in the scratchpad, code-rs / codex-cli / docs only).

## What it is

Community fork of `openai/codex`, npm `@just-every/code`, Apache-2.0, not affiliated with OpenAI. The active Rust tree is `code-rs/` (crates named `code-*`); `codex-rs/` is the upstream mirror and is not what ships. Only a terminal surface exists: no desktop app, no bundle id, no IDE extension, no daemon, no cloud runner of its own (`code cloud` browses OpenAI's Codex Cloud tasks).

## What I checked

- README, `docs/config.md`, `docs/integration-zed.md`, `docs/homebrew.md`, `docs/exec.md`, `docs/advanced.md` (raw.githubusercontent.com).
- Source: `codex-cli/bin/coder.js`, `codex-cli/postinstall.js`, `codex-cli/package.json`, `code-rs/cli/src/main.rs`, `core/src/rollout/{recorder,policy,catalog,mod}.rs`, `core/src/codex/events.rs`, `core/src/protocol.rs`, `protocol/src/protocol.rs`, `core/src/auto_drive_pid.rs`, `core/src/config_types.rs` (hooks), `core/src/project_features.rs`, `core/src/user_notification.rs`, `core/src/otel_init.rs`, `otel/src/config.rs`, `core/src/agent_defaults.rs`, `core/src/agent_tool.rs`, `core/src/shell.rs`, `core/src/seatbelt.rs`, `core/src/config/sources.rs`.
- Homebrew tap `just-every/homebrew-tap` Formula/Code.rb; npm registry entry.
- Downloaded the arm64 release tarball into the scratchpad (not installed, sha256 5cf4b48d... equals the tap formula). Ran only `--version`, `--help`, `resume --help`, `exec --help`, `acp --help`, with HOME and CODE_HOME pointed at an empty scratch dir; nothing was written there. Ran `strings -a` on it.
- Local: `ps` (nothing), `~/.code` (absent), `~/Library/Caches/just-every` (absent), `/usr/local/bin/code` (dangling symlink to VS Code).
- Probe rules against 21 made-up argv lines (`tools/agents_probe.matches()`, synthetic, not live ps):
  - match tui: cache path `.../just-every/code/0.6.195/code-aarch64-apple-darwin` (bare, and `resume <uuid>` giving that uuid as session id); node_modules `@just-every/code/bin/code-aarch64-apple-darwin --model x`; legacy `coder-aarch64-apple-darwin`; Homebrew `/opt/homebrew/Cellar/code/v0.6.195/bin/code` and `/opt/homebrew/bin/code resume --last` (session id comes out as `--last`, harmless); `... auto goal`.
  - match exec surface: `... exec --full-auto fix` and the self-spawned `... -s read-only exec --skip-git-repo-check Plan`.
  - match daemon: `... mcp-server`, `... app-server`.
  - no match: `... acp`, `... login`, `... --version`, `node .../@just-every/code/bin/coder.js` (argv[0] is node), `node /usr/local/bin/coder`, `/bin/bash /usr/local/bin/code`, VS Code `Electron`, Cursor, the Codex `codex` binary, `zsh -c ls`.

## Findings that change how to detect it

1. Two processes per npm launch. `coder` is a node script that spawns the native binary as a direct child (stdio inherited). Only the native one is matchable, because matching reads argv[0] and the node wrapper's argv[0] is `node`. The native binary usually runs from `~/Library/Caches/just-every/code/<ver>/code-aarch64-apple-darwin`.
2. One process is one session. Unlike current Codex, the TUI runs the agent loop in-process; there is no shared app-server daemon and no `thread-writer-locks`.
3. No sleep inhibitor at all. 0 hits for `IOPMAssertion`, `caffeinate`, `prevent_idle_sleep` in the binary; none in the source. Codex has an opt-in assertion; Every Code has nothing to read from `pmset`.
4. Approval and question events are written to the rollout. `should_persist_event_msg` drops only four event kinds (image generation begin and three delta kinds). In upstream Codex approvals, `request_user_input` and elicitations are explicitly not persisted, so a waiting Codex looks like a quiet open turn. In Every Code, by source, the tail record itself says it is waiting. Not confirmed against a real file.
5. The rollout file is held open by the process (writer task owns the fd, flush per record), so `lsof -p <pid>` names the transcript of an interactive session that has no session id in argv. Inferred from source.
6. Hooks are per project, in the user's config file: `[[projects."/abs/path".hooks]]` in `~/.code/config.toml`. There is no `~/.claude`-style global hooks file and no permission or notification event. Events use dotted names (`session.start`, `tool.before`, `stop`, ...). `UserPromptSubmit` and `Stop` are accepted as aliases.
7. Multi-agent runs spawn the same binary as direct children (`code -s read-only exec --skip-git-repo-check ...`) and also external CLIs (`claude`, `gemini`, `qwen`, `agy`). Both would show up as separate sessions; drop a match whose parent is an every-code process. The probe already keeps only the outer process for same-row matches.
8. `~/.codex` is read, `~/.code` is written. This Mac has real Codex rollouts in `~/.codex/sessions`; `code resume` can list them and resuming one appends to the `~/.codex` file. Tell them apart by `session_meta.originator` and `cli_version`, not by directory.
9. Auto Drive writes `~/.code/auto-drive/pid-<pid>.json` for the whole run (keys: pid, started_at, mode, goal, cwd, command). That is the only per-run liveness file. The `goal` key is private text: read only pid and mode.

## Contradicts the docs or common belief

- `docs/integration-zed.md` says Zed launches `npx -y @just-every/code acp`. In v0.6.195 `acp` is only a visible alias of `mcp` (`code mcp [OPTIONS] <COMMAND>` with list/get/add/remove); `acp --help` prints that. So the documented Zed setup does not start a server by this help output. I did not run it further. The row therefore has no Zed/ACP surface; the servers that exist are `app-server` and `mcp-server`.
- The README says the CLI is `code`. The npm package publishes only `coder`; the `code` shim is created only when no other `code` is on PATH (VS Code is the reason). On this Mac `/usr/local/bin/code` is VS Code's, so an npm user here would get `coder`.
- Docs show hook payload `transcript_path` as `~/.code/sessions/rollout-....jsonl` (flat); the writer creates `sessions/YYYY/MM/DD/`. The row follows the source.
- Naming: OTel events keep the `codex.*` prefix and the originator is `code_cli_rs`; the fork is not "codex" in the process table (`code-aarch64-apple-darwin`, not `codex-aarch64-apple-darwin`), so the `codex` row does not match it.
- OpenTelemetry is logs only (no traces or metrics exporter), unlike current Codex which has all three.

## Could not determine

- Any live behaviour: the real `ps` line, the real argv of the native child (does the wrapper pass extra flags?), whether `lsof` shows the rollout, and whether `task_started` and `exec_approval_request` really appear in the JSONL as inferred. The core `TaskStarted` is a unit variant converted through serde into `TurnStartedEvent`; conversion should succeed but was not seen.
- Whether `/usr/bin/sandbox-exec` execs into the shell (so the tool child shows as `zsh`, not `sandbox-exec`). Assumed from upstream behaviour.
- Homebrew process shape: the tap installs the binary as `bin/code`; I did not check that `brew` links it (a Cellar path and `/opt/homebrew/bin/code` are both listed as inferred).
- Whether `code acp` is meant to be handled elsewhere (docs vs help disagree). What starts the ACP server, if anything, is unknown.
- Two `OTEL_` strings in the binary (likely a dependency's variable names). Not resolved.
- CPU floor and the 30 s hold window: no measurement; borrowed from the Codex row (README section 4).
- Windows and Linux behaviour: not looked at.
- Whether the `[projects."<path>"]` hooks require `trust_level = "trusted"`: the docs example sets it but do not say it is required.

## Privacy

No session content read. No `~/.code` exists here. Key names only were taken from source. The auto-drive pid file's `goal` field is content and is not to be read.

## Verification

Adversarial pass, 2026-09-29, by a second reviewer. Confidence stays `documented`: the harness is not installed and no turn was watched, so it cannot be higher. Re-fetched from just-every/code main (commit fe8dac63d319, v0.6.195), re-downloaded the arm64 tarball into the scratchpad (not installed; HOME and CODE_HOME pointed at an empty dir, which stayed empty), and re-ran `tools/validate_row.py` (ok before and after) and `tools/agents_probe.py --row` (no process on this Mac matches).

Confirmed (checked against the source or the binary again):
- Release v0.6.195, published 2026-09-28T23:10:00Z, nine assets including code-aarch64-apple-darwin.tar.gz at 23178006 bytes (`gh api repos/just-every/code/releases/latest`).
- Tarball sha256 5cf4b48d...96c1 equals Formula/Code.rb; one entry, `file` says Mach-O arm64; `--version` prints `code 0.6.195`. Formula installs it as `bin/code` and writes a bash `coder` shim that `exec`s it.
- Subcommand list, `Usage: code [OPTIONS] [PROMPT]`, `resume [SESSION_ID]`, `exec` having its own `resume`, no `review`, no daemon (main.rs enum Subcommand and `--help`).
- `acp` is only a visible alias of `mcp` (main.rs line 116; `acp --help` prints `Usage: code mcp`), contradicting docs/integration-zed.md, which still says `acp` starts an ACP server.
- npm exposes only `coder` (package.json, registry latest 0.6.195); coder.js prefers `~/Library/Caches/just-every/code/<ver>/code-<triple>`, falls back to legacy `coder-<triple>`, spawns with stdio inherit; postinstall adds a `code` shim only without a conflicting `code`. Platform packages @just-every/code-darwin-arm64 and -x64 exist.
- Rollout path `~/.code/sessions/YYYY/MM/DD/rollout-<local ts>-<uuid>.jsonl`, opened append, one flushed write per record, resume appends (recorder.rs create_log_file, write_line, Resume). Docs example path is flat; the row follows source.
- Persist policy drops exactly ImageGenerationBegin and three delta kinds; TaskLifecycle is dropped by event_msg_to_protocol; TaskStarted is emitted at streaming.rs:2534 and persisted through make_event -> persist_event; protocol wire names task_started/task_complete with turn_* aliases, plus TurnAborted; ExecApprovalRequest, ApplyPatchApprovalRequest and RequestUserInput are core EventMsg variants outside the exclusion list.
- Catalog `sessions/index/catalog.jsonl` with session_id, rollout_path, cwd_real, git_branch, session_source, last_event_at; `history.jsonl`; `archived_sessions`; `auto-drive/pid-<pid>.json` written by exec/src/lib.rs and tui/src/chatwidget.rs, removed on Drop.
- find_code_home order CODE_HOME, CODEX_HOME, ~/.code; README says reads both, writes only ~/.code.
- No sleep inhibitor: 0 hits for IOPMAssertion, caffeinate, 'running an active turn', prevent_idle_sleep; now also 0 for IOPM, PreventUserIdle, NoIdleSleep, keepawake, sleep_inhibit, and `otool -L` shows no IOKit.
- Hooks: eight events, aliases UserPromptSubmit/Stop, env vars, exit 2 semantics, `trust_level`, fields incl. run_in_background (docs/config.md, ProjectHookConfig). `notify` only agent-turn-complete (UserNotification has one variant); `tui.notifications` supports approval-requested. otel: docs text, exporter kinds, logs only, event names, `code_otel` and `codex.conversation_starts` in the binary, service.name = originator.
- Multi-agent children: agent_defaults.rs args `-s read-only exec --skip-git-repo-check` and `-s workspace-write --dangerously-bypass-approvals-and-sandbox exec ...`, cli names include coder, claude, agy, qwen (also copilot, cloud); spawned from CODE_BINARY_PATH or current_exe.
- Shell tool commands: shell.rs `-lc` invocation, seatbelt.rs `/usr/bin/sandbox-exec`. That sandbox-exec execs into the shell stays inferred (no live ps).
- Not installed here: no `~/.code`, no `~/Library/Caches/just-every`, no Every Code process.

Corrected:
- The surface label listed `code auto "goal"` as an interactive TUI command. It is headless: main.rs runs Subcommand::Auto through code_exec::run_main with auto_drive set. Label fixed. It still falls to the tui surface because the exec surface cannot match a bare `auto` (substring test would hit `--full-auto`); this is now stated in the exec label and notes.
- The claim that a bare `code` name is safe against VS Code was too strong. The standalone VS Code CLI is a native binary called `code` (VS Code 1.74 and 1.99 release notes). On the synthetic line `code tunnel --accept-server-license-terms` the old row matched both the tui surface and the daemon surface (`-server` is a substring of `--accept-server-license-terms`). Added exclude_args `tunnel`, `serve-web`, `--install-extension`, `--uninstall-extension`, `--list-extensions` to the tui surface and `tunnel`, `serve-web` to the exec and daemon surfaces; re-run: no match. Residual: `code -r .` from that binary still matches as an idle session.
- The originator hint. The row said Codex uses codex-tui / codex_sdk_ts. Upstream Codex's default originator is `codex_cli_rs` (openai/codex codex-rs/login/src/auth/default_client.rs line 42); Every Code writes `code_cli_rs` (code-rs/core/src/default_client.rs line 8, used by recorder.rs). The Every Code binary also contains the string `codex-tui` (4 hits), so only the `code_` versus `codex` prefix is a safe discriminator, with cli_version as a second. Source entry rewritten.
- The auto-drive pid file leaks the goal in two keys, not one: `goal` and `command` (full argv). The row and notes now say to read only pid and mode.
- The two unresolved `OTEL_` strings are resolved: they are the opentelemetry-otlp crate's standard env var names.

Unsupported or still inferred (left as inferred, not upgraded):
- `lsof -p <pid>` naming the rollout file: follows from the held tokio File, never observed.
- task_started and exec_approval_request appearing as `event_msg` lines in a real JSONL, and the exact JSON shape of the unit-variant TaskStarted after conversion: source only.
- sandbox-exec exec-ing into the shell, so the child shows as zsh/bash.
- Homebrew process shape (`/opt/homebrew/Cellar/code/v0.6.195/bin/code` or `/opt/homebrew/bin/code`): argv[0] path and name not seen in ps.
- The CPU floor of 3% and the 30 s window are borrowed guesses (README section 4).
- tool_children can over-report: PTY exec sessions run `<shell> -lc <cmd>` (exec_command/session_manager.rs) and a long-running command outlives its call. Added to notes; not observed.
- Whether hooks need `trust_level = "trusted"`: docs example sets it, no statement either way.
- The 21 made-up argv lines from the first pass were not re-run one by one; a 16-line subset was re-run on the repaired row (results above in the Corrected list).
