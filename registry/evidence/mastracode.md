# Mastra Code: evidence notes (2026-09-30)

Row: `registry/agents/mastracode.json`. Validator: ok. Confidence `documented`. Nothing was run: no Mastra Code on this Mac (`which mastracode` and `which mastra` print nothing, no `~/.mastracode`, no `~/Library/Application Support/mastracode`, no matching process, no app bundle). Every claim below is from docs or source.

## What I checked

- Docs at code.mastra.ai: index, configuration (storage, hooks, macOS sleep prevention, env vars, telemetry), headless, terminal-notifications.
- Public source: sparse clone of `github.com/mastra-ai/mastra` at `4ea9e1f` (2026-09-30) into the scratchpad, `mastracode/` plus `packages/core/src/agent-controller`, `workspace/sandbox`, `storage`. Read `tui/src/main.ts`, `tui/src/tui/mastra-tui.ts`, `display.ts`, `notify.ts`, `sdk/src/index.ts`, `utils/thread-lock.ts`, `utils/signals-pubsub.ts`, `utils/project.ts`, `agents/workspace.ts`, and the core run engine.
- The published npm package: `npm view mastracode` (0.43.0, modified today), tarball downloaded to the scratchpad and extracted, not installed. Confirmed the shebang, the bin name, the caffeinate code in `dist/tui-*.js`, and no `process.title`.
- Ran `agents_probe.matches()` on ten synthetic command lines against the row (shim path, `--tui-prompt`, `--prompt`, `-p`, `--acp`, `prune`, real script path, `npm exec`, an unrelated node script under a `mastracode/` folder, Homebrew node). Results as intended, listed under "Match limits".

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | TUI (`mastracode`), headless (`--prompt`, `-p`, or a bare positional prompt), ACP stdio server (`--acp`), `plugin scaffold` and `prune` subcommands. Separate server product: Factory (`mastracode/factory`, `web`, `factory-ui`, `create-factory`), not read in depth | `main.ts`, `mastracode/README.md` |
| Process name | Node script. `#!/usr/bin/env node`, `bin.mastracode = ./dist/cli.js`. No retitle. ps shows `node <prefix>/bin/mastracode` (symlink path, inferred from how shebangs and env work) or `node .../mastracode/dist/cli.js` | npm tarball, grep |
| Bundle ids | None. No `.app`, no cask found | `ls /Applications`, docs install section (npm, pnpm, yarn, bun only) |
| Process to session | Session = thread. Hook `session_id` is the thread id (the vendor's own script joins it to `mastra_threads.id`). Headless takes `--thread <id>` or `-t`. The interactive TUI takes no id flag: it resumes the newest thread for the directory's resource. Lock files with the owner pid exist in code but are off by default in the TUI (see contradictions) | docs terminal-notifications, headless flag table, `sdk/src/index.ts` |
| Store | `~/Library/Application Support/mastracode/mastra.db`, LibSQL (SQLite), all threads of all projects in one file. Tables `mastra_threads` (id, resourceId, title, metadata, createdAt, updatedAt), `mastra_messages`. Moves with `MASTRA_DB_PATH`, `MASTRA_APP_DATA_DIR`, or a Turso/Postgres backend chosen in `/settings`. Also there in the same directory: `mastra-vectors.db`, `observability.duckdb` (opt-in), `locks/`, `settings.json`, credentials | docs storage, `utils/project.ts` |
| Turn in progress | Best: a direct `caffeinate -i -m` child of the node process. Started on `agent_start`, killed on any `agent_end`. Then a direct `/bin/sh -c` child (the shell tool). CPU last | `mastra-tui.ts`, docs macOS sleep prevention |
| Waiting on human | Hook only, exactly: `PermissionRequest` (kind tool_approval, sandbox_access, plan_approval), `Notification` (tool_approval, ask_question, plan_approval, sandbox_access, agent_done), `AgentEnd` with stop_reason `suspended`. No file or process record | docs hooks, `notify.ts`, `display.ts` |
| Hooks | 14 events, `~/.mastracode/hooks.json` then `.mastracode/hooks.json`, JSON on stdin, `/hooks reload`, `MASTRACODE_DISABLE_HOOKS=1` turns them off. Only PreToolUse, Stop, UserPromptSubmit can block | docs |
| OpenTelemetry | No. Mastra's own Observability: local DuckDB exporter (opt-in `/observability local on`) and a Mastra platform exporter. PostHog product analytics with `MASTRA_TELEMETRY_DISABLED=1` | `sdk/src/index.ts`, docs telemetry |

## Contradicts common belief

- The hint says Herdr sees no outside signal without hooks. That is Herdr's limit, not Mastra Code's. On macOS the TUI holds a `caffeinate -i -m` child for exactly one run, per the vendor's docs and source (added in 0.9.2, PR 14586). Same mechanism as `claude-code`. It needs no hook, but it is TUI-only and macOS-only, and `MASTRACODE_DISABLE_CAFFEINATE=1` removes it.
- caffeinate is not a clean working flag in both wait cases. A tool-approval prompt is awaited inside the run, so caffeinate stays (working while waiting, case 4 of the README). An `ask_user`, `submit_plan` or sandbox-access question ends the run as `suspended`, which kills caffeinate, so the TUI reads idle while it is blocked on the human. Derived from reading the run engine and the TUI's handleEvent, not observed.
- Thread lock files (`<appData>/locks/<threadId>.lock` holding a pid) look like a free pid-to-session map, but they are only created when cross-process pubsub is off. The TUI passes `unixSocketPubSub: true` unless `MASTRACODE_DISABLE_UNIX_SOCKET_PUBSUB` is set, and `crossProcessPubSub` then defaults to true, which disables the lock. So by default there are no lock files. Coordination uses sockets `/tmp/mc/<resourceId>/<threadId>.sock` instead.
- Mastra Code is not the `mastra` CLI. `mastra` (packages/cli) is the framework tool; `mastracode` is the coding agent. `mastracode/tui` publishes the package `mastracode`; the runtime lives in the separate `@mastra/code-sdk`.
- The repo layout changed: `mastracode/` is now a set of packages (sdk, tui, factory, web, factory-ui) and the npm package's repository directory is `mastracode/tui`.
- A bare prompt argument (`mastracode "fix it"`) runs headless, not the TUI. `hasHeadlessFlag` counts any positional argument as a prompt.
- The terminal title is `Mastra Code - <thread title or cwd folder>`. It never carries a state, unlike Grok Build.

## Match limits (what the probe test showed)

- Matched: shim path (nvm, Homebrew), real script path, `--tui-prompt`. `--prompt` goes to the headless surface. `--acp` goes to the daemon surface.
- Not matched, deliberately: `-p` (vetoed on the TUI surfaces, no surface can carry it because `args_contain` is a substring test), `prune`, `plugin`, `--help`, `npm exec mastracode`, and a node script in a folder that only contains the word mastracode.
- Wrong on purpose or unavoidable: a positional prompt reads as a TUI session (one-shot, alive means working). Because `exclude_args` is an exact match on any word, a prompt word equal to `plugin` or `prune` hides a real session.
- `bun x mastracode` and `bun add -g` may launch under the `bun` runtime instead of `node`. Not covered: I did not check what Bun does with the shebang.

## Could not determine

- Real `ps` output of a live instance. The shim-path match rests on how `#!/usr/bin/env node` scripts show up, not on a Mastra Code process.
- Whether the `caffeinate` child is visible to `pmset -g assertions` the way the probe's `child_process` signal expects: it is a direct child, so `child_process` applies, but I saw none.
- The gap between `agent_start` and the child appearing, and whether `caffeinate` lingers after `agent_end` (source kills it synchronously, `child.kill()`).
- What holds the `/tmp/mc/<resourceId>/<threadId>.sock` listener when several processes share a thread (broker election in `@mastra/core` `UnixSocketPubSub`, not read). Whether `lsof -U` on a TUI pid reliably names its thread is unverified.
- Whether goals, schedules or GitHub signals start runs with no human present. They go through the same controller, so `agent_start` should fire and caffeinate should show, but I did not confirm it.
- LSP and MCP children: both are spawned by the process, but I did not check that none of them is a shell (they should not be, but a hook command with `shell` would be, and hooks run as short-lived children).
- Factory (`mastra factory dev`, the web host, sandboxes): process names, session files and any working signal. Left out of the row.
- CPU floor for `tree_cpu` (3% is a guess) and hold window.

## Also

The task said to remember Grok Bot. That is a separate harness (`grok-bot` in `registry/harnesses.json`, documented at docs.x.ai/grok-bot, distinct from `grok-build`) and needs its own row. I wrote only the two files named for Mastra Code.

## Verification

Adversarial re-check, 2026-09-30, by a reviewer who did not write the row. Method: `tools/validate_row.py` (ok before and after), re-read of the cloned source at `4ea9e1f`, a fresh `npm pack mastracode@0.43.0` unpacked into the scratchpad (not installed), fresh scrapes of code.mastra.ai (index, configuration, headless, terminal-notifications), and `agents_probe.matches()` over 16 synthetic command lines. Nothing was run: no Mastra Code on this Mac (`which mastracode`, `ls /Applications | grep -i mastra`, `~/.mastracode`, `~/Library/Application Support/mastracode`, `ps` all empty). Confidence stays `documented`, the ceiling for an uninstalled harness.

### Confirmed

- caffeinate: `CAFFEINATE_ARGS = ['-i','-m']` (line 119), darwin plus `MASTRACODE_DISABLE_CAFFEINATE !== '1'` (187), start on `agent_start` (917), stop in the `finally` of any `agent_end` (972), `spawn('caffeinate', CAFFEINATE_ARGS, { stdio: 'ignore' })` (1059). Same strings in the 0.43.0 dist (`CAFFEINATE_ARGS` at line 26869, spawn at 27514). No `-w`, so it is a plain direct child named `caffeinate`.
- Vendor docs quote on macOS sleep prevention, the opt-out variable, and the 0.9.2 changelog entry (PR 14586).
- Tool-approval wait keeps the run (`await approvalPromise` at session-run-engine.ts 925-932, comment about approval-gated calls never emitting `tool-call-suspended`). `ask_user`, `submit_plan` and sandbox access notify from `tool_suspended` (display.ts 176-190); `finishAgentRun('suspended')` at 566-573; display.ts comment that `agent_end` `suspended` follows `tool_suspended`. The combined conclusion (caffeinate drops on suspension) is still inference, as the row says.
- Shell tool: workspace.ts 257 `new LocalSandbox({ workingDirectory, env })` with no isolation, LocalSandbox defaults `isolation` to `'none'`, local-process-manager.ts `detached: true, shell: isolation === 'none'`.
- npm: version 0.43.0, modified 2026-09-30T13:24Z, `bin.mastracode = ./dist/cli.js`, first line `#!/usr/bin/env node`, zero `process.title` in `dist/`, none in the source. No `.app`.
- CLI modes: `plugin` (main.ts 371), `prune` (378), `hasHeadlessFlag` (398), `--acp` (404), `--tui-prompt` and `--tui-initial-prompt` start the TUI (docs index and headless page; `initial-prompt.ts`). `hasHeadlessFlag` is `--prompt`, `-p`, or any positional when not help. Headless flag table (`--thread/-t`, `--continue/-c`, `-o`) matches the docs.
- Store: docs say LibSQL in `~/Library/Application Support/mastracode/`; the file name `mastra.db` comes from `project.ts getDatabasePath` and from the vendor's own notify script (`$HOME/Library/Application Support/mastracode/mastra.db`, `select title from mastra_threads where id = ...`); `MASTRA_DB_PATH` override confirmed in docs and source. Hook `session_id` = thread id: docs payload example (`thread-abc123`) plus the vendor script.
- Hooks: 14 events, config paths and order, `run_id`, `permission_kind` values, `AgentEnd` reasons incl. `suspended`, only PreToolUse/Stop/UserPromptSubmit block (docs). Payload field `stop_reason` confirmed in `sdk/src/hooks/manager.ts` (line 280) and `types.ts`. Notification reasons and hooks firing in mode `off` (notify.ts). Events added in 0.28.0 and PR 20923 in the changelog.
- Telemetry: no `otlp` or `opentelemetry` anywhere in `sdk/src` or `tui/src`; no `@opentelemetry/*` dependency; DuckDB exporter only when `localTracing`; `MastraPlatformExporter` always; `serviceName: 'mastracode'`; `getObservabilityDatabasePath` -> `observability.duckdb`; PostHog plus `MASTRA_TELEMETRY_DISABLED=1` (docs).
- Thread lock and pubsub: lock file holds the pid, `threadLock` is undefined when `crossProcessPubSub` (index.ts 605, 1522), TUI passes `unixSocketPubSub` unless disabled (main.ts 92), sockets under `/tmp/mc/<resourceId>` with the 104-byte limit. Still never observed.
- Factory left out: `mastracode/README.md` package table, `web/package.json` `api` script.
- Herdr claim: `registry/evidence/herdr.md` line 67 lists MastraCode among hook-authority agents. Row's contradiction on the process side follows from the caffeinate evidence above.

### Corrected

- Shim pattern missed `npx` and local installs. `args_contain: ["/bin/mastracode"]` does not match `node_modules/.bin/mastracode` (a dot precedes `bin`), yet the label claimed `npx mastracode`, and the vendor docs list npx, pnpm dlx, yarn dlx and bun x. Probe test: old pattern gave no match for `node /x/node_modules/.bin/mastracode`. Now `bin/mastracode`; matches `.bin/` and `/bin/` paths. Still inferred: the shim path is what `ps` shows (shebang behaviour), not observed.
- Headless and ACP surfaces were false-positive prone. They required only the substring `mastracode` in any argument plus `--prompt` or `--acp`, so `node /home/me/mastracode-notes/run.js --prompt x` or any node CLI whose prompt text says "mastracode" matched as a Mastra Code session (probe test confirmed the first). Each is now two surfaces, one with `bin/mastracode` and one with `/mastracode/dist/cli.js`, both still requiring the flag. The other cases, `mastra dev` (the framework CLI) and `-p`, `prune`, `--help`, stay unmatched.
- `tool_children` was incomplete. `mastracode/sdk/src/hooks/executor.ts` runs every user hook as `spawn('/bin/sh', ['-c', command])`, a direct child of the TUI. Stop, AgentEnd and Notification (agent_done) hooks run after the run ends, so an idle TUI with hooks configured can show a shell child briefly. The evidence file said only "a hook command with `shell` would be"; the row now says it and the notes tell the detector to debounce. New source entry added.
- Line numbers for `main.ts` in the CLI-modes source were wrong (`~222/229/249/255`); actual 371, 378, 398, 404. Also noted that the headless test runs before the `--acp` test.
- Notes gained one line: if stdin is piped and no TTY can be reopened, the TUI command falls back to headless and reads as a TUI surface here (main.ts, "No TTY available").

### Unsupported or unverified (left as the row states them, marked inferred or never run)

- The literal `ps` shape of a live instance (`node <symlink>/bin/mastracode`); the `bun x` runtime question; `lsof -U` mapping of a pid to a thread; whether `caffeinate` appears in `pmset` output for this signal; the 3% CPU floor (guess, and the row says so); whether goals, schedules or GitHub signals start runs with no human present.
- `--prompt=<text>` (equals form): `hasHeadlessFlag` tests `--prompt` by exact equality, so this form may start the TUI, while the probe's substring test would label it headless. Not checked further, rare.
- Third-party Herdr behaviour was not tested against Herdr itself.
