# CodeWhale

Research date 2026-09-30. Not installed on this Mac, so nothing was run. Everything comes from the public repo (https://github.com/Hmbown/Codewhale, main at 568abae, tag v0.10.0) and its docs. Confidence is `documented`, not `verified-locally`.

## What was checked

- **Local absence.** `which codewhale codew deepseek deepseek-tui` printed "not found" four times; `ps` showed no such process; `~/.codewhale` and `~/.deepseek` do not exist.
- **Binary and names.** One Rust binary, `codewhale` (crates/cli, `[[bin]]`). `codew` is a byte-identical copy made by the release workflow. The TUI runs in-process since v0.9.5; no sibling `codewhale-tui` is needed. `crates/tui` still declares a `codewhale-tui` bin (cargo install). macOS release assets: `codewhale-macos-arm64|x64`, `codew-macos-*`, plus `codewhale-tui-macos-*` kept as a compatibility filename. No `.app`, so no bundle id.
- **Wrappers.** The npm bins are node scripts that `spawn(binaryPath, args, {stdio:"inherit"})` the native binary from `<pkg>/bin/downloads/codewhale`. argv[0] of the shim is `node`, so only the native child matches.
- **Working signal.** The interactive TUI spawns `caffeinate -i` (v0.10.0) or `caffeinate -i -w <own pid>` (main) as a direct child for the whole turn (`SleepGuard`, bound to `Engine::run_turn`, gated on `terminal_chrome_enabled`). `exec`, `serve`, `app-server` and `web` never hold it. This is the most precise signal and fits the probe's direct-child rule.
- **Other turn chrome.** Title becomes a whale (frames 🐳🐋🐳🐋) plus a verb, and OSC 9;4;1 progress is written, on the same gate. Not needed given caffeinate; recorded for the terminal-title study.
- **Waiting.** Hook `waiting_for_user` (reason `approval`, `user_input`, `goal_continuation`), `session_idle`, `session_busy`; the opt-in control socket `status` answers `turn_state` = `idle|in_progress|waiting`; the opt-in lifecycle outbox writes `turn.started` and `turn.completed|failed|interrupted|stalled`. All exist in the v0.10.0 tag.
- **Hooks.** 15 events, TOML in `~/.codewhale/config.toml` (`[[hooks.hooks]]`), project file `.codewhale/hooks.toml` only after `/hooks approve`. Fire in the TUI, four events in Runtime API threads, two in `exec --hooks`.
- **Sessions.** `~/.codewhale/sessions/<uuid>.json`, one pretty-printed JSON document per session; legacy `~/.deepseek/sessions` entries are copied in when missing. Top-level keys from the struct: `schema_version, metadata, messages, journal, leaf_id, system_prompt, context_references, artifacts, work_state, window_title`. Sidecars: `sessions/<id>/` (runtime store, `control.sock`, `approval_receipts.jsonl`), `sessions/checkpoints/<id>.json`, and an exclusive flock on `sessions/.late-usage/<id>.live` while a process owns the session. Retention cap 50 active transcripts, older ones archived. I did not read a record; key names are from the source.
- **Process to session.** `--resume/-r <id or prefix>`, `--session-id`, `-c/--continue`; `codewhale resume <id>` is a positional subcommand. A fresh session has no id in argv.
- **Telemetry.** No OpenTelemetry anywhere in the Rust workspace (Cargo.lock has no opentelemetry crate; the only OTLP mentions are in `pet/`, a separate visualiser that imports traces). Product analytics: aggregate batches to telemetry.codewhale.net, on by default, `CODEWHALE_TELEMETRY=0` to stop.
- **Row rules.** Ran the row through `tools/validate_row.py` (ok) and through `agents_probe.matches()` on 13 synthetic argv: `codewhale`, full path with `--resume`, `codew`, `exec`, `doctor`, `--version`, `serve --http`, `app-server --http`, `web`, a prompt containing "web", `deepseek-tui`, the node shim. Results as intended; `web` and `doctor` are dropped.

## Could not determine

- Whether a running TUI really keeps `caffeinate` during an approval or question wait. Source says the guard lives for the whole `run_turn` and approvals are awaited inside it, so I expect yes, but it was never observed. If so, working reads true while the agent is blocked on the human.
- When the session JSON is autosaved (per message, per turn end, or on a timer). Because of that, `transcript_write` is not listed. A write at turn end would keep "working" up for the hold window.
- The exact ps shape of a shell tool call on macOS. Source says `/usr/bin/sandbox-exec -p ... /bin/sh -c ...` in its own process group, with a simple command exec'd in place; not observed. MCP servers, LSP and background shells are long-lived children, so `tool_children` is left out.
- Whether `checkpoints/<id>.json` is removed at turn end (it would then be a clean open-turn record).
- Desktop app: bundle id, process name and store are unknown; it is a development build with no public download. The VS Code extension is community-made and its process layout is unknown. Hence surfaces without a `process`.
- `codewhale web`, `serve --web|--acp|--mcp` and legacy `app-server` cannot be matched without matching bare words that appear in prompts; only `--http` is matched (daemon, `host: true`). Per-thread state there needs `GET /v1/threads/running` with the bearer token.
- No exact pid to session mapping without lsof on the `.late-usage/<id>.live` flock (inferred, untested) or reading the control-socket directory name.
- Grok Bot was mentioned in the launching request but is not part of this task; no file was written for it.

## Contradicts common belief

- The name is not `deepseek-tui` any more. `deepseek`/`deepseek-tui` are the pre-rebrand binaries (before 0.8.41). Current name is `codewhale`, alias `codew`. Env vars stay `DEEPSEEK_*` and hooks still set `DEEPSEEK_SESSION_ID`, which is why the old names keep turning up.
- The hook session id `sess_xxxxxxxx` is not the saved-session UUID in the file name. A hook cannot be joined to a transcript by id alone.
- Sessions are one whole JSON document, not JSONL. Rewritten atomically, so mtime is a save time, not a per-event stream.
- The `deepseek-harness` row (dsh, Electron app) is a different product. CodeWhale can connect to it (`codewhale integrations dsh`), but the two share no process names.
- Two binaries used to exist (dispatcher plus TUI child) up to v0.9.4. No release before v0.10.0 holds caffeinate at all (see Verification), so those installs only have tree_cpu, which sums the dispatcher's whole tree. Current builds are one process.
- Telemetry is on by default, but it is not OpenTelemetry and carries no turn timeline.

## Verification

Second-pass review, 2026-09-30, by a reviewer who did not write the row. Method: fresh partial clone of https://github.com/Hmbown/Codewhale at main 568abae (0.10.1 candidate) plus tags v0.8.40 to v0.10.0, `gh api`, a live fetch of https://codewhale.net/en/product, and `agents_probe.matches()` run on 34 synthetic argv. The harness is not installed here, so confidence stays `documented` at most. `tools/validate_row.py` passes after the repairs.

### Confirmed

- One binary `codewhale`, `codew` a byte-identical copy, TUI in-process from v0.9.5 (`run_tui_in_process` count 0 in v0.9.4, 27 in v0.9.5; ENVIRONMENTS.md; INSTALL.md "64 MiB each, Mach-O arm64"). npm shim spawns the native binary with stdio inherited (`npm/codewhale/scripts/run.js` line 68).
- Rebrand in v0.8.41 (tag dated 2026-05-23); `.codewhale` vs legacy `.deepseek` in `crates/paths/src/lib.rs`; DEEPSEEK_* env vars still honoured.
- Latest release v0.10.0 (2026-09-22T17:28:34Z), macOS assets `codewhale-macos-*`, `codew-macos-*`, `codewhale-tui-macos-*`; main is `0.10.1`; only tag `v0.10*` is v0.10.0.
- v0.10.0 sleep guard: `spawn("caffeinate", &["-i"])`, gated on `terminal_chrome_enabled`, held in `run_turn`; main uses `["-i","-w",pid]` (`crates/runtime/src/sleep_guard.rs` caffeinate_args). Exec (`exec_agent.rs:673`) and Runtime API threads (`runtime_threads.rs:13605`) set `terminal_chrome_enabled: false`. Whale title frames and OSC 9;4 progress ride the same gate.
- Sessions: `<uuid>.json` per session, pretty-printed by `serde_json::to_string_pretty`, written with `write_atomic`; top-level keys match the `SavedSession` struct (the row lists the main ones; the struct also has `approval_receipts`, `last_auto_route`, `turn_outcomes`, all optional); retention cap `MAX_SESSIONS = 50` with archive; `.late-usage/<id>.live` flock lease; `checkpoints/<id>.json`; `<sessions>/<id>/control.sock`.
- Process to session: `-r/--resume`, `--session-id`, `-c/--continue` exist in the `Cli` struct; `resume`/`fork` are positional subcommands.
- Hooks: 15 events (counted), three steering events, `waiting_for_user` reasons, `session_busy`/`session_idle` in the v0.10.0 tag, scope table (TUI yes, exec `--hooks` 2 events, Runtime API 4 events), project `.codewhale/hooks.toml` needs `/hooks approve`.
- Control socket (`status` returns `turn_state` idle|in_progress|waiting, off by default, in v0.10.0), lifecycle outbox event names, Runtime API `GET /v1/threads/running`, `codewhale web` on 127.0.0.1:7878, `serve`/`app-server` flags (`--http`, `--mobile`, legacy 8787).
- Subcommand veto list equals the clap `Commands` enum plus aliases (`tts`, `receipt`, `cloud`, `cloud-agent`, `completions`). `run`, `resume`, `rc`, `fork` are deliberately not vetoed because they open the interactive TUI (`Commands::Rc` passes `--remote-control`).
- Shell tools on macOS use `/usr/bin/sandbox-exec -p` (`seatbelt.rs`), spawned with `process_group(0)` (`shell.rs` lines 2389, 2540, 2749, 2778).
- Desktop app: "Development build ... public download is coming later" and hosted web "Development preview" on the product page; GPUI and "separate repository" in `README.<lang>.md` line 58; VS Code extension `HengQuWorld.brotherwhale-vscode` and helper id `net.codewhale.computer-use.helper` in `README.md` and `crates/tui/build.rs`. Author name "Hunter Bown" from `gh api users/Hmbown`.
- Legacy `deepseek-tui` was spawned by the `deepseek` dispatcher (v0.8.40 `delegate_simple_tui`), upgraded from "inferred" to source-confirmed. Not observed running.
- No OpenTelemetry: `opentelemetry` count in Cargo.lock 0; matches for OTEL/OTLP only in `pet/` and `telemetry-ingest/package-lock.json`.
- Approval wait keeps the guard: still inferred, not observed. `await_tool_approval` is a method awaited from tool execution inside the engine turn (`approval.rs` line 184); no run was possible.

### Corrected

- **Caffeinate exists only from v0.10.0.** The row and notes implied the 0.8.41 to 0.9.4 `codewhale-tui` child holds caffeinate. It does not: `sleep_guard.rs` is absent from v0.8.40, v0.8.41, v0.9.0, v0.9.4, v0.9.5, v0.9.10 and v0.9.13, and CHANGELOG [0.10.0] introduces it. Before v0.10.0, and for legacy `deepseek-tui`, the only working signal is tree_cpu. Row: signal meaning, legacy surface label, source and notes (7) rewritten.
- **Telemetry wording.** The row said "PostHog-backed batch". TELEMETRY.md says batches go to the first-party ingest and the PostHog sink is optional and inert until the operator configures it. Row `telemetry.how`, source claim and notes rewritten.
- **Local-observation source.** "~/.local/bin holds codex only" was false (23 entries). Replaced with the commands that were re-run, adding /opt/homebrew/bin, ~/.cargo/bin, /usr/local/bin and `npm ls -g`, all empty for these names.
- **Homebrew.** INSTALL.md documents Homebrew for Linux only, but the tap formula `Hmbown/deepseek-tui/codewhale` has a macOS block. TUI label now names the tap.
- Sessions glob note: `~/.codewhale/sessions/*.json` also matches `session_boot_owners.json`, which is not a session.

### Unsupported or limited (kept, with the limit stated in the row)

- **False positives in the process patterns, tested.** `args_contain` is a substring test on every argument, so an interactive `codewhale` whose argument merely contains `exec` (`-C ~/executive`, `--model x-exec`, a prompt about an "executor") is filed as the one-shot surface, where alive means working; a prompt containing `--http` is filed as a daemon host. `exclude_args` is an exact match on any argument, so a prompt equal to a vetoed word, or a flag value such as `--workspace model`, hides a real session. The registry has no positional match, so this cannot be repaired in the row (README section 3 case 16); it is now written into the surface labels and notes. A `path_contains` trick would widen the match to unrelated programs, so it was not used.
- Name collisions: `codewhale`, `codew`, `codewhale-tui` and `deepseek-tui` are not known to be used by other programs; `deepseek` is correctly left unmatched. Dispatcher-era (0.8.41 to 0.9.4) trees have both `codewhale` and `codewhale-tui` matching; the outermost rule reports the dispatcher, and tree_cpu covers the child.
- The 3% CPU floor is the registry default, not measured for this harness. `working_signals` for `exec` and the Runtime API host rest on it alone.
- Whether caffeinate stays held during an approval wait, when the session JSON autosaves, and the ps shape of a shell tool call remain unobserved. Everything the row says about them is marked inferred.
- Desktop app bundle id and process name are unknown; nothing is matched for it.
