# OpenCode: evidence notes (2026-09-29)

Row: `registry/agents/opencode.json`. Validator: ok. Confidence `documented`. OpenCode is not installed here and nothing was running, so no surface was classified live. Version researched: 1.18.33 (released 2026-09-28), repo `anomalyco/opencode`, branch `dev`.

## What I checked

- README and docs pages (`packages/web/src/content/docs/`: cli, server, plugins, tui, troubleshooting, ide), plus opencode.ai/install.
- Public source, from a dev-branch tarball unpacked to the scratchpad (not built, not run): desktop (`packages/desktop`), TUI thread (`packages/opencode/src/cli/cmd/tui.ts`), session status/permission/question, database and global paths (`packages/core`), plugin hooks (`packages/plugin`), observability (`packages/core/src/observability`).
- The real desktop release zip for 1.18.33, downloaded and read with `unzip -p`/`plutil` only. It gave the bundle id, executable name and helper names. Not mounted, not installed, not launched.
- npm registry and Homebrew API metadata for install layout.
- Local: `which`, `ps`, `ls /Applications`, `mdfind`, `ls ~/.local/share/opencode ~/.config/opencode`, `tools/agents_probe.py --row`. All empty. Matching was tested with made-up ps lines through the probe's own matcher.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | TUI, `serve`, `web`, `run` (one-shot), `acp` (stdio for editors), desktop app (Electron), VS Code/Cursor extension (a terminal running the TUI with `--port`) | docs, source |
| TUI process | One native Bun binary named `opencode` (`~/.opencode/bin/opencode`, brew Cellar). The npm package installs it as `bin/opencode.exe`. Agent and server run in a Worker thread of that process | install.sh, postinstall.mjs, tui.ts |
| Desktop process | `/Applications/OpenCode.app/Contents/MacOS/OpenCode`, bundle id `ai.opencode.desktop` (beta `.beta`, dev `.dev`), helper id `ai.opencode.desktop.helper`. Server is a utility helper, `--type=utility --utility-sub-type=node.mojom.NodeService`, listening on a random 127.0.0.1 port with a random password | Info.plist read, server.ts, index.ts, issue 48020 |
| Process to session | No id in argv except `-s/--session` on resume. Otherwise cwd to `session.directory` in the DB. TUI has no socket unless `--port`. Desktop server password is unreachable | tui.ts, cli docs, sql.ts |
| Store | SQLite (WAL) `~/.local/share/opencode/opencode.db`, shared by CLI and desktop. Tables `session`, `message`, `part`, `todo`. Not a promised path (docs describe the old JSON layout), so `documented: false` | database.ts, global.ts |
| Turn in progress | Session status `busy`/`retry`/`idle` (`session.status`, `GET /session/status?directory=`). Reachable only on a server you can connect to. From outside a plain TUI: bash child processes (noisy) and CPU | status.ts, run-state.ts, server docs |
| Waiting on human | `permission.asked` / `question.asked` events, `GET /permission`, `GET /question`. Status stays `busy` meanwhile | permission/index.ts, question/index.ts |
| Hooks | JS/TS plugins in `~/.config/opencode/plugins/`, `.opencode/plugins/`, or the `plugin` array in `opencode.json`. `event` hook sees every bus event | plugins docs, plugin/src/index.ts |
| OpenTelemetry | Yes, undocumented: `OTEL_EXPORTER_OTLP_ENDPOINT` gives OTLP/HTTP traces and logs, no metrics. `experimental.openTelemetry` adds AI SDK spans | otlp.ts, flag.ts, config.ts |

## Could not determine

- Real `ps` output for any surface. The `opencode` vs `opencode.exe` name on macOS for an npm install is from postinstall source, not observed.
- The exact helper name of the desktop server process on macOS (`OpenCode Helper` or `OpenCode Helper (Plugin)`). The row matches the shared path prefix plus the sub-type argument, which the opencode issue tracker and an Electron PR show. Beta and dev app names contain a space (`OpenCode Beta.app`), which the probe's space-splitting cannot match by path.
- CPU floor for `tree_cpu` (5 percent is a guess) and whether the TUI spinner costs measurable CPU.
- Whether the packaged Bun binaries include the OTLP exporter code path. Source says yes (dynamic imports), unverified. GUI apps do not inherit shell env, so enabling OTel for the desktop app is untested.
- Whether `ps eww` can read the desktop sidecar's environment. Not tried.
- Whether `session.status` for one directory is visible from `/global/event` for all directories (it is a global stream; I did not trace per-instance scoping beyond the `?directory=` routing).
- The `-wal` write cadence in practice. Source says text deltas are not persisted, so a long model stream is quiet on disk.

## Contradicts common belief, the hint, or the docs

- The docs' Storage section still says sessions are JSON under `project/<slug>/storage/`. The source stores them in SQLite (`opencode.db`). Do not glob for JSON.
- The desktop app is Electron now, not Tauri, and its docs page still says the app runs an `opencode-cli` sidecar. The prod bundle has no CLI at all: the server is an Electron utility process. The main app process has only Chromium helpers as children, so `tool_children` on it is always true. The row matches the helper instead.
- The server docs say the TUI "randomly assigns a port". It does not listen at all unless `--port`, `--hostname` or `--mdns` is given.
- `busy` does not mean working. A pending permission or question leaves status `busy`. Only the `*.asked` events reveal the human wait.
- `session.idle` is marked deprecated in the source, but it is still the event the docs' notification example uses. Use `session.status`.
- OpenTelemetry exists but no official doc mentions it. Only the source and `experimental.openTelemetry` in the config schema show it.
- No power assertion or `caffeinate` anywhere, unlike Claude Code. There is no cheap OS-level busy signal.
- Terminal title is `OpenCode` or `OC | <title>`: static, not a spinner.
- `opencode` is not a Node process even from npm: postinstall hard-links a native binary as `bin/opencode.exe`. A `node`-name filter would miss it, and an `opencode`-only name filter would miss `opencode.exe`.
- A second, unreleased CLI (`lildax`, `@opencode-ai/cli`, with a background service and `server.json`) is in the repo. npm has only `0.0.0-*` prereleases. Not in the row; revisit when it ships. The desktop app can already use it behind `OPENCODE_SIDECAR_V2=1` in dev builds.
- `args_contain` is a substring test, so the `serve`, `web`, `run`, `acp` surfaces also match a project path containing those strings.

## Verification

Adversarial re-check on 2026-09-29. Validator: `ok`. Method: re-fetched every URL, downloaded the v1.18.33 and v2.0.19 source tags and both desktop zips to the scratchpad (read with `unzip -p`, `plutil`, `grep` only; nothing mounted, installed or run), re-ran the local commands, and pushed made-up ps lines through the probe's `matches()`. The v1.18.33 tag and the `dev` branch tarball are byte-identical for the 15 source files I compared (desktop server/index/builder config, tui.ts, index.ts, database.ts, global.ts, session.ts, permission, question, otlp.ts, app.tsx, plugin index, status.ts, run-state.ts), so those line numbers hold; the rest were read from the tag directly. Confidence stays `documented`: OpenCode is not installed or running here (`which -a opencode` printed "opencode not found", `ps` empty, no `/Applications/OpenCode.app`, no `~/.local/share/opencode`), so nothing was classified live.

### Verdict

The draft was right about v1 and blind to v2. It called the successor CLI unreleased; `@opencode/cli` 2.0.19 was published to npm on 2026-09-29 and the docs carry a "v2 is now available" banner. v2 changes the process shape enough that the draft's working signals are wrong for it. The row now covers both lines and says which parts of v2 are unverified.

### Confirmed

- v1 release 1.18.33 (npm `opencode-ai` latest, published 2026-09-28), repo `anomalyco/opencode`, default branch `dev`, MIT.
- Install layout: `opencode.ai/install` line 68 `INSTALL_DIR=$HOME/.opencode/bin`, line 350 `cp ... "${INSTALL_DIR}/opencode"`; `postinstall.mjs` targets `bin/opencode.exe`, hard-links via `copyBinary`; npm `bin` is `{opencode: bin/opencode.exe}`; cask `opencode-desktop` installs `/Applications/OpenCode.app`; formula `opencode` exists in homebrew/core.
- v1 desktop bundle: `ai.opencode.desktop`, executable `OpenCode`, URL scheme `opencode`, version 1.18.33, four Helper apps, zero `opencode-cli` entries in the zip.
- Channel ids `ai.opencode.desktop[.beta|.dev]` and product names in `electron-builder.config.ts`.
- v1 desktop server is a single `utilityProcess.fork` with `serviceName: 'opencode server'`, loopback, `socket.listen(0, ...)`, `randomUUID()` password, default sidecar v1 unless `OPENCODE_SIDECAR_V2=1`, bundled CLI only when channel is dev.
- Electron PR 50278 shows a macOS ps line for `--type=utility --utility-sub-type=node.mojom.NodeService`; issue 48020 quotes the same flags (Linux, see below).
- v1 TUI is one process with a Bun `Worker`, `external = hasArg('--port') || hasArg('--hostname') || network.mdns === true`, in-process fetch to `http://opencode.internal`; the server docs' "randomly assigns a port" is contradicted by that source.
- CLI docs flag table: `--continue -c`, `--session -s`; `opencode db path` documented; troubleshooting page still documents the old JSON `project/<slug>/storage/` layout.
- `SessionTable` columns `id`, `project_id`, `parent_id`, `directory`, `title`, `time_created`, `time_updated` (via `Timestamps`), `time_archived`; ids start `ses_`.
- SQLite WAL, `synchronous = NORMAL`; XDG data dir `~/.local/share/opencode`; desktop sets only `OPENCODE_CLIENT=desktop` and `XDG_STATE_HOME`, so it does not move the data dir.
- Text deltas are not persisted: `updatePartDelta` only publishes; `PartUpdated` is defined with the persisted `...options`, `PartDelta` is not.
- Status `idle | retry | busy`, `onBusy` sets busy, `session.idle` marked deprecated, `directory` query or `x-opencode-directory` header routing.
- Permission and question requests await a `Deferred` with no status change; TUI notifications subscribe to `permission.asked`, `question.asked` and `session.status` separately; routes `/permission` and `/question` exist.
- Plugin docs: dirs, `plugin` array, event list including `session.idle`, `permission.asked`, `permission.replied`, `todo.updated`, `server.connected`; `question.asked` is absent from the docs list (source-only, as the row says). Hook interface in `packages/plugin/src/index.ts`.
- Env exports `AGENT=1`, `OPENCODE=1`, `OPENCODE_PID`; desktop `OPENCODE_CLIENT=desktop`; VS Code extension `OPENCODE_CALLER=vscode`, `_EXTENSION_OPENCODE_PORT`, runs `opencode --port <n>`.
- No power assertion tied to a turn in v1 (grep empty).
- Terminal title `OpenCode` / `OC | <title>`, disabled by `OPENCODE_DISABLE_TERMINAL_TITLE`.
- OTLP: `flag.ts` reads both env vars, `otlp.ts` posts to `/v1/logs` and `/v1/traces` with `serviceName: 'opencode'`, `experimental.openTelemetry` in config, `experimental_telemetry` in `llm.ts`; no mention in `packages/web/src/content/docs`.
- Local absence claim (re-run, same output).

### Corrected

- "Current release is 1.18.33": true for v1 only. v2 is 2.0.19 (`@opencode/cli`). Row source rewritten; brew formula lags at 1.18.30.
- "lildax is unreleased, npm only 0.0.0-*": wrong in effect. The dev branch still names the package `@opencode-ai/cli` (bin `lildax`), but the release is `@opencode/cli` from branch `2.0` / tag `v2.0.19`, bins `opencode` and `opencode2`.
- Helper bundle ids: only the plain helper is `ai.opencode.desktop.helper`; the others are `.helper.Plugin`, `.helper.GPU`, `.helper.Renderer`.
- DB channels: `latest`, `beta`, `prod` map to `opencode.db` (the draft wrote "stable", not a channel name). A dev-channel build uses `opencode-dev.db`, so "all processes share one database" holds for the release channels only.
- `GET /session/status` does not return `idle` per session. Idle sessions are deleted from the map and are simply absent. The note "returns busy|retry|idle per session" was wrong.
- gui surface and the "desktop runs the server in a utility helper" claim are v1 only. The 2.x desktop (same bundle id, checked in the 2.0.19 zip) has no utility helper; it stages `opencode-cli` under `~/Library/Application Support/<app>/cli/<version>/` and runs `serve --service`. The row would have missed every v2 desktop user; a daemon surface was added.
- The v2 TUI matches the tui surface but is a thin client of a detached shared service, so `tree_cpu` and `tool_children` on it read idle. Signal texts and labels now say so.
- TUI `exclude_args` gained `providers`, `generate`, `console`, `completion` (v1) and `api`, `pair`, `reload`, `service` (v2), all verified command names; `mini` deliberately not excluded because it is an interactive agent UI.
- Power-assertion claim widened: v2 desktop has a user-toggled keep-screen-active `powerSaveBlocker`, not tied to a turn.
- Issue 48020 is a Linux Flatpak report, not macOS. It supports the flag spelling only. OpenCode's fork call passes no `allowLoadingUnsignedLibraries`, so the macOS helper should be plain `OpenCode Helper`; the row matches the shared prefix, so either name works.
- The `run` label said "existing means working" as if encoded; no signal encodes it. Reworded as inferred.

### Unsupported or still unverified

- CPU floor of 5 percent and the TUI spinner cost: inferred, never measured.
- The v2 desktop service surface (`path_contains /Library/Application` plus args `opencode-cli` and `--service`): derived from source and a synthetic ps line only. The `Application Support` space defeats the probe's name match, so this is a workaround. userData name (`<app>`) not read from a running app.
- v2 HTTP signals (`GET /api/session/active`, `GET /api/permission/request`, `service.json` contents): read from `openapi.json` and handler source, not exercised. The password in `service.json` was never read (no service exists here).
- v2 plugin hooks, event names, OTLP payload, and whether v1 tables coexist with `session_v2` after an upgrade: not checked. The `hooks` and `telemetry` fields describe v1.
- Whether the npm v2 install leaves the process named `opencode`/`opencode.exe` (postinstall hard-link, same as v1) or launches through `bin/opencode.cjs` with a cached `.opencode`: launcher source read, no install performed.
- `opencode.ai/v2` docs and download links still name 2.0.6 while npm and the tag are at 2.0.19; the 2.0.19 desktop and CLI zips exist at `opencode.ai/files/bin/2.0.19/`.

### Process pattern false positives and misses (probe, made-up ps lines)

- Same-name product: the archived Go project `opencode-ai/opencode` (now Crush) ships a binary named `opencode`, installs to the same `$HOME/.opencode/bin`, and also comes via `brew install opencode-ai/tap/opencode` and `go install`. `opencode -d` and `opencode -c <dir>` lines match the tui surface. Not fixable from ps: no exclude flag is unique (`-c` collides with v1 `--continue`). Recorded in notes and sources.
- Word collisions: `opencode --prompt run the tests` lands on the run surface, `opencode --prompt fix serve bug` on the serve daemon, `opencode run --dir /Users/me/web-app x` on the web daemon first. Cause is the probe's space split plus exact-word `exclude_args`. Recorded, not fixable in the row.
- Desktop: main process and GPU/Renderer helpers do not match; plain and `(Plugin)` NodeService helpers match the gui surface; beta and dev apps (space in the name) do not.
- Unrelated Application Support processes with `serve --service` args but without `opencode-cli` do not match the new v2 desktop surface.
