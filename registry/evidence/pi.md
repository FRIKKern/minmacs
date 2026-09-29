# pi coding agent: evidence notes (2026-09-29)

Row: `registry/agents/pi.json`. Validator: ok. Probe on this Mac: 0 pi processes, so nothing was classified live. Confidence is `documented`, not `verified-locally`.

## What I checked

- Install: `pi` is an npm global (`@earendil-works/pi-coding-agent` 0.82.0, nvm node v22.22.2). `bin/pi` is a symlink to `dist/cli.js`, a `#!/usr/bin/env node` script. `pi --version` and `pi --help` only.
- Package docs shipped inside the install (`docs/*.md`, `README.md`, `CHANGELOG.md`) and the compiled source in `dist/` (read-only `grep`/`sed`): `cli.js`, `config.js`, `core/session-manager.js`, `core/tools/bash.js`, `modes/interactive/interactive-mode.js`.
- Upstream: `https://github.com/badlogic/pi-mono` (redirects), `packages/telemetry` README, `https://pi.dev/install.sh`.
- Sessions: listed names, sizes and mtimes under `~/.pi/agent/sessions/`; printed only key names of one record. Checked that each filename's uuid equals the header `id`. No content read.
- Processes: `ps` for pi, cli.js, node. `lsof` not needed since nothing was running. Looked for app bundles in `/Applications` and Application Support: none.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | TUI only on this Mac. Also `--mode rpc`, `--mode json`, `-p` print mode and an embeddable SDK (same runtime, no TTY) | README, docs/rpc.md, docs/json.md, docs/sdk.md |
| Process name | Node process that sets `process.title = "pi"`; ps should show `pi` | source, inferred for ps |
| Path | node under nvm (or `~/.local/share/pi-node` for the pi.dev installer); script `.../@earendil-works/pi-coding-agent/dist/cli.js`; shim `.../bin/pi` | local + installer script |
| Bundle ids | none | local |
| Process to session | `--session-id <id>` gives the uuid, which is in the filename. `--session` takes a path or partial uuid. `--resume` and `--continue` carry no id. Otherwise use the cwd folder, newest file. Bash-tool children get `PI_SESSION_ID`/`PI_SESSION_FILE` in their env (not the pi process itself) | `--help`, docs |
| Store | `~/.pi/agent/sessions/--<cwd, / to ->--/<ISO ts>_<uuid>.jsonl`, JSONL, v3 tree via `id`/`parentId`, documented | docs/session-format.md, local |
| Turn in progress | Best in-process: `agent_start` to `agent_settled`. RPC `get_state.isStreaming`. From outside a plain TUI: bash-tool child process, then transcript append (message granularity), then CPU | docs, source |
| Waiting on human | No built-in state. No permission prompts exist. Only extension dialogs (`ctx.ui.confirm/select/input`, here the `ask_user` tool) block on the human, invisible from outside | README Philosophy, docs/extensions.md |
| Hooks | No hook config. TypeScript extensions in `~/.pi/agent/extensions/`, `.pi/extensions/`, or `extensions`/`packages` in `settings.json` | docs/extensions.md |
| OpenTelemetry | No. Contracts package exists upstream, no exporter, not in 0.82.0 | telemetry README, local grep |

## Could not determine

- Real `ps` output for a live pi. No pi was running and I may not start one. The `names: ["pi"]` surface rests on `process.title` in source plus my belief that libuv rewrites the argv area on macOS. If wrong, the two `node` fallback surfaces catch it. Nobody has checked which one fires. First live run should settle this.
- CPU floor for `tree_cpu`. 5 percent is a guess. No idle-versus-streaming measurement exists.
- Whether the TUI's Working spinner costs measurable CPU, and whether provider sockets stay open between turns (so `socket_activity` was left out).
- Whether the bun-compiled standalone binaries from GitHub releases show a different process name or path. Not installed here.
- Session dir when `PI_CODING_AGENT_DIR` or `--session-dir` is set: the glob is the default only. I did not inspect any process env.
- Whether `agent_settled` and the other events were present in older pi versions than 0.82.0.

## Contradicts common belief or the hint

- The repo is no longer `badlogic/pi-mono`. It redirects to `earendil-works/pi`, and the npm scope moved from `@mariozechner` to `@earendil-works`. Docs in the install still say `pi-mono` in places.
- pi is a Node script, but its process name is meant to be `pi` (title rewrite). A `node` name filter would miss it if the rewrite works. Do not key on `node` alone.
- pi has no permission prompts, so there is no "waiting for approval" state to detect, unlike Claude Code's Notification hook. It also has no hook config file: hooks are code.
- `agent_end` is not idle. Pi can retry, compact, or run queued follow-ups after it. Only `agent_settled` means done.
- Transcript writes are per finished message, not streamed. A file may not exist at all until the first assistant reply completes, so a fresh working session can have no transcript. A 20 second freshness window will call a long tool run or long generation idle.
- `--resume` takes no session id (it opens a picker). The probe's `session_id_args` reads the next argv token, so `--resume` must not be listed. I listed only `--session-id` and `--session`.
- Terminal title is static (`pi - <name> - <cwd>`), so it is not a working signal.
- `pi-telemetry` and OpenTelemetry words in the repo do not mean pi exports OTel. The only shipped telemetry is an anonymous install ping to pi.dev.
- Extensions on this Mac can change the picture: `claude-code-acp.ts` runs whole turns inside a real Claude Code child, and `background-terminals` keeps long-lived children. Child-based signals can therefore report working while pi itself is idle, or point at a Claude Code process that a claude-code row already counts.
- Third-party harnesses embed pi (the README points at openclaw). Some `pi` processes are not user TUIs.

## Verification

Independent refutation pass, 2026-09-29. Validator: ok before and after. `tools/agents_probe.py --row registry/agents/pi.json` reports 0 sessions; `ps` shows no pi, cli.js or pi-coding-agent process, so the classification could not be tested against a live instance. Result: 1 surface removed, 2 claims corrected, confidence lowered from `documented` to `inferred`.

### Row changes

- Removed the third surface (`node` + args_contain `/bin/pi`). Proven too loose with the probe's own `matches()`: it matched `node /usr/local/bin/pinact`, `.../pio`, `.../pino-pretty`, `.../piscina-worker`. It also would not have matched the pi.dev installer layout (`.../node_modules/.bin/pi` contains `/.bin/pi`, not `/bin/pi`). Substring matching cannot anchor to the end of an arg, so it cannot be tightened.
- Surface 2 label now says a shim launch shows the symlink path and is not matched by it.
- Terminal-title claim corrected (see below).
- `confidence` set to `inferred`, notes rewritten to say why and what the first live run must check.

### Claims

| Claim | Verdict | Basis |
|---|---|---|
| Installed 0.82.0, bin symlink to `dist/cli.js`, `#!/usr/bin/env node` | confirmed | `ls -la $(which pi)`, `pi --version`, `head -1` |
| `process.title = APP_NAME` (cli.js line 11), `APP_NAME = piConfigName \|\| "pi"` (config.js line 392) | confirmed | read both files; package.json has no `piConfig.name` |
| ps shows `pi` instead of `node ...` on macOS | unsupported (inferred) | never observed. Supporting only: libuv `proctitle.c` overwrites the original argv region. `dist/bun/cli.js` also sets the title. This is the row's main risk |
| Node fallback surface on `pi-coding-agent/dist/cli.js` | confirmed as a pattern, weak as a fallback | specific enough to avoid false positives, but a shim launch puts the symlink path in ps, not the `dist/cli.js` path |
| Loose `/bin/pi` surface | corrected (removed) | false positives shown above |
| No app bundle, no bundle id | confirmed | `ls /Applications`, `ls ~/Library/Application Support` printed nothing for `pi`/`earendil` |
| Installer: same npm package, managed Node under `~/.local/share/pi-node`, wrapper execs the real bin | confirmed | fetched https://pi.dev/install.sh: `PI_PACKAGE="@earendil-works/pi-coding-agent"`, `npm install -g --ignore-scripts`, `pi_release_bin=$pi_release_dir/node_modules/.bin/pi`, `exec "$pi_release_bin" "$@"` |
| Standalone bun binaries exist | confirmed | package.json `build:binary` (`bun build --compile ./dist/bun/cli.js`), root README links "Building standalone binaries from release source". Not installed here |
| Session flags (`--session-id`, `--session`, `--fork`, `--session-dir`, `--no-session`; `--resume`/`--continue` take no id) | confirmed | `pi --help`. Extra: `--session-id` cannot combine with `--session`, `--continue` or `--resume` (main.js `validateSessionIdFlags`); only the space-separated form is parsed (cli/args.js line 67) |
| Store path `~/.pi/agent/sessions/--<cwd>--/<ts>_<uuid>.jsonl`, header id equals filename uuid | confirmed | docs/session-format.md "File Location"; re-ran on all 5 local files: all True |
| Record shape (keys only) | confirmed, one key added | header `cwd,id,timestamp,type,version`; entries `id,parentId,timestamp,type`; assistant messages also carry `errorMessage` on some records |
| Per-message `appendFileSync`, file created only after first assistant message, not held open | confirmed | session-manager.js `_persist()` lines 724-751 |
| `PI_CODING_AGENT_DIR`, `PI_CODING_AGENT_SESSION_DIR`, `--session-dir` override the glob | confirmed | docs/environment-variables.md, `pi --help` |
| Bash tool spawns a detached child shell; `PI_SESSION_ID`/`PI_SESSION_FILE` only in bash-tool commands since 0.82.0 | confirmed | bash.js line 56 `detached`; CHANGELOG 0.82.0 line 17; env docs |
| `PI_CODING_AGENT=true` in children | corrected | set by the CLI and RPC entry points, not when embedded through the SDK (env docs "Process Marker") |
| `agent_end` is not idle, `agent_settled` is | confirmed | docs/extensions.md "Agent Events"; upstream page on github.com/earendil-works/pi main also documents `agent_settled` |
| RPC `get_state.isStreaming`, JSON mode events | confirmed | docs/rpc.md, docs/json.md exist and match (isStreaming seen in the get_state example) |
| No permission popups, no hooks config file | confirmed | README line 499; docs/extensions.md "Extension Locations" |
| All 24 hook event names | confirmed | each appears as a `pi.on("<event>"` example in docs/extensions.md |
| Terminal title is `pi - <name> - <cwd>` | corrected | `APP_TITLE` is the letter π (config.js line 393), so the title is `π - <name> - <cwd>` or `π - <cwd>`. Static either way, so the conclusion (not a working signal) stands |
| Repo moved from badlogic/pi-mono to earendil-works/pi; npm scope moved | confirmed | firecrawl scrape of github.com/badlogic/pi-mono returned url github.com/earendil-works/pi; package.json repository.url |
| No built-in OpenTelemetry; telemetry package is contracts only | confirmed | packages/telemetry README ("no exporter, global current-span state, or dependency on a telemetry backend"; `pi.ai.*`, `pi.harness.*`, `pi.session.*` names); `node_modules/@opentelemetry` holds only `api` and `semantic-conventions`; README "Telemetry and update checks" |
| Install ping only, opt out `PI_TELEMETRY=0` | confirmed | README lines 312-313, 671 |
| Vendor "Earendil Works (created by Mario Zechner)" | confirmed for author and org, inferred for the vendor name | package.json author, repo owner; source entry added |
| `ask-user` extension registers `ask_user` | confirmed | `name: "ask_user"` in `~/.pi/agent/extensions/ask-user/index.ts` line 101 |
| No pi process was running, so nothing was classified live | confirmed | `ps` and the probe, re-run at verification time |
| `tree_cpu` floor 5 percent | unsupported (already labelled inferred in the row) | no idle versus streaming measurement exists |
| `tool_children` as a working signal | partly supported | source shows a detached child per bash call. The probe counts any non-caffeinate child, so extensions with long-lived children (`background-terminals`) give false "working". Idle-time children of the `git-info` extension were not checked |
| `transcript_write` 20 s window | supported with a limit | the probe only reads a transcript when the process argv has `--session-id <id>`; with `--session <path\|partial uuid>` or no flag the per_session glob resolves nothing and the signal is silent |

### Probe versus reality

The probe matches by `basename(argv[0])`, so surface 1 fires only if ps args start with `pi`. Nothing ran, so the believable-versus-`ps` check reduces to: (a) every field parses and matches the probe's contract (validator ok), (b) surface 1 and 2 give the right answers on synthetic argv (`pi`, `pi -p hi`, `node .../pi-coding-agent/dist/cli.js` match; `node .../bin/pino-pretty` does not), (c) a live run is still needed. Headless `pi -p`/RPC processes also match surface 1 and show up as agents without a TTY.

### Still unproven

- What `ps` prints for a running pi on this Mac (title rewrite versus `node .../bin/pi`).
- The CPU floor, and whether the idle TUI is quiet.
- Whether bun standalone binaries show the same title.
- Session directory when a `--session-dir` or `PI_CODING_AGENT_DIR` override is in the process env.
