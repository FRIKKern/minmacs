# Command Code (`command-code`)

Researched 2026-09-30. Not installed on this Mac (`~/.commandcode` and `/Applications/Command Code.app` absent, no matching process in `ps`). Everything is from docs, the published npm package `command-code@1.72.4` (unpacked into the scratchpad with `curl` + `tar`, nothing installed or run) and the Desktop 0.1.44 release zip (read with HTTP range requests, not downloaded whole, not mounted). Confidence in the row: `documented`.

## What it is

- `github.com/CommandCodeAI/command-code` holds only a readme, issue templates and docs pointers (23 commits, no source). The real code is the npm package: one bundled `dist/cli.mjs` (2.8 MB, minified but readable with grep), a 1.8 KB `dist/index.mjs` launcher, bundled skills and a VS Code `.vsix`.
- Bins: `cmd`, `cmdc`, `command-code`, `commandcode`, all `dist/index.mjs`. Windows docs say `cmd` is taken by cmd.exe, so use `cmdc`. Node >= 22.
- Desktop app (beta): Electron, `/Applications/Command Code.app`, bundle id `ai.commandcode.desktop`, repo `CommandCodeAI/desktop` (installer, releases, issues only; app source private). It embeds the harness and the CLI package, so no CLI install is needed.
- The `.vsix` is an IDE bridge (shares the open file and selection with a terminal session, `cmd --ide-setup`), not an agent host. No surface for it.

## What I checked

| Question | Answer | Where |
|---|---|---|
| Process name | `command-code`, always. `cli.mjs` runs `process.title = "command-code"` at module load (changelog 1.50.1). Every bin and every subcommand ends up with that title. | `cli.mjs setStableProcessTitle`, `CHANGELOG.md` |
| What `ps` shows | Only `command-code`. Reproduced on a stand-in `node -e "process.title=..."`: `ps args=` gave `command-code`, `real_argv` gave `['command-code','','']`. So no flags, no `--resume <id>`, no path. | local command, see row |
| Desktop process | `/Applications/Command Code.app/Contents/MacOS/Command Code`; helpers `Command Code Helper (Renderer\|GPU\|Plugin)` and plain `Command Code Helper` under `Contents/Frameworks`. Row's path substring matches the main one only (probe score 46 vs 0 on helpers). | zip central directory, `probe.matches` |
| Session -> process | Not possible by id (args gone). Use the process cwd (`lsof`) -> project slug folder -> newest UUID `.jsonl`; ambiguous when two sessions share a directory. Exact mapping needs a `SessionStart` hook (stdin has `session_id`, `transcript_path`) or a mod. | derived |
| Store | `~/.commandcode/projects/<slug>/<uuid>.jsonl`, append-only tree. Sidecars: `.meta.json`, `.share.json`, `.checkpoints.jsonl`, `.prompts.jsonl`, `.scheduled-tasks.json`, `.v2.bak`. Backups in `~/.commandcode/file-history/<id>/`. Scratch dir `/tmp/commandcode-<uid>/<cwd>/<id>/scratchpad`. Documented. | docs `/sessions`, `cli.mjs sessionSidecarPaths` |
| Record keys | Header: `type, version(3), id, timestamp, cwd, parentSession?`. Entry (V3): `type, id, parentId, timestamp` plus, for `type: message`, `message{role, content}` and optional `usage, model, effort`; other types `model_change, effort_change, compaction, branch_summary, custom, custom_message, label, session_info`. (Corrected in Verification: an earlier version listed the legacy V2 keys.) Read from source; no real file to look at. | `cli.mjs createSessionStoreV3`, `Af` set |
| Turn in progress | No sleep inhibitor at all (0 hits for caffeinate, pmset, IOPM, powerSaveBlocker, wakeLock in the CLI; 0 for powerSaveBlocker in Desktop). Best outside signals: direct `sh -c` child while a shell tool runs (`spawn(cmd, [], {shell})`), transcript appends (round commits), CPU. | source greps |
| Exact state | The CLI has an exact machine: `working` (a run or compaction open), `blocked` (`permission` or `question` open), `idle`. It is sent as `pane.report_agent` JSON lines to a Unix socket, but only when launched inside Herdr (`HERDR_ENV=1`, `HERDR_SOCKET_PATH`, `HERDR_PANE_ID`). Same events are subscribable by a user mod: `interaction_requested` / `interaction_resolved`. | `cli.mjs createHerdrReporter/reportFor`, changelog 1.50.1 |
| Waiting on the human | No hook, no title glyph, no file. Only the Herdr report or a mod. Desktop shows an OS toast and a badge, in-app only. | source, docs |
| Hooks | Shell hooks: `PreToolUse`, `PostToolUse`, `Stop`, `SessionStart` (docs and the literal array in source). Config `~/.commandcode/settings.json`, `<project>/.commandcode/settings.json`, `settings.local.json`. Richer lifecycle (turn start/end, run end, sub-agents) only through mods (`~/.commandcode/mods`, `--mod`). | docs `/hooks`, mod-builder reference bundled in the package |
| OpenTelemetry | SDK bundled, but it exports spans to hard-coded vendor endpoints; no `OTEL_EXPORTER_OTLP_*` is read, only `OTEL_SDK_DISABLED`. Row says `otel: false` (nothing a user can point at a collector). Opt out with `telemetry:false` in `~/.commandcode/config.json`, `DO_NOT_TRACK=1`, or `CMD_LOCAL_ONLY`. | `cli.mjs`, docs `/troubleshooting/telemetry` |

Also verified: the row passes `tools/validate_row.py`; on a stand-in Node process with the retitled name, `tools/agents_probe.py --row` reports idle, then working once a direct `sh` child exists.

## Could not determine

- Any live behaviour: CPU idle vs busy, whether a busy turn animates, real `ps` output of the real CLI, real record contents. The 3% CPU floor is a guess and marked so.
- Exact slug for unusual paths (camelCase, dots, unicode): the code calls `@sindresorhus/slugify` (dependency, not installed); I did not run it. Glob uses `*`, so it does not matter for matching.
- Whether the Desktop app's harness starts helper processes for tools other than through the Electron main process (no `utilityProcess` or `fork` in `out/main/index.js`, but a bundled chunk could differ). Where the Desktop thread-index SQLite file lives (Electron `userData`, exact name not read); it has no status column anyway.
- Whether Desktop `Terminal` panel shells are direct children of the main process (inferred from `@lydell/node-pty`); that is why the row warns off the shell-child signal for Desktop.
- What a "sub-agent" or background agent looks like as a process (in-process by the docs; not verified).
- Whether `checkpoints.jsonl` or `prompts.jsonl` mtime marks the start of a turn (they are written per prompt by the docs' account; not checked in source). Could be a useful "turn opened" raise signal.
- How `/loop` and cron scheduled turns behave with the terminal sitting idle (they run turns with no human; `scheduler-lease.json` under `~/.commandcode/cron/` holds a pid). Not read further.

## Contradicts common belief

- The hint's bin names do not identify the process on macOS. `ps` never shows `cmd`, `cmdc` or `commandcode`, nor a `node ... dist/index.mjs` line: it shows `command-code`. Matching by `names: ["command-code"]` is the only shape that works, and it works only because of the retitle.
- The README says start with `cmd`. That is the primary bin on macOS and Linux; `cmdc` is the Windows alias. Neither is a process name.
- "Has hooks" is thin: four events, tool-scoped. No `UserPromptSubmit`, `Notification`, `SessionEnd` in the shell-hook layer (`SessionEnd` exists only as a mod hook `onSessionEnd`). Waiting cannot be seen from hooks, unlike Claude Code's `Notification`.
- Telemetry is not "OpenTelemetry you can use": it is OTel plumbing pointed at the vendor.
- The Desktop app is not the CLI in a window: one Electron main process hosts the harness for every chat, so per-session process signals do not exist.
- Sessions do not get rewritten in place (the older V2 store used tmp + rename; the V3 tree store used since the docs' session rewrite appends). Writes happen when a round commits, and the file appears only after the first assistant reply, so a quiet transcript never proves idle and a missing one never proves a session absent.
- A background `sh` (dev server, log tail started by the agent) keeps running after the turn ends, so "has a shell child" can stay true while idle.
- After a reload the CLI can run as a wrapper with a child copy of itself; the probe keeps the outer one, and the work then sits a level down.

## Sources fetched

- https://github.com/CommandCodeAI/command-code (readme), https://github.com/CommandCodeAI/desktop and its `install.sh`, `INSTALL.md`, releases API (v0.1.44, 2026-09-29).
- https://commandcode.ai/docs: `reference/cli`, `sessions`, `hooks`, `background-tasks`, `rc`, `desktop`, `ide-integration`, `troubleshooting/telemetry`, `settings`, `headless`.
- npm: `command-code@1.72.4` tarball and `npm view` metadata; Desktop v0.1.44 arm64 zip (`Info.plist`, `package.json`, `out/main/index.js`, `out/main/thread-index.store-*.js`).
- Prior art context: `registry/evidence/prior-art.md` row 10 (Emdash, Orca, Agent Deck name it).

## Verification

Adversarial pass 2026-09-30, by a second reviewer. Not installed here (`~/.commandcode` and `/Applications/Command Code.app` absent, no matching process), so confidence stays at most `documented`. `tools/validate_row.py` printed `ok` before and after the edits. Re-checked against the npm tarball `command-code@1.72.4` (fetched, unpacked in the scratchpad, not installed), the docs pages, and the Desktop v0.1.44 arm64 zip (HTTP range reads of the central directory, `Info.plist`, `out/main/index.js`, thread-index chunk).

### Claims

| Claim | Result | How |
|---|---|---|
| bins cmd, cmdc, command-code, commandcode -> dist/index.mjs; Node >=22; UNLICENSED; latest 1.72.4, modified 2026-09-30 | confirmed | `npm view command-code@1.72.4 bin engines license time.modified`; dist-tags latest 1.72.4 |
| index.mjs is a `#!/usr/bin/env node` script that imports ./cli.mjs | confirmed | head and tail of `dist/index.mjs` |
| CLI sets `process.title = "command-code"` at module load, for every command | confirmed | `function setStableProcessTitle(){process.title="command-code"}`, a top-level call, and CHANGELOG 1.50.1. It is the only `process.title` assignment in cli.mjs |
| macOS Node title replaces args; probe sees `['command-code','','']` | confirmed (stand-in) | `node -e "process.title='command-code'..."`: `ps args=` printed `command-code`, `real_argv` returned `['command-code','','']`. Stand-in, not the real CLI |
| Row matches the retitled process, idle then working on a direct `sh` child; Desktop main matches; helpers do not; no other row matches | confirmed (stand-in) | Re-ran `agents_probe.py --row`: idle, then `working ... tool shell running` with `sh -c 'sleep 4; sleep 1'`. `matches()` over all 63 rows: bare `command-code` hits only this row (score 1), Desktop main path hits only this row (46), both Helper shapes, `node`, `cmd`, `cmdc`, `commandcode` hit none. Note `sh -c 'sleep 5'` execs in place and shows `sleep` as the child, so a lone-command shell tool is invisible (registry/README.md section 3 case 9); not specific to this row |
| Sessions: JSONL, one file per session under ~/.commandcode/projects/<slug>/<id>.jsonl, sidecars, header first, `--no-session` writes nothing, `-p` sessions saved but hidden | confirmed | https://commandcode.ai/docs/sessions, re-fetched. Docs list four sidecars (meta, share, checkpoints, prompts); source `sessionSidecarPaths` adds `.scheduled-tasks.json` and `.v2.bak` |
| Transcript record key names | **corrected** | The entry keys in the row were the legacy V2 shape (`toStoredEntry`). The V3 transcript entry is `{type, id, parentId, timestamp, ...}`, `message` entries carry `message{role,content}` plus optional `usage, model, effort`, entry ids are 8-char UUID prefixes. Header keys were right. Row and this file fixed |
| Header written only after the first assistant message | confirmed, detail added | `persistEntry` returns until `isAssistantMessageEntry`, then `writeWholeFile(header + buffered entries)`, then `appendLineToDisk` per entry. Docs agree ('Empty sessions leave no file') |
| Project folder is `@sindresorhus/slugify` of cwd, `root` fallback | confirmed (default slug not run) | `function slugify(e){return ve(e)||"root"}`, `getProjectDirName(e){return slugify(e.cwd)}`. Exact slug for unusual names still untested, as the row says |
| Shell tool is a direct child (`spawn(command, [], {shell, detached})`); background shells detached | confirmed | `createNodeShell.run` and `spawnBackground` in cli.mjs; https://commandcode.ai/docs/background-tasks (`run_in_background`, `kill_shell`) |
| tool_children false positives: auto-update script | confirmed | `spawnBackgroundUpdate` runs `buildUpdateScript` via `spawn(script, [], {detached:true, shell:true})`, a direct `sh -c` child |
| No sleep inhibitor (CLI and Desktop) | confirmed | 0 matches in cli.mjs for caffeinate, pmset, IOPM, powerSaveBlocker, wakeLock, idleSleep; 0 for powerSaveBlocker, utilityProcess and `fork(` in Desktop `out/main/index.js` |
| Terminal tab title is static and not a busy indicator | confirmed | `formatSessionTabTitle` builds `<glyph> Command Code . <dir> [. model]` or the session title; `useTerminalTitle` only re-asserts on `isCmdCodeBusy` change and every 5 s |
| Herdr socket state machine (working/idle/blocked, gated by HERDR_ENV=1, HERDR_SOCKET_PATH, HERDR_PANE_ID, CMD_HERDR not 0/false) | confirmed | `resolveHerdrConfig`, `nextLifecycle`, `reportFor`, `buildHerdrLine` (`pane.report_agent`); also a pane-owner env var suppresses a nested session's reports (detail the row omits, harmless) |
| Mods can subscribe to interaction_requested/resolved; catalog omits them | confirmed | `vN=["run_start","run_end","interaction_requested","interaction_resolved","compaction_start","compaction_done"]` in `createHerdrMod`; 0 hits for `interaction_requested` in `dist/bundled/mod-builder/reference/*.md` |
| Shell hooks: four events, no Notification, no UserPromptSubmit | confirmed | https://commandcode.ai/docs/hooks ('Supported events'); 0 hits for UserPromptSubmit in cli.mjs; the literal array `["PreToolUse","PostToolUse","Stop","SessionStart"]` |
| Hook config paths, precedence, env vars, stdin fields, system shell | confirmed with two corrections | Docs table lists only user and project settings.json and says project > user. `<project>/.commandcode/settings.local.json` is read by `loadSettingsHooks` (source only, undocumented). Docs list four env vars (the row named three; source also sets COMMANDCODE_CWD and COMMANDCODE_PERMISSION_MODE). Hooks load once at session setup |
| Telemetry: no user OTLP export, only vendor endpoints, OTEL_SDK_DISABLED is the only OTEL_ var | confirmed | `grep -o 'OTEL_[A-Z_]*'` printed only `OTEL_SDK_DISABLED`; `createCommandCodeSpanProcessor` posts to a fixed URL with a bearer; `ingestion.claicode.com/v1/inference-events` present |
| Telemetry opt-outs: telemetry:false, DO_NOT_TRACK=1, CMD_LOCAL_ONLY | corrected attribution | The docs page documents only `telemetry:false` in ~/.commandcode/config.json. DO_NOT_TRACK, CMD_LOCAL_ONLY and COMMAND_CODE_TELEMETRY_CONSOLE come from cli.mjs source. Source entry reworded |
| CLI can relaunch as wrapper plus child copy (exit 75) | confirmed | `runRelaunchLoop` spawns `process.execPath` with `process.argv[1]`, env `CMD_RELOAD_FILE`, `CMD_RELOAD_WRAPPER_PID`; `ex=75`; `isWrappedChild` |
| `--experimental --rpc`, `--sandbox` exist | confirmed | `isMachineReadableExperimental`, option table in cli.mjs |
| `/rc` (Telegram, Discord) runs inside the session process | unsupported, reworded | Docs and the slash-command table show `/rc` as a session command; nothing read shows where the bot loop runs. Marked inferred |
| Desktop: bundle id ai.commandcode.desktop, executable `Command Code`, path `/Applications/Command Code.app`, arm64 and x64 | confirmed | Range-read `Info.plist` from the v0.1.44 arm64 zip: CFBundleIdentifier `ai.commandcode.desktop`, CFBundleExecutable `Command Code`, version 0.1.44, URL scheme `commandcode`. Release assets include Intel x64 zip and dmg. `/Applications` path is from install.sh, not re-fetched |
| Desktop helper names and main path | confirmed | Central directory of the same zip (24810 entries): `Contents/MacOS/Command Code`, and `Command Code Helper`, `(Renderer)`, `(GPU)`, `(Plugin)` under `Contents/Frameworks` |
| Desktop runs the harness in the Electron main process; no power assertion; SQLite thread index without status column; shared ~/.commandcode root; in-app notifications | confirmed | `out/main/index.js`: `@commandcode/harness` imported, 0 hits for `utilityProcess`, `fork(`, `powerSaveBlocker`; `notifyNeedsInput` and `notifyRunEnd` use Electron `Notification`; `resolveSessionProjectPath` uses `join(homedir(), ".commandcode")`; thread-index chunk `CREATE TABLE threads(id,title,project_path,model,git_branch,unread,created_at,updated_at,last_activity_at,has_transcript)`; package.json lists `@lydell/node-pty` |
| Desktop docs: beta, no CLI needed, tool rows running/complete/failed/waiting for approval | confirmed | https://commandcode.ai/docs/desktop, re-fetched |
| tree_cpu floor 3% | unsupported (guess) | Row already says inferred and unmeasured |

### Process pattern false positives

- Desktop main: `path_contains` `/Command Code.app/Contents/MacOS/Command Code` is a substring of argv[0] only. The Helper apps live at `.../Command Code Helper (Renderer).app/Contents/MacOS/Command Code Helper (Renderer)`, which does not contain that string (probe score 0). No other registry row matched it.
- TUI: `names: ["command-code"]` compares argv[0] base name. Only the retitled CLI has that argv[0]; bins `cmd`, `cmdc`, `commandcode`, a plain `node .../dist/index.mjs` line, and `/usr/local/bin/command-code-foo` all scored 0. The only other process with that title is the reload child of a wrapper, and the probe keeps the outermost.
- Same-title lookalikes that do match and read as brief idle sessions: `cmd -p`, `cmd mcp ...`, `cmd status`, `cmd update`, `cmd taste ...`. Cannot be excluded because args are erased; the row's label says so.
- **Found and left, documented:** the probe applies `working_signals` to every surface of a row. On the Desktop host, `tool_children` (permanent node-pty terminal shells, inferred) and `tree_cpu` (Electron helper tree at a 3% floor) can read working with no turn running. The schema cannot scope a signal to one surface, so the row keeps the Desktop surface as a host marker, its label and notes say the state is unreliable, and a source entry records the reason.

### Confidence

`documented`, unchanged. Every process-shape and store claim rests on source, docs or a stand-in Node process; no real Command Code session was observed. Open items: real `ps` output of the real CLI, real record contents, CPU behaviour, the unusual-path slug, whether Terminal-panel shells are direct children of Desktop main.
