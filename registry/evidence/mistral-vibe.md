# Mistral Vibe: evidence notes (2026-09-29)

Not installed here (no `vibe`, no `~/.vibe`, nothing running, no VS Code extension, `import setproctitle` fails). Every claim comes from the official docs and a shallow clone of `github.com/mistralai/mistral-vibe` (main at 7c19608, 2026-09-23, package 2.25.8), read only, in the scratchpad. Nothing was executed, so nothing is `verified-locally`. Confidence is `documented`.

## Shape

```
Python TUI (default)      python -> setproctitle -> ps shows "Vibe CLI"     ONE process, agent in-process
Rust TUI (VIBE_CLI=rust)  vibe-rs  (execvpe from the python launcher)
                           '- vibe-app-server (python script)               agent lives here
vibe-acp                  editor child (Zed, JetBrains, Neovim, VS Code ext) hosts many sessions
vibe-app-server           desktop clients; also the Rust TUI's child          hosts many sessions
tool shell, legacy        TUI -> /bin/sh -c <cmd>                            direct child
tool shell, unified       TUI -> python pty helper -> $SHELL -lc <cmd>       shell is a grandchild
```

## What I checked
- Surfaces: three console scripts in `pyproject.toml` (`vibe`, `vibe-acp`, `vibe-app-server`). Default install is `uv tool install mistral-vibe` (installer script or by hand), so the real process is a venv python running a script. PyInstaller specs exist for `vibe`, `vibe-acp`, `vibe-app-server` (Zed uses the `vibe-acp` one).
- Process name: `vibe/cli/entrypoint.py::_set_process_title` calls `setproctitle.setproctitle("Vibe CLI")` first thing in `main()`. Applies to every subcommand. No other module retitles.
- Rust TUI: `launcher.py` gates on `VIBE_CLI=rust`, `_rust.py` execs `vibe/_bin/vibe-rs`, `startup/launch.rs` spawns `vibe-app-server`. Wheel bundles `vibe/_bin/*`.
- Session id: `--resume [ID]` (partial match allowed), `-c/--continue` (no id). A fresh launch has none. Since the TUI erases argv, the id is gone from `ps` for the default TUI anyway.
- Pid to session: `~/.vibe/logs/session/active/<id>.lock.json` with `process_id`, from `session_lease.py`. Same file in the unified store.
- Store: legacy `~/.vibe/logs/session/session_<UTC ts>_<id8>/{meta.json,messages.jsonl}`. Unified `~/.vibe/logs/session/unified/<id>/{CURRENT,journal/<16 digits>.jsonl,chunks/}`. Key names were read from the `SessionMetadata` and `LLMMessage` types and the save code, not from a file (no file exists here).
- Working: no caffeinate or power assertion anywhere (grep over `vibe harness docs README.md CHANGELOG.md`). Save cadence of `messages.jsonl` read from `_loop.py`. Shell children read from `core/utils/shell.py` and the unified `_processes/_posix.py`.
- Waiting: `TextualNotificationAdapter` and the Rust `terminal_notifier.rs` both write OSC 0 titles `>> title` (running) and `? title` (waiting); default on. Bell and the `- Action Required` / `- Task Complete` suffix only when unfocused.
- Hooks: `pre_tool`, `post_tool`, `post_agent` in `hooks.toml` (user and trusted project). Official page fetched and matches the README.
- OTel: `enable_otel` (default false) + `enable_telemetry` (default true), OTLP/HTTP, `BatchSpanProcessor`.
- Surfaces beyond the terminal: VS Code extension `mistralai.mistral-vibe-code` (docs, marketplace: macOS arm64 and x64), ACP for Zed/JetBrains/Neovim, Vibe Code Web (cloud, via `/teleport`).
- I ran the row's surfaces through `tools/agents_probe.py` `matches()` on 11 made-up command lines (uv-tool python + `vibe`, `vibe-acp`, `vibe-app-server`, the pty helper, `vibe-rs`, frozen `vibe-acp`, an extension path, `Vibe CLI`, unrelated python). All matched the intended surface or none. Made-up input, not a real process list.

## Could not determine
- Whether macOS `ps` really shows `Vibe CLI` after `setproctitle`. Inferred from the library's documented behaviour and source; not seen. If it does not, the `python ... /bin/vibe` surface is the only match and every flag is visible again.
- The VS Code extension's bundled binary: name, folder, whether it is a PyInstaller `vibe-acp` or python. The row's path prefix `/extensions/mistralai.mistral-vibe-code-` is a guess from VS Code's naming; I did not download the VSIX.
- Vibe Desktop: only the CHANGELOG mentions it (local Code sessions, one app-server process per session, released a second after each turn). No public download, bundle id or executable name found; Reddit users were asking what it is. No surface written for it. The App Store "Vibe by Mistral (ex-Le Chat)" is iPhone/iPad/visionOS only.
- Which session layout a given user gets. `vibe_cli_unified_harness_rollout` is a server-side flag; the harness is bundled since 2.25.6 and unmarked as experimental. I cannot see the rollout share. Both globs are recorded.
- CPU floor and window: 3% and 30 s are guesses. No turn was observed.
- Whether an idle Python TUI really sits near 0% (Textual timers, blinking cursor).
- Whether Rust `vibe-rs` sets any terminal title when `experimental_enable_tab_status` is off (it sets `SetTitle("Vibe")` at start).
- Homebrew or Nix packaging. `flake.nix` exists; no brew formula is documented.
- The PyInstaller `vibe` release zip is macOS ad-hoc signed and not notarized per a workflow comment; no evidence anyone runs it. No surface written.

## Contradicts common belief or the obvious approach
- The process is not called `vibe` and not `python`. It renames itself `Vibe CLI` (two words), so a name match on `vibe` finds nothing, and `ps` splits into `Vibe` + `CLI`. The row keys on that. (Compare `hermes`, where setproctitle is not a dependency and the rename does not happen.)
- Renaming also erases the flags: `--resume <id>`, `-p`, `--agent` are not in `ps`. One-shot `vibe -p` cannot be told from a TUI. `session_id_args` can only work for the Rust TUI and for the short pre-retitle window.
- `vibe-acp` and `vibe-app-server` are NOT retitled, so they show as `python .../bin/vibe-acp`, and they are on the same install as the TUI. Name-only matching on python would swamp the list; the row requires the script path.
- The Rust TUI is not a separate product but a second front-end on the same Python engine, spawned as a child. From the probe's view its tool shells are grandchildren.
- No sleep inhibitor at all, unlike Claude Code and Qwen Code. No `caffeinate`, no assertion.
- The best turn signal is the terminal title, not a process or file. `>>` means running and `?` means waiting; it is on by default but only in source and the bundled skill text, not in the docs. Docs only promise notifications.
- Hooks are only three (`pre_tool`, `post_tool`, `post_agent`). `pre_tool` fires before the permission prompt, so it is not a wait signal. There is no turn-start hook, so a hook-only tracker cannot see a turn that has not yet called a tool.
- Session logs are written per model step, not per token; and there are two on-disk formats depending on a server-side flag. The sibling docs and third-party pages describe only `~/.vibe/logs/session/` with `messages.jsonl`.
- `per_session` cannot take a full uuid: folder names carry the first 8 characters only.
- `experimental_enable_tab_status` is still named experimental although it defaults to on.
- "Vibe" also means the renamed Le Chat (mobile app, web "Work"/"Code" products). Only the Code CLI, its ACP server and the VS Code extension run on the Mac as far as public sources show.

## Author checks
- `tools/validate_row.py registry/agents/mistral-vibe.json` -> `ok`.
- `tools/agents_probe.py --row registry/agents/mistral-vibe.json` on this Mac -> 0 sessions (nothing installed), as expected.

## Verification
Adversarial re-check, 2026-09-29, by a second agent. Repo re-cloned at the same commit (7c19608, 2026-09-23, 2.25.8; `git ls-remote` HEAD unchanged). Docs re-fetched. Nothing installed or run except read-only commands and one `subprocess.Popen` of `sleep` to see how `ps` shows a shell child. `tools/validate_row.py` -> `ok` before and after. Confidence stays `documented`: the harness is not installed here, so nothing can be `verified-locally`.

Confirmed
- Version 2.25.8, three console scripts, Python >= 3.12, CHANGELOG date 2026-09-23 (pyproject.toml, CHANGELOG.md).
- Installer runs `uv tool install mistral-vibe` and prints `commands: vibe, vibe-acp` (re-ran `curl https://mistral.ai/vibe/install.sh`).
- `setproctitle.setproctitle("Vibe CLI")` is the first call in `main()`; `setproctitle==1.3.7` is a hard dependency; no other module retitles (grep over `vibe` and `harness`). So `vibe-acp` and `vibe-app-server` keep their argv.
- Launcher: `VIBE_CLI=rust` execs `vibe/_bin/vibe-rs` in place; `--internal-posix-pty-helper` and `update` stay in Python; `VIBE_APP_SERVER_BIN` is the script beside the launcher.
- Python TUI runs the app server in process (`memory_transport_pair` in `vibe/app_server/local.py`, used from `vibe/cli/cli.py`).
- Title indicators `>>` / `?` / `- Action Required` / `- Task Complete`, OSC 0, both `textual_notification_adapter.py` and `terminal_notifier.rs`; `experimental_enable_tab_status = True` and `enable_notifications = True` in `vibe_schema.py`; headless writes nothing.
- Docs row `enable_notifications | boolean | true | OS-level notifications when a long task finishes or input is needed` (fetched from the configuration reference). The tab-status option appears only in the schema, the built-in skill text (`vibe/core/skills/builtins/vibe.py:192`) and CHANGELOG line 257, not in the docs.
- Hooks: three types, both file locations, project first and trusted-only, payload keys, `pre_tool` before the permission prompt, `post_tool` only if the tool ran, `post_agent` after a turn with no pending tool calls (docs page fetched).
- OTel: `enable_otel` default false, needs `enable_telemetry`, OTLP/HTTP, `/v1/traces` (README, schema lines 535-592).
- Session store: `~/.vibe` default, `VIBE_HOME` override, `meta.json` and `messages.jsonl`, `SessionLoggingConfig` defaults, folder name `<prefix>_<UTC ts>_<id8>`. Key names of `SessionMetadata` and `LLMMessage` match `vibe/core/types.py`. Lease files `active/<id>.lock(.json)` with `lease_version, session_id, process_id, acquired_at` (`session_lease.py`, and the twin in the harness `_storage.py`). `MISTRAL_VIBE_SESSION_ROOT` is read by the unified host only.
- Unified layout `unified/<id>/...` under `~/.vibe/logs/session` and the selection order in `resolve_harness_selection` (legacy flag, then experimental flag, then rollout cache, then legacy). CHANGELOG 2.25.6 bundles the runtime.
- No `caffeinate`, `IOPMAssertion`, sleep-inhibit or wakelock anywhere (same grep, no output).
- Zed extension: `./vibe-acp` from `vibe-acp-darwin-{aarch64,x86_64}-2.25.8.tar.gz`; PyInstaller specs name `vibe`, `vibe-acp`, `vibe-app-server`; ACP `request_permission` in `vibe/acp/agent.py`.
- VS Code extension `mistralai.mistral-vibe-code` 1.22.86, macOS Apple Silicon and Intel, agent built in, runs through ACP, shares config and sessions with the CLI (both docs pages and the Marketplace page re-fetched). The marketplace lists per-platform builds, so the folder is probably `mistralai.mistral-vibe-code-<ver>-darwin-<arch>`, which the `/extensions/mistralai.mistral-vibe-code-` prefix still matches.
- Vibe Desktop only in CHANGELOG (line 15 and others) and README line 970; no public bundle id or download found again. An unofficial third-party app called VibeZ exists; it is not Mistral's and is not a surface.
- Process patterns, run through `agents_probe.matches()` on 16 made-up command lines: `Vibe CLI`, uv-tool and Homebrew-shaped python lines, `vibe-rs`, frozen `vibe-acp`, extension path all hit the intended surface; unrelated python and node lines did not.

Corrected
- Homebrew. The old claim "no Homebrew formula is documented" was wrong. README line 984 says `brew upgrade mistral-vibe` and homebrew-core has `mistral-vibe` (stable 2.25.0, `python@3.14`, virtualenv; `brew info` printed it). It runs as a venv python with the script path, so the interpreter surfaces already cover it. New source added.
- Shell child name. The old text said `ps` shows `/bin/sh -c ...`. `executable=$SHELL` replaces argv[0], so it is `/bin/zsh -c ...` on a default macOS account (observed with Python's `subprocess` and `/bin/zsh`). Both are in the probe's `SHELLS` set. Worse for `tool_children`: a single simple command is exec'd in place, so `ps` shows `sleep 2` and no shell at all (observed). The signal is weaker than the row said; meaning text and notes fixed.
- Frozen pty helper. A frozen `vibe-app-server` re-runs itself as `vibe-app-server --internal-posix-pty-helper <fds>` (`_posix.py::_helper_argv`; `vibe/app_server/entrypoint.py` handles the flag). Surface 1 matched that helper by name. The probe hides it only because its parent matches. Added `exclude_args: ["--internal-posix-pty-helper"]` so the row is right without the parent rule.
- Rust TUI storage. Its app-server child is always started with `--experimental-harness` (`process.rs` line 84), so it always uses the unified store, not "whatever the server flag says". The lease pid is the child's pid. Added to the surface label and notes.
- Interpreter false positives were understated. `args_contain: "/bin/vibe"` is a substring test, so python running `bin/vibe.py`, `bin/vibecoder` or `bin/vibe-kanban` matches the pre-retitle surface (tested). Cannot be tightened with the current schema; notes say so.
- Lease files exist only while `session_logging.enabled` is true (`_acquire_session_lease` returns None otherwise). Added to notes.

Unsupported or still inferred
- That macOS `ps` shows exactly `Vibe CLI` for this program. Now backed by a third-party report that `setproctitle` changes `ps` output on macOS when its native module loads (py-setproctitle issue 128; version 1.2.3, not 1.3.7), and by the library README listing macOS as supported. Not observed with Vibe or with 1.3.7. If the module fails to load, the call is a silent no-op and the pre-retitle python surface takes over, so the row degrades to a match, not a miss.
- The VS Code extension's process path (`/extensions/mistralai.mistral-vibe-code-`). Marketplace and docs confirm the extension and the ACP subprocess, not the folder layout or the executable name. VSIX not fetched.
- `tree_cpu` floor 3%, `transcript_write` window 30 s, and idle CPU of the Python TUI. Guesses, unmeasured.
- Vibe Desktop process shape. No source.
- Which session layout a given user gets (server-side rollout flag). Cannot be seen from outside.
- The `Vibe` + `CLI` retitle surface could in theory match an unrelated program whose argv[0] basename is `Vibe` and has an argument containing `CLI`. Not found; an Electron app named Vibe does not match because its arguments carry no `CLI`.
