# Kilo CLI: evidence notes (2026-09-29)

Row: `registry/agents/kilo.json`. Validator: `ok`. Confidence `documented`. Kilo is not installed here and nothing was running, so no surface was classified live. Version researched: `@kilocode/cli` 7.8.1 (npm `latest`), repo `Kilo-Org/kilocode`, branch `main`, commit `88681ca` (2026-09-29).

## What I checked

- Docs (kilo.ai, read from `packages/kilo-docs/pages` in the repo, the four key URLs returned 200): CLI page, CLI reference, Keep Awake, Session history, Plugins, JetBrains architecture.
- Public source, from a sparse blobless clone in the scratchpad (not built, not run): `packages/opencode` (`bin/kilo`, `script/postinstall.mjs`, `src/cli/cmd/{tui,serve,run,daemon}.ts`, `src/kilocode/daemon/*`, `src/kilocode/cli/cmd/tui/*`, `src/tool/shell.ts`, `src/session/status.ts`, `src/server/routes/...`), `packages/core` (`global.ts`, `database`, `session/sql.ts`, `kilocode/caffeination.ts`, `observability/otlp.ts`, `flag/flag.ts`), `packages/kilo-telemetry`, `packages/sdk` (event types), `install`.
- npm registry metadata for `@kilocode/cli` and `@kilocode/cli-darwin-arm64`. GitHub release assets for v7.8.1. Homebrew API (`kilo`, `kilocode`, `kilo-code`: 404 for formula and cask).
- Herdr docs (agents and integrations pages) as an independent third-party view.
- Prior repo research: the `vscode-agents` row already covers the VS Code extension's `kilo serve`; I did not repeat it and made this row not match it.
- Local, read-only: `which`, `ls`, `ps`, `ls ~/.vscode/extensions`, `ls /Applications`. All empty (exact output in the row's sources). Matching was tested with made-up ps lines through `tools/agents_probe.py` `matches()`.

## Process shape (the part most likely to go wrong)

```
npm install -g @kilocode/cli
  node <prefix>/lib/node_modules/@kilocode/cli/bin/kilo      argv[0] = node   (launcher, NOT matched)
    `- <prefix>/.../@kilocode/cli/bin/.kilo                   native Bun binary, direct child  (matched)
       or node_modules/@kilocode/cli-darwin-arm64/bin/kilo    when install scripts were skipped
curl https://kilo.ai/cli/install | bash
  ~/.kilo/bin/kilo                                            native binary, no launcher

TUI, no daemon:   one process; agent + HTTP server in a Worker THREAD; no listening port
TUI, daemon up:   TUI = thin client  --HTTP-->  <binary> serve --hostname 127.0.0.1 --port 4097..4116 (detached)
kilo run:         one process for one prompt
VS Code / JetBrains:  editor -> <ext or IDE cache>/bin/kilo serve --port 0
```

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | TUI, `run` (one-shot), `attach` (TUI client), `serve`, `daemon`, `acp` (stdio, editors), VS Code extension, JetBrains plugin, cloud agent. No desktop app | docs, source, release assets |
| Executable | `kilo` and `kilocode` bins. On macOS the running file is `<pkg>/bin/.kilo` (npm, hard-linked by postinstall), `.../@kilocode/cli-darwin-*/bin/kilo`, or `~/.kilo/bin/kilo` | bin/kilo, postinstall.mjs, install |
| Bundle id | None. No .app, .dmg or .pkg is released | GitHub release assets |
| Process to session | No id in argv except `-s/--session` (TUI, run, attach). `-c/--continue` has no id. Otherwise cwd to `session.directory` in the DB. A plain TUI has no socket | tui.ts, cli-reference |
| Store | SQLite WAL `~/.local/share/kilo/kilo.db`, shared by every surface. Tables `session`, `message`, `part`. Path is documented, `kilo db path` prints it | session-history.md, global.ts, sql.ts |
| Turn in progress | `GET /session/status` (busy or retry), or SSE `session.turn.open`/`close`. Only on a server you can reach and authenticate to. From outside a plain TUI: shell child, CPU, and `caffeinate` if the user enabled Keep Awake | status.ts, session.ts, types.gen.ts |
| Waiting on human | `GET /permission`, `GET /question`; plugin events `permission.asked`/`question.asked`; OSC 777 `waiting` if `KILO_TERMINAL_ACTIVITY=1`; title glyph only if `title_icon` is set | source, docs |
| Hooks | TS/JS plugins only (`~/.config/kilo/plugin/`, `.kilo/plugin/`, `plugin` array). No shell hooks | plugins docs |
| OpenTelemetry | Yes: `OTEL_EXPORTER_OTLP_ENDPOINT`, traces and logs over HTTP | otlp.ts, cli docs |

## Could not determine

- Any real `ps` line. The `.kilo` dotfile name comes from postinstall source; nothing was run. The tarball for `@kilocode/cli-darwin-arm64` was not downloaded (listing it would have been fine but I stayed clear of anything that looks like installing), so the layout of `bin/` inside it is from the launcher and postinstall code, not from the archive.
- Whether Bun-compiled binaries show `argv[0]` as the invoked path in `ps` on macOS. Assumed yes, as the `opencode` row does.
- The macOS path where the JetBrains plugin extracts the binary. The docs say `<PathManager.getSystemPath()>/kilo/bin/kilo`; `~/Library/Caches/JetBrains/<product><version>/` is my reading of that, and the row's `/kilo/bin/kilo` substring rests on it.
- CPU floor (5 percent is copied from the `opencode` row, a guess). Whether the TUI's render loop costs measurable CPU during a turn.
- Whether text deltas are written to `kilo.db` while streaming. Assumed not (opencode lineage), not checked in this fork, so I did not add a transcript signal.
- Whether Keep Awake survives a restart. The source starts `enabled` at false in the TUI component and stores only the confirmation dialog answer, so I say it does not, "as far as the source shows".
- `kilo remote` and `kilo cloud`: not read. Both are excluded from the TUI surface by name.
- Whether `session.status` `scheduled` and `offline` matter in practice. `offline` counts as attention in the TUI.
- The HTTP status API was read in source only. Never called.

## Contradicts common belief, the hint, or the docs

- **The executable is not named `kilo` on an npm install.** Postinstall hard-links it to `.kilo`. A name filter on `kilo` misses the common case and matches an unrelated text editor and the VS Code extension's server. The row matches by path for that reason.
- **Two processes for one npm session.** A `node .../bin/kilo` launcher parents the native binary. Only the child does agent work. Matching `node` scripts would double count.
- **The hint says "serve mode" as if one thing.** There are three unrelated `serve` shapes (hand-run, the daemon's detached child, editor-owned child) and a fourth that is not `serve` at all (the TUI's in-process worker). The TUI has no port unless `--port`.
- **`kilo daemon` is opt-in.** `kilo` only attaches to a daemon that already runs. It does not start one. A daemon-attached TUI reads idle while the daemon works.
- **The terminal title is not a status line by default.** It is `Kilo CLI | <title>`. Glyphs appear only when `title_icon` is `unicode` or `emojis` (default `none`).
- **There is a purpose-built terminal activity stream nobody documents.** OSC 777 `kilo;activity;1;<state>;<ms>` with a real `waiting` state, gated on `KILO_TERMINAL_ACTIVITY=1`. Nothing in the checked-out source sets it, and Herdr's docs describe a plugin or screen reading instead (whether Herdr sets it was not checked).
- **`experimental.openTelemetry` is not about OpenTelemetry.** It opts out of PostHog analytics (default true). The docs heading "OpenTelemetry Export" puts the two next to each other. Real OTLP needs `OTEL_EXPORTER_OTLP_ENDPOINT`. In opencode the same key name enables AI SDK spans; in Kilo `llm.ts` hard-codes `experimental_telemetry: {isEnabled: false}`.
- **`busy` does not mean working.** No status is set on a permission ask, so status stays `busy` while the user is being asked. Same as opencode.
- **Keep Awake is per TUI, off by default, and CLI-only for the CLI.** The docs describe it for VS Code and CLI together; in the CLI it is the TUI process that holds `caffeinate -i -w <pid>`, and `run`, `serve` and `daemon` never do. So a missing `caffeinate` child says nothing, unlike Claude Code.
- **Kilo 7 is an opencode fork, not the old Kilo.** The docs still say "version 1.0 and later"; npm `latest` is 7.8.1 and `next` is 1.0.8. The old Roo/Cline-based CLI (0.x, `~/.kilocode/cli/`) is a different program that the code only migrates config from.
- **macOS data lives in `~/.local/share/kilo`,** not `~/Library/Application Support`, because it uses `xdg-basedir`. The docs say so, but the usual macOS habit would look in the wrong place.
- **No Homebrew formula.** Only npm, the curl script and release zips.
- **Loose matching.** `args_contain` is a substring test, so `run`, `serve`, `acp` and `attach` surfaces also match prompts or project paths that contain those strings, and `exclude_args` vetoes on an exact word (a `--prompt run` hides a TUI session).

## Synthetic matcher results (tools/agents_probe.py matches, first matching surface)

Matched as expected: npm cached `.kilo` TUI (bare, `--session`, `-c`), `node_modules/@kilocode/cli-darwin-arm64/bin/kilo` TUI, `~/.kilo/bin/kilo` TUI, `serve --port 0`, daemon child `serve --hostname 127.0.0.1 --port 4097`, JetBrains-style `.../JetBrains/IntelliJIdea2025.2/kilo/bin/kilo serve --port 0` (daemon), `run`, `attach`, `acp`. Not matched, as intended: `kilo --version`, `kilo auth login`, `kilo daemon start`, `kilo db path`, the `node .../bin/kilo` launcher, `<vscode ext>/bin/kilo serve --port 0` (owned by `vscode-agents`), `/usr/local/bin/kilo notes.txt`, `./kilo`, a Claude Code binary. The `../cli-darwin-arm64` spelling in one of my test lines missed only because the test path was built with `..`; a real resolved path matches.

## Verification

Adversarial pass, 2026-09-29. Method: re-ran `tools/validate_row.py` (ok before and after), re-fetched the vendor source at `Kilo-Org/kilocode` main (commit `88681ca`, sparse blobless clone of `packages/opencode`, `packages/core`, `packages/kilo-docs` in the scratchpad, plus raw fetches for `packages/sdk`), re-read the three docs pages on kilo.ai (all HTTP 200), re-queried npm, GitHub release v7.8.1 (`gh api`) and the Homebrew API, re-fetched the Herdr docs, and pushed synthetic `ps` lines through `tools/agents_probe.py` `matches()`. Kilo is not installed here (`which kilo kilocode`: not found), so nothing was seen live: confidence stays `documented`, never higher.

### Corrections made to the row

1. **False positive found and fixed: the background-process guardian.** Kilo starts persistent background processes through `<same native binary> __background-process-runner <token> <payload>` (runner.ts, setup.ts `runner()`, pty-self-command.ts uses `process.execPath`). That line passes the path test and had no veto, so it matched the `run` surface (substring `run` inside `runner`) and would show as a one-shot session. Added `__background-process-runner` to `exclude_args` on all five process surfaces. Synthetic line before: matched `run`; after: matches nothing.
2. **TUI veto list was incomplete.** `generate`, `providers` (alias of `auth`), `plug` (alias of `plugin`) and `worktree` are real top-level commands in 7.8.1 and were missing. Added. Only `generate` and `worktree` are absent from the docs; all four are in `index.ts`, `lazy-commands.ts` or `setup.ts`.
3. **Release assets claim corrected.** The source said the release holds "a JetBrains zip". v7.8.1 has 57 assets: CLI archives, VSIX files, OCI SBOMs, SBOM and checksum files, no JetBrains zip. Claim reworded.
4. **`acp` surface label corrected.** "Zed, JetBrains AI chat and similar" has no support: the docs say only `start ACP (Agent Client Protocol) server`. Label now says which editors launch it, and one child per connection, are inferred.
5. **Streaming-writes note sharpened.** "Not checked" replaced by what the source shows: `updatePartDelta` only publishes a bus event and no projector for `PartDelta` was found. Still inferred, since the grep covered two packages only.
6. **`question.asked`** is in the source bus events but not in the plugin docs' event list. Row now says so.
7. Serve label now records that a bare TUI given a project path containing `serve` (for example `~/observer`) lands on the `serve` surface.

### Claims, one by one

| # | Claim | Result |
|---|---|---|
| 0 | npm `@kilocode/cli` 7.8.1, bins `kilo` and `kilocode`, darwin-arm64/x64/x64-baseline optional deps | confirmed (npm registry: latest 7.8.1, next 1.0.8, alpha 0.0.5, rc 7.8.0; bin and optionalDependencies as stated) |
| 1 | launcher is a node script, spawns native binary as direct child, prefers `<pkg>/bin/.kilo`, else `node_modules/@kilocode/cli-<platform>-<arch>/bin/kilo` | confirmed (`bin/kilo`: `cached = path.join(scriptDir, ".kilo")`, `childProcess.spawn(target, argv.slice(2), {stdio: "inherit"})`, `findBinary`) |
| 2 | postinstall hard-links or copies binary to `bin/.kilo` | confirmed (`postinstall.mjs`: `targetBinary = .../bin/.kilo`, `linkSync` then `copyFileSync`). Note it falls back to a temp `npm install --ignore-scripts` of the platform package if the local copy fails |
| 3 | curl installer to `~/.kilo/bin/kilo`; docs list npm only; no Homebrew formula or cask | confirmed for Homebrew core (formula and cask `kilo`, `kilocode`, `kilo-code`: 404). A third-party tap was not searched |
| 4 | no macOS app bundle, no bundle id | corrected (asset list re-read; JetBrains zip removed from the claim). Absence of a bundle id remains inferred |
| 5 | TUI runs agent and server in a Worker thread, no port unless `--port`/`--hostname`/`--mdns`, attaches to a running daemon first | confirmed (`tui.ts`: `new Worker(...)`, `KiloTuiThreadDaemon.attach(...)` before it; `Daemon.ensure` called only in `daemon.ts` and `console.ts`) |
| 6 | `kilo daemon start` spawns detached `serve --hostname H --port P`, ports 4097-4116, `daemon.json` mode 0600, env `KILOCODE_FEATURE=daemon` | confirmed (`daemon.ts`: PortRange, `args()`, `spawn(... detached: true ...)`, `writeJson(file(), input, 0o600)`) |
| 7 | JetBrains runs extracted `kilo serve --port 0` at `<PathManager.getSystemPath()>/kilo/bin/kilo` | confirmed for the docs text (`jetbrains-plugin.md` lines 38, 66, 74). The macOS expansion of `getSystemPath` stays inferred; the `/kilo/bin/kilo` substring does not depend on it |
| 8 | session status in memory, values idle/busy/retry/offline/scheduled, `GET /session/status`, permission ask does not change it | confirmed (`types.gen.ts` SessionStatus union; `groups/session.ts` `status: ${root}/status`; every `status.set(` site is busy or idle or retry or offline, none on permission) |
| 9 | `session.turn.open` / `session.turn.close` with reasons completed, error, interrupted, superseded | confirmed (`types.gen.ts` EventSessionTurnOpen/Close; `kilocode/session/event.ts` CloseReason) |
| 10 | shell tool spawns `<shell> -c <command>` detached, direct child; macOS default `/bin/zsh` | confirmed (`tool/shell.ts` `ChildProcess.make(command, [], {shell, detached: platform !== "win32"})`; `core/src/shell.ts:134`). `$SHELL` is preferred when acceptable, `/bin/zsh` is the fallback |
| 11 | Keep Awake off by default, TUI-only for CLI, `/usr/bin/caffeinate -i -w <pid>` only while busy/retry/wakeup pending | confirmed (docs: "Keep Awake is off by default", `/caffeinate`; `caffeination.ts:73` `["-i","-w",String(pid)]`, `:105` `/usr/bin/caffeinate`; `caffeination.tsx` `createSignal(false)`, `driver.start(process.pid, ...)`). "Not saved across launches" is source-reading only; only `caffeination_confirmed` is stored |
| 12 | terminal title `Kilo CLI \| <title>`, glyph only with `title_icon` unicode/emojis, default none, `KILO_DISABLE_TERMINAL_TITLE` | confirmed (`APP_TITLE = "Kilo CLI"`, `title-icon.ts Default = "none"`, `flag.ts:50`) |
| 13 | OSC 777 `kilo;activity;1;<state>;<ms>` gated on `KILO_TERMINAL_ACTIVITY=1`, six states, every 5 s | confirmed (`terminal-activity.ts`: `input.enabled !== "1"` returns, `setInterval(send, 5_000)`, state union; `app.tsx:91`) |
| 14 | store `~/.local/share/kilo/kilo.db`, SQLite WAL, `kilo db path`, tables session/message/part | confirmed (session-history.md lines 142-154; `db.ts:35`, `:110`; `sql.ts`: `session.directory`, `time_updated` etc.). Column list in `session_store.note` is a summary, not re-listed here |
| 15 | hooks are code plugins only; dirs and `plugin` array; no shell-command hooks | confirmed for dirs, `KILO_PURE`, event names (18 of 19 checked names appear in the plugin docs; `question.asked` does not, see correction 6). "No `hooks` key anywhere" is an absence claim, not exhaustively re-proved |
| 16 | OTLP via `OTEL_EXPORTER_OTLP_ENDPOINT`, traces and logs over HTTP; `experimental.openTelemetry` is a PostHog opt-out | confirmed for the docs text (`cli.md:503`). The `setup.ts` / `client.ts` half was not re-read in this pass: documented, not re-verified |
| 17 | Herdr: Kilo is a lifecycle-plugin agent, plugin at `~/.config/kilo/plugin/herdr-agent-state.js`, resume `kilo --session <id>`, screen manifest otherwise | confirmed against both herdr.dev pages (integrations table: "Lifecycle authority: ... Kilo Code CLI"; agents table row) |
| 18 | Kilo not installed or running here | confirmed again: `which kilo kilocode` printed `kilo not found`, `kilocode not found` |
| 19 | synthetic matcher results | corrected: two of the "not matched, as intended" list held, but the guardian, `worktree`, `generate`, `providers`, `plug` had been missed. Re-run after repair: TUI, `--session`, `serve`, `run`, `acp`, `attach`, `~/.kilo/bin/kilo`, JetBrains-style `serve` all match the intended surface; guardian, subcommands, `--version`, `daemon start`, `pr`, `mcp`, `remote`, `cloud`, node launcher, VS Code extension `serve`, `/usr/local/bin/kilo x` match nothing |
| notes / working signals | `tree_cpu` floor 5, transcript claims, `attach` and daemon-attached TUI read idle | unsupported as measurement: 5 percent is copied from `opencode` and is a guess; the row already says "Inferred, not measured". Left as is |
| surface `run` label | "alive means working" | unsupported by any source; the row already says inferred |
| surface `acp` label | which editors spawn it | unsupported, relabelled (correction 4) |

### Process pattern audit (false positives)

- The bare name `kilo` is never matched; only path fragments. `/kilo/bin/kilo` needs a directory named exactly `kilo` containing `bin/kilo`; the VS Code extension path `kilocode.kilo-code-<ver>/bin/kilo` does not contain it (tested), so `vscode-agents` keeps it. antirez `kilo` at `/usr/local/bin/kilo` does not match (tested).
- The node launcher has `node` as argv[0], so it never matches.
- The legacy Roo/Cline-based Kilo 0.x CLI is a node script with no `.kilo` file and no `@kilocode/cli-darwin-` path, so it does not match. Not run, from package layout only.
- Remaining looseness, all substring effects and unfixable with the current `args_contain` semantics: a TUI whose argv holds a path or URL containing `serve`, `acp`, `run` or `attach` is filed under that surface first (surfaces are tried in order: serve, acp, run, attach, TUI). Worst case is a wrong surface label; the working signals are the same row-wide, so state is unaffected except `attach`.
- Unverified live: whether a Bun-compiled binary reports its exec path as argv[0] in `ps` on macOS (assumed, as in the `opencode` row), and the exact form of the guardian's `ps` line.
