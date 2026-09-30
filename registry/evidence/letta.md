# Letta Code evidence notes (2026-09-30)

Not installed here: no `letta`, no `~/.letta`, no Letta.app, nothing running, no power assertion (commands in the row's last local-observation source). No live turn was seen, so confidence is `documented`, not `verified-locally`. Nothing was installed or started; the desktop app was inspected by ranged HTTP reads of its public download zip.

Versions read: `letta-ai/letta-code` main at `96eb977` (v0.34.0, 2026-09-29), shallow clone in the scratchpad, read only. Desktop app `Letta 0.32.19` (zip last-modified 2026-09-24). The product is now branded "Letta Harness / Letta app / Letta CLI" in the docs ("formerly Letta Code"); the npm package and repo keep the old name.

## Shape

```
npm/pnpm/bun/nix:  node <prefix>/bin/letta [flags]          one bundled ESM file, #!/usr/bin/env node
PyPI wheel:        <site-packages>/letta_code/_payload/bin/node  .../_payload/app/letta.js   (Python launcher execve()s it)
  |- Ink TUI; `-p` makes it a headless one-shot (same process shape)
  |- Bash tool: /bin/zsh -c|-lc <cmd> = DIRECT detached child (pipes); MCP/LSP servers = long-lived direct children
  |- subagent = direct child `letta.js -p <prompt> --output-format stream-json` (same executable)
  |- writes the terminal title itself: Braille spinner = busy, `[ ! ] Action Required` = blocked; OSC 9;4;3 while a dialog is up
  |- NO caffeinate, NO IOKit assertion, NO lock/pid file, NO OpenTelemetry
  '- state: Cloud backend (default) = server side; local backend = ~/.letta/lc-local-backend/conversations/<base64url>/messages.jsonl

letta server [--listen ws://..] / letta remote:  same binary, App Server or cloud "computer" listener, many conversations per process

Letta.app (Electron, ToDesktop, bundle com.todesktop.260305dtu2nh5)
  |- main process: holds powerSaveBlocker('prevent-app-suspension') while a renderer reports a run (10 s heartbeat)
  '- child: <Letta binary> --require setProcessTitle.js .../app.asar.unpacked/node_modules/@letta-ai/letta-code/letta.js remote --env-name N --backend api|local
             ELECTRON_RUN_AS_NODE=1, retitled `letta-code-listener` (ps shows only the title); runs the loop and the tool shells
```

## What I checked

- Repo README and package.json, `build.js`, `python/` wheel launcher, `src/cli/args.ts`, `src/cli/subcommands/{router,server}.ts`, `src/tools/impl/{shell-launchers,shell-runner,shell-env}.ts`, `src/agent/subagents/*`, `src/cli/helpers/{window-title-config,terminal-title,chunk-log}.ts`, `src/cli/components/TerminalTitleWriter.tsx`, `src/cli/hooks/use-progress-indicator.ts`, `src/cli/app/{AppCoordinator,notifications,use-approval-flow,use-conversation-loop}`, `src/hooks/*`, `src/backend/local/*`, `src/utils/debug.ts`, `src/telemetry/index.ts`, `src/websocket/listen-log.ts`, `src/types/loop-status-protocol.ts`. Grepped for `caffeinate|powerSave|IOPM|prevent sleep`, `process.title`, `opentelemetry|OTEL|otlp`: nothing (non-test).
- Docs at docs.letta.com (fetched as `.../index.md`): llms.txt, CLI reference, headless, settings, troubleshooting, desktop app, mods, deprecated hooks, App Server and its protocol lifecycle.
- Desktop app: read the zip central directory of `https://download.letta.com/mac/zip/arm64` with `curl -r` ranges; printed `Letta.app/Contents/Info.plist`, `Resources/app-update.yml`, the bundle layout and the `app.asar.unpacked/node_modules/@letta-ai/letta-code/` file list; extracted the one entry `app.asar` (63 MB compressed of a 256 MB file), parsed the asar header, read `dist/main.js`. The app's own code is closed; this is a read of the shipped file, not public source.
- Local: `command -v letta`, `ls -d ~/.letta`, `ls /Applications | grep -i letta`, `ps`, `pmset -g assertions | grep -ci letta`, `mdfind` on the bundle id: all empty.
- Process rules run through the probe's own `matches()` and `session_id()` on 22 synthetic argv lines (no process started): symlink and nvm forms, `--conv`/`-C` ids, `-p` and subcommands vetoed, `server`/`remote` daemons, PyPI path, app main and its Renderer helper (not matched), `letta-code-listener`, unretitled listener, unrelated `node server.js`, old Python `letta`, `claude`. All landed where intended, plus the one known misfile below.
- `tools/validate_row.py registry/agents/letta.json` prints `ok`; `tools/agents_probe.py --row registry/agents/letta.json` reports 0 sessions (nothing running).

## Could not determine

- **Any live behaviour.** No process line, assertion, title or file was seen. The 30 s window and 3% CPU floor are guesses.
- **The real `ps` line of an npm install.** I assumed `node <prefix>/bin/letta` (symlink path) from how shebang scripts are exec'd and from the `gemini-cli` row; not seen for Letta. `bun` in `names` is inferred from `engines.bun` and build comments about global Bun installs.
- **Whether the retitled listener shows `letta-code-listener` in `KERN_PROCARGS2`** (what the probe reads) or only in `ps`. The app's own comments say `ps -o command` reports the title; the probe reads the same kernel data, so it should. Unverified.
- **The `pmset` name of the desktop assertion.** Electron `prevent-app-suspension`; label unknown. Also unknown: whether a pending approval keeps it held, because the renderer's call to `set-processing-state` is not in the app bundle (the UI is loaded from elsewhere or was not found).
- **Whether the desktop app runs a listener for every window/agent, or how many of the three slots are live** in a stock install.
- **Whether `letta.js` re-execs or spawns a relaunch child** (Gemini-style). No such spawn found in `src`; the only self-spawns are subagents and the short-lived image-resize worker (`process.execPath image-resize-worker.js`, which does not match the `letta` argv rules).
- **A hold window for the title spinner.** It also runs for start-up, `!` bash mode and slash commands, so it means "busy", not strictly "model turn".
- **Windows/Linux, the Docker image, Nix module details.** Out of scope (macOS only); Docker on macOS would hide the process in a VM.
- **Any session-id-to-process map.** The TUI session id is `${Date.now()}-${random}`, generated in-process and written only into log file names. No pid registry exists for the CLI. The desktop app keeps its own `listener-spawn-registry.json` (pid, start token, command) under its userData directory; path not confirmed.

## Contradicts common belief

1. **Hooks are deprecated.** The docs README still links "Hooks", but `docs.letta.com/letta-code/hooks` now redirects to `reference/deprecated/hooks` (`status: legacy`, "may be removed in a future release"). The replacement is Mods (TypeScript files in `~/.letta/mods/`, in-process, events `turn_start`, `turn_end`, `tool_start` ...). Hooks are Claude-Code-compatible in shape (a `hooks` key in `settings.json`, 11 events; the source says "Claude Code-compatible") but live in `~/.letta/settings.json` and `.letta/settings*.json`, not `~/.claude`. Do not copy the `claude-code` row's paths.
2. **There is no sleep inhibitor in the CLI.** Many harnesses have one (`claude-code`, `grok-build`). Letta's CLI has none. Only the desktop app does, as an Electron `powerSaveBlocker` held by the app's main process, not by the process that runs the agent.
3. **`--resume` does not take an id.** In Letta it is a boolean that opens a selector. The id flag is `--conversation`/`--conv`/`-C`. `-a/--agent` is an agent id, not a session. Plain `letta` carries no id in argv.
4. **Signed-in sessions leave no transcript on disk.** Cloud is the default backend; conversations live on Letta's servers. Only `--backend local` (and the desktop "local" mode) writes `messages.jsonl`. Message files are in base64url-named directories, so a `{session_id}` path template cannot find one.
5. **The desktop listener is not called `letta`.** The Letta app runs the harness as `letta-code-listener` (a retitled Electron binary in Node mode), and its tool shells are grandchildren of the app. A `tool_children` rule on the app finds nothing.
6. **Old PyPI `letta` is a different product.** The `letta` package on PyPI used to be the MemGPT server. The current wheel is Letta Code with a bundled Node and installs the same command name. A Python-run `letta` (argv[0] `python`) is the old server and is not matched.
7. **The terminal title is the only precise per-process signal, and the CLI writes it by default.** Braille spinner while busy, `[ ! ] Action Required` <-> `[ . ] Action Required` while blocked; OSC 9;4;3;0 only while a dialog is mounted. Herdr's manifest agrees (`registry/evidence/hosts-2.md` section 3). It cannot be read from `ps`.

## Known errors of the row

- `letta server` is found by the substring `server`, so a TUI started as `letta -n api-server` is filed as a daemon (checked with the probe: score 3 beats the TUI's 2). A value equal to a subcommand (`letta -n memory`) hides a real TUI. Same limits as `grok-build`.
- Headless `-p` runs and subagents are vetoed and not reported. A `-p` substring rule would also match `--permission-mode` and any path containing `-p`. Herdr rejects them the same way.
- `power_assertion` has no name, so any assertion held by the Letta process tree counts.
- Desktop: the listener is folded into the app by the probe (its parent matches), so the app's assertion and tree CPU are the only signals; per-conversation state is not visible.

## Verification

Adversarial re-check, 2026-09-30, by a reviewer who did not write the row. Method: shallow clone of `letta-ai/letta-code` at `96eb977` (v0.34.0, same commit as the row) and of `herdrdev/herdr` at `d4e335e`, fresh fetches of the docs pages the row cites, a re-read of the desktop zip by `curl -r` ranges and of its `app.asar` (parsed header, 25110 files), and the row's process rules replayed through `tools/agents_probe.py` `matches()` on 16 synthetic argv lines before and after the repair. Nothing was installed or started. `tools/validate_row.py registry/agents/letta.json` prints `ok` before and after. Confidence stays `documented` (Letta is not installed here, so `verified-locally` is impossible).

Status of each claim:

| # | Claim | Status |
|---|---|---|
| 1 | package `@letta-ai/letta-code`, bin `letta` -> `letta.js`, engines node >=22.19.0, bun >=1.3.2, v0.34.0; docs say Node 22.19+ | confirmed (package.json lines 3, 8-10, 143-146; llms.txt line 11) |
| 2 | one bundled ESM file with `#!/usr/bin/env node`; ws, node-pty, @vscode/ripgrep, grammy external; no `process.title` | confirmed (build.js lines 79-162; `grep -rn 'process\.title' src` empty; the shipped 0.32.19 `letta.js` has none either) |
| 3 | npm install shows `node <prefix>/bin/letta` with the symlink path | unsupported as observation (inferred from shebang exec; the row already says so). Not contradicted. Nix and pnpm show the real-path form instead, see 5 |
| 4 | `bun` in `names` is inferred | corrected: for Nix it is documented. `flake.nix` line 87 `makeWrapper ${pkgs.bun}/bin/bun ... --add-flags $out/lib/letta-code/letta.js`. For npm/pnpm/bun-global installs it is still inferred |
| 5 | `letta server` / `remote` daemons | corrected: matched only through `bin/letta`, so the Nix wrapper and pnpm/npx real-path forms (`bun .../letta-code/letta.js server`) matched nothing. Two daemon surfaces added (`letta-code/letta.js` + `server`, + `remote`) |
| 6 | PyPI wheel: launcher `execve()`s bundled node, argv `<pkg>/letta_code/_payload/bin/node <pkg>/letta_code/_payload/app/letta.js`, `LETTA_CODE_DISTRIBUTION=pypi` | confirmed (python/letta_code/__init__.py lines 8-26). Old MemGPT `letta` runs under python and is not matched (replayed) |
| 7 | `--conversation`/`-C` take an id, `--conv` is rewritten, `--resume`/`-r` boolean, `-p`/`--prompt` headless | confirmed; line numbers in the cited source were stale and are fixed in the row. Added: `--conv default --agent <id>` and `--conv <agent-id>` mean an agent's default conversation, so a session id from argv is not always a conversation id |
| 8 | headless one-shots and subagents are vetoed by `-p` / `--prompt` | REFUTED for subagents. `manager.ts` line 338 passes `promptTransport: "stdin"` and line 218 only pushes `-p` when the transport is not stdin. A subagent argv has `--output-format stream-json`, `--tags`, `--permission-mode unrestricted` and no `-p`. Replayed with the probe: the old row filed a subagent as an idle TUI session. Repair: exact-argument vetoes for every headless-only flag in `args.ts` (matches Herdr's `is_interactive_letta_process`). Not fixable from argv: a bare `letta` with piped stdin is headless too (`startup-mode.ts`); `--flag=value` spellings also slip past exact matching |
| 9 | management subcommands are not sessions | corrected: list was incomplete. `upgrade` (alias of `update`), `--update`/`--upgrade` (index.ts lines 101-113) and `trajectory` (alias of `trajectories`) were missing; `letta upgrade` was reported as a session (replayed). Added |
| 10 | Bash tool is a direct detached child `/bin/zsh -c|-lc <cmd>` on macOS, zsh first then `$SHELL` | confirmed (shell-launchers.ts `unixLaunchers` line 259-285; shell-runner.ts `spawnPipeProcess` spawn `shell:false`, `detached`) |
| 11 | only shell tools are children; zsh may exec a lone command in place; MCP/LSP long-lived children; updater `npm install -g` via execFile | confirmed for LSP (`LETTA_ENABLE_LSP`, index.ts 638) and updater (`execFile`, auto-update.ts); exec-in-place and MCP children are inference, unchanged |
| 12 | no sleep inhibitor in the CLI | confirmed (grep for caffeinate, powerSave, IOPM, systemd-inhibit over `src scripts docs` empty) |
| 13 | terminal title: default items activity + agent-name, Braille spinner 100 ms, `[ ! ] Action Required` alternating with `[ . ] Action Required` every 1 s, OSC 0 with BEL | confirmed (window-title-config.ts lines 39-68; TerminalTitleWriter.tsx; terminal-title.ts writes only when stdout is a TTY). Herdr's `letta.toml` reads the same strings |
| 14 | OSC 9;4;3;0 only while an approval or question dialog is mounted, cleared with 9;4;0;0 | confirmed (use-progress-indicator.ts). Herdr maps `4;3` to blocked |
| 15 | Notification hook messages `Approval needed`, `Turn completed, awaiting your input`; BEL written | confirmed (notifications.ts; call sites listed) |
| 16 | hooks deprecated in favour of Mods; three settings files; 11 events; `hooks.disabled` | confirmed (docs status: legacy; hooks/types.ts and loader.ts) |
| 17 | local backend: `~/.letta/lc-local-backend/conversations/<base64url(key)>/messages.jsonl`, key `default:<agentId>` or `conversation:<id>`, header keys type, version, id, timestamp, cwd; entry keys type, id, parentId, timestamp, message | confirmed (local-store.ts encodePathSegment line 284, conversationKey line 3262; local-transcript.ts) |
| 18 | default backend is Letta Cloud, no local transcript | confirmed (docs settings/app-server pages; README) |
| 19 | chunk log and debug log paths; both "skipped when `LETTA_CODE_TELEM=0`" | corrected: `~/.letta/logs/debug/...` is skipped (debug.ts line 98), the chunk log is NOT (`chunk-log.ts` `init()` has no env check). Paths, "last 100 chunks", "5 files kept" and the `${Date.now()}-${random}` session id confirmed |
| 20 | App Server `letta server --listen` at `/ws`; `letta server` alone is a cloud computer listener; `letta remote` alias; desktop app uses the App Server | confirmed (app-server docs lines 21, 45; server.ts) |
| 21 | LoopStatus values and `WAITING_ON_APPROVAL` / `WAITING_ON_INPUT` | confirmed (loop-status-protocol.ts line 36) |
| 22 | desktop app: `/Letta.app`, bundle id `com.todesktop.260305dtu2nh5`, executable `Letta`, 0.32.19, Electron, ToDesktop | confirmed (Info.plist re-read; zip is 217891192 bytes, `Letta 0.32.19 - arm64-mac.zip`, last-modified 2026-09-24) |
| 23 | the app spawns the listener with `ELECTRON_RUN_AS_NODE=1` and `remote --env-name <n> --backend api|local`; up to three slots | confirmed (main.js `startListener`, `startLocalBackendListener`, `ALL_DESKTOP_LISTENER_SLOTS`) |
| 24 | ps shows the title `letta-code-listener` instead of the arguments | REFUTED as stated. `main.js` passes `--require <dist>/setProcessTitle.js` only if that file exists (`existsSync`). The shipped `app.asar` has no such file anywhere (dist/ contains only main.js, preload.js, fileOpsWorker.js, index.html, package.json, 3rdpartylicenses.txt, favicon, welcome image and assets/) and `app.asar.unpacked` has only the letta-code package. So 0.32.19 most likely runs un-retitled: `Letta <...>/letta-code/letta.js remote --env-name ...`. The un-retitled daemon surface is now the expected one and the titled one is kept as a fallback. Replayed: both forms still classify as daemons. Unverified without a running app |
| 25 | desktop holds Electron `powerSaveBlocker('prevent-app-suspension')`, 10 s heartbeat | confirmed in the shipped `dist/main.js` (`ProcessingSleepInhibitor.reconcile`, `PROCESSING_HEARTBEAT_TIMEOUT_MS = 10000`, `set-processing-state`) |
| 26 | `power_assertion` signal with `name` = a prose description | corrected: the probe tests `want.lower() in <pmset assertion name>`, so a sentence can never match (checked against "Electron", "PreventUserIdleSystemSleep", "Letta"). `name` removed; the prose moved into `meaning`. The real pmset name is still unknown (unsupported). Side effect: any non-caffeinate assertion in the Letta tree counts |
| 27 | GUI surface `/Letta.app/Contents/MacOS/Letta` does not match the Electron helpers | confirmed (helpers live under Contents/Frameworks; replayed) |
| 28 | no OpenTelemetry; product analytics to `/v1/metadata/telemetry`; opt out `LETTA_CODE_TELEM=0` / `DO_NOT_TRACK=1` | confirmed (`grep -c opentelemetry package.json bun.lock` 0 and 0; telemetry/index.ts lines 393-400; the POST is at `backend/api/metadata.ts` line 100, not 93) |
| 29 | product now called Letta Harness / Letta app / Letta CLI ("formerly Letta Code") | confirmed (llms.txt line 25) |
| 30 | nothing of Letta installed or running here | confirmed again: `command -v letta` empty, `ls -d ~/.letta` no such file, `ls /Applications/Letta.app` no such file, `pmset -g assertions | grep -ci letta` 0, `ps` matches only the checking shell |
| 31 | `tree_cpu` floor 3% and hold window 30 s | unsupported (guesses, as the row says). One shared floor cannot differ by surface, so an idle Electron desktop tree may sit above 3%; README section 4 says 10 for Electron hosts |
| 32 | Herdr rejects headless runs the same way | confirmed and stronger than the row said: Herdr also vetoes `--output-format`, `--run`, `--tags` and others (`src/detect/mod.rs` `is_interactive_letta_process`) |

False-positive review of the process patterns:

- `names node|bun` + `bin/letta` is a substring on any argument, so `node /x/bin/letta-foo.js` would match. No real collision was found. The old PyPI `letta` (MemGPT server) runs under python. The Letta app's helpers do not match. `-n <name>` values equal to a subcommand still hide a session, and a substring `server` in any argument (`--system-custom "...server..."`, a path) still files a TUI as a daemon (score 3 beats 2). Both limits are known and stay.
- `letta-code/letta.js` also matches a developer's own source checkout run with node/bun. That is a Letta process, not a collision.
- `letta-code-listener` as a bare name matches nothing else known.
- After the repair: a subagent (`--output-format`) and `letta upgrade` no longer match; the Nix real-path `server` matches a daemon; every other replayed line landed where it did before.

What is still unsupported: any live behaviour, the npm `ps` line, the pmset assertion name, whether a pending approval keeps the desktop assertion held, whether the desktop ships or lacks the retitle at runtime, and the CPU floor and hold window.
