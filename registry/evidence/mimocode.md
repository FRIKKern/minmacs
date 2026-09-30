# mimocode (MiMo Code, Xiaomi)

Research date 2026-09-30. MiMo Code is not installed on this Mac and nothing was running, so nothing was run and no live process was classified. Row: `registry/agents/mimocode.json`, validator `ok`, confidence `documented`. Version researched: repo HEAD 698f0f2 (2026-09-30, CLI 0.1.15); latest GitHub release v0.1.14 (2026-09-23); npm `@mimo-ai/cli` 0.1.15.

## What I checked

- Cloned `XiaomiMiMo/MiMo-Code` (depth 1) to the scratchpad and read it: `install`, `packages/cli/bin/mimo`, `script/build.ts`, `script/postinstall.mjs`, `src/index.ts`, `src/global`, `packages/shared/src/global.ts`, `src/storage/db.ts`, `src/session/{session.sql,status,run-state,claude-import,external-import.sql}.ts`, `src/cli/cmd/{tui/thread,tui/worker,tui/attach,run,serve}.ts`, `src/server/{server,auth,middleware}.ts`, `src/llm-server/tokens.ts`, `src/tool/bash.ts`, `src/shell/shell.ts`, `src/permission`, `src/question`, `src/config/{paths,plugin,config}.ts`, `src/effect/observability.ts`, `src/flag/flag.ts`, `packages/plugin/src/index.ts`, `src/installation/index.ts`, TUI visual mode.
- Docs at https://mimo.xiaomi.com/mimocode/ : install, sessions, troubleshooting, cli-subcommands, env-vars, config-files (fetched as HTML, text only).
- GitHub releases API, npm registry metadata for `@mimo-ai/cli`, unpkg `xdg-basedir@5.1.0/index.js`.
- Desktop: docs page https://mimo.mi.com/docs/en-US/updates/feature/desktop and a HEAD request on the public DMG URL. Nothing downloaded.
- Local: `which -a mimo`, `pgrep -x mimo`, `ls` of `~/.mimocode`, `~/.local/share|state|cache/mimocode`, `~/.config/mimocode`, `~/Library/Application Support/mimocode`, `/Applications`. All empty.
- Matching: ran 16 made-up argv vectors through `tools/agents_probe.py` `matches()` against every row. `mimo`, `~/.mimocode/bin/mimo`, npm `.../@mimo-ai/cli/bin/.mimocode` and the platform-package `mimo` are a TUI; `run`, `serve`, `acp` land on their own surfaces; `attach`, `--version`, `upgrade`, `mcp list`, the npm Node shim and `zsh -c` match nothing; `opencode` still lands on the `opencode` row.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Process | Bun-compiled native binary, name `mimo`. curl: `~/.mimocode/bin/mimo`. npm: Node shim `bin/mimo` (argv[0] `node`, never matched) spawns `<pkg>/bin/.mimocode` (a hard link of the platform binary); platform package `@mimo-ai/mimocode-darwin-arm64/bin/mimo` | install, bin/mimo, postinstall.mjs |
| Bundle ids | none for the CLI. Desktop app: not determined | closed source |
| Surfaces | TUI, `run` (one-shot), `serve` (headless server), `acp` (stdio for editors), `attach` (thin client, excluded), Desktop beta (no matcher) | README, source |
| Process to session | `--session`/`-s <id>`; `--continue`/`-c` carries no id. Otherwise cwd to `session.directory` in the DB (`parent_id IS NULL`, newest `time_updated`) | thread.ts, session.sql.ts |
| Store | SQLite (WAL) `~/.local/share/mimocode/mimocode.db`, shared by all processes. Tables `session`, `message`, `part` (JSON `data` columns). Non-stable channels `mimocode-<channel>.db`, override `MIMOCODE_DB`. Path is not promised by docs, so `documented: false`. Key names only from source; no store exists here to read | db.ts |
| Turn in progress | Exact: in-process `session.status` = `busy`, or a `session.pre` to `session.post` bracket in a plugin. From outside a plain TUI: a direct shell child (raises only) and CPU (weak) | status.ts, bash.ts, plugin/src/index.ts |
| Waiting on human | `permission.asked` and `question.asked` events; `GET /permission`, `GET /question` on an open `serve`. Status stays `busy` meanwhile | permission/index.ts, question/index.ts |
| Hooks | JS/TS plugins only (`plugins/*.{ts,js}` in `~/.config/mimocode/`, any `.mimocode/`, `$MIMOCODE_CONFIG_DIR`, or the `plugin` array in `mimocode.jsonc`) | config/plugin.ts, paths.ts |
| OpenTelemetry | Yes, undocumented: `OTEL_EXPORTER_OTLP_ENDPOINT`, OTLP/HTTP traces and logs, no metrics, resource still `service.name=opencode` | observability.ts |

## Could not determine

- Real `ps` output for any surface. The claim that argv[0] stays `mimo` (no retitle) rests on a grep for `process.title` finding nothing and on Bun compiled binaries keeping the launch argv.
- The Desktop app: bundle id, executable and helper names, whether its engine is a `mimo` child or in-process (a source comment says in-process), and whether it writes to the same `mimocode.db`. It is a 368 MB DMG (HTTP 200, `Last-Modified` 2026-09-29) and I did not download or open it. Source is private.
- Idle CPU of a vivid-mode TUI, and the working CPU. The 10 percent floor is a guess.
- Whether `zsh -c '<one command>'` execs in place (then the direct child is the command, not a shell).
- The live shape of the SQLite file, and whether `time_updated` moves during a long model stream (in OpenCode, text deltas are not written until the part completes).
- Whether the Homebrew, Scoop or Chocolatey channels ship yet: the source has them commented out (`TODO(mimocode): uncomment when mimocode is published`).

## Contradicts common belief, the hint, or the docs

- README says macOS data lives in `~/Library/Application Support/mimocode/`. It does not: `xdg-basedir` 5.1.0 uses `~/.local/share` on every OS, and the troubleshooting docs agree. The hint (`~/.local/share/mimocode`) is right; the README paragraph is wrong.
- The docs' Storage section still describes JSON under `project/<slug>/storage/` (OpenCode's old layout). The source stores sessions in SQLite `mimocode.db`.
- Unlike OpenCode v1, every MiMo TUI opens a loopback HTTP listener and advertises its pid and port. That does not make it observable: the password is generated per process and kept out of the environment, so a plain TUI's status API is unreachable. Only `mimo serve` or `--port` with no `MIMOCODE_SERVER_PASSWORD` is open (unauthenticated).
- `busy` does not mean working: a pending permission or question leaves the status `busy`.
- No sleep inhibitor (no `caffeinate`, no IOKit assertion), unlike Claude Code, Codex and Grok Build.
- No shell-command hooks like Claude Code's. A bundled skill's reference text contains Claude Code hook JSON; it is a reference for the `claude-code` skill, not MiMo config.
- MiMo copies other tools' sessions into its own DB at startup (Claude Code from `~/.claude/projects`, Codex, OpenCode; table `external_import`, off with `MIMOCODE_DISABLE_CLAUDE_IMPORT`). The store holds conversations that were never MiMo turns, and a reader of `time_updated` can see import writes.
- OpenTelemetry exists but no doc mentions it, and the exported service name was not renamed from `opencode`.
- Terminal title is static (`MiMoCode` or `MC | <title>`, and `OC | <id>` on plugin routes), not a spinner.
- The MiMo name covers other products: "Xiaomi MiMo Desktop", "MiMo Claw", the API platform, and `mimo` models used inside Cursor, Cline and Zed. Only the CLI binary and the desktop app are this harness.
- `exclude_args` is exact and `args_contain` is a substring test, so a project path or prompt word equal to or containing `run`, `serve`, `acp` or another subcommand changes the surface (registry README section 3, case 16).
- Scope note: this pass covers MiMo Code only. Grok Bot, which the requester also named, is not part of this task.

## Verification

Independent refutation pass, 2026-09-30. Re-read the repo at the same clone (HEAD 698f0f2, `git log -1` confirmed, remote XiaomiMiMo/MiMo-Code), re-fetched the docs pages, npm and GitHub release metadata, and ran `tools/agents_probe.py` `matches()` over 32 made-up argv vectors (no live process; MiMo Code is still not installed: `which -a mimo` printed "mimo not found", `pgrep -x mimo` empty, `~/.mimocode` and `~/.local/share/mimocode` absent). Confidence stays `documented`; nothing was seen live. `tools/validate_row.py` prints `ok` before and after.

### Claims

| Claim | Result | Note |
|---|---|---|
| Fork of OpenCode; binary `mimo`; curl, npm, PowerShell installs | confirmed | README lines 50-51 (npm), 551-553 (fork); docs install page shows the curl and PowerShell lines |
| curl install to `~/.mimocode/bin/mimo`; updater treats `.mimocode/bin` and `.local/bin` as curl | confirmed | `install` line 68; `installation/index.ts` lines 207-208 |
| npm `@mimo-ai/cli` bin `mimo` is a Node shim that spawnSyncs `bin/.mimocode`, falling back to `@mimo-ai/mimocode-<os>-<arch>/bin/mimo`; postinstall hard-links | confirmed | `bin/mimo`, `script/postinstall.mjs` read; registry printed 0.1.15 and `{'mimo': 'bin/mimo'}`. The Node shim (argv[0] `node`) is the parent and never matches; the child's argv[0] is the target path, so the path rules are right |
| Release v0.1.14 darwin assets | confirmed | API printed v0.1.14, 2026-09-23, darwin-arm64.zip, darwin-x64.zip, darwin-x64-baseline.zip |
| Bun compile to `dist/<target>/bin/mimo`; nothing sets `process.title` | confirmed | `build.ts` line 236; grep for `process.title` finds nothing (only `renderer.setTerminalTitle`). Not seen live, so "ps shows launch argv" stays source-only |
| TUI agent is a Worker thread in the same process; loopback listener with generated password kept out of the environment | confirmed | `thread.ts` line 271 (`new Worker`), lines 338-350; `worker.ts` line 98; `flag.ts` lines 289-295 |
| Listener is advertised by "pid and port only" | corrected | the address file holds pid, hostname, port, url, started (`tokens.ts` type `Address`); still no credential. Row label fixed |
| Data root `~/.local/share/mimocode`, state, config; `MIMOCODE_HOME` | confirmed | `shared/src/global.ts`; troubleshooting page says `~/.local/share/mimocode/`; env-vars page describes `MIMOCODE_HOME`. README line 422 (Application Support) is the wrong one, as stated |
| Docs Storage section is stale (JSON under project/<slug>/storage/) | confirmed | troubleshooting page still says so; source uses SQLite |
| One shared `mimocode.db` (WAL), tables session/message/part, JSON data columns, `MIMOCODE_DB` override | confirmed | `db.ts`, `session.sql.ts` (`time_created`/`time_updated` come from the shared `Timestamps` object) |
| "Non-stable channels use `mimocode-<channel>.db`" | corrected | `MIMOCODE_DISABLE_CHANNEL_DB` defaults to true (`flag.ts` line 419, env-vars page), so a plain install always uses `mimocode.db`; per-channel files only with it set false. Row source and notes fixed. The glob `mimocode*.db` still covers both |
| MiMo imports Claude Code, Codex and OpenCode sessions at startup | corrected | startup calls only `ClaudeImport.run()` (`index.ts` line 166). Codex and OpenCode import only through `POST /global/import/run` (`server/routes/global.ts`); no startup caller of `runAll`. Row source and notes fixed. Claude import off with `MIMOCODE_DISABLE_CLAUDE_IMPORT` confirmed |
| Resume flags `--session/-s`, `--continue/-c`, `--fork`; `mimo session list`, `mimo export` | confirmed | docs sessions page; `thread.ts` and `run.ts` both define `-s` and `-c` |
| Status idle/busy/retry/notice in memory, served by `GET /session/status`; permission requests do not touch it | confirmed | `status.ts`; `routes/instance/session.ts` `/status`; grep of `permission/index.ts` and `question/index.ts` for status writes prints nothing; the only writers are `run-state.ts`, `processor.ts` and `prompt.ts` |
| Bash tool spawns a detached child via the shell, `/bin/zsh` fallback on macOS | confirmed | `bash.ts` lines 447-453, `shell.ts` line 89. Detail: it uses `$SHELL` unless it is on a blacklist, then the fallback. Both are in the probe's shell set except exotic shells |
| No sleep inhibitor | confirmed | the grep prints nothing |
| Vivid default with animated background; static terminal title | confirmed | `visual.ts`, `starry-background.tsx` (three `setInterval`), `app.tsx` lines 344-361 |
| 15 plugin hook names; plugin dirs and `plugin` array; `--pure` | confirmed | all 15 keys found in `packages/plugin/src/index.ts`; `config/plugin.ts` glob `{plugin,plugins}/*.{ts,js}`; `paths.ts` `.mimocode` and `MIMOCODE_CONFIG_DIR`. `session.post` on failure and interruption confirmed by the comment at line 559 |
| `permission.asked`, `question.asked`, question tool on for cli/app/desktop | confirmed | `permission/index.ts`, `question/index.ts`, `tool/registry.ts` lines 213-214 |
| Skip-permissions flags, 60 s forced-ask auto-reject, `--never-ask` | confirmed | `flag.ts` line 133, `permission/index.ts` line 24, bundled permissions doc |
| `mimo serve` refuses non-loopback bind without password; unsecured warning | confirmed | `serve.ts`, `server.ts` lines 115-121 |
| `mimo web` commented out | confirmed | `index.ts` lines 203-204 |
| OTLP via `OTEL_EXPORTER_OTLP_ENDPOINT`, traces and logs, `service.name=opencode`; docs list no OTEL variable | confirmed | `observability.ts`; env-vars page has no OTEL entry. Added: the page does list `MIMOCODE_ENABLE_ANALYSIS` (default on), a separate first-party analytics switch |
| Desktop app: closed, invite beta, v0.1.0 of 2026-09-01, MiMo Code as core engine | confirmed | changelog page says V0.1.0 (2026-09-01); README lines 21-27 (invitation, "core engine"); DMG HEAD returned 200, 368442523 bytes, Last-Modified 29 Sep 2026. Bundle id and process shape remain unknown, so no matcher, correctly |
| Nothing installed or running here | confirmed | re-ran the commands above |
| `tree_cpu` floor 10 percent | unsupported | a guess by the row's own admission, never measured. Kept as a weak fallback; needs a live idle and working sample |
| `tool_children` shell child raises working | unsupported live | source-only; `zsh -c 'one command'` may exec in place and MCP or language servers are permanent non-shell children. Consistent with registry README cases 8 and 9 |

### Process patterns

| Pattern | Result |
|---|---|
| Name `mimo` alone | Kept. No other registry row uses `mimo` or a `mimocode` path (grep of all rows). An unrelated program named `mimo` on PATH would be filed as an idle TUI; none known. This is the weakest rule and it is the only rule that catches a `mimo` copied to an unlisted directory (for example `MIMOCODE_BIN_PATH` pointing elsewhere), which is inferred, not observed |
| Path rules `/.mimocode/bin/mimo`, `/@mimo-ai/cli/bin/.mimocode`, `/@mimo-ai/mimocode-` | Confirmed specific: they only occur in this product's install locations, including pnpm and bun layouts (`.../node_modules/@mimo-ai/mimocode-darwin-arm64/bin/mimo` scores 20). The npm Node shim and `zsh -c` match nothing |
| Subcommand exclusion | Repaired. Before: `mimo llm-server list` matched the serve daemon surface (the word `llm-server` contains `serve`), and `mimo acp --cwd <path containing serve>` tied between acp and serve, which the earlier surface (daemon) wins in `agents_probe.py`. Fix: the run, serve and acp surfaces now carry the TUI's full subcommand list minus their own word; `github` is left off the run surface on purpose so the CI `mimo github run` agent, alive while working, still counts. After: llm-server, mcp, db, pr and session vectors match nothing, acp resolves to ide only, `mimo run "fix it"` and `mimo serve --port 4096` still match their own surfaces |
| Substring surfaces `run`, `serve`, `acp` | Unchanged, cannot be fixed with this schema: a prompt or path merely containing the word still changes the surface (`~/runner` files as one-shot, `~/observer` as the serve daemon; both reproduced). Recorded in notes as a known error, same as registry README case 16 |
| `mimo pr <n>` | Its own process matches nothing; it spawns `mimo` as a child (`pr.ts` line 127) which matches as a normal TUI |
