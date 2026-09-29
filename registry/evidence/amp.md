# Amp: evidence notes (2026-09-29)

Row: `registry/agents/amp.json`. Validator: ok. Probe on this Mac: 0 Amp processes, so nothing was classified live. Confidence is `documented`, not `verified-locally`.

## What I checked

- Official docs (scraped and `curl` of the `/docs/markdown/<page>` variants): manual/intro, `/docs/cli`, `/docs/cli/settings`, `/docs/cli/runners`, `/docs/cli/execute-mode`, `/docs/cli/streaming-json`, `/docs/cli/remote-control`, `/docs/macos-and-ios`, `/docs/macos-and-ios/runner`, `/docs/customize/plugins`, `/docs/plugin-api`, `/docs/threads`, `/docs/tools`, `/docs/support/reporting-bugs`, `/security`, news post "The Coding Agent Is Dead".
- Installer: `https://ampcode.com/install.sh` (read in full, not run). npm metadata for `@sourcegraph/amp`, `@ampcode/cli`, `@ampcode/sdk`, `@ampcode/plugin`. Unpacked `@ampcode/cli` (install.cjs), `@ampcode/sdk` and `@ampcode/plugin` tarballs into scratch to read them. `github.com/ampcode/amp` is private (API 404), so there is no public CLI source.
- The vendor binary itself, downloaded but never executed or installed: `amp-darwin-arm64.gz` v0.0.1790672760-g076f82 (sha256 matches the published `.sha256`). It is a Bun single-file binary; the JS is stored as UTF-16 runs, so I extracted them with python3 (macOS `strings` has no `-e`) and grepped. Plain `strings -a` was used for the ASCII side.
- The Mac app: downloaded `Amp-1.0-634.dmg`, decoded the UDIF blocks in python (LZFSE via `compression_tool`), never mounted it. Read Info.plists and strings from the raw image.
- Third parties: txcript's `docs/formats/amp.md`, a 2026-08-06 blog on session-log paths, a vibeproxy issue quoting `cli.log`.
- Local machine: `which amp` (none), `ls ~/.config/amp ~/.local/share/amp` (absent), `ps` for amp/ampcode/sourcegraph (nothing). No session store exists here, so no private data was touched.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | (1) CLI: interactive TUI, `amp -x/--execute` one-shot, `amp --no-tui` runner. (2) Amp for macOS app (beta, macOS 26+). (3) Web, iOS/iPadOS app, orbs (cloud). (4) No editor extension any more | docs, news |
| Process name | `amp` (Bun compiled binary). npm installs store `bin/amp` and make `bin/amp.exe` a symlink on macOS so the process still shows as `amp` | install.cjs comment |
| Paths | `~/.amp/bin/amp` (real file, from install.sh) with symlink `~/.local/bin/amp`; Homebrew `/opt/homebrew/Cellar/ampcode/<ver>/bin/amp` (formula `ampcode`); npm `.../@ampcode/cli/bin/amp` | install.sh, binary strings |
| Bundle ids | Mac app `com.ampcode.amp.macos` (executable `Amp`, `/Applications/Amp.app/Contents/MacOS/Amp`; share extension `com.ampcode.amp.macos.share`). CLI has none | Info.plist in DMG |
| Process to session | Interactive `amp` takes no session-id flag and one process can host several threads (background threads, `amp.thread.autoArchiveOnQuit`). `amp threads continue T-...` passes the id positionally. Only a running shell-tool child carries the id in its env (`AMP_CURRENT_THREAD_ID`, `AGENT_THREAD_ID`, plus `AGENT=amp`) | docs, binary |
| Store | Server-side. No local transcript in the current CLI (data dir has no `threads/`). Local diagnostics only: `~/.cache/amp/logs/cli.log`, `logs/threads/<T-id>.log` (execute and headless modes only, 7-day purge), `logs/no-tui.log`, `~/Library/Logs/Amp/runner.log`. Prompt history `~/.local/share/amp/history.jsonl`, token in `~/.local/share/amp/secrets.json` (documented on /security) | docs, binary |
| Turn in progress | In-process: agent loop state not `idle`. From outside: a `/bin/bash -c` child of amp (shell tool), then CPU. No transcript write, no power assertion | binary |
| Waiting on human | In-process state `awaiting_approval` (plugin API `ThreadState` `awaiting-approval`, TUI label "Waiting for Approval"). Outside: transient `afplay Ping.aiff` child of amp, if notifications are on and the terminal is not focused. `afplay Submarine.aiff` marks turn end | binary, settings docs |
| Hooks | No hook config. TS/JS plugins (`.amp/plugins/`, `~/.config/amp/plugins/`, personal and workspace plugins): `session.start`, `tool.call`, `tool.result`, `agent.start`, `agent.end`, `changes.prompt`. No `session.end` | plugins docs |
| OpenTelemetry | No. Only `@opentelemetry/api` is bundled, no exporter, no `OTEL_EXPORTER_*` read | binary |

## Could not determine

- Real `ps` output for a live Amp. I did not run the binary. `names: ["amp"]` rests on the npm installer's comment and on the file name. Whether Bun rewrites argv or `process.title` is unknown. The `path_contains` entries only help if the detector resolves the executable path rather than reading `ps` args.
- CPU floor for `tree_cpu` (5 percent is a guess) and whether the TUI redraws enough at idle to matter.
- Whether persistent children of an idle CLI exist in practice. Source shows stdio MCP servers and plugin runtime processes are spawned as long-lived children (`AMP_PLUGIN_RUNTIME_LOG_FILE`), which is why the row keys on a `bash` child name and not on "any child". I did not see what executable the plugin runtime is.
- Whether `afplay` appears when the terminal is focused (source says it is skipped, so the focused case is invisible) and whether Amp also plays sounds when launched from the Mac app runner (a runner has no TUI, so probably not).
- The `~/.local/share/amp/ide/*.json` schema (`workspaceFolders, port, ideName, authToken, pid`) and whether anything still writes it now that the extensions are gone. Likely only amp.nvim, which is deprecated.
- Bundle id of `Amp Desktop Helper.app` (only installed for `amp --no-tui --desktop`, under `~/.amp/bin/amp-desktop-helper/<version>`). Not in the docs and I did not look inside its zip.
- iOS app bundle id (irrelevant on a Mac).
- Whether the permission rules in the binary (`amp.permissions` with `allow|reject|ask|delegate`, guarded-file prompts, `--dangerously-allow-all`) are meant to be public. They exist in the binary but the current docs page says plugins are the way.

## Contradicts common belief or the hint

- "Editor extensions" no longer exist. Amp killed its VS Code and Cursor extensions on 2026-03-05 ("The Coding Agent Is Dead"). Editors only connect to a running CLI. The row has no `ide` surface.
- "Sourcegraph's agent": the product is now branded Amp (ampcode.com). The npm package `@sourcegraph/amp` is a thin wrapper that depends on `@ampcode/cli`. Amp is now mostly cloud-side: orbs, runners, Puck. The Mac app does not run the agent.
- Sessions are not local files. Older guides (and txcript, the third-party format doc) point at `~/.local/share/amp/threads/T-*.json`. The current binary has no such directory; the txcript doc itself says it is a legacy artifact. A tail-the-transcript detector would find stale files and mis-read them. That is why `session_store` is omitted.
- No caffeinate or IOKit assertion in the CLI, unlike Claude Code. The Mac app does hold an activity, but only while its runner is on ("Keep This Mac Awake"), not per turn, so `power_assertion` would say "working" all day. Do not use it.
- The Mac app looks like the obvious thing to match, but matching its process would swallow the `amp --no-tui` runner it launches (probe keeps the outermost match) and give a permanently idle row. The row matches it by bundle id only.
- Docs say Amp does not ask for approval by default. So "waiting on the human" is rare in default setups; it only appears with plugin `ctx.ui.confirm`, permission rules, guarded files or MCP approvals.
- `amp -x` and `amp --no-tui` are not the TUI. The TUI surface excludes them by exact argument; the `-x` surface uses a substring match on `-x`, so an unrelated argument that contains `-x` would also match.

## Verification

Adversarial re-check on 2026-09-29 by a second reviewer. Validator: `ok` before and after. Confidence stays `documented` (harness not installed, no Amp process observed). Method: re-fetched every cited docs page, the installer, npm metadata and tarball, the Homebrew API, the third-party pages; re-hashed the downloaded CLI binary (sha256 16c83e76... equals the published `darwin-arm64-amp.sha256`, latest version file still `0.0.1790672760-g076f82`); re-extracted its UTF-16 and ASCII string runs with my own script and re-grepped; re-read the Mac app Info.plists from the raw DMG; replayed synthetic `ps` lines through `tools/agents_probe.py` `matches()` before and after the repair. Nothing was executed or installed. The bash-child, afplay and CPU signals were not observed live.

### Confirmed

- Install: `install.sh` uses `BIN_DIR=$AMP_HOME/bin` (default `~/.amp/bin`) and links into `~/.local/bin`; npm `@ampcode/cli` `install.cjs` stores `bin/amp` and symlinks `bin/amp.exe`, with the Activity Monitor comment quoted in the row.
- Mac app: `com.ampcode.amp.macos`, executable `Amp`, package type `APPL`, `LSMinimumSystemVersion` 26.0, Sparkle embedded; share extension `com.ampcode.amp.macos.share`. Runner command `amp --no-tui --no-serve-cwd --runner-id <name>` in the home folder, suffix `-amp-app` (runner docs). Beta status (macos-and-ios docs).
- Flags `--no-tui`, `--runner-id`, `-x/--execute`, `--executor local|orb|runner:<id>`, `--stream-json` (cli, runners, execute-mode, streaming-json docs).
- Plugin events `session.start`, `tool.call`, `tool.result`, `agent.start`, `agent.end`, `changes.prompt` are exactly the `PluginEventMap` keys, so no `session.end`; `agent.end` status `done|error|cancelled`; plugin locations and `amp plugins list|add` (plugins docs).
- `ThreadState = 'idle' | 'running' | 'awaiting-approval' | 'error'`; TUI states and label "Waiting for Approval" (plugin-api docs, binary).
- "Amp does not ask for approval before running tools" (tools docs, twice).
- Threads are server-authoritative; run in an orb, on a runner or in a local CLI session (threads docs).
- Agent shell tool: `/bin/bash`, then `/usr/bin/bash`, then `/bin/sh`, with `AGENT`, `AI_AGENT`, `AGENT_THREAD_ID`, `AMP_CURRENT_THREAD_ID`, stdio piped.
- Notification sounds Submarine (idle), Glass (idle-review), Ping (awaiting approval); 2000 ms throttle; skipped when terminal reports focus; BEL over SSH or `AMP_FORCE_BEL`; `amp.notifications.enabled` default true (settings docs).
- No OTLP exporter: `OTEL_` hits are only `unset OTEL_EXPORTER_OTLP_*` in launch scripts for other agents; only `@opentelemetry/api` bundled.
- No `caffeinate`, `IOPMAssertion` or `PreventUserIdle` string in the CLI binary. The Mac app has `beginActivityWithOptions`, `MacKeepAwakeController`, "Keep This Mac Awake".
- Logs: `cli.log` (10485760 default cap, `AMP_MAX_LOG_FILE_SIZE`), `logs/threads/<id>.log` purged after 604800000 ms by mtime, called from the execute path (`EVt(),UOe()`) and the headless path, `logs/no-tui.log`; Mac app strings `Logs/Amp/runner.log`.
- Editor extensions killed 2026-03-05 ("The Coding Agent Is Dead": "self-destruct on March 5 at 8pm Pacific Time"); amp.nvim README says deprecated; `ide connect` documented in the CLI docs.
- Legacy thread files: txcript doc says they are a legacy artifact of CLIs up to early 2026 (verified by bisection there).
- `~/.cache/amp/logs/cli.log` path appears in vibeproxy issue 363.

### Corrected

- Process patterns, false positive (repaired): `path_contains` entry `/.amp/bin/amp` is a substring of `/.amp/bin/amp-desktop-helper/<ver>/Amp Desktop Helper.app/...`. The helper is started with `open -n -g -a` (parent launchd), so the probe's outermost-match rule does not hide it, and it matched the interactive TUI surface as a phantom idle row (reproduced with `matches()`). Removed the entry; every remaining entry is redundant with `names` anyway. After the repair the helper path does not match.
- Process patterns, false positive (repaired): non-interactive subcommands `--version`, `-V`, `-v`, `--help`, `-h`, `version`, `login`, `logout`, `update`, `completions`, `plugins`, `runner` matched the TUI surface. Added to that surface's `exclude_args`. All are top-level commands in the binary or documented (`amp login`, `amp logout`, `amp update`, `amp completions`, `amp plugins list`, `amp runner dirs add`). `threads` was deliberately left out because `amp threads continue` opens the TUI.
- Homebrew: the row said the formula is `ampcode`. Only the Cellar path is in the binary. `formulae.brew.sh/api/formula/ampcode.json` and `cask/ampcode.json` return 404; homebrew-core's `amp` is an unrelated terminal text editor. Reworded the claim; docs only say Homebrew installs exist.
- Keep-awake: the runner docs say the Mac app holds it only while the runner is on and the Mac is plugged in and the setting is on (off by default). The row said only "while the runner is on".
- afplay: Ping is 1.5 s (`afinfo`), not "about a second". It goes through `child_process.exec`, so a `sh -c` wrapper may sit above afplay. The focus flag defaults to focused and only flips on a terminal focus event, so a terminal without focus reporting presumably never triggers it (inference, not observed).
- Shell child: `bash` applies to agent tool calls only. Human-typed TUI shell commands use `$SHELL`. Wrapping (`amp-run-workload`) happens only on Linux orbs. Corrected in the signal text.
- Plugin runtime: the notes said the executable was unknown. It is the amp binary re-run with `BUN_BE_BUN=1` (child named `amp`).
- Data dir listing gained `guest-id`; only `secrets.json` is documented on the security page, `history.jsonl` is from the binary alone.
- Execute-mode surface labels claimed "working for the whole life of the process". The docs support a one-turn lifetime but the probe has no per-surface signal, so that is not encoded. Labels reworded; `amp -ox` noted as landing on the interactive surface.
- Telemetry text: added the `/api/telemetry` POST as evidence for "Amp sends its own telemetry".

### Unsupported or thin

- `names: ["amp"]` for the live process. Only inferred: the npm comment plus the analogy that Claude Code, also a Bun single-file binary, shows argv[0] as typed in `ps` on this Mac. Not seen on Amp.
- `tree_cpu` floor 5 percent: a guess, labelled as such.
- The `bash` child signal and the whole afplay waiting signal: read from source, never observed running.
- The `/Cellar/ampcode/` and `/@ampcode/cli` path entries: harmless and redundant, but the Homebrew formula name is unconfirmed.
- Blog https://allaboutcoding.ghinda.com/where-ai-coding-clis-store-session-logs/ still lists a local `T-*.json` mirror. The binary has no such directory and no `AMP_THREADS_DIR`, and txcript's bisection agrees, so the row keeps `session_store` omitted. That is the least certain design choice here: if a live Amp on this Mac shows a `threads/` folder being written, revisit it.

### Remaining false positives the row format cannot fix

- Any other program whose executable is named `amp` (homebrew-core's `amp` editor) matches by name and shows as an idle TUI row. `process` has no path-exclusion field in the schema or the probe.
- Transient idle rows for other short-lived subcommands (`amp threads list`, `amp mcp ...`, `amp usage ...`).
- A stdio MCP server configured as `bash ...` would keep the `bash` child signal true.
