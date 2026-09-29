# GitHub Copilot CLI evidence notes (2026-09-29)

Not installed on this Mac. Nothing below was observed on a running instance, so confidence is `documented`, not `verified-locally`. The github/copilot-cli repo has no source (README, changelog.md, install.sh only). The readable "public source" is what the vendor ships: the npm packages and the GitHub Copilot app zip. I downloaded them into the scratchpad, extracted, and read or `strings`-scanned. Nothing was installed or executed.

## What I checked
- Local: `which copilot` (not found), `ls ~/.copilot` (missing), `ps | grep copilot` (empty).
- Docs (all fetched): CLI command reference, config-dir reference, hooks reference, OTel section. Repo `install.sh`, `changelog.md` (v1.0.88). Homebrew API for cask `copilot-cli` and `github-copilot-app`.
- `@github/copilot@1.0.89` (npm latest; prerelease 1.0.90-2): 12 KB `npm-loader.js`. `@github/copilot-darwin-arm64@1.0.89`: one 154 MB Mach-O arm64, a Node single-executable app. It embeds `copilot.tgz` (index.js, 7.5 MB app.js, `prebuilds/darwin-arm64/runtime.node`, ripgrep, tgrep, a helper `Copilot Computer Use.app`). I extracted the tgz from the binary and read app.js.
- GitHub Copilot desktop app v1.1.23 zip: read `Info.plist`, `generated/session-events.d.ts`, and scanned `Contents/MacOS/github`.
- `github/copilot-cli` issue #2609 for the lock file layout.

## Answers
- Process: native `copilot` (basename). Homebrew: `/opt/homebrew/bin/copilot` symlink. install.sh: `~/.local/bin/copilot` or `/usr/local/bin/copilot`. npm: `node .../@github/copilot/npm-loader.js` parent plus `.../@github/copilot-darwin-arm64/copilot` child. Auto-updates load a newer `index.js` in the same process, so the exe never changes.
- GUI: `/Applications/GitHub Copilot.app`, bundle id `com.github.githubapp`, exe `Contents/MacOS/github`.
- Daemon shapes: `--acp`, `--server`/`--headless`, `--ui-server` (TUI plus server), and app/SDK-spawned children using `--port` or `--stdio`.
- Session store: `~/.copilot/session-state/<uuid>/events.jsonl` (+ `workspace.yaml`, plans, checkpoints), `~/.copilot/session-store.db` (SQLite index), `~/.copilot/logs/process-<ts>-<pid>.log`. `COPILOT_HOME` relocates all of it.
- Record keys (from the SDK typings, not from a real file): `id, parentId, timestamp, type, data`, optional `agentId`, `ephemeral`.
- Best turn signal that exists on disk or in `ps`: hooks. `userPromptSubmitted` opens a turn, `agentStop` closes it. Without hooks: a fresh `events.jsonl` write, weak.
- Waiting on human: `notification` hook (`permission_prompt`, `elicitation_dialog`). Terminal side: OSC 9;4 progress and OSC 0 title.
- Hooks: 14 events, JSON files, listed in the row. OTel: yes, off by default.

## Could not determine
- Real `ps` args, CPU idle vs working, and child processes of a live TUI. `tree_cpu` at 3 percent is a guess.
- Whether the Copilot app's Keep Awake setting is on by default. Its exact assertion name string is truncated in the binary scan ('GitHub Copilot app ... N active session(s)').
- The exact argv the app uses to start its CLI children, and whether that CLI is the user's `copilot` or an extracted bundled copy (the app reports `bundled_version`, `extracted`, `embedded`). The `--port` daemon needle is inferred from strings.
- Where the live session registry lives. The runtime has `remote_registry_write_entry/list_entries` and the TUI sidebar lists other live sessions as `sessionId@pid@host:port`. That would be a clean pid to session map. I found no path string.
- Whether `permission.requested` is written to events.jsonl. It is typed `ephemeral?: boolean`, unlike `user_input.requested` and `elicitation.requested`, which are always transient.
- Whether the VS Code Copilot Chat "Copilot CLI" agent runs this binary as a separate process, and its path. Not in any source I read.
- Actual `inuse.<pid>.lock` behavior on macOS or in 1.0.89. Evidence is a Linux user report on 1.0.21 plus an `inuse.` string in runtime.node.

## Contradicts common belief or the obvious approach
- It is not a node process any more. Old advice to look for `node .../copilot/index.js` is wrong for 1.0.x. Under npm the node parent is only a launcher; match the native child.
- caffeinate exists (`caffeinate -dis -w <pid>`) but is opt-in (`keepAlive` default `off`). In `on` or timed mode it runs while idle. Do not copy the Claude Code rule (any caffeinate child means working).
- `session.idle`, the real end-of-turn event, is transient and never written to events.jsonl. `assistant.turn_start`/`turn_end` are per model round-trip, so "last record is turn_end" does not mean idle. The transcript cannot show idle.
- A plain interactive process has no session id in argv. Only `--session-id`, `--resume`, `--connect` carry one, and `--resume` may be a prefix or a name. Use the `inuse.<pid>.lock` files or the process log name.
- The desktop app is a second surface with its own power assertion and its own CLI children, but writes the same `~/.copilot` store. The probe's space-split of `ps args` cannot match `/Applications/GitHub Copilot.app/...` (argv[0] becomes `/Applications/GitHub`, which would also collide with GitHub Desktop). Use the bundle id.
- Hooks also read Claude's `.claude/settings.json` and `.claude/settings.local.json` in the repo, and accept Claude-style PascalCase event names (`Stop`, `PreToolUse`) with snake_case payloads.
- Docs and README mention Claude Sonnet 4.5 as default; the README is stale (Feb 2026). Not relevant to detection.
- The package ships `Copilot Computer Use.app` (`com.github.computeruse.service`). It is a tool helper. Do not count it as a session.

## Verification

Independent refutation pass, 2026-09-29. `tools/validate_row.py registry/agents/copilot-cli.json` printed `ok` before and after the repairs. Sources were re-fetched (docs, npm registry, Homebrew API, GitHub Atom feed and issue page, changelog) and the two vendor packages were re-downloaded into the scratchpad and read statically (`file`, `strings`, extracting the embedded `copilot.tgz`, reading `app.js`, `sea-loader.js`, `copilot-sdk/index.js`, `session-events.d.ts`, `Info.plist`). Nothing was installed or executed. Confidence stays `documented`: the harness is not installed here and no live process was classified.

### Confirmed
- Not installed: `which copilot` -> not found, `~/.copilot` missing, no copilot process, `/Applications` holds only GitHub Desktop.
- install.sh: `copilot-${PLATFORM}-${ARCH}.tar.gz`, `INSTALL_DIR=$PREFIX/bin`, PREFIX default `/usr/local` as root and `$HOME/.local` otherwise, `tar -xz -C "$INSTALL_DIR"`.
- Homebrew cask `copilot-cli` 1.0.89: binary `copilot` -> `$HOMEBREW_PREFIX/bin/copilot`; zap trashes `~/.copilot` and `~/Library/Caches/copilot`. Cask `github-copilot-app` 1.1.23 installs `GitHub Copilot.app`.
- npm: `bin.copilot = npm-loader.js`; it `spawnSync`s `@github/copilot-<platform>-<arch>` with `stdio:"inherit"`. optionalDependencies include darwin-arm64 and darwin-x64. dist-tags latest 1.0.89, prerelease 1.0.90-2.
- Native package: `file` -> Mach-O 64-bit executable arm64 (154,630,864 bytes); `NODE_SEA_FUSE_...` present; embedded gzip tar holds index.js, app.js, sea-loader.js, prebuilds/darwin-arm64/runtime.node, ripgrep, tgrep. sea-loader.js loads index.js in-process with `await import(pathToFileURL(r))` and has no `spawn`. Process stays `copilot`.
- Docs (config-dir reference): `session-state/` (events.jsonl, workspace artifacts), `session-store.db` (SQLite, rebuild with `/chronicle reindex`), `logs/process-{timestamp}-{pid}.log`, `COPILOT_HOME`, `--config-dir` legacy, `keepAlive` default `"off"`, `terminalProgress` default true, `updateTerminalTitle` default true.
- caffeinate: app.js `startChildProcessKeepAlive({command:"caffeinate",args:["-dis","-w",String(process.pid)]})` on darwin, `/keep-alive` alias `/caffeinate` with on|off|busy|DURATION (command reference line 789).
- OSC: app.js `PROGRESS_INDETERMINATE="\x1b]9;4;3;0\x07"`, `PROGRESS_OFF="\x1b]9;4;0;0\x07"`, title `\x1b]0;...`, notify `\x1b]777;notify;...`.
- Hooks reference: 14 events (agentStop, errorOccurred, notification, permissionRequest, postToolUse, postToolUseFailure, preCompact, preToolUse, sessionEnd, sessionStart, subagentStart, subagentStop, userPromptSubmitted, userPromptTransformed); the six locations listed plus `/etc/github-copilot/policy.d/*.json`; `.claude/settings.json` and `.claude/settings.local.json` read; notification types permission_prompt, elicitation_dialog, agent_idle, agent_completed, shell_completed, shell_detached_completed; fire-and-forget; prompt hooks only on sessionStart; PascalCase gives snake_case payloads; agentStop carries `transcriptPath` / `transcript_path`.
- OTel: env vars, defaults (off, otlp-http, http/json, `OTEL_SERVICE_NAME=github-copilot`), content capture off by default, invoke_agent root span with chat and execute_tool children, `github.copilot.turn_count` = LLM round-trips. Enterprise managed telemetry confirmed in app.js (`applyManagedTelemetry`, help text 'enterprise managed telemetry settings').
- Lock files: issue #2609 is real, Linux, CLI 1.0.21, 'Each file contains only its PID', stale after exit. `inuse.` and 'held session lock files mutex poisoned' are in `runtime.node`. Still undocumented and not seen on macOS.
- Desktop app: bundle id `com.github.githubapp`, executable `github`, display name GitHub Copilot, v1.1.23, URL schemes github-app, ghapp, gh. `IOPMAssertionCreateWithName`, `PreventUserIdleSystemSleep`, 'Session became busy/idle (keep-awake tracking)', `grace_period_minutes`, 'GitHub Copilot app ' + ' active session(s)' are all in `Contents/MacOS/github`.
- Helper `Copilot Computer Use.app`: bundle id `com.github.computeruse.service`, `LSUIElement=1`, at `package/plugins/computer-use/`. Its executable path contains none of the row's needles, so it is not counted.
- Record keys `id, parentId, timestamp, type, data, agentId?, ephemeral?` from `session-events.d.ts`.

### Corrected
- Repo state: latest commit is 'Update changelog.md for version 1.0.89' (2026-09-28), not 1.0.88. The repo also has a `.github` dir and the file is `LICENSE.md`.
- npm loader size: 12,968 bytes unpacked for the package, 1,185 bytes for `npm-loader.js` (not '12 KB loader').
- Extraction cache path: on macOS `~/Library/Caches/copilot/pkg/darwin-arm64/<version>` (env `COPILOT_PKG_CACHE_HOME` or `COPILOT_CACHE_HOME` override); `$COPILOT_HOME/pkg` and `~/.copilot/pkg` are fallback lookups.
- 'official-docs' claim about `--ui-server/--headless/--port`: the official option table has `--acp`, `--session-id`, `--resume`, `--connect`, `-p`, but no `--server`, `--headless`, `--ui-server` (one passing mention) or `--port`. They are real in app.js, so the claim was split: docs cover the first group, source-code covers the second.
- Turn-end events: `user.message`, `assistant.turn_start/turn_end`, `assistant.message`, `tool.execution_*` are typed `ephemeral?: boolean`, not proven persisted. Only `ephemeral: true` types are proven transient. `transcript_write` meaning reworded.
- pid to session map: `logs/process-<ts>-<pid>.log` gives the pid only; the notes no longer call it a session map.
- Desktop app children: the SDK can also run the runtime in-process (`Transport::InProcess`), and its spawn is `<runtime> --headless --no-auto-update [--stdio | --port N]`. 'Runs its own copilot CLI child processes' softened; 'shares ~/.copilot' marked inferred.
- Process patterns (tested with the probe's own `matches()` on synthetic ps rows):
  - Removed `path_contains "/.local/bin/copilot"`: it duplicated `names` and also matched `/.local/bin/copilot-language-server` and `copilot-agent`.
  - Removed `--port` from TUI `exclude_args` and dropped the standalone `--port` daemon surface: `copilot --ui-server --port N` is a TUI (app.js `embeddedServer:{port}`), and `--port` alone does nothing outside `--server/--headless/--acp/--ui-server`.
  - Added `--ahp-host` (TUI exclude plus a daemon surface). It is a headless host that awaits forever and can outlive its CLI; the old row listed it as a TUI.
  - Added daemon surface `copilot-runtime` (the SDK/app runtime wrapper; its process name is not `copilot`).
  - Labels for `--acp` (needs `--stdio` or `--port`, stdio default), `--server` (CLI itself spawns `--server --port 0 --managed-server`) and `--headless` updated.

Probe results, original row vs repaired row (first matching surface):

| argv | original | repaired |
| --- | --- | --- |
| `copilot --ui-server --port 4321` | daemon `--port` | tui |
| `copilot --ahp-host` | tui | daemon `--ahp-host` |
| `.local/bin/copilot-language-server --stdio` | tui (false positive) | no match |
| `.local/bin/copilot-agent` | tui (false positive) | no match |
| `copilot-runtime --headless --stdio` | no match | daemon |
| `copilot --acp --stdio`, `--server ...`, `--headless ...` | daemon | daemon |
| `GitHub Copilot.app/.../github`, GitHub Desktop, `gh copilot`, `node .../npm-loader.js` | no match | no match |

### Unsupported or unresolved (left as flagged in the row)
- Name collision with the AWS Copilot CLI: Homebrew-core formula `copilot` (1.34.1, ECS/Fargate, end-of-support 2026-06-12) installs a binary also called `copilot` at the same path. `copilot svc deploy` still matches the TUI surface. It cannot be fixed inside the schema: `exclude_args` is matched against every space-separated token, prompt words included, so excluding AWS subcommand words would hide real `copilot -p "..."` runs. A detector should also require a live `inuse.<pid>.lock` or `process-*-<pid>.log` for the pid. Noted in the TUI label and in `notes`.
- `tree_cpu` 3 percent: inferred, never measured. Already labelled so.
- `power_assertion` GUI signal: assertion name truncated in the binary; Keep Awake default unknown; probe has no power-assertion reader.
- Real argv of app-spawned children, and whether the SDK's `.js` path (`node <index.js> ...`) is used on macOS. A `node`-hosted runtime would match no row.
- `inuse.<pid>.lock` on macOS and in 1.0.89: only the Linux 1.0.21 report and the `runtime.node` string.
- Probe limits, not row errors: `--resume=ID` and `--session-id=ID` equals forms are not read; a bare `--resume` grabs the next argv token; `session_store.glob` ignores `COPILOT_HOME`; the GUI path never matches because ps args are split on spaces.
- Snapshot dependency: everything is for CLI 1.0.89 and app 1.1.23. The runtime changes fast (1.0.90 prerelease was published the same morning); `--ahp-host` was not in the vendor docs at all.
