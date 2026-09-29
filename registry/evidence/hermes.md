# Hermes Agent: evidence notes (2026-09-29)

Row: `registry/agents/hermes.json`. Validator: ok. Probe on this Mac: 0 Hermes processes, nothing classified live. Confidence is `documented`, not `verified-locally`.

## What I checked

- Not installed here: `which hermes hermes-acp` not found, no `~/.hermes`, no `~/Library/Application Support/Hermes`, nothing in `/Applications`, 0 matching processes. So no `--version`, `--help`, `strings` or `lsof` were possible.
- Source: shallow `git clone --depth 1` of `NousResearch/hermes-agent` into the session scratchpad (outside the repo, not installed, nothing run). Commit `6ffe3b2` dated 2026-09-29. Raw GitHub was rate limited, so a clone was the way to read files. Read: `AGENTS.md`, `tui_gateway/AGENTS.md`, `apps/desktop/AGENTS.md`, `hermes_cli/{main,_launchers,main_tui_launch,gateway_launchd,process_identity,plugins,_parser}.py`, `hermes_state*.py`, `agent/turn_facade*.py`, `gateway/status.py`, `apps/desktop/{product-identity.cjs,electron-builder.config.cjs,electron/*}`, `scripts/build/launchers.py`, `agent/monitoring/otlp_exporter.py`.
- Docs (all returned 200): `hermes-agent.nousresearch.com/docs/` pages for hooks, session-storage, gateway-monitoring, desktop, sessions, tui. Same text as `website/docs/` in the clone.
- Synthetic matcher test: I fed made-up `ps` argv strings through `matches()` from `tools/agents_probe.py`. Results: CLI/TUI, gateway, serve, ACP and Desktop main hit the intended surface; the `tui_gateway` child, Electron helpers and an unrelated python hit nothing. These lines are constructed from the source, not observed.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | CLI (classic prompt_toolkit), TUI (`--tui`), Electron Desktop, messaging gateway daemon, ACP server for editors, web dashboard (embeds the TUI over a PTY). One agent core, one state.db | AGENTS.md, tui_gateway/AGENTS.md |
| Process name | Not `hermes`. The `hermes` command is `#!/bin/sh` + `exec <store python3> -I -c <bootstrap>`; after exec ps shows python. `setproctitle` would rename it but is not a dependency; the macOS fallback `pthread_setname_np` is invisible to ps (the code says so) | `_launchers.py`, `main.py::_set_process_title` |
| Executable path | `~/.hermes/tools/<...>/bin/python3` (source install), or the Python inside `Hermes.app/Contents/Resources/agent-payload` (`-P -c`). Commands `hermes`, `hermes-agent`, `hermes-acp` in `~/.local/bin` (symlinks into the app payload on macOS bundles) | `_launchers.py`, `scripts/build/launchers.py` |
| Bundle ids | `com.nousresearch.hermes`, `-bundled`, `-light`, each with `-canary`; commit builds append `-<sha7>` | `product-identity.cjs` |
| Process to session | Only resumed sessions carry an id on argv (`--resume`/`-r`, may be a title). Fresh sessions: none. Reliable route is the lease holder `pid=` (below). TUI also has env `HERMES_TUI_ACTIVE_SESSION_FILE` pointing at a temp file `{session_id}` | `_parser.py`, `main_tui_launch.py` |
| Store | `~/.hermes/state.db`, SQLite WAL, one per profile home (`~/.hermes/profiles/<p>/state.db`), documented. Not JSONL | session-storage doc |
| Turn in progress | Best: row in `session_turn_leases` with `expires_at > now` and live holder pid. Gateway: `gateway_state.json` `active_agents > 0`. Weak: WAL mtime, tree CPU | source, see below |
| Waiting on human | Only approval prompts have observer hooks (`pre_approval_request` / `post_approval_response`). Nothing for clarify, sudo, secret | `VALID_HOOKS`, hooks doc |
| Hooks | Four systems: shell (`hooks:` in config.yaml), Python plugin, gateway-only dir, signed outbound webhook. Row lists config paths and events | hooks doc |
| OpenTelemetry | Yes but narrow: opt-in OTLP/HTTP for gateway and cron health, content-free, `config.yaml` keys | gateway-monitoring doc |

### The lease, in detail

`agent/turn_facade.py::run_conversation` calls `admit_durable_turn_lease` first and releases in `finally`. Row: `conversation_id` (lineage root session id), `holder` = `pid=<pid>:turn=<session>:<task>:<hex>:platform=<p>`, `acquired_at`, `expires_at`. TTL 300 s, refresher every 60 s. It exists for exactly the length of one turn, in every surface (CLI, TUI, Desktop, gateway, cron, ACP, subagents). A read-only query of that one table exposes no message content. Caveats: a killed holder leaves the row until expiry, so check the pid; turns may run in a compute-host child pid; the refresher keeps renewing while the turn is blocked on approval.

## Could not determine

- Real `ps` output on macOS. Whether the multi-line `-c` argument renders with spaces, `?` or newlines is unknown. The row matches on the substring `hermes_cli.main`, which survives any of those, but nobody has looked.
- CPU floor for `tree_cpu`. 5 percent is a guess with no idle/streaming measurement.
- Which app name ships on macOS: the code disagrees with itself (see below). Both are listed.
- Whether a fresh Hermes tree keeps long-lived children while idle (MCP servers, a slash-command worker, browser drivers are all documented as possible). I left `child_process` and `tool_children` out for that reason but have not seen it.
- Whether the lease query works from outside without side effects on a live WAL database (a `mode=ro` open needs the `-shm` file). Hermes itself opens read-only this way; I did not try it.
- Real process shape of Desktop's `hermes serve` (child of Electron or attached, single or several per profile). Docs say one per host, multiplexing profiles.
- Exact name/path of the dashboard-only process (`hermes dashboard`) beyond the argv `dashboard`; not given its own surface.
- `hermes acp` as a subcommand: matched by argv `hermes_cli.main` + `acp`, not confirmed to stay in-process.

## Contradicts common belief or the hint

- The hint says "CLI, ~/.hermes/state.db". True but small. There are six surfaces, and the CLI is not the busiest one: Desktop runs its own headless `hermes serve`, it does not embed the TUI.
- The process is not called `hermes` on macOS. It is a python interpreter with an inline script. A name filter on `hermes` finds nothing unless `setproctitle` was added by hand.
- No sleep assertion per turn, unlike Claude Code's `caffeinate`. Desktop has a keep-awake setting, default off, unrelated to turns. Docs tell operators to run `caffeinate` on a gateway host themselves. Do not use `power_assertion`.
- `tool_children` and `child_process` are unusable. A TUI session always has a node child and a tui_gateway grandchild while idle.
- state.db is one shared database, not per-session files, so the schema's `per_session` path cannot exist and `transcript_write` cannot be evaluated per session by the probe. Any process writing any session moves the WAL mtime.
- The most precise "working" signal is a DB row, and the schema's `signal` enum has no kind for it. I put it in a non-schema key `x_precise_working_signal` and suggest adding `sqlite_row`. The validator ignores the key.
- `on_session_end` is a per-turn event, not a session-close event. `post_llm_call` skips failed and interrupted turns. Hook names look Claude-Code-like (shell hooks accept `{decision: block}` and exit 2) but there are no `Stop`, `Notification`, or `SessionEnd` events by those names.
- Approval hooks are observers only and cover only dangerous-command approvals. A `clarify` question blocks the turn with no hook and no on-disk trace.
- "Exports OpenTelemetry" is true only for the gateway and cron, opt-in, by `config.yaml`, with an optional extra. No `OTEL_*` variables are read, and an interactive CLI/TUI/Desktop turn is never exported. Rich traces go through observer hooks, a Langfuse plugin or NeMo Relay instead.
- App naming is inconsistent inside the repo: installer docs and the updater code say `Hermes.app` / `com.nousresearch.hermes`; `product-identity.cjs` names the bundled variant (which the release workflow builds) `Hermes Agent` / `com.nousresearch.hermes-bundled`. Only an installed copy can settle it.
- Probe limits found while testing: it splits `ps` on spaces, so a path such as `Hermes Agent.app/Contents/MacOS/Hermes Agent` cannot match, and first-match-wins means surface order in the row matters.
- The launchd gateway is wrapped: `osascript` (kept alive on purpose for macOS Local Network privacy) -> `sh` -> python `hermes_cli.stderr_timestamp` -> python `gateway run`. The probe keeps the outermost matching python, which is the wrapper.

## Verification

Adversarial pass, 2026-09-29, by a second reader who did not write the row. Method: `tools/validate_row.py` (ok before and after), re-reading every cited file at commit `6ffe3b2` in the existing scratchpad clone, re-fetching the five docs pages (all HTTP 200, text searched), an in-memory SQLite test of the lease query, and running `matches()` from `tools/agents_probe.py` over constructed argv (built from the launcher script text in `hermes_cli/_launchers.py`). Hermes is not installed here (`which hermes hermes-acp` not found, no `~/.hermes`, no `~/Library/Application Support/Hermes`, nothing in `/Applications`, 0 matching processes), so nothing is `verified-locally`; the ceiling is `documented`, and the row stays there. Nothing observed on a real Hermes process.

### Claims (in the order of `sources`)

| # | Claim | Result |
|---|---|---|
| 1 | Six surfaces, one agent core, one state.db | Confirmed. `AGENTS.md` (What Hermes Is, Project Structure), `tui_gateway/AGENTS.md` (Node Ink -> stdio JSON-RPC -> Python tui_gateway), directories `acp_adapter`, `gateway`, `apps/desktop`, `ui-tui`, `hermes_cli/web_server.py` all exist. |
| 2 | SQLite `~/.hermes/state.db`, WAL, per-profile state.db, replaced JSONL | Confirmed by the docs page text. Docs add: default root is `~/.hermes` on macOS/Linux, `HERMES_HOME` overrides. |
| 3 | JSONL only as emergency spill | Confirmed. `hermes_state.py:421 divert_session_transcript_jsonl` appends to `HERMES_HOME/sessions/<id>.jsonl`. That file holds message content: never read it. |
| 4 | Lease table, TTL 300 s, refresh 60 s, holder format | Confirmed. Schema at `hermes_state_common.py:555`, `LEASE_TTL_SECONDS = 300.0`, refresh default 60.0, release in `release_session_turn_lease`. Holder is `pid=<pid>:turn=<relay_turn_id>:platform=<p>` and `relay_turn_id` = `<session_id>:<task_id>:<uuid hex[:8]>` (`turn_facade.py:64`), so `x_precise_working_signal.holder_format` is right. Platform falls back to `unknown`. |
| 5 | Lease renewal is no proof of progress; stalled turn renews forever | Corrected. The docstring says so, but a liveness watchdog (`agent.turn_liveness.timeout_s`, default 600 s, `<= 0` disables) aborts an inactive turn and stops the refresher. Worst case the row reads "working" about 600 s into a wedge plus up to 300 s of TTL. Dead-pid reclaim only on proof: confirmed (`_compression_lock_holder_process_is_dead`, psutil or `os.kill(pid, 0)`; recycled pids read as alive). |
| 6 | ps shows the interpreter, not `hermes`; setproctitle not a dependency | Confirmed. `_set_process_title` docstring says macOS `pthread_setname_np` is "lldb/top only, not ps aux"; `grep -rn setproctitle` over the clone finds only `hermes_cli/main.py`, none in `pyproject.toml`, `pm/`, `uv.lock`. |
| 7 | Launchers `-I -c` (source) and `-P -c` (bundle), store python, `~/.local/bin` symlinks | Confirmed (`_launchers.py` `_write_shell`, `scripts/build/launchers.py` last line `exec "$PYTHON" -P -c`, `_symlink_sealed_launchers`). Store python is `<default root>/tools/bin/python3` only by default; an install stamp `runtimeDir` or `HERMES_RUNTIME_DIR` moves it. |
| 8 | Hermes' own process matcher | Confirmed (`hermes_state_holders.py` lines 36-38, 127-141). |
| 9 | TUI process tree and active-session file | Confirmed (`main_tui_launch.py` `--expose-gc` argv, `subprocess.call`, `HERMES_TUI_ACTIVE_SESSION_FILE`, `hermes-tui-active-session-` prefix; `gatewayClient.ts:455` spawn; `writeActiveSessionFile`). |
| 10 | `--resume/-r` and `--continue/-c` | Confirmed (`_parser.py` 175-190). `--resume` also accepts `latest`; both may be a title, not an id. |
| 11 | Desktop backend `hermes serve --host 127.0.0.1 --port 0`, spawn ledger | Confirmed (`backend-command.ts serveBackendArgs`, `process_identity.py` `LEDGER_FILENAME = "spawn-ledger.json"`, `REAPABLE_PURPOSES`, `cli.py:1747 register_self("cli")`, `gateway/run.py:6033`). Ledger entries also carry `isolated` (an SSH backend that must not be adopted). |
| 12 | Bundle ids | Confirmed by formula in `product-identity.cjs`: `com.nousresearch.<hermes\|hermes-light\|hermes-bundled>[-canary\|-<sha7>]`; bundled workflow sets `HERMES_DESKTOP_VARIANT: bundled` (lines 444, 852). The `-light-canary` and `-bundled-canary` ids are derived, not seen in a build. |
| 13 | `/Applications/Hermes.app`, executable `Hermes`, contradiction with `Hermes Agent` | Confirmed as a contradiction, not resolved. `main_desktop.py` launches `/Applications/Hermes.app/Contents/MacOS/Hermes`; GitHub issue 125245 logs "Installed the rebuilt Desktop app at /Applications/Hermes.app". `electron-builder.config.cjs` sets `CFBundleExecutable` to the display name, so the bundled variant is `Hermes Agent.app/.../Hermes Agent`. Only an installed copy settles which ships. |
| 14 | No per-turn power assertion | Confirmed. Only `powerSaveBlocker` behind a user setting (default false); the one other `caffeinate` hit is a settings search keyword; docs tell operators to run `caffeinate` themselves. |
| 15 | Gateway launchd job, osascript wrapper | Confirmed (`gateway_launchd.py get_launchd_label`, `launchd_program_arguments`, `_timestamped_stderr_gateway_command`; `gateway.py get_launchd_plist_path`). |
| 16 | gateway_state.json, `active_agents`, stale after 120 s | Corrected. Source confirms the file name, `_RUNTIME_STATUS_STALE_TTL_S = 120`, `derive_gateway_busy`. The cited docs page defines `active_agents` but never mentions `gateway_state.json` or 120 s, so those are source-only. Also `derive_gateway_busy` treats a stale heartbeat as a health warning, not death. The source entry was rewritten. |
| 17 | Four hook systems, config paths, consent file | Confirmed against the hooks docs page ("Hermes has four hook systems", `~/.hermes/shell-hooks-allowlist.json`, `--accept-hooks`, `HERMES_ACCEPT_HOOKS=1`, `hooks_auto_accept`). |
| 18 | Hook event list, per-turn `on_session_end` | Confirmed. Every listed plugin event is in `VALID_HOOKS`; the gateway names are in `gateway/hooks.py`; docs say `on_session_end` fires "canonically at each turn finalization". Also confirmed: exit code 2 blocks `pre_tool_call`, and `{"decision":"block"}` is accepted. |
| 19 | Approval/clarify/sudo/secret are blocking server-to-client requests | Confirmed (`tui_gateway/AGENTS.md` line 22, 83). |
| 20 | OTLP narrow, opt-in, no `OTEL_*` | Confirmed. Docs and `pyproject.toml` extra `otlp` (`opentelemetry-sdk==1.39.1`); grep for `OTEL_` outside tests and locales finds nothing. |
| 21 | Not installed here | Confirmed again with the same commands (0 hits). |
| - | `session_store.note`: read only `session_turn_leases`, `gateway_heartbeats`, sessions metadata | Confirmed that `gateway_heartbeats` exists (`backend_id, pid, started_at, last_heartbeat, profile, host`, no content). Had no source entry; the table definition is now the evidence. |
| - | Lease query in `x_precise_working_signal` | Confirmed by test: in-memory SQLite, schema copied from `hermes_state_common.py:555`, one live and one expired row, returned only the live one. Constructed data only. |
| - | "Every surface takes a lease" (evidence file text) | Corrected. `admit_durable_turn_lease` returns without a row when the agent has no session DB or `_persist_disabled` (background review agents set it). Subagents do take rows, with `platform=subagent`. |
| - | Weak `transcript_write` signal on `state.db-wal` mtime | Unsupported by any observation (nothing to run). Follows from WAL mode plus per-round flushes in source; `last_activity_at` "about every 60 s" was not re-verified and stays a source-reading inference. The row already calls the signal weak. |
| - | `tree_cpu` floor 5 percent | Unsupported. Already labelled inferred and uncalibrated. |

### Process patterns

Test: `matches()` from `tools/agents_probe.py` on constructed argv (`<store python> -I -c <launcher script> [args]`). This is source-derived, not observed; real `ps` rendering of the multi-line `-c` argument is unknown.

| Argv | Before repair | After repair |
|---|---|---|
| `hermes`, `--tui`, `--resume x`, `chat -q hello` | tui | tui |
| `gateway run`, `serve --host ...`, `acp`, `hermes-acp` | gateway, serve, ide, ide | same |
| `python -m tui_gateway.entry` (TUI child) | none | none |
| `hermes dashboard --no-open` (legacy Desktop backend) | none, although the serve label claimed it | new dashboard surface |
| `hermes mcp serve` | serve daemon, a false positive | none |
| `chat -q "explain the server"`, `chat -q "preserve the file"` | serve daemon | serve daemon, unfixed |
| `chat -q "fix gateway bug"` | gateway daemon | gateway daemon, unfixed |
| `pytest tests/hermes_cli/test_gateway.py`, `pytest tests/acp_adapter/...` | gateway, ide | same, unfixed |

Findings:

- `hermes mcp serve` is spawned as a helper by other agents (its own docstring names Claude Code, Cursor, Codex). It was filed as a Hermes backend. Fixed: `exclude_args: ["mcp"]` on the serve surface.
- The legacy Desktop backend `-m hermes_cli.main dashboard --no-open` (`backend-command.ts dashboardFallbackArgs`) matched nothing, because the tui surface excludes `dashboard` and the serve surface needs `serve`. Fixed: added a dashboard daemon surface.
- Matching is asymmetric: `args_contain` is a substring test, `exclude_args` is an exact-token test. So any token that merely contains `gateway`, `serve`, `dashboard` or `acp_adapter` is misfiled, not just a whole word. The old note said "separate token". Note rewritten. Not fixable inside the schema; left documented.
- `path_contains` `/Hermes.app/Contents/MacOS/Hermes` would also match an unrelated macOS app named Hermes if its executable is also `Hermes` (a Pandora client, github.com/HermesApp/Hermes; its bundle and executable names are inferred, not stated on the page). Cannot be fixed by path alone; the note now says to check `com.nousresearch.*` in Info.plist.
- Canary and commit desktop builds (`Hermes Canary.app`, `Hermes <sha7>.app`) are not covered by `path_contains`, only by `bundle_ids`.
- Fallback surface `names: ["hermes"]`: unreachable in a default install (setproctitle not a dependency) and would match any other executable called hermes. Kept for hand-configured installs, flagged in notes. Not proven to collide with a real program.
- Paths with spaces (`Hermes Agent.app`, `Hermes Light.app`) cannot match in the reference probe, which splits `ps` on spaces.

### Repairs made (only `registry/agents/hermes.json` and this file)

1. Serve surface: added `exclude_args: ["mcp"]`, label corrected.
2. New dashboard daemon surface (`hermes_cli.main` + `dashboard`).
3. Source entry 5 (lease renewal) corrected for the 600 s watchdog; source entry 16 (gateway_state.json) corrected to say docs do not cover the file or the 120 s window.
4. Seven `VERIFICATION:` source entries added (lease query test, holder format and persistence-disabled agents, dashboard fallback, mcp serve, matcher results, bundle executable naming, Hermes.app name collision).
5. `notes` rewritten: substring misfiling, mcp exclusion, name collision, canary paths, wedge lag of about 15 minutes.

Confidence stays `documented`. It is not `verified-locally` (no instance to observe) and not `inferred` (the claims that matter trace to vendor source and docs I re-read). The weakest parts, all already labelled: `tree_cpu` floor, the WAL-mtime signal, real `ps` rendering of the `-c` argument, which app name ships on macOS, and whether `serve` is a child of Electron or attached.
