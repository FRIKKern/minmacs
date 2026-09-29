# CodeBuddy evidence notes (2026-09-29)

Not installed on this Mac, nothing running. Nothing below was seen on a live turn. Confidence is `documented`. Sources: the docs at codebuddy.ai/docs/cli (all load; the home page redirects to `/banned` and 404s from here), the npm tarball `@tencent-ai/codebuddy-code` 2.159.0 (downloaded and unpacked in a scratch folder, not installed; the bundle is minified JS, so cites are by class or function name), the Homebrew tap formula and casks, and two IDE release zips read by HTTP range requests (Info.plist, product.json and a few JS files only).

## What I checked
- Local: `which codebuddy cbc workbuddy`, `ls /Applications | grep -i buddy`, `ls -d` on `~/.codebuddy`, `~/.codebuddycn`, `~/.workbuddy`, `~/.workbuddy-ai`, `~/.local/share/codebuddy`, `~/.local/bin/codebuddy`, `~/Library/Application Support/CodeBuddyExtension`, `ps | grep -i buddy`, `pmset -g assertions | grep -i buddy`. All empty.
- Surfaces:
  - CLI `codebuddy` (Tencent Cloud "CodeBuddy Code"). npm install runs as `node <prefix>/bin/codebuddy`. Homebrew and `install.sh` install a native Bun-compiled binary `codebuddy` (plus `cbc` symlink).
  - `--serve` daemon, `--acp` server, `--bg` background job, `--prewarm` standby, Agent View job broker.
  - CodeBuddy IDE (VS Code fork; `com.tencent.codebuddy`, main executable `Electron`). CodeBuddy CN IDE (`com.tencent.codebuddycn`). Both confirmed from the archives' Info.plist.
  - WorkBuddy (`com.tencent.workbuddy.mac`, `com.workbuddy.workbuddy-ai`; bundle ids from the Homebrew casks only).
  - VS Code / JetBrains plugin: runs in the extension host, no process of its own.
- pid to session: `~/.codebuddy/sessions/<pid>.json` (documented, and the source overwrites `sessionId` with the real UUID once the session exists). argv carries an id only for `--session-id` and `--resume`.
- Store: `~/.codebuddy/projects/<slug>/<sessionId>.jsonl`. Slug rule read from source (`normalizeWorkspacePathBase`).
- Working signals: searched both CLI bundles for sleep inhibitors, process title changes, terminal title, progress sequences and status files. Findings in the row.
- Hooks: 27 events, settings.json scopes, prompt and command types. OTel: traces only.
- Ran `matches()` from `tools/agents_probe.py` over 32 synthetic `ps` lines; all classified as intended. Validator passes.

## Could not determine
- Real `ps` args for the Bun native binary on macOS, and where `codebuddy install` puts it. The `/.local/share/codebuddy/` needle is inferred from the uninstall docs and from how Claude Code lays out its versions folder.
- Executable names inside `WorkBuddy.app` and `WorkBuddy AI.app` (only DMGs are published; not opened). The row matches the app folder. Where the WorkBuddy sidecar (`--serve`, lite-wb bundle) runs from is unknown, so it is not matched.
- Any working signal for the IDE and WorkBuddy. The IDE main process starts an Electron `powerSaveBlocker` (`prevent-app-suspension`) when a renderer sends IPC `codebuddy:power-save-blocker`, but I found no caller in the workbench, the genie extension or its webviews. Unknown whether it is held per agent turn or for a whole window.
- Real CPU or transcript cadence during a turn. `tree_cpu` at 3 percent and the 30 s transcript window are guesses.
- Record key names of a transcript line. No local store exists; I did not read one. Nothing was inferred beyond "one JSON object per line".
- Whether the terminal-title spinner distinguishes waiting: source says it does not (see below), but I did not watch one run.
- Default of `enableTerminalProgressBar` (source only disables it on an explicit `false`, so it is on by default) and whether iTerm2/Ghostty in a multiplexer pass OSC 9;4 through.
- Whether the Agent View job files (`~/.codebuddy/jobs/<id>/state.json`) exist for a plain interactive session. Source says only for job workers and sessions handed to the background.
- JetBrains plugin process shape. The docs say the plugin starts the CodeBuddy process; how was not traced.

## Contradicts common belief or the obvious approach
- There is no per-turn `caffeinate`. The one `caffeinate -i -w <pid>` belongs to the `--serve` daemon and lives as long as the daemon. A "caffeinate child means working" rule (Claude Code, Qwen Code) marks every idle CodeBuddy daemon working forever and sees nothing on a TUI turn. The CLI bundles contain no IOKit assertion either.
- CodeBuddy's hook system looks like Claude Code's (same event names, `permission_prompt`, `idle_prompt`, `transcript_path`, and it accepts `CLAUDE_CODE_ENABLE_TELEMETRY`), but the layout differs: `~/.codebuddy`, and the project slug has no leading dash (`Users-me-x`, not `-Users-me-x`) and keeps dots.
- Its IDE plugin lock files are looked up in `~/.claude/ide`, Claude Code's folder.
- The terminal-title spinner is not a "working" signal on its own: it spins for every run state except idle, so it also spins while waiting for a permission or an answer. Idle is U+2733.
- `status` and `waitingFor` in the PID file look like the answer to "working vs waiting", but they are written only for Agent View jobs and handed-off background sessions. `codebuddy ps` prints `unknown` for a plain session.
- `idle_prompt` fires only after 60 s idle. `Stop` is not fired on a manual interrupt, so a hook-tracked turn can stay open.
- The `cbc` alias collides with COIN-OR Cbc, a solver. The native rows leave `cbc` out; a Homebrew user who types `cbc` is not matched.
- Agent View runs every background job under a broker. On the native build the broker and the inner CLI share a command line, so a detector sees two processes (the outermost is kept); on npm the broker is `dist/codebuddy-broker.js` and is not matched.
- IDE chats are a directory of JSON under `~/Library/Application Support/CodeBuddyExtension/<uid>/history/<md5 of workspace>/`, not the JSONL store the CLI uses. The IDE's `dataFolderName` is `.codebuddy`, so it uses the same `~/.codebuddy` folder name as the CLI (what it stores there was not checked).
- `codebuddy -p` and `--bg` (which forces `--print -y`) are working for their whole life; they match the tui surfaces.

## Verification
`python3 tools/validate_row.py registry/agents/codebuddy.json` printed `ok   registry/agents/codebuddy.json`.

## Verification

Second pass, 2026-09-29, by a reviewer who did not write the row and tried to refute it. Nothing was installed or run; the harness is not on this Mac, so confidence stays `documented` at best. Re-fetched: the npm registry entry and the 2.159.0 tarball (unpacked in a scratch folder), the Homebrew tap formula, `formulae.brew.sh` cask and formula JSON, `install.sh`, the docs pages cli-reference, installation, daemon, hooks, monitoring, env-vars, settings, plugins-reference, codebuddy-dir, ide-integrations, and the two IDE zips by HTTP range reads (Info.plist, file lists, `out/main.js`, byte scans of the JS). `python3 tools/validate_row.py registry/agents/codebuddy.json` printed `ok` before and after the repairs. A 43-line synthetic `ps` set was run through `matches()` and `session_id()` before and after.

Confirmed
- npm package `@tencent-ai/codebuddy-code`: latest 2.159.0 published 2026-09-27T17:37:39Z; bins codebuddy, cbc, codebuddy-code, codebuddy-lowmem (all `bin/codebuddy`) and cbc-prewarm (`bin/cbc-prewarm`); `bin/codebuddy` line 1 is `#!/usr/bin/env node` and `minNode = '18.20.8'`.
- Homebrew tap formula `codebuddy-code` 2.158.0 installs the native binary `codebuddy` plus a `cbc` symlink from `codebuddy-code_Darwin_{arm64,x86_64}.tar.gz`; `install.sh` downloads the same archive and runs `install`; the docs uninstall section removes `~/.local/bin/codebuddy`.
- Bundle ids and app names from the casks: `com.tencent.codebuddy` (CodeBuddy.app), `com.tencent.codebuddycn` (CodeBuddy CN.app), `com.tencent.workbuddy.mac` (WorkBuddy.app), `com.workbuddy.workbuddy-ai` (WorkBuddy AI.app).
- IDE Info.plist read again from both zips: CFBundleIdentifier `com.tencent.codebuddy` and `com.tencent.codebuddycn`, CFBundleExecutable `Electron` in both, helpers named `CodeBuddy Helper (Renderer|GPU|Plugin)` and `CodeBuddy CN Helper ...`, so the helpers do not match the IDE rows (checked with `matches()`).
- The IDE agent is the `coding-copilot` extension (publisher Tencent-Cloud, 3.10.0, `extensions/genie`), `EXTENSION_DATA_DIR_NAME = "CodeBuddyExtension"`, `SessionSource.listSessions()` reads `<userData>/<uid>/history/<workspace>/`. No CLI agent binary ships in the IDE archive.
- `process.title` is set only on win32 (TerminalTitleUpdater.writeTitle); macOS gets the OSC 0 title.
- The one `caffeinate -i -w <pid>` spawn is in the daemon WakeDetector, in both `dist/codebuddy.js` and `dist/codebuddy-headless.js`; `CODEBUDDY_DAEMON_ALLOW_SLEEP` disables it; no IOKit or `powerSaveBlocker` call in the CLI bundles.
- Transcripts at `~/.codebuddy/projects/<slug>/<sessionId>.jsonl` (daemon doc log table, codebuddy-dir doc); slug rule `replace(/[/\\:]/g,'-')`, strip leading and trailing `-`, collapse runs, 255-byte limit with 180-byte cut plus djb2 base36; session id pattern `^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$`; retention default 30 days (`cleanupPeriodDays`).
- `--session-id <uuid>`, `-r, --resume [sessionId]`, `-c, --continue`, `--no-session-persistence` exist in the option definitions.
- PID registry `~/.codebuddy/sessions/<pid>.json` (daemon doc, PID File Registry); management subcommand skip list `ps logs attach kill stop rm respawn` plus `daemon project`; `mapRunStatus()` maps WAITING_FOR_PERMISSION to waiting/'permission prompt', WAITING_FOR_USER to waiting/'input needed', IDLE to idle, the request and tool states to busy.
- Terminal title: ten braille frames every 200 ms, idle prefix U+2733, `isSessionRunStatusBusy(s) = s !== IDLE` in both bundles, so a permission or question wait also spins. Disabled without a TTY or with `CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE`.
- Hooks: 27 event names all present in the hooks and plugins-reference docs; scopes merge and matching hooks run in parallel; `Stop` skipped on manual interrupt; `idle_prompt` after 60 s; prompt hooks only for Stop, UserPromptSubmit, PreToolUse; `$CODEBUDDY_PROJECT_DIR`, `$SHELL`, 60 s timeout, `disableAllHooks`, `allowUntrustedFrontmatterHooks`, `generation_id` in hook stdin.
- OTel: traces only, http/protobuf only, `CLAUDE_CODE_ENABLE_TELEMETRY` accepted, `DISABLE_TELEMETRY=1` wins, `user_input_wait` span under `OTEL_SEMCONV=agentlens`.
- WorkBuddy embeds the engine: `bin/codebuddy` routes `CODEBUDDY_FORCE_LITE_WB_BUNDLE` and `CODEBUDDY_FORCE_HEADLESS_BUNDLE` for the workbuddy-server sidecar and prewarm; `getWorkbuddyConfigDir()` is `WORKBUDDY_CONFIG_DIR` or `~/.workbuddy`.
- The CLI looks for IDE lock files only in `~/.claude/ide` (plus WSL Windows-home copies).
- The IDE main process starts an Electron `powerSaveBlocker` (`prevent-app-suspension` on macOS) on IPC `codebuddy:power-save-blocker`. Two byte scans of the IDE's JS (209 files including workbench and genie, 158 others) found the channel name only in `out/main.js`, so the "no caller found" negative holds for those files.
- Agent View broker on npm: the broker entry is `dist/codebuddy-broker.js` run under `process.execPath` with the user's args, so it does not match `bin/codebuddy`; on the native build the broker and inner CLI share a command line.
- Cbc: Homebrew formula `cbc` is "Mixed integer linear programming solver" (COIN-OR), so leaving the `cbc` alias unmatched on the native side is right.
- Local absence: `which codebuddy cbc workbuddy`, `ls /Applications | grep -i buddy`, `ls -d` on the seven home and Application Support paths, `ps -axo pid=,args= | grep -i -E 'codebuddy|workbuddy'`, `pmset -g assertions | grep -i buddy` all empty or "No such file".

Corrected
- Native install layout. The row called `/.local/share/codebuddy/` "inferred" and used it as a broad path rule for the tui, `--serve` and `--acp` native surfaces, with an evidence example `.../versions/2.158.0 --serve`. Source shows the installer writes `<data>/versions/<version>/codebuddy` (data = `(XDG_DATA_HOME || ~/.local/share)/codebuddy`) and links or copies it to `~/.local/bin/codebuddy`. The re-spawn argv[0] therefore ends in `/codebuddy` and the name rule already matches it. The broad path rule would have matched any other executable in that data directory (a synthetic `~/.local/share/codebuddy/vendor/rg --files` matched as a session), so it is now `/codebuddy/versions/`. The docs list `~/.local/share/codebuddy` only under optional configuration cleanup.
- Subcommands not excluded. `doctor`, `config`, `sandbox`, `plugin`, `marketplace` and `cleanup` are root commands in the source and matched the tui surfaces as brief idle sessions (`codebuddy doctor`, `codebuddy config list`, `codebuddy marketplace list`, `codebuddy sandbox info`). Added to `exclude_args` on the three tui surfaces.
- `cbc-prewarm`. `node .../bin/cbc-prewarm list|ping|status|activate` matched the `bin/cbc` surface as a session. Its subcommands are now excluded on that surface.
- Teammates. Agent-team teammates run as `--serve --teammate-mode ...` (PID file kind `teammate`) and matched the `--serve` daemon surfaces, described as a multi-session host. They are helpers of a lead session; `--teammate-mode` is now an excluded token on both `--serve` surfaces. PID file kinds now include `teammate`.
- OSC 9;4 / OSC 99 progress. The row filed it as "while the run is interruptible". `ProgressSyncService` subscribes to `session.interruptionSubject`, which carries pending tool approvals (PermissionBridge, `surfaceApprovalUI`, ACP `handleToolApproval`), so the indicator marks WAITING on a permission decision, not a running turn, whatever the word "Working..." says. The waiting_signals entry, source and notes now say so. Still source-only, not seen live.
- Telemetry "off by default" was wrong. The monitoring doc says tracing is enabled by the built-in product configuration or by the env var, and the shipped `product.json` has `telemetry.tracing.enabled`, `telemetry.report.standard.enabled` and `telemetry.report.model.enabled` true (no `url` key). Text in `telemetry.how` and source 13 changed; the destination of the shipped default was not traced.
- Caffeinate wording. "The only 'caffeinate' string" is wrong (a log label in `logEnhancementsStatus` also has it); the claim now says "the only caffeinate spawn". The spawn is gated on `CODEBUDDY_SESSION_KIND=daemon`, which `daemon start` sets; a hand-run `codebuddy --serve` was not traced.
- Home page. The row said `https://www.codebuddy.ai` redirects to `/banned` and 404s. From this Mac it returned 200 with no redirect (9768 bytes); an earlier firecrawl fetch got the redirect and the re-run failed with a proxy error. The behaviour is location dependent and proves nothing about the row.
- Synthetic test claim. The earlier list used `<home>/.local/share/codebuddy/versions/2.158.0 --serve`, a path that does not exist in the real layout; replaced by the 43-line run described in source 21.
- `--session-id` help text allows a colon in the id, the store's own id pattern does not. Recorded in `session_store.glob_note`; what the store does with a colon id was not traced.
- The `tree_cpu` floor of 3 percent is row-level and so also reaches the Electron IDE and WorkBuddy surfaces, where README section 4 wants 10 percent. The signal's meaning now says those `host: true` surfaces must not take a state from it.

Unsupported (kept, marked as such in the row)
- Every working-signal timing: the 30 s transcript window and the 3 percent CPU floor are guesses; no live turn was watched. The transcript is not read on this Mac and no record key was seen.
- WorkBuddy and WorkBuddy AI main executable names and where the WorkBuddy `--serve` sidecar runs: only DMGs are published and they were not opened; the path rules are inferred from the app folder names.
- `codebuddy --serve` started by hand, or by launchd through `daemon install`, was not traced for its command line or its `caffeinate`.
- Real `ps` output of the Bun native binary on macOS, the Agent View job files on a live job, and whether iTerm2, Ghostty or tmux pass OSC 9;4 through were not observed.
- Residual false positive that cannot be fixed with substring matching: any node process that has `bin/codebuddy` inside an argument (`node server.js --config bin/codebuddy.json`, `node bin/codebuddy-tool.js`) matches the npm tui surface. Requiring a leading slash would lose `node_modules/.bin/codebuddy`.
