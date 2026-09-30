# Deep Agents Code (`deepagents`): evidence notes (2026-09-30)

Row: `registry/agents/deepagents.json`. Validator: ok. Confidence `documented`. Nothing was run: no dcode on this Mac (`which dcode deepagents-code deepagents` prints nothing, no `~/.deepagents`, no matching process, no app bundle). Every claim is from vendor docs, public source, or wheels downloaded to the scratchpad and unzipped (never installed).

## What I checked

- Source: shallow clone of `github.com/langchain-ai/deepagents` at `c9b2ce1` (2026-09-30). Read `libs/code` (`ARCHITECTURE.md`, `HOOKS.md`, `THREAT_MODEL.md`, `pyproject.toml`, `scripts/install.sh`, `main.py` arg parser, `client/launch/server.py` and `server_manager.py`, `sessions.py`, `_paths.py`, `event_bus.py`, `app.py` spinner code, `tui/textual_adapter.py`, `hooks/*`, `offload_api.py`), `libs/deepagents` (`backends/local_shell.py`), `libs/talon`, `libs/acp`.
- Docs at docs.langchain.com: `/oss/deepagents/code/overview`, `quickstart`, `configuration`, `hooks` (the `.md` forms).
- PyPI JSON and wheels: `deepagents-code` 0.1.79, `deepagents-cli` 0.0.59, 0.2.2, 0.3.0, `deepagents` 0.7.20, `deepagents-talon` 0.0.8, `langgraph-sdk` (ThreadStatus), `langgraph-api` 0.15.1 (OTel config), `langgraph-checkpoint-sqlite` 3.1.1 (WAL).
- Local: a stand-in script with a uv-tool shebang, run from the scratchpad, to see what `ps` shows for a uv console script (below). Then `agents_probe.matches()` on 18 synthetic command lines against the row and all other rows.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| What "deepagents" is | Three things. The SDK `deepagents` (library, no process). The coding agent Deep Agents Code, command `dcode`, package `deepagents-code`. The experimental host `deepagents-talon`. The catalog's "CLI" is dcode | `libs/code/pyproject.toml`, `libs/talon` |
| Process names | A Python console script, so `ps` shows `<venv python> <script>`. uv/pipx install: `~/.local/share/uv/tools/deepagents-code/bin/python /Users/<u>/.local/bin/dcode [args]`. No retitle | docs `dcode doctor` sample path, `install.sh`, stand-in observation |
| Executable paths | `~/.local/share/uv/tools/deepagents-code/bin/python` (interpreter) and `~/.local/bin/dcode` / `deepagents-code` (symlink into the tool venv). Row matches `/deepagents-code/bin/python` in argv[0] | docs, source |
| Bundle ids | None. No app, no cask found, install is `curl -LsSf https://langch.in/dcode \| bash` (uv tool) | README, overview docs |
| Surfaces | TUI client; headless one-shot (`-n`, `--non-interactive`, stdin); agent-server child; `--acp` stdio server; Talon host; legacy `deepagents-cli` 0.0.x TUI | `main.py`, `server.py` |
| Process to session | `-r` / `--resume` `[ID]` gives the thread id; a fresh session has none in argv (UUID7 made in-process). Hook payload `session_id` is the thread id. No pid-to-thread file found. Opt-in `$TMPDIR/deepagents/events-<pid>.sock` (`DEEPAGENTS_CODE_EXTERNAL_EVENT_SOCKET`) is keyed by pid but is ingress only | `main.py`, `sessions.py`, `event_bus.py` |
| Store | `~/.deepagents/.state/sessions.db`, SQLite, LangGraph checkpoints of every thread in one file, WAL. Documented. `DEEPAGENTS_HOME` moves it. Also `history.jsonl` (input history) and, only when hooks run, `~/.deepagents/transcripts/<thread>.jsonl` | docs configuration, `_paths.py`, `hooks/transcript.py` |
| Turn in progress | Best: thread `status == "busy"` from the agent server's unauthenticated loopback API (source-level). Then a direct `sh -c` child of the server process. Then WAL mtime (raise only), then CPU | see below |
| Waiting on the human | Hooks `PermissionRequest` and `Notification` (`permission_prompt`, `agent_needs_input`). Or thread status `interrupted` from the server | `HOOKS.md`, `projection.py`, `textual_adapter.py` |
| Hooks | Yes, 12 events, `~/.deepagents/hooks.json`, project file after trust, plugin file. JSON on stdin, exit 2 blocks | docs hooks page |
| OpenTelemetry | No first-party OTel. LangSmith tracing is the documented path. The server child would auto-enable OTel if `OTEL_EXPORTER_OTLP_ENDPOINT` is in the shell environment (inferred) | `langgraph_api/config`, `server.py` |

## How a session is shaped (diagram)

```
 dcode TUI (python <venv>/bin/python .../bin/dcode -r <id>)      <- client: Textual UI, approvals, hooks for client events
   |  HTTP + SSE on 127.0.0.1:<ephemeral>, no auth
   v
 python -m langgraph_cli dev --port N --config /var/.../deepagents_server_XXXX/langgraph.json   <- server: model calls, tools, MCP
   |-- /bin/sh -c "<command>"        (shell tool, only while a command runs)
   |-- MCP stdio servers             (permanent, not shells)
   '-- sessions.db (+ -wal)          (~/.deepagents/.state, shared by all threads)
```

One server per client, torn down when the client exits. `dcode -n` starts the same server. `dcode --acp` has no server child.

## Contradicts common belief

- The name. `deepagents` is not the coding CLI any more. The old `deepagents-cli` package (commands `deepagents`, `deepagents-cli`) was the Textual TUI up to 0.0.59 (2026-05-12); from 0.1.0 it is deploy tooling and PyPI marks it deprecated in favour of `managed-deepagents` (`mda`). The coding agent was forked to `deepagents-code` (`dcode`). A detector keyed on a `deepagents` binary finds nothing on a fresh install.
- There is no wrapper binary. `ps` shows the venv's `python`, not `dcode`. A name match on `dcode` never fires; only argv[1] or the venv path carries it. A renamed shim (the vendor's documented per-worktree pattern) hides even that.
- The TUI is not where the work happens. Model calls, shell tools and MCP servers run in a second process, `python -m langgraph_cli dev`, a child of the TUI. Tool children on the TUI are always absent; that is the wrong place to look. In `-n` runs the server child is the only visible process (the short `-n` cannot be matched positively).
- No sleep inhibitor. Unlike Claude Code and Mastra Code there is no `caffeinate` child and no power assertion (grep of `libs/code`, `libs/deepagents`, `libs/acp`, `libs/talon`). The TUI emits OSC 9;4 progress instead (on by default), which `ps` cannot see.
- The server API is open. The vendor's own threat model says the loopback API has no authentication and any local process can read thread state. That makes an exact `busy` / `interrupted` read possible without a hook, which few harnesses offer. It is also the vendor's stated weak point, so it may be locked down.
- Sessions are not per-file. One SQLite file holds every thread of every project, so no transcript can be mapped from a pid, and a fresh WAL mtime says only that some dcode process wrote.
- `Notification` is a real wait signal here (`permission_prompt`, `agent_needs_input`), but its `idle_prompt` type is declared and never emitted. `agent_completed` is emitted, and marks the end of a turn.
- Hooks are split by owner: `PermissionRequest`, `Notification`, `SessionStart`, `UserPromptSubmit`, `SessionEnd` run in the client; `PreToolUse`, `Stop`, and the rest run in the server. A `Stop` hook can block and continue the turn (cap of eight continuations), so `Stop` is not always the end.

## Match limits (what the probe test showed)

Tested with `agents_probe.matches()` on synthetic lines shaped like the stand-in observation. As intended:

- uv/pipx TUI (with and without `-r <id>`, and via `deepagents-code`), the server child, `--non-interactive`, `--acp`, Homebrew/pip python with `/bin/dcode`, `uvx` cache path, legacy `deepagents`, Talon: matched to the right surface. `-r` yields the id.
- Not matched: `threads list`, `--version`, `config get`, a user's own `langgraph dev`, an unrelated python script, `deepagents deploy` (legacy deploy tool).
- Stolen from another row: no other row in registry/agents matched any of the cases.
- Known holes: `dcode -n ...` (short flag) shows only as its server child; a renamed shim; `python -m deepagents_code`; `exclude_args` is an exact match on any word, so a prompt equal to `config` or `update` hides a real session; a `dcode -r` with no id followed by a flag word is read as an id.

## Could not determine

- A real `ps` of dcode. The argv shape rests on a stand-in script using another uv tool's interpreter (`claude-swap`), not on dcode. `sys.executable` staying at the venv path (not the resolved managed python) is assumed from how venvs work.
- Whether `POST /threads/search` on a live dcode server returns `busy` during a turn and `interrupted` at an approval. The vendor's own `offload_api` depends on both statuses, and the SDK type lists them, but I did not call it. The dev server keeps thread rows in memory and registers them separately from checkpoints, so a thread row may be missing right after launch.
- The CPU floor (3 is a guess) and whether the Textual spinner burns measurable CPU.
- Whether the WAL mtime moves during a long model stream. Checkpoints are written per graph step, so expect it not to.
- OTel: whether `OTEL_EXPORTER_OTLP_ENDPOINT` really starts export inside the `langgraph dev` (in-memory) server, and whether the resolved langgraph-api at install time matches 0.15.1.
- Talon: only the README and entry point were read. No turn signal is known for it.
- Legacy 0.0.59: read from the wheel only (same server prefix, same state dir, same `hooks.json`); its exact subcommand and flag set was not compared with the current one beyond `help agents threads update`.
- Older installs of `deepagents-cli` from before the `.state` move (`state_migration.py` moves `sessions.db*` into `.state`) may still keep `~/.deepagents/sessions.db`.
- The `managed-deepagents` / `mda` CLI (0.8.3) is a deploy tool and was not studied.
- "Grok Bot" from the user's request is not part of this task's two files.

## Verification

Independent refutation pass, 2026-09-30. Validator after repair: `ok`. Confidence stays `documented` (the harness is not installed here: `which dcode deepagents-code deepagents` prints nothing, no `~/.deepagents`, no matching process). I re-cloned `langchain-ai/deepagents` (`c9b2ce1`), re-fetched the docs pages, and downloaded the PyPI wheels for `deepagents-cli` 0.0.59, 0.1.0, 0.3.0, `langgraph-api` 0.15.1, `langgraph-checkpoint-sqlite` 3.1.1 and `langgraph-sdk` into the scratchpad (unzipped, never installed). Then I ran `agents_probe.matches()` on about 40 synthetic command lines against all rows.

### Identity and packaging

- Coding agent is `deepagents-code`, scripts `dcode` and `deepagents-code`, 0.1.79 uploaded 2026-09-29, Python >=3.12,<4.0: confirmed (`libs/code/pyproject.toml`, PyPI JSON).
- `deepagents-cli` forked away at 0.1.0 (2026-05-12), 0.3.0 is "DEPRECATED: Deployment tooling", 0.0.59 (2026-05-12) is the last TUI, 0.1.0 wheel has no `app.py`: confirmed (CHANGELOG line 1324, wheels).
- SDK `deepagents` 0.7.20, `deepagents-talon` 0.0.8 (2026-09-11): confirmed (PyPI).
- Install `curl -LsSf https://langch.in/dcode | bash`, uv tool: confirmed (`install.sh` header, README, quickstart docs).
- Doctor sample path `/Users/naomi/.local/share/uv/tools/deepagents-code`: confirmed (configuration docs).

### Process shape

- uv tool console script shows as `<venv>/bin/python <script> [args]`, no retitle: confirmed for uv-managed Python (stand-in run, `ps` printed the claude-swap venv python plus `./shim2/dcode -r 0193abcd`; `grep -rniE 'setproctitle|process_title|prctl'` prints nothing).
- **Corrected.** The same argv shape does NOT hold for a framework Python (Homebrew, python.org). Local test: `/opt/homebrew/bin/python3.14 -c ... bin/dcode`, and a venv named `deepagents-code` made with that interpreter, both show `ps` argv[0] as `.../Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python`. So `/deepagents-code/bin/python` cannot match a pipx or uv-tool install built on such an interpreter, and the base name is `Python`, which the name lists did not contain. The earlier "Homebrew python matched" probe test used a fake argv[0] of `/opt/homebrew/bin/python3.12` that real `ps` never shows. Repair: name `Python` added to the script-path, alias, server and Talon surfaces; two new surfaces (`--non-interactive`, `--acp`) keyed on argv[1] script path plus flag for framework Python. Not repaired: legacy `deepagents-cli` under a framework Python (path rule only).
- Server child `<sys.executable> -m langgraph_cli dev --host --port --no-browser --no-reload --config <tmp>/deepagents_server_*/langgraph.json`, Popen with `start_new_session`: confirmed (`server.py` `_build_server_cmd`, `_spawn`; `server_manager.py` `mkdtemp(prefix='deepagents_server_')`).
- `-n` short run is invisible on TUI surfaces and seen through its server child: confirmed by simulation (`-n` matches nothing; server line matches the daemon surface). Under a framework Python it now also matches through the daemon `Python` name.
- Exact-argument vetoes: flags `-h --help -v --version --update --install --uninstall --acp -n --non-interactive` and subcommands help, agents, skills, plugin(s), mcp, threads, update, doctor, tools, install, uninstall, config, auth: confirmed in `main.py` (`add_parser`, `_HELP_SPECS`, dispatch at 5325-6220). No unlisted top-level subcommand found.
- False positives: a user's own `langgraph dev` does not match; `python -m pytest`, plain scripts and a framework `Python` running an unrelated script do not match; no other registry row matches any dcode line. Two dcode-owned helpers do match the venv-path surface with no veto: the post-update re-exec `<venv python> -m deepagents_code ...` (same session, harmless) and the legacy-hook adapter `<venv python> -m deepagents_code.hooks.migration ...` (`hooks/migration.py:113`). The probe drops the adapter because its parent matches the same row. Any other tool's console script installed into the same venv would also match; accepted.
- Legacy `deepagents-cli` surface: **corrected**. 0.0.59 also has `skills` and `mcp` subcommands and `--update` (`main.py` `_HELP_SPECS`, line 919), which were not vetoed; a `deepagents skills list` would have read as an idle TUI. Added `skills`, `mcp`, `--update`. 0.3.0 has only init, deploy, agents, mcp-servers, all vetoed already.
- Talon: confirmed as a separate experimental host (`libs/talon/README.md`, script `deepagents-talon`). **Corrected**: its state is `~/.deepagents/<assistant_id>/checkpoints.sqlite`, not the dcode `sessions.db`; label updated. Unsupported: any turn signal for Talon (none claimed).

### Session store and thread mapping

- `~/.deepagents/.state/sessions.db`, SQLite, documented: confirmed (docs table "Sessions | ~/.deepagents/.state/sessions.db | SQLite checkpoint database"; `_paths.py` `sessions_file`).
- WAL mode: confirmed (`langgraph_checkpoint_sqlite-3.1.1` `aio.py:318` and `__init__.py:141` `PRAGMA journal_mode=WAL`; lock pins 3.1.1; dcode uses `AsyncSqliteSaver`, `sessions.py:1681`).
- `-r/--resume [ID]`, fresh thread id is an in-process UUID7: confirmed. **Corrected**: the id in argv is only the launch thread. `/clear` and `/threads` mint or switch the thread inside the same process (`app.py` 6210, 6224, 6246, 6286), so a session mapped by argv can go stale. Recorded in notes.
- Hook transcripts under `~/.deepagents/transcripts` only when hooks run: confirmed (hooks docs, `hooks/transcript.py`).

### Working signals

- No sleep inhibitor: confirmed (grep over `libs/code`, `libs/deepagents`, `libs/acp`, `libs/talon` prints nothing for caffeinate, IOPMAssertion, pmset, prevent-sleep).
- Shell tool is `subprocess.run(command, shell=True)` inside the server: confirmed (`local_shell.py:304`, `agent.py` `LocalShellBackend`, `server_graph.py` `MCPSessionManager`). Local-context detection also runs a short bash in the server (`local_context.py`).
- `tool_children` on the server surface: claim is true but **corrected for the probe**. `agents_probe.py` skips any process whose parent matches a surface of the same row, so while the TUI lives the server is never classified and the TUI's only direct child is the server python, not a shell. Under today's probe a TUI session is decided by `tree_cpu` alone. Caveat added to the signal.
- `socket_activity`: `ThreadStatus = idle|busy|interrupted|error` and `POST /threads/search` with `status` and `select` confirmed in `langgraph_sdk` (`schema.py:34`, `_async/threads.py` payload keys). The server is unauthenticated: confirmed (`THREAT_MODEL.md` TB10 text, `_build_server_env` sets `LANGGRAPH_AUTH_TYPE=noop`). **Corrected wording**: `offload_api` allows `idle` and `error` (`_OFFLOADABLE_THREAD_STATUSES`), not only idle; the source entry now says so. Still not exercised: no live server was queried.
- `tree_cpu` floor 3 and the spinner: unsupported as measured (already labelled inferred). OSC 9;4 progress on by default: confirmed (`app.py` 10885-10905, `_env_vars.py:651`).
- `transcript_write` on the WAL mtime: consistent with the source (per-step checkpoints); not measured.

### Waiting signals and hooks

- Hook config paths, trust flag, plugin hooks, client or server ownership: confirmed (docs hooks page, `HOOKS.md`).
- Event count: **corrected**. The public docs page tables 11 events; `HOOKS.md` and the `HookEvent` enum list 12 (`PostToolUseFailure`, emitted in `server_middleware.py`). Row keeps 12, source claim now says where each count comes from.
- `Notification` types: confirmed. `permission_prompt`, `agent_needs_input`, `agent_completed` are emitted (`textual_adapter.py` 3387, 3707, 4088; `non_interactive.py` 1864, 2425); `idle_prompt` is declared with no emitter.
- `PermissionRequest` meaning: **corrected**. The row said auto-approve runs do not fire it. In `textual_adapter.py` 3594-3620 the YOLO shortcut applies only when no PermissionRequest handler exists, so with a handler installed the event fires under auto-approve, and a handler can approve or deny by itself (`plan.fully_resolved`) with no dialog. The reliable wait edge is `Notification` `permission_prompt`, emitted after both paths. Row text rewritten.
- `interrupted` thread status as a wait: source-level, not exercised; also true for a cancelled run (row already says so).

### Telemetry

- LangSmith is the documented tracing path (`DEEPAGENTS_CODE_LANGSMITH_PROJECT`, `/auth`): confirmed (quickstart docs).
- langgraph-api 0.15.1 auto-enables `OTEL_ENABLED` on `OTEL_EXPORTER_OTLP_ENDPOINT` or `_TRACES_ENDPOINT`: confirmed (`langgraph_api/config/__init__.py` 587-592), and the server env is a copy of `os.environ` with only a small denylist. Whether the in-memory dev server then exports is unobserved. **Corrected**: `telemetry.otel` changed from true to false; dcode has no OTel code (grep prints nothing) and no vendor doc claims it. The dependency behaviour stays in `how` as unverified.

### Unsupported or still open

- No real `ps` of dcode, no live server call, no CPU measurement, no WAL timing. Everything above marked "confirmed" is vendor docs, vendor source or PyPI artefacts, plus the two local stand-in observations.
- Whether a `uv tool` install ever selects a framework Python by default is not established (uv prefers managed Python); the fix is defensive for pipx and pip venvs on Homebrew Python, which is common.
- `python3.15` and later interpreter names are not in the name lists.
- The user's request also asked for "Grok Bot"; that harness is outside this row and these two files.
