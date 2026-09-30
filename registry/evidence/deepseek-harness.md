# DeepSeek Harness (dsh) evidence notes (2026-09-30)

Not installed here: no `dsh`, no `~/.dsh`, no app, nothing running, no power assertion. No live turn and no session file was seen, so the row is `documented`, not `verified-locally`. The source is public (`github.com/deepseek-ai/deepseek-harness`, MIT, TypeScript, developer preview), so most claims were read in code. Version read: `@deepseek-ai/dsh` 0.2.0-rc.2, commit `639ed01` (the tag `dsh-v0.2.0-rc.2`, released 2026-09-29; npm `latest` and `next` are the same version).

## Shape

```
npm / npx / global:   node  <...>/.bin/dsh  web          one Node process, plugin tree in-process
                        |- serves 127.0.0.1:3080 (HTTP + WebSocket), prints "dsh web: <url>?<token>" to stdout
                        |- model call: in-process HTTPS stream, NO child process
                        |- tools: `bash -c <cmd>` = direct child (via sandbox-exec when confined)
                        |- also permanent children: sidebar terminals (node-pty), jobs, MCP, LSP
                        '- sessions: ~/.dsh/sessions/--<cwd>--/<id>/session.v4.jsonl.zstd  + session.lock

Desktop (official DMG):  DeepSeek Harness.app  (Electron main + helpers, no dsh arguments)
                        '- Host = same binary, ELECTRON_RUN_AS_NODE=1 --expose-internals .../dsh-desktop-host/lib/index.js
                              serves 127.0.0.1:19387, same tool children and same store

Desktop `dsh` command:   /usr/local/bin/dsh (sh script) -> exec MacOS/DeepSeek Harness ... dsh-desktop-host/lib/cli.js <args>
Python SDK:              .../deepseek_harness_runtime/runtime/deepseek-harness-sdk-runtime-macos-arm64 --profile sdk   (needs DSH_HOME)
Other profiles:          --profile headless "task" (one shot), --profile sdk, --profile acp (stdio servers)
```

## What I checked

- README, `apps/cli/README.md`, `apps/cli/reference/README.md` (entry modes, app arguments, shipped profiles), `apps/desktop/README.md`, `python/sdk-runtime/README.md`, `python/sdk/README.md`, the hooks, OTel, persistence, session-format, approval, agent-lifecycle and web-server docs in the repo.
- Code: `apps/cli/src/bin.ts`, `apps/desktop/src/host-process.ts`, `node-environment.ts`, `main.ts`, `apps/desktop/cli/dsh`, `apps/desktop-host/src/index.ts`, `packages/bundle/{base,web-app}/cordis.patch.yml`, `packages/bundle/web-app/src/index.ts`, `packages/session/session-persistence-jsonl/src/{lease,format}.ts`, `packages/subprocess/subprocess-local/src/{spawn,index}.ts`, `packages/shell/bash-local`, `packages/sandbox/sandbox-local`.
- Web: `registry.npmjs.org/@deepseek-ai/dsh` (dist-tags, bin), GitHub releases page, `deepseek.com/harness/en/` (official macOS DMG link, link read only), a search for desktop builds.
- Local, read-only: `command -v dsh` (nothing; node and npx exist under `~/.nvm/versions/node/v22.22.2/bin`), `ls -d ~/.dsh` (no such directory), `mdfind` for bundle id `com.deepseek.harness*` (nothing), `ps -axo pid=,args= | grep -i [d]eepseek` (only the checking shell), `pmset -g assertions` (no dsh or deepseek line).
- Process rules run through `tools/agents_probe.py` `matches()` on hand-written argv lists, no process started. Matched the intended surface: Desktop Host (`gui`, score 55); Desktop `cli.js web` (`daemon`); `node .../_npx/<hash>/node_modules/.bin/dsh web` with and without `--no-open --port 8080`; `node ~/.nvm/.../bin/dsh web`; `node .../@deepseek-ai/dsh/lib/bin.js --profile headless "run the tests"`; the SDK runtime executable `--profile sdk`. Matched nothing: bare `DeepSeek Harness` (Electron main), a renderer helper, `cli.js plugin ...`, `.bin/dsh --version`, `bin/dsh plugin ...`, `npm-cli.js exec @deepseek-ai/dsh web`, `sh -c "dsh web"`, `node .../.bin/vite`, `bin.js --dump-config`. `claude --resume` still goes to the `claude-code` row, unaffected.

## Could not determine

- **Any live behaviour.** No session record, lock file, socket, or turn was seen. The 30 s window and 3% CPU floor are guesses.
- **The real macOS bundle id.** The release id is injected at build time (`DSH_DESKTOP_APP_ID`). The only committed value is the example `com.deepseek.harness` in `apps/desktop/.env.macos.example`, put in the row as inferred. The dev build uses `com.deepseek.harness.dev.<hash>`. The DMG was not downloaded.
- **The exact argv the Host and CLI show in a packaged app.** Read from source (`spawn(this.node, ['--expose-internals', entry, ...])`); `resources.dsh` resolves to `app.asar/dsh`; not observed. Same for the argv under npx and global installs (inferred from Node and npm behaviour).
- **How long the agent holds its session write handle.** The `session.lock` flock is held for the life of the handle, so `lsof` on a host should list lock files. Whether an idle loaded session keeps its lock, or it is dropped after the turn, was not traced. Treat the lock as "loaded", not "busy".
- **Real record content.** Key names come from the `SessionEvent` type (`type`, `seq`, `time`, `data`, optional `ignorable`, `surfaceOp`, `sourceEventSeqs`) and the header from `SessionHeader`; nothing was decoded from a real file.
- **How often the log is written during a long model call.** Docs say stream chunks are transient and only settled messages are appended, so the log can stay quiet for the length of a generation. Batching window is internal and not documented in seconds.
- **Whether `sandbox-exec` leaves the child reading as `bash`.** It execs the command in place by design; not observed.
- **Wait state from the outside.** The only external evidence is the log (`approval/asked` without `approval/decided`, open `ask_user_question` call). Both need Zstandard decoding. Live status needs the token from the printed URL.
- **A live query API.** The Host API is authenticated per process token; no unauthenticated status route was found. The `workspace/session-activity` RPC exists but was not exercised.
- **Community desktop wrappers.** `dataelement/dsh-desktop` (DSH Desktop) and `salathleizhang/deepseek-harness-desktop` package the app under their own ids and paths; not researched.

## Against common belief

- **"dsh is a terminal agent."** It has no shipped terminal UI. The npm CLI's main mode is `dsh web`, a local server whose UI is a browser tab. `tui` appears in the docs only as an example of a profile you could install. The default command line is a Node server, not a TTY program, so a tty on the process says nothing here.
- **"There is no official desktop app."** A third-party post says the official route is `npx @deepseek-ai/dsh web`. The official page `deepseek.com/harness/en/` links a macOS arm64 DMG at `download.deepseek.com/desktop/dsh-latest-macos-arm64.dmg`, the repo ships `apps/desktop` with a signed-and-notarised packaging path, and rc.2 release notes mention the desktop menu.
- **"It holds a sleep assertion or runs caffeinate like other agents."** It does neither. No code for either exists in the tree.
- **"A shell child means a turn is running."** Only if you also know nothing else is parked. A sidebar terminal is a shell child for as long as it stays open, and jobs, MCP servers and language servers are children too. `tool_children` is left out of the row for this reason. The model call itself, the longest part of a turn, has no child at all.
- **"The session list is `~/.dsh/sessions`, one file per session."** It is `sessions/--<cwd>--/<id>/`, zstd-compressed by default (readable as plain lines only with `compression: none`), with `session.lock` beside the log. `$DSH_HOME` moves all of it, and the Python SDK runtime refuses to start without an explicit `DSH_HOME`, so SDK sessions are not under `~/.dsh` by default.
- **"OpenTelemetry means I can point a collector at it."** There is an OTel service, but no user-facing exporter. Desktop sends product analytics (OTLP logs) to DeepSeek's collector by default with no switch; the Web profile sends none; session logs are uploaded only when the user submits feedback.
- **"Hooks are built in."** No shipped profile mounts any. The two hook plugins only replay existing Claude Code or Codex `hooks.json` command hooks, and neither event list has a `Notification` or permission-request event.
- **"`dsh` on a Mac is one program."** The same grammar runs as `node .../dsh`, as an Electron binary in Node mode (Desktop Host and Desktop command), and as a `pkg` executable (Python runtime). Only the argument tail is common.

## Verification

Independent check, 2026-09-30, by a second agent that did not write the row. Method: `tools/validate_row.py` (ok before and after), a fresh shallow clone of `deepseek-ai/deepseek-harness` at `639ed01` (`git fetch` printed the same hash), `registry.npmjs.org/@deepseek-ai/dsh`, the GitHub release API for `dsh-v0.2.0-rc.2`, a live scrape of `deepseek.com/harness/en/`, `curl -sI` on the DMG, and `tools/agents_probe.py` `matches()` on 20 synthetic argv lists. Nothing was installed or started. Confidence stays `documented` (the harness is not installed here); no claim needed downgrading to `inferred`.

Confirmed
- Repo, MIT, `@deepseek-ai/dsh` 0.2.0-rc.2, dist-tags latest and next, bin `lib/bin.js`, tag `dsh-v0.2.0-rc.2` published 2026-09-29 on commit `639ed01`.
- Entry modes, profile names (`web`, `headless`, `sdk`, `sdk-minimal`, `acp`), `plugin` and the three `--dump-*` flags, `-V/--version`, `-h/--help` (`apps/cli/README.md`, `apps/cli/src/args.ts`); web default port 3080 (`packages/bundle/web-app/cordis.patch.yml` line 174); no shipped terminal UI.
- `dsh web` prints `dsh web: <authenticated url>` and opens a browser unless `--no-open` (`packages/bundle/web-app/src/index.ts`).
- Desktop Host: spawned with `process.execPath`, args `--expose-internals <runtimeDir>/node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js <runtimeDir> <projectDir> <primaryRuntime> [pnpm nodeBin]`, `ELECTRON_RUN_AS_NODE=1`, IPC stdio; `apps/desktop-host/src/index.ts` runs the web app with `--no-open --port 19387`; product name `DeepSeek Harness`, executable `Contents/MacOS/DeepSeek Harness` (`smoke-packaged-runtime.ts`).
- `apps/desktop/cli/dsh` execs the Electron binary in Node mode on `dsh-desktop-host/lib/cli.js`.
- Official DMG: link present on the vendor page, `curl -sI` gives HTTP/2 200, `application/x-apple-diskimage`, last modified 2026-09-29; rc.2 release notes mention the "Manage dsh command" menu item.
- Sessions: `dshHomePath('sessions')` in `packages/bundle/base/cordis.patch.yml`, `--<cwd>--` or `_no-cwd` project dir, `SESSION_FORMAT_VERSION = 4` (`packages/core/session/src/types.ts` line 89), default `compression: 'zstd'` with fsync per batch, synthetic closers on resume, `session.lock` taken with `flock(2)` (`lease.ts`). Desktop shares `$DSH_HOME` with the CLI (`apps/desktop/README.md`).
- Event names `turn/start`, `turn/end`, `approval/asked`, `approval/decided`, `tool/call`, `tool/result`, `assistant/message`, `assistant/attempt` exist in `docs/persistence-catalog.md`; `approval/asked` is log-only and needs an open turn (`docs/subsystems/approval.md`).
- No sleep inhibitor: the row's exact grep over the whole tree prints nothing; a wider grep (power-save, suspension, wake lock, keep awake, powerMonitor) only finds `powerMonitor` resume and shutdown listeners in `apps/desktop/src/main.ts`, which hold no assertion.
- Tool shell is `bash -c` (`packages/shell/bash-local/src/index.ts` line 188); node-pty terminals (`subprocess-local/src/index.ts` line 289); macOS containment is the `fallback` mode with the quoted warning; Seatbelt via `sandbox-exec`. The shipped base bundle mounts only the two in-process subagent providers; the Claude Code, Codex, ACP and dsh-sdk providers are in no shipped bundle.
- Hooks: only the two bridge plugins, no bundle mounts them; supported events as listed; `Notification` and `PermissionRequest` are explicitly unsupported (`hooks-claude-code/README.md` line 174).
- Telemetry: product-analytics OTLP logs to `dsh-otel-collector.deepseeksvc.com` for Desktop, none for Web (`packages/host/product-telemetry-otel/README.md`).
- Model endpoint `https://api.deepseek.com/anthropic` (`packages/llm/llm-deepseek/src/config.ts` line 106).
- `ask_user_question` blocks by default; `mode: timed` and `timeout: -1` as described; mounted by the web presets (`tool-ask-user`, lines 130-131).
- Python runtime: executable name from `python/sdk-runtime/platforms.json`; the `dsh` console command needs `DSH_HOME` and never falls back to `~/.dsh`; the dev-only Node carrier needs Node 22.19 or newer.
- Process rules (synthetic argv, real `matches()`): the Host matches `gui` (score 55), `cli.js web` matches `daemon` (55), `npx` and global `node .../bin/dsh web` match `daemon`, the SDK runtime with `--profile sdk` matches `daemon` (31). No match for the Electron main process, a renderer helper, `--expose-internals pnpm.mjs`, `cli.js plugin`, `bin/dsh --version`, `bin.js --dump-config`, `perl /usr/bin/dsh` (Debian dsh), `sh -c "dsh web"`, `npm-cli.js exec`, `node .bin/vite`.

Corrected
- Desktop `dsh` command: the row said Desktop "creates /usr/local/bin/dsh, a /bin/sh script". `apps/desktop/README.md` says installation creates a link ("the macOS link preserves and restores the displaced launcher"); the script is `apps/desktop/cli/dsh`, which resolves symlinks. Label fixed. Matching is unaffected, because the script `exec`s the Electron binary.
- CPU floor 3 changed to 10. `registry/README.md` section 4 sets 10% for desktop hosts, and every dsh host tree carries a Node server plus permanent children. Still a guess, still a fallback.
- Scheduled tasks: the row said "off by default in Desktop". The repo says only that the shipped Web composition has no `schedule` row and the plugin is opt-in experimental (the vendor page lists it under Official, Experimental). Wording changed to opt-in; the Desktop default was not checked.
- Line reference `apps/desktop/src/main.ts` line 159 changed to 158.
- Process patterns: the `/bin/dsh` and `/.bin/dsh` surfaces are substring tests, so `node <dir>/bin/dshell.js` and `node <dir>/.bin/dsh-lint` also match (daemon, score 2, shown with `matches()`). The schema has no end-anchored match, so this is documented on the surface and in notes, not fixed. Every other pattern needs a second discriminator (the Desktop paths, `lib/bin.js`, or the runtime executable name) and held.

Unsupported or still unproven
- Bundle id `com.deepseek.harness`: only the macOS and Windows `.env` examples and a `~/Library/Caches/com.deepseek.harness` lock path in a release script agree. The release value is injected at build time and the DMG was not opened. Stays inferred. The probe never reads `bundle_ids`.
- Live behaviour: the 30 s window, the CPU floor, `socket_activity`, `lsof` showing `session.lock`, `sandbox-exec` leaving a `bash` child, and how long an idle loaded session keeps its lock. None observed; all marked as guesses or inferred in the row.
- Exact argv in a packaged app, and under npx and global installs: read from source and from how `env`, npm and Electron pass argv. Not observed.
- Community wrappers: their existence is now sourced (`dataelement/dsh-desktop`, `salathleizhang/deepseek-harness-desktop`, and at least 17 more under the `deepseek-desktop` topic; the second ships an app also named DeepSeek Harness). Their argv was not inspected, so whether the Desktop `gui` surface would also match them is unknown.
