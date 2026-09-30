# Prime Agent evidence notes (2026-09-30)

Row: `registry/agents/prime-agent.json`. Validator: ok. Probe with `--row` on this Mac: 0 sessions, because Prime Agent is not installed (`ls ~/.prime` no such file, `which prime-agent` not found, no `prime` process). Nothing was started. Confidence is `documented`, not `verified-locally`. Everything comes from the public repo and the vendor blog.

## Shape

```
terminal:  prime-agent            ~/.local/bin/prime-agent  (/bin/sh launcher: sets PRIME_AGENT_CODING_AGENT_DIR,
   |                                PRIME_AGENT_DAEMON_SOCKET=${TMPDIR:-/tmp}/prime-agent-rust-<uid>/daemon.sock, then exec)
   |                              -> ~/.local/share/prime-agent/prime-agent  (one Rust binary; releases/<ver>-<platform>-<sha>/)
   |  thin client: attaches over a Unix socket, renders, forwards input
   v
prime-agent --mode daemon --daemon-socket <sock>     detached supervisor, ppid 1, no model/tool work
   |  one per active session (each RLM subagent gets its own; corrected in Verification)
   v
prime-agent worker                                    argv exactly "worker"; the process that works
   |- python -m rlm.repl   (<agent-dir>/kernel-venv/bin/python)   direct child, lives with the session
   |     '- bash tool commands (Popen, new session)                grandchildren of the worker
   '- shell for `!` user commands                                  direct child, only while one runs

embedded:  prime-agent --mode acp   -> bridges to a client-owned worker (no_session=true, no file)
           prime-agent --mode rpc   -> in-process engine
           prime-agent -p / --mode json / piped stdin -> one-shot, in-process

sessions:  ~/.prime/agent/sessions/<uuidv7>.jsonl   flat, append-only, header + tree entries
state:     ~/.prime/agent/{daemon-workers/*/<workerId>.json, session-leases/, logs/, kernel-venv/, settings.json}
```

## What I checked

- Repo `PrimeIntellect-ai/prime-agent`, shallow clone of `main` at 883b5a1 (2026-09-30), Cargo version 0.9.8, highest tag v0.9.8. Read: `README.md`, `AGENTS.md`, `install-rust.sh` (launcher heredoc), `crates/pa-cli` (args, mode, command registry, public commands, daemon spawn, print runtime), `crates/pa-daemon` (main, supervision, descriptor, lease, paths, platform/paths, roster activity, worker summary, ACP transport), `crates/pa-types/src/session.rs`, `crates/pa-core` (kernel startup, session ids, update install layout, telemetry), `crates/pa-telemetry/README.md`, `prime-agent-runtime` (kernel, bash.py, uv.lock), `packaging/homebrew`.
- Vendor blog https://www.primeintellect.ai/blog/prime-agent (daemon, workers, Agents View, JSONL sessions, install line).
- Older TypeScript docs at commit 36307ca (2026-07-21): `sessions.md`, `session-format.md`, `daemon-implementation-summary.md`, `extensions.md`, via raw.githubusercontent.com. The TS product is what the installer replaces.
- Third party for the ACP command line only: a SuperQode write-up (`run_command "prime-agent --mode acp"`).
- Row logic run against 17 synthetic argv lists with `tools/agents_probe.py matches()` (no process started, nothing written).

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | terminal TUI; detached supervisor; session worker; `--mode acp`; `--mode rpc`. One-shots (`-p`, `--mode json`, piped stdin) have no surface of their own | source |
| Process name | `prime-agent` for all of them, told apart by arguments | launcher `exec`, args.rs, supervision.rs |
| Path | `~/.local/bin/prime-agent` (launcher, does not stay in the process list); running image `~/.local/share/prime-agent/prime-agent` or `.../releases/<ver>-darwin-arm64-<sha>/prime-agent` | install-rust.sh |
| Bundle ids | none; no desktop app. The in-repo Homebrew cask is a draft sketch pointing at a different repo | packaging/homebrew |
| Process to session | TUI: `--resume <id>` only. Fresh session: no id in argv. Worker: `~/.prime/agent/daemon-workers/*/<workerId>.json` has `pid` and `sessionFile` (also holds an auth token, do not read it). `prime-agent list --json` gives `sessionFile` and `activity` per session but no pid | descriptor.rs, worker.rs types, summary.rs |
| Store | `~/.prime/agent/sessions/<uuidv7>.jsonl`, JSONL v3 tree, documented. ACP (`no_session`) and `--no-session` write nothing | docs, paths.rs, acp/daemon.rs |
| Record keys | header: `type version id timestamp cwd` (+ `parentSession rlmDepth git`). Entries: `type id parentId timestamp` plus `message` (role user, assistant, toolResult, bashExecution, custom, branchSummary, compactionSummary), `session_state`, `model_change`, `compaction`, ... From type definitions, no live file opened | pa-types session.rs |
| Turn in progress | Exact: roster `activity == "working"` (worker busy or compacting), via `prime-agent list --json`. From files: last message entry is user, toolResult or assistant with `stopReason: toolUse`, with the worker alive. From processes: only tree CPU of the worker | summary.rs, session.rs |
| Waiting on human | No such state. No permission prompts; README says commands run with the user's permissions, no sandbox | README, grep of source |
| Sleep assertion | None. No caffeinate or IOKit assertion anywhere in the repo | grep |
| Hooks | None in the Rust build. TS predecessor had TypeScript extensions (`~/.prime/agent/extensions/`, events `agent_start`, `turn_end`, `tool_call`, ...) | grep, TS docs |
| OpenTelemetry | No. PostHog-style analytics (`pa-telemetry`), opt-out `PRIME_AGENT_TELEMETRY=0` / `DO_NOT_TRACK=1`. `opentelemetry-api` in the kernel lockfile is a transitive dependency of `mcp` | pa-telemetry README, uv.lock |

## Could not determine

- Real `ps` output. No live process. The name `prime-agent` and the `worker` argv rest on source. After the shell `exec`, argv[0] should be `.../.local/bin/../share/prime-agent/prime-agent`; I did not confirm that macOS keeps the un-normalised path.
- Idle versus working CPU for the worker, the kernel and the TUI. The 3 percent floor is a guess, and model waits burn nothing.
- Whether the worker's roster push is late for a model call that never emits an event. `activity` flips at the busy flag, which I read in `session_summary` but did not trace to the exact line that sets `busy`.
- Real macOS socket paths. The supervisor socket is pinned by the launcher to `$TMPDIR/prime-agent-rust-<uid>/daemon.sock`. Worker sockets use `socket_dir()`, whose uid comes only from `/proc/self/status` and falls back to `user` off Linux, so I expect `$TMPDIR/prime-agent-user/worker-*.sock`. Unverified.
- Whether a permission or approval mode arrives in a later release. I searched v0.9.8 only.
- Whether a detector may read the worker descriptors while the supervisor holds them (owner-only permissions, same user, so should work). Not tried.
- Homebrew or other package routes. Only the curl installer is real; `install.sh` itself is served from app.primeintellect.ai and is not in the repo (the repo file is `install-rust.sh`, which the release workflow uploads).
- The TypeScript build's real process shape (Node, or a native binary). The row assumes the same command name and `--mode daemon --daemon-socket` argv, which the Rust source says it copies (`TS spawns its own entrypoint with --mode daemon --daemon-socket`).

## Contradicts common belief or the hint

- **`--mode acp` is not an in-process agent.** The hint reads like a stand-alone engine. In v0.9.8 it first ensures a supervisor, creates a client-owned daemon session with `no_session: true`, and bridges to a worker. There is no transcript file, no shell child on the ACP process, and it holds one session per process. It only falls back to the in-process engine when the daemon is unreachable.
- **The store is not `~/.prime/agent/sessions/<cwd>/...`.** It is flat, `<uuidv7>.jsonl` (older per-project folders were migrated). The header holds the cwd. Two sessions in one directory do not share a folder, so id mapping is easier than for Claude Code, but a fresh TUI has no id in argv at all.
- **The visible process is the least useful one.** The TUI has no working children and does not write the file; the worker is not its child and is not a `prime-agent` with a session flag. The generic detector (shell child, transcript write, tree CPU) reads an idle TUI while a turn runs. This is README case 11 (thin client) plus case 8 (kernel is a permanent child).
- **Shell tool commands are grandchildren.** The model's only tool is a persistent Python kernel; its `bash` runs from `bash.py`, so a direct-child rule on the worker sees only the kernel. `tool_children` was left out of the row.
- **No sleep inhibitor, no approval prompts, no hooks, no OTel.** Common expectations from Claude Code or Codex do not carry over. `prime-agent list --json` is the vendor's own status API and it is the only exact signal.
- **`worker` is a substring hazard.** A TUI prompt argument that merely contains `worker` matches the worker surface (score 2 beats the TUI's 1), because `args_contain` is a substring test. Cost: a wrong surface label, same signals. The reverse (dropping the worker surface) would hide the process that actually works.
- **The repo's docs are in flux.** README still says a `rust` branch publishes betas, `AGENTS.md` says main; the Homebrew files point at `kevinjosethomas/prime-agent-rs`. The TS packages tree (`packages/coding-agent`) is gone from main; its docs survive at commit 36307ca. I cite both and say which is which.

## Matching test (synthetic, `agents_probe.matches()`)

Launcher path used: `/Users/x/.local/bin/../share/prime-agent/prime-agent`.

| argv after the binary | result |
|---|---|
| (none), `--resume 01abc`, `agents`, `-p hello`, `--cwd /x/worker-app` | tui (1) |
| `--mode daemon --daemon-socket <s>` | daemon (4) |
| `worker` | daemon (2), the worker surface |
| `--mode acp`, `--mode acp --daemon-socket <s>`, `--mode acp --cwd /x/daemon-thing` | ide (3), ACP |
| `--mode rpc` | ide (3), RPC |
| `"fix the worker pool"` | daemon (2), worker surface: known misfile, see above |
| `--mode json -p x`, `list --json`, `update --check`, `--version`, another binary with `--mode acp` | no match |

## Scope note

The request also says to remember Grok Bot. That is a separate harness (`grok-bot` in `registry/harnesses.json`, distinct from `grok-build`) and needs its own row and its own research. I wrote only the two files named for Prime Agent.

## Verification

Refutation pass, 2026-09-30. Validator: `ok` before and after. Repo re-checked at `PrimeIntellect-ai/prime-agent` main 883b5a1 (no newer commit, highest tag v0.9.8); vendor blog and the SuperQode article re-fetched live. Prime Agent is still not installed here (`ls ~/.prime` no such file, `which prime-agent` not found, no matching process), so confidence stays `documented`, not `verified-locally`.

Verdict: one defect repaired, one claim corrected, one claim withdrawn. The rest held.

### Confirmed

| Claim | Check |
|---|---|
| Not installed here | Re-ran the three commands: same output |
| v0.9.8, binary target `prime-agent`, MIT | `Cargo.toml` version, `crates/pa-cli/Cargo.toml` `[[bin]]`, `LICENSE` |
| Installer launcher at `~/.local/bin/prime-agent` ends in `exec "$(dirname "$0")/../share/prime-agent/prime-agent" "$@"`; payload in `releases/<version>-<platform>-<sha256>/`; darwin-arm64 and darwin-x64 known | `install-rust.sh` lines 1-30 and 1471; `update/install.rs` `KNOWN_PLATFORMS` |
| No app bundle, no bundle id | Homebrew cask is a draft for another repo with a placeholder sha256; no Info.plist or `.app` in `packaging` or `install-rust.sh` |
| `--mode <text\|json\|rpc\|acp\|daemon>` | `args.rs` 274-283, `command_registry.rs` |
| ACP command `prime-agent --mode acp` | SuperQode article TOML, verbatim |
| Supervisor spawned as `<exe> --mode daemon --daemon-socket <path>`, detached, stdio null | `interactive_mode/daemon.rs` 175-197 |
| Worker spawned as `<exe> worker`, stdin/stdout null, stderr to a log, new process group | `supervisor/supervision.rs` 419-441; `pa-cli/src/lib.rs` 173-183 |
| Kernel is `python -m rlm.repl`, a direct child of the worker; model shell commands are `Popen(..., start_new_session=True)` from `bash.py`, so grandchildren | `kernel/manager/startup.rs` 176-190; `bash.py` 315-323 |
| TUI is a daemon client; closing it detaches | Blog ('attach and detach ... without affecting the underlying agent loop'); `print_runtime.rs` 47-51 |
| `--mode acp` tries the daemon first, `no_session`, in-process only as fallback; `--mode rpc` is in-process | `print_runtime.rs` 47-110 (`acp_mode_main`, `try_daemon_attached_acp`, the Rpc arm comment) |
| Store `~/.prime/agent/sessions/<uuidv7>.jsonl`, flat, header carries cwd; archive at 30 days or 200 sessions | TS `session-format.md` at 36307ca, `paths.rs`, `ids.rs`, `pa-daemon/README.md` |
| Record shape: header keys, `session_state` active/archived/crash, stopReason stop/length/toolUse/error/aborted | `pa-types/src/session.rs` `SessionHeader`, `SessionStateStatus`; `ai/mod.rs` `StopReason`. Key names only; no session file exists here |
| Worker descriptor holds `pid`, `sessionFile`, `authenticationToken`; leases only when `PRIME_AGENT_INTERNAL_SESSION_LEASES` is 1/true/yes | `pa-types/src/daemon/worker.rs`, `lease.rs` `leases_enabled` |
| `activity` is `working` exactly when `busy` or compacting; `list`/`sessions --json`; fields `isStreaming`, `isCompacting`, `attachedClients`, `sessionFile`, `cwd`, `isQuotaParked`; `isSessionActive` also true for queued input | `worker/summary.rs` 365-430; `daemon_session_list.rs` `list_status` |
| Public commands and removed names | `command_registry.rs` `COMMAND_SPECS`, `REMOVED_COMMAND_NAMES`; `public_command.rs` |
| No sleep inhibitor | `grep -rIl -i -E 'caffeinate\|IOPMAssertion\|NoIdleSleep\|pmset\|sleep inhibit\|prevent.{0,10}sleep' --exclude-dir=vendor .` printed nothing |
| No permission or approval state; README says not a sandbox | Grep hits are only the Anthropic provider, refine review, MCP catalog text and test data; README line 75 |
| No hooks or extension runtime in the Rust build | Grep for hook/PreToolUse/SessionStart hits only internal Rust traits (`AgentCronSchedulerHooks`, agent-loop `beforeToolCall`) and comments; no `-e`/extension flag in `args.rs`; `--autonomous-gate` is a completion gate |
| No OpenTelemetry; PostHog-style analytics with opt-outs | `pa-telemetry/README.md`; no `opentelemetry` in `crates`, `skills`, `prime-agent-runtime/src`; only `uv.lock` lists `opentelemetry-api` |
| Blog install line, daemon and Agents View text | Live fetch of https://www.primeintellect.ai/blog/prime-agent |
| Worker socket dir falls back to `prime-agent-user` off Linux | `platform/paths.rs` 12-45. Still inferred, not observed |

### Corrected

- **A worker serves one session, not a session tree.** The row and notes said one worker per root session tree that also runs every RLM subagent. That is the blog's wording for the TypeScript design. In the Rust build `rlm_children.rs` says 'this redesign gives every child its own supervised worker process', and `context_tree_children.rs` says 'daemon children live in separate worker processes'. The blog agrees a subagent is 'a full session with its own model, IPython kernel'. Effect: a busy tree shows several `prime-agent worker` processes, and each has its own kernel. Child transcripts sit in `<agent-dir>/session-artifacts/<parent-id>/sub-<id>/`, outside the sessions glob, so map a child worker through its descriptor `sessionFile`. Row label, source and notes fixed.
- **`--mode text` is not always a one-shot.** `AppMode::resolve` makes only daemon, rpc, acp and json explicit; `--mode text` on a terminal without `-p` is the interactive TUI. The TUI veto on `--mode` hides that rare form. Label corrected; the veto stays because it is what keeps the acp, rpc and daemon surfaces apart.

### Repaired (false positive found)

The worker surface (`args_contain: worker`, substring) had no subcommand vetoes. Synthetic runs before the fix: `prime-agent send worker-1 hello`, `schedule add worker "0 9 * * 1-5" -- x` (the vendor's own help example), `stop worker-1`, `rename a worker`, `session export worker`, `package install worker-skill` and `help worker` were each filed as a `daemon` worker (score 2), and `attach worker-1` was filed as a worker instead of a TUI. Fix: the worker surface now carries the same subcommand, removed-name and info-flag vetoes as the TUI, plus `agents`, `attach` and `help`. A real worker has argv exactly `worker`, so nothing genuine is lost. After the fix all of these match nothing (or only the TUI for `attach`), and `worker`, `--mode daemon --daemon-socket <s>`, `--mode acp` and `--mode rpc` still land on their own surfaces. `node ... --mode acp` and a binary named `prime` match nothing.

### Unsupported or withdrawn

- 'The TypeScript predecessor used the same command name and argv shapes, so the row matches both.' The command name and store are shared, but nothing shows the TS process's argv[0]. Its `package.json` points at `dist/index.js` and has a `bun build --compile` script; the installer notes mention an npm package and a standalone node. An npm run would be `node`, which this row cannot match. Withdrawn from the label, and the row no longer claims it.
- The three-line 'TS hooks' description in `hooks.config` rests on the TS docs at 36307ca only; the docs say the extension paths, the code was not read. Left as documented-from-docs.

### Left as known limits (not repairable under the schema)

- A single prompt argument that contains the substring `worker` (`prime-agent "fix the worker pool"`) still matches the worker surface as well as the TUI, and the worker wins on score. The schema has no argc test.
- `--export=<file>` and `--list-models=<x>` equals forms are not vetoed by exact match, so those short runs read as TUI sessions.
- `-p` and piped-stdin runs match the TUI surface but run in-process, so the thin-client note does not apply to them. Only CPU shows them.
- Still unmeasured, because nothing is installed: real `ps` command lines, the 3 percent CPU floor, worker idle versus turn CPU, macOS socket paths. `working_signals[0]` (`socket_activity`) needs `prime-agent list --json`, which the probe cannot call.
- Not read: whether a later release adds approvals or hooks; the row is stated for v0.9.8 and the project ships several releases a week.
