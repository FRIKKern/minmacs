# Qwen Code evidence notes (2026-09-29)

Not installed on this Mac. Nothing below was observed on a running instance. Source: shallow clone of QwenLM/qwen-code (main at a903de1, package 0.24.6, same as npm `latest` and Homebrew stable), read-only, in the scratchpad. Docs URLs on qwenlm.github.io/qwen-code-docs returned 200. Confidence is `documented`.

## What I checked
- Local: `which qwen`, `ls ~/.qwen`, `ps | grep -i qwen`, `ls /Applications | grep -i qwen` all empty.
- Install shapes: npm `@qwen-code/qwen-code` (bin `qwen` -> `cli-entry.js`, node >=22), Homebrew formula `qwen-code` (node + ripgrep), standalone archive (`bin/qwen` shell shim -> `<root>/node/bin/node <root>/lib/cli-entry.js`, bun flavour exists), Desktop app.
- Surfaces: TUI (Ink; an OpenTUI preview exists), `qwen serve` daemon, `qwen --acp` child (daemon-spawned or editor-spawned), Desktop app (Tauri 2, id `com.alibaba.qwen-code`, "Qwen Code Desktop"), VS Code companion (publisher `qwenlm`, spawns the editor's Electron as node with `--acp --channel=VSCode`), Zed extension (`cli.js --acp`), JetBrains and GitHub Action (not inspected further; they drive the CLI).
- Process shape: `cli-entry.js` runs the CLI in-process; `llm.tsx` then execve-replaces or spawns a relaunch child (same argv[1], `QWEN_CODE_NO_RELAUNCH=true`). One or two nested node processes. `process.title` is only set on Windows.
- Session id in argv: only `--session-id <uuid>`, `--resume/-r [id]`. `--continue/-c` has no id. Plain `qwen` has none.
- PID to session: `~/.qwen/sessions/<pid>.json` (live registry, unlinked on exit, has `sessionId`, `cwd`, `kind`) and `~/.qwen/projects/<slug>/chats/<sessionId>.runtime.json` (interactive only, never deleted). Both documented in source comments; the bundled `/stuck` skill greps the runtime sidecars for a PID. Key names read from TypeScript types, not from a file.
- Store: `~/.qwen/projects/<cwd with non-alphanumerics -> '-'>/chats/<sessionId>.jsonl`. Docs (headless.md) state it. Full session id in the file name, so a per-session glob works.
- Working signal: `caffeinate -is` child while streaming a model response or running a tool (`sleepInhibitor.ts`, `general.preventSystemSleep`, default true). Transcript writes are bursty. CPU is a guess.
- Waiting: `Notification` hook `permission_prompt`, `PermissionRequest` hook, terminal title prefix (sparkle asterisk for WaitingForConfirmation, half circle for Responding), bell.
- Hooks: 22 events, types command/http/prompt/function, `hooks` key in `~/.qwen/settings.json`, `.qwen/settings.json`, `/Library/Application Support/QwenCode/settings.json`.
- OTel: built in, off by default, OTLP grpc/http or outfile.

## Could not determine
- Real `ps` args on a Mac. `bin/qwen` for npm/Homebrew assumes node keeps the symlink path in argv[1] (it does for shebang scripts, but unverified here).
- Executable file name inside `Qwen Code Desktop.app/Contents/MacOS/`. The row matches the folder.
- Whether the desktop app has any users or a Mac release channel beyond the `desktop-latest` GitHub release; no bundle was fetched or inspected.
- Real CPU when working or idle. `tree_cpu` at 3 percent is a guess.
- Whether `caffeinate` stays continuously up across a multi-step turn. Streams and tool executions each acquire and release with a shared counter, so a gap between the end of one stream and the start of the next tool is expected but I did not time it.
- Actual record keys from a real transcript. Listed from the `ChatRecord` type.
- Whether headless `-p` runs register in `~/.qwen/sessions`. ACP children register as `headless` or `serve`; the `-p` path was not traced.
- VS Code surface path match: the probe splits `ps` args on spaces, so `/Applications/Visual` is a workaround for "Visual Studio Code". Other editors (Cursor, VS Code Insiders, Windsurf) that install the companion would not match.
- JetBrains and the GitHub Action process shapes.

## Contradicts common belief or the obvious approach
- Qwen Code is described as a Gemini CLI fork, but its session layer is different: JSONL under `~/.qwen/projects/<slug>/chats/<id>.jsonl` (Claude-Code-like layout, full session id in the name), not Gemini's `tmp/<hash>/chats/session-<time>-<id8>.jsonl`. The hook system is Claude-Code-shaped (event names, `permission_prompt`/`idle_prompt`, `CLAUDE_PROJECT_DIR` set too), not Gemini's BeforeTool style.
- Unlike Gemini CLI, it does have a sleep inhibitor: `caffeinate -is` on macOS while a turn streams or a tool runs. Default on, user can disable.
- It writes explicit PID-to-session files for outside observers (`runtime.json`, `sessions/<pid>.json`). The source comment says exactly why: argv has no session id on a fresh launch.
- `runtime.json` is never deleted on quit or crash, so its presence says nothing about liveness. The `sessions/<pid>.json` registry is the one that is cleaned up (and swept when stale).
- Stale in-source doc: `ChatRecordingService` class comment says `~/.qwen/tmp/<project_id>/chats/`. The code writes `~/.qwen/projects/...`. `tmp/<hash>` still exists but holds shell history, checkpoints, tool results.
- The permission-prompt wait is not covered by the sleep inhibitor (per the setting description), so "no caffeinate" during a started turn hints at waiting on the human. Inferred.
- The repo top-level `package.json` name is `@qwen-code/qwen-code` (private, workspace); the published bin is the generated `cli-entry.js`, not `dist/index.js` that `packages/cli/package.json` lists.
- The desktop app is not a second agent. It is a shell around `qwen serve` and its Web Shell, so its sessions are `qwen --acp` children of a node daemon, all inside the app's process tree.
- Hooks docs say `timeout` is in seconds but values of 1000 or more on command hooks are still read as milliseconds. Irrelevant to detection, noted because a hook-based detector should not set large timeouts.

## Verification

Adversarial pass, 2026-09-29. Re-read QwenLM/qwen-code at a903de1 (package 0.24.6), re-fetched npm, the Homebrew formula and the four docs pages (all HTTP 200), evaluated the row's process patterns with `tools/agents_probe.py matches()` on synthetic ps lines. Qwen Code is not installed here (`which qwen`: not found; no `~/.qwen`; no qwen process; nothing in /Applications), so confidence stays `documented`, never `verified-locally`. `tools/validate_row.py` printed `ok` before and after the repairs.

### Confirmed
- npm `@qwen-code/qwen-code` latest 0.24.6, bin `{qwen: cli-entry.js}`, engines node >=22; Homebrew formula `qwen-code` 0.24.6 depends on node and ripgrep and symlinks `libexec/bin/*`.
- Standalone shim runs `<root>/node/bin/node <root>/lib/cli-entry.js` (bun flavour uses `bun/bin/bun`); default install dir is `~/.local/lib/qwen-code`.
- No `process.title` change except on win32.
- Desktop: productName `Qwen Code Desktop`, identifier `com.alibaba.qwen-code`, Cargo package `qwen-code-desktop`; spawns `<Resources>/runtime/qwen-code/node/bin/node lib/cli-entry.js serve --port 0 --hostname 127.0.0.1 --require-auth --workspace <dir> --no-open` with `QWEN_CODE_DESKTOP=1`; log and state paths match the README.
- VS Code companion: publisher `qwenlm`, spawns `process.execPath <cliEntryPath> --acp --channel=VSCode` with `ELECTRON_RUN_AS_NODE=1`.
- Session id in argv only via `--session-id`, `--resume/-r`; `--continue/-c` carries none; `--session-id` cannot combine with resume/continue.
- `runtime.json` sidecar: keys, path, interactive only, never deleted. `~/.qwen/sessions/<pid>.json`: keys, kinds `tui|headless|serve|external`, `<pid>-<8hex>.json` for multi-session children, swept when stale.
- Transcript path `~/.qwen/projects/<sanitizeCwd>/chats/<sessionId>.jsonl` (headless docs quote it; `sanitizeCwd` replaces `[^a-zA-Z0-9]` with `-`). `ChatRecord` keys as listed. The stale `~/.qwen/tmp/<project_id>/chats/` class comment exists.
- `caffeinate -is` on darwin, acquired while streaming and while executing a tool (llm-chat.ts 3461, coreToolScheduler.ts 5595, Session.ts 15001), gated by `preventSystemSleep` (default true, requires restart) and not safe mode. The settings text says idle prompt time and permission prompts do not inhibit sleep. New detail: `-s` only holds on AC power, but the `caffeinate` child exists either way.
- Hooks: all 22 event names, four hook types, `disableAllHooks`, three settings locations plus `QWEN_CODE_SYSTEM_SETTINGS_PATH`, `QWEN_PROJECT_DIR`/`CLAUDE_PROJECT_DIR`/`GEMINI_PROJECT_DIR`, project hooks only in trusted folders, Notification types `permission_prompt|idle_prompt|auth_success`, `PermissionRequest` fires when the dialog shows.
- Telemetry: off by default, env var names, defaults (grpc, `http://localhost:4317`, outfile override, logPrompts true), event names.
- Title prefix mapping (half circle, sparkle, none) and `ui.hideWindowTitle`.
- `idle_prompt` hook fires on entering Idle.
- Local: nothing installed (all four commands re-run, all empty).
- `ps` keeps the symlink path for a shebang launch. Previously listed as unverified; now observed with a stand-in script (see sources). `node <prefix>/bin/qwen` is what `bin/qwen` matches.

### Corrected
- Desktop GUI surface never matched. The probe splits ps args on spaces, so `/Applications/Qwen Code Desktop.app/...` gives argv[0] `/Applications/Qwen` and name `Qwen`; the old `path_contains` ("Qwen Code Desktop.app/Contents/MacOS/") and the bundled node (name `Qwen`, not `node`) both failed. Repaired to `path_contains ["/Applications/Qwen"]` plus `args_contain ["Desktop.app/Contents/"]` (the second needle keeps a different Qwen app out). Tested on synthetic lines for both possible executable names; the shell is now reported as the outermost match. The old notes only recognised the space problem for VS Code.
- Relaunch child argv: the row said the child keeps "the same argv[1]". It does not. `cli-entry.js` rewrites `process.argv[1]` to `<package>/cli.js` before importing, and `relaunchAppInChildProcess` reuses that. So the launcher shows `node .../bin/qwen` and the relaunch child shows `node .../@qwen-code/qwen-code/cli.js`. Source text and notes fixed.
- TUI relaunch surface needle `@qwen-code/qwen-code/` was too wide: Qwen spawns other files from that folder (`codeModeHost.js` via `host-client.ts`). Narrowed to `@qwen-code/qwen-code/cli.js`. Label no longer claims a source checkout (a checkout runs `dist/cli.js`, which does not match).
- Standalone daemon needle `cli-entry.js` + `serve` matched any node tool with a `cli-entry.js` and a "serve" substring. Added `qwen` as a third needle (the standalone root is `.../qwen-code/`). Label no longer claims the Desktop daemon.
- Assistant-turn recording: the cited lines 5128-5145 are the deferred partial-turn flush after an abort or stream error, not the normal path. The accepted turn is recorded near llm-chat.ts 6635 once the stream is fully processed. Conclusion (recorded after the stream ends, not per chunk) stands.
- ACP child command: it is `node [heap args] <cliEntry> --acp`, with `cliEntry` from `QWEN_CLI_ENTRY` or the daemon's argv[1], i.e. a cli.js path rather than the `qwen` binary. Zed runs a relative `./package/cli.js --acp` pinned to package 0.10.0, which has no "qwen" in argv and is not matched by the ACP surface.
- Bell setting: key is `general.terminalBell` (default true, so not "needs enabling") and it also rings for approval prompts while unfocused unless `general.notificationMode` is `task-complete`. The old row named a `ui` key.
- Title: only OSC 2 is written inside tmux/screen; the prefix is also dropped when `ui.showStatusInTitle` is false.
- `QWEN_RUNTIME_DIR` does not move only `projects/` and `chats/`; it moves the whole runtime base (tmp, debug logs and so on). `~/.qwen/sessions` follows `QWEN_HOME` only.
- Old note said VS Code Insiders would not match the IDE surface. It does (`/Applications/Visual` prefix); Cursor and Windsurf do not.
- Executable name in `Contents/MacOS/`: Tauri docs say the default is the cargo output binary unless `mainBinaryName` is set, and there is none. So the name may be `qwen-code-desktop`, not the product name. The source entry now cites the Tauri docs instead of a "third-party" label.
- `session_store.glob` also matches `<id>.ledger.jsonl` sidecars in the same folder; noted in `glob_note`. `per_session` is exact and unaffected.

### Unsupported or still inferred
- `tree_cpu` at 3 percent: inferred, never measured.
- Continuity of `caffeinate` across a multi-step turn: source shows a shared acquire/release counter and separate acquire sites, so a gap is possible; not timed.
- No Mac release of Qwen Code Desktop was fetched; bundle layout and the `/Applications` location are from source and Tauri defaults, not from a bundle.
- Whether headless `-p` registers in `~/.qwen/sessions`: not traced.
- Real ps args for Homebrew, nvm and standalone installs: `bin/qwen` is confirmed for a shebang symlink launch in general, not on a Qwen install. The standalone shim resolves `ROOT` from `$0`, which was not checked for the `~/.local/bin/qwen` symlink case.
- Residual false positives the probe cannot anchor away: `bin/qwen` matches `bin/qwen-proxy`; `qwen mcp` or `qwen review` helper invocations look like sessions; `qwen` in any argument of a node `--acp` process (for example another agent run with a qwen model name) matches the ACP surface. `--resume=<id>` (with `=`) is not read by `session_id_args`, and `-r` with no id makes the probe take the next argument as the id.
- Record keys are from the TypeScript types, no real transcript or sidecar was read.
