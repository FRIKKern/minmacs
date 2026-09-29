# kimi (Kimi Code, Moonshot AI)

Research date 2026-09-29. Kimi is not installed on this Mac, so nothing was run and no live process was classified. Confidence is `documented`. Everything below is from vendor docs, public source, and the public desktop update feed.

## What I checked

- Cloned `MoonshotAI/kimi-code` (HEAD f409caa, 2026-09-29; CLI 2.1.1, VS Code extension 0.8.1) and `MoonshotAI/kimi-cli` (HEAD 9ab1286, 2026-09-22, archived; 1.52.0) into the scratchpad and read them.
- Read the docs at `docs/en/` in kimi-code (data locations, sessions, hooks, kimi command, server API, remote control, env vars) and https://www.kimi.com/code/docs/en/ (overview, desktop quick start, settings).
- Read `https://code.kimi.com/kimi-code/install.sh`, the desktop feed `https://cdn.kimi.com/kimi-code/desktop/latest-mac.yml`, and, by HTTP range reads of the zip directory and `Info.plist` only, the 1.0.4 arm64 Desktop zip. Nothing was downloaded whole, extracted, mounted or installed.
- Read libuv `proctitle.c` to work out what `ps` shows after `process.title = ...`.
- Local: `which`, `ls ~/.kimi ~/.kimi-code`, `ls /Applications`, `ps` for anything named kimi. All empty.

## Surfaces

| Surface | Process as seen by `ps` | Bundle id | Source |
|---|---|---|---|
| Kimi Code CLI 2.x (TUI, `-p`, `acp`, `web`, `rc`, `vis`) | `kimi-code` (retitled), possibly truncated to a prefix | none | source, inferred for ps |
| Kimi Code Desktop 1.0.4 (Electron) | `/Applications/Kimi Code.app/Contents/MacOS/Kimi Code`, space-split to `/Applications/Kimi` + `Code.app/Contents/MacOS/Kimi` + `Code` | `com.kimi.code.desktop` | Info.plist in the public zip |
| VS Code extension `moonshot-ai.kimi-code` | none: agent runs in the extension host | none | source |
| Legacy Kimi CLI 1.x (Python, archived) | title `Kimi Code` via setproctitle | none | source, inferred for ps |

The CLI binary is a Node single-executable build installed at `~/.kimi-code/bin/kimi` (install.sh), also via Homebrew and npm (`@moonshot-ai/kimi-code`, `dist/main.mjs`). Data root `~/.kimi-code`, moved by `KIMI_CODE_HOME`.

## Session store

`~/.kimi-code/sessions/<workDirKey>/<sessionId>/` with `state.json`, `agents/main/wire.jsonl`, and one `agents/<id>/wire.jsonl` per subagent. `workDirKey` is `wd_<slug>_<first 12 hex of sha256>` of the working directory. `session_index.jsonl` at the root. JSONL, path documented, record content not promised beyond the vendor's generated manifest. Desktop, VS Code and CLI share it. Legacy store is `~/.kimi/sessions/<work-dir-hash>/<id>/{context.jsonl,wire.jsonl,state.json}`, not in the row's `session_store`.

Key names seen in source only (no real record was read): wire lines are `{type, ...payload, time}`; first line `{type:"metadata", protocol_version:"1.5", created_at}`. `state.json` keys: id, version, title, titleKind, lastPrompt, createdAt, updatedAt, archived, archivedAt, cwd, forkedFrom, agents, custom, lastTurnReason.

## Signals

- Working, most precise: an open turn in `agents/main/wire.jsonl`, i.e. `turn.prompt` with no later `turn.ended` (or `turn.cancel`), only while the pid is alive.
- Raise-only: a direct `bash -c` child (the Bash tool spawns `/bin/bash -c`). Blind while the model streams.
- Fallback: CPU (the TUI animates a spinner). Floor 3 is a guess.
- Waiting: `PermissionRequest` hook (approvals), `interaction.request` without `interaction.resolved` in the wire file (approvals and questions), and the local server API field `pending_interaction` for `kimi web` and `kimi rc`.
- Exact busy/idle for web, rc (and maybe Desktop): `GET /api/v1/sessions/{id}` returns `busy`, `main_turn_active`, `pending_interaction`, `last_turn_reason`. Needs a bearer token.
- Hooks: 20 events in `[[hooks]]` of `~/.kimi-code/config.toml` (and plugin manifests). `TurnStarted` opens a turn; `Stop`, `StopFailure` or `Interrupt` closes it.
- OpenTelemetry: no. Only Moonshot's own anonymous events (`KIMI_DISABLE_TELEMETRY=1` or `telemetry = false` turns them off).

## Contradicts common belief

- "Kimi CLI" is not current. The Python `kimi-cli` (`~/.kimi`, `uv tool`) is archived and replaced by a TypeScript CLI in a different repo (`kimi-code`) with a different data root (`~/.kimi-code`). Both install a command called `kimi`. The old PyPI package `kimi-code` is a legacy alias of `kimi-cli`, not the new CLI.
- The new CLI is not a Python or plain Node process to match on. It retitles itself, so `ps` should show `kimi-code`, not `node ...` or the install path, and the arguments vanish. Session id flags cannot be read from `ps` after that.
- The `Notification` hook is not "needs attention" as in Claude Code. It fires only on background-task status changes. Approval waits use `PermissionRequest`. No hook for agent questions was found.
- `Interrupt` fires instead of `Stop` when the user presses Esc, so a hook-tracked turn must close on both.
- No `caffeinate`, no power assertion, in either generation. The usual "sleep inhibitor means working" trick does not apply.
- The Desktop app's executable is `Kimi Code` with a space, so a space-split `ps` gives argv[0] `/Applications/Kimi`. That is also the base name of the separate Kimi chat app (`Kimi.app`) and, after the split, the legacy CLI title `Kimi Code`. The row orders surfaces and uses exact-argument exclusions to keep them apart.
- The docs page for hooks says only four fields are allowed in a `[[hooks]]` entry, but the source type `HookDef` also has `cwd` and `env` (probably for plugin hooks). Not resolved.

## Could not determine

- What `ps` prints for a running kimi on macOS. The `kimi-code` title and the truncation rule (`names` lists prefixes down to 4 characters) come from `main.ts` and libuv source. Same open step as `pi`. First live run should settle it, and if `ps` still shows the original argv, the `path_contains` and `names: ["kimi"]` entries cover it.
- Whether the process holds `wire.jsonl` open, or flushes records per event. So the open-turn read may lag, and pid-to-session mapping for a fresh session (no id in argv) is by cwd only and ambiguous for two sessions in one directory.
- Whether Desktop takes a power assertion or exposes the server API (closed source, `code-app` repo is private). Its helper process layout and whether the agent runs in a utility helper were not checked. The row reports the main process as a host.
- The format of `~/.kimi-code/server/instances/*` and `server/rc.json` (only the paths and the pid in `rc.json` are documented).
- Homebrew install path and whether the formula/cask is a symlink to the SEA binary (docs say `brew install kimi-code`).
- Legacy `ps` title: `setproctitle` is a hard dependency and the code calls it, but macOS output was not seen.
- Hook payload key names beyond the documented base fields; no hook was fired.

## Verification

Second-pass review, 2026-09-29, by an agent that did not write the row. Method: `tools/validate_row.py` (ok before and after), every source re-fetched or re-run (raw files from a fresh shallow clone of MoonshotAI/kimi-code at f409caa and kimi-cli at 9ab1286, the docs pages, install.sh, the Desktop zip by HTTP range reads), and the process patterns run through `matches()` from `tools/agents_probe.py` on synthetic ps lines. Confidence stays `documented`: no Kimi harness is installed here (`which kimi kimi-cli kimi-code`, `ls ~/.kimi ~/.kimi-code`, `ls /Applications | grep -i kimi`, `ps` all empty again).

Confirmed:
- Product split, kimi-cli archived (README banner; last commit 2026-09-22), Desktop, CLI and extension share ~/.kimi-code (Desktop settings page lists `~/.kimi-code/` as shared and applies `[[hooks]]` to the app).
- `process.title = PROCESS_NAME` is the first statement of `main()` (main.ts line 164), `PROCESS_NAME = 'kimi-code'` (app.ts line 7); main.ts calls `main()` for every subcommand.
- install.sh installs to `${KIMI_INSTALL_DIR:-$HOME/.kimi-code}/bin/kimi` with `install -m 0755`; SEA build steps exist; package.json bin and version 2.1.1.
- libuv arithmetic (`cap` = span from argv[0] to the end of the last argument, `len >= cap` truncates to `cap - 1`).
- Desktop zip 1.0.4: bundle id, executable name, four helper apps, app-update.yml url, no separate kimi binary, release date 2026-09-24.
- Session layout, workDirKey format, `session_index.jsonl`, `agents/main/wire.jsonl`, sub-agent dirs (`agents/agent-0/`), KIMI_CODE_HOME.
- `SessionMeta` keys (17 lines, matches), wire manifest (64 record types, protocol 1.5, metadata line, `turn.ended` reasons, `interaction.request` kinds), Bash tool spawn (`processService.spawn(env.shellPath, ['-c', ...])`, bash candidate order, detached).
- Server API fields, busy filter, healthz auth exemption, default port 58627 with +1 retry, instances dir, rc.json, `~/.kimi-code/server.token`.
- 20 hook events, exit-code protocol, blockable events, `PermissionRequest` before approval wait, `Notification` is background-task status, four config fields, plugin hooks, `.kimi-code/local.toml`.
- CLI flags `-S/--session`, `-r/--resume`, `-c/--continue`; OSC 9;4 allow-list (kimi-tui.ts 3870-3875, terminal-notification.ts 114-125).
- No sleep inhibitor and no OpenTelemetry: the grep was re-run; the only hits are syntax-highlighting grammars in `apps/kimi-code/dist-web/assets`, not code. Telemetry: `telemetry = true` config and `KIMI_DISABLE_TELEMETRY` documented; `kfc_` prefix appears in agent-core-v2 `cloudTransport.ts`.
- Legacy CLI: setproctitle title 'Kimi Code', workers 'kimi-code-worker' and 'kimi-code-bg-worker', `~/.kimi/sessions/<md5>/<id>/{context,wire}.jsonl,state.json`, 13 hook events, TurnBegin/TurnEnd (TurnEnd may be omitted on interrupt).
- VS Code extension: in-process `createKimiHarness`, no `child_process` in apps/vscode/src or packages/node-sdk/src, publisher moonshot-ai, name kimi-code.
- Not installed here.

Corrected:
- Legacy surface false positive (proved with `matches()`). Any Desktop bundle executable other than the main process and the Kimi Code Helper apps split to argv[0] `/Applications/Kimi` plus a `Code.app/...` argument, so it matched as a legacy Kimi CLI. The 1.0.4 zip has four such executables: `chrome_crashpad_handler`, Squirrel `ShipIt` (a launchd job with ppid 1, so the probe's parent rule would not hide it), `screenshot-window-list`, node-pty `spawn-helper`. Their first arguments are now in the legacy `exclude_args`. All four printed a legacy match before, none after.
- The "arguments are gone" statement now rests on a local observation. Plain node 22.22.2 on this Mac, title set to 'kimi-code': `ps -axo args=` printed `kimi-code NVM_INC=...` (title, then a stray environment string), and a two-character argument gave `kimi-co NVM_INC=...`, the truncation the row predicts. So argv[0] matching is sound and tokens after it must not be used. Still not run against the SEA binary.
- The source claim for Homebrew: docs do not give a brew command. What exists is the updater's Cellar-path detection (source.ts line 47), `brew upgrade kimi-code` (preflight.ts line 130) and a changelog line. The formula name is known, the binary path is not.
- The hook busy window is near-exact, not exact. `Stop` fires only when a step ends with no tool calls and no pending requests and can force one continuation; `StopFailure` needs an error payload; `Interrupt` fires when the turn ends with reason cancelled (the docs say programmatic aborts do not fire it, the code does not check that); a `blocked` turn end fires none. Wording in `waiting_signals` fixed.
- `turn.cancel` is the cancel request, the close is the `turn.ended` with reason cancelled that follows. `turnId` is a number, written on `turn.prompt` at turn start (loopService.ts line 1199); the schema marks it optional.
- Source path typo: the hooks service is `features/externalHooks/agent/agentExternalHooksService.ts` (the line numbers were right).
- The GUI label said the legacy surface had to stay below it; the legacy `exclude_args` also drop the main process, so the order is a second guard.
- "archived 2026-09": the archive date is not shown anywhere I could read; only the README banner and a last commit of 2026-09-22.
- Added: hidden `__update_download` (detached, unref'd, same executable, retitled) can appear as one extra idle session while a download runs after the TUI exited; `__plugin_run_node` is a same-executable child. Both added to the TUI `exclude_args`, which only helps before the retitle. Background shell tasks and hook commands are also direct shell children, so `tool_children` can outlive a turn.

Unsupported (kept, marked inferred or unverified in the row):
- Desktop hosts every session in one main process: closed source, not observable here. Label now says inferred.
- Desktop power assertion, Desktop use of the server API, and the pid-to-session mapping by cwd for a fresh session.
- Whether wire.jsonl records are flushed per event, and what `ps` prints for the SEA binary and for the legacy 'Kimi Code' title on macOS.
- `tree_cpu` floor of 3 percent: a guess.
- The stdin key names of hook payloads beyond the documented base fields; `turn_id` and `origin_kind` are documented, other kinds than user, task, system_trigger exist in the wire manifest.
- Pattern limits accepted: a bare program named `kimi` matches the TUI surface, and the legacy pattern matches any process with argv[0] basename `Kimi` and an argument containing `Code` that is not one of the excluded Desktop executables.
