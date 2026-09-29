# openhands: evidence notes (2026-09-29)

Row: `registry/agents/openhands.json`. Validator: ok. Confidence `documented`. OpenHands is not installed here and nothing was running, so no surface was classified live. Versions read: Agent Canvas 1.24.0 (released 2026-09-25), OpenHands-CLI 1.16.0 (2026-05-08, last commit 2026-08-11), software-agent-sdk / openhands-agent-server 1.49.6 (main at b1b237c).

## What I checked

- docs.openhands.dev (via `llms.txt`): CLI installation, command-reference, headless, resume, gui-server, web-interface; Agent Canvas overview, setup, architecture, local backend; hooks (product and SDK); observability; persistence; local agent server; sandboxes.
- Public source, shallow clones into the scratchpad, read only, nothing built or run: `OpenHands/OpenHands` (now Agent Canvas: `electron/`, `scripts/dev-safe.mjs`, `scripts/dev-with-automation.mjs`, `config/defaults.json`, `docker/`), `OpenHands/OpenHands-CLI` (pyproject, spec, `openhands_cli/`), `OpenHands/software-agent-sdk` (`openhands-sdk` state, hooks, observability; `openhands-agent-server` lease and config; `openhands-tools` terminal).
- `install.openhands.dev/install.sh` fetched with curl and read, not run. GitHub API for release lists and assets.
- Local, read only: `which`, `ls`, `mdfind` on the bundle id, `ps`, `ls /private/tmp/tmux-501`. All empty for OpenHands.
- Matching tested with 17 made-up `ps` lines through the probe's own `matches()` and `session_id()`. Results: uv-tool CLI and PyInstaller CLI match tui; `--headless` matches the oneshot tui; `serve`, `web`, `--version` match nothing; `acp` matches ide; uvx `agent-server` and `-m openhands.agent_server` match daemon; `docker run ... --name openhands-app` matches gui; an unrelated docker run, a plain python script, a pytest run and another uv tool (`cswap`) match nothing. `--resume abc123` yields the id.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | (1) CLI `openhands` (Textual TUI), `--headless` one-shot, `acp` for editors, `web` (TUI in browser), `cloud`, `serve` (legacy Docker GUI). (2) Agent Canvas: `agent-canvas` / `npx @openhands/agent-canvas` (browser UI on :8000), Docker image, and a native Electron desktop app (preview). (3) Python Agent Server, alone (`python -m openhands.agent_server`) or under Canvas. (4) OpenHands Cloud | docs, source |
| CLI process | Two shapes. `uv tool install openhands`: argv is `<uv tools>/openhands/bin/python <~/.local/bin/openhands> ...` (argv[0] is the interpreter). PyInstaller binary `openhands` (asset `openhands-macos-arm64`) in `/usr/local/bin` or `~/.local/bin` | pyproject, spec, install.sh, local `cswap` observation of the shebang shape |
| Desktop app | `OpenHands Agent Canvas.app`, bundle id `dev.openhands.agent-canvas`, universal dmg (first dmg release v1.6.1, 2026-07-28). Main process runs the launcher in-process and spawns `uvx` agent-server, automation, node ingress and static server | electron-builder.config.mjs, electron/main.mjs |
| Agent server process | `python <uv env>/bin/agent-server --host 127.0.0.1 --port 18000 --import-modules ...`, cwd `<state>/workspaces`, one process for all conversations | dev-safe.mjs, pyproject scripts |
| Process to session | CLI: only `--resume <id>`; a fresh session has no id in argv. Agent server: no mapping in argv. Side channel: `owner_lease.json` in each conversation dir holds `owner_pid` | resume docs, conversation_lease.py |
| Store | `~/.openhands/conversations/<uuid hex>/base_state.json` plus `events/event-NNNNN-<event id>.json` (CLI, documented). Agent Canvas: `~/.openhands/agent-canvas/dev_conversations/` (npm, desktop) or `.../agent-canvas/conversations` (Docker), same layout (undocumented, from launcher source). JSON, not JSONL | resume and persistence docs, dev-safe.mjs, entrypoint.sh |
| Turn in progress | `execution_status == "running"` in `base_state.json`, set for the whole `run()` and autosaved. Not readable by the reference probe (no JSON-field signal), so the row falls back to file mtime and CPU | state.py, local_conversation.py |
| Waiting on the human | `execution_status == "waiting_for_confirmation"`. No hook for it | state.py, agent.py:1150, hooks types |
| Hooks | `hooks.json`, first of `<cwd>/.openhands/hooks.json` then `~/.openhands/hooks.json`. Six events: PreToolUse, PostToolUse, UserPromptSubmit, Stop, SessionStart, SessionEnd. Claude Code compatible format | hooks docs, hooks/config.py |
| OpenTelemetry | Yes, traces only, env-var driven, via Laminar instrumentation | observability docs, laminar.py |

## Could not determine

- Real `ps` output for any surface. The shapes come from launcher source and the shebang behaviour seen on another uv tool. In particular: whether `uvx` execs the console script (so no `uvx` parent stays) and whether the ephemeral env python is named `python` or `python3.12` in argv[0]. The row lists both names.
- Whether the PyInstaller one-file bootloader shows two identical processes on macOS. The probe keeps the outer one either way.
- CPU while streaming or idle for any surface. The 3 percent floor is a guess.
- How often `base_state.json` is rewritten during a long LLM call or tool. Source says on every public field change; I did not measure the gap, so a quiet file is not idle.
- Whether the desktop app, npm launcher and Docker image really agree on the state path for a given install. Two different paths exist in source (`dev_conversations` and `conversations`).
- Legacy `openhands serve` Docker GUI: where its conversations land on the host (the container mounts `~/.openhands` at `/.openhands`) and its agent-server image details. Nothing readable from a Mac process table.
- The `openhands web` mode: it should spawn the TUI per browser session as a child; not traced, so the row vetoes `web`.
- Whether `openhands` on this Mac would find tmux 3.6a and use it. Source says yes (auto-detect). No `openhands` socket exists in `/private/tmp/tmux-501`, consistent with never having run.
- Live behaviour of ACP under Zed or JetBrains.
- Automation Server (schedules, event triggers) was not traced; it is a separate uvx Python process.

## Contradicts common belief, the hint, or the docs

- The hint's repo `All-Hands-AI/OpenHands` is now `OpenHands/OpenHands`, and that repo is no longer the Python app server. It is the Agent Canvas web client, launcher and Electron app (`@openhands/agent-canvas`). The Python agent lives in `software-agent-sdk` (server) and `OpenHands-CLI`. Docs call `openhands serve` legacy and say it will not run if only `agent-canvas` is installed.
- There is a native macOS desktop app now (preview): bundle id `dev.openhands.agent-canvas`, not `com.openhands...` or `com.electron...`. The "local GUI" in older guides (Docker, port 3000) is a different product from it.
- Common belief: OpenHands runs the agent inside a Docker sandbox. Under Agent Canvas the default local backend is a plain host process with no isolation (docs warn about it). Only `openhands serve` and the Docker variants use containers.
- The shell tool is not a usable child-process signal. With tmux installed (tmux 3.6a is on this Mac) commands run under a dedicated tmux server on socket `openhands`, so they are not direct children of the agent. Without tmux there is a persistent `bash -i` child that exists from the first tool call until the conversation closes, so a shell-child test reads idle sessions as working. The row therefore has no `tool_children` or `child_process` signal.
- Session files are JSON, not JSONL. One `base_state.json` plus one small JSON file per event, ids are uuid hex without dashes though `--resume` accepts dashes. Older V0 guides show `trajectory.json` and `~/.openhands-state`; that is gone.
- Hooks look like Claude Code's (same events, PascalCase accepted) but there is no `Notification` event, only six. Config is `.openhands/hooks.json`, not a settings file. Project hooks replace user hooks; they do not merge.
- The CLI default confirmation policy is AlwaysConfirm, so "waiting on the human" is common by default. Headless is always-approve and cannot be changed.
- No sleep inhibitor anywhere (no `caffeinate`, no `powerSaveBlocker`, no IOPM call in source), unlike Claude Code. `pmset -g assertions` should show nothing for OpenHands (inferred, not observed).
- OpenTelemetry exists but only for traces, and it is separate from PostHog product analytics that agent-server sends by default under Agent Canvas (`DO_NOT_TRACK=1` disables it).
- A `--resume --last` command puts `--last` in the slot where the probe reads the session id, so that id is wrong. `exclude_args` is an exact-argv test, so a prompt that is exactly `serve` or `web` would be missed.
- The CLI repo is quiet: last release 1.16.0 in May, last commit August, while the SDK and Canvas ship almost daily. Docs still show `AGENT_SERVER_IMAGE_TAG=1.26.0-python` for the CLI Docker route.

## Verification

Reviewed 2026-09-29 by a second pass that tried to refute the row. Sources re-fetched: docs.openhands.dev pages (.md), shallow clones of OpenHands/OpenHands (b9d174c), OpenHands-CLI (954f2ba, tag 1.16.0), software-agent-sdk (main b1b237c, tag v1.21.0 files by raw fetch), install.sh, PyPI JSON for `openhands` 1.16.0, `gh api` release lists. `tools/validate_row.py` passes. Confidence stays `documented` (nothing installed or running here, so it cannot be higher). Matching was re-tested through the probe's own `matches()` and `session_id()` on 30 made-up `ps` lines; all give the expected surface, including the new cases below.

Status per claim: confirmed, corrected (row edited) or unsupported (removed or downgraded in the row).

### Confirmed

- Agent Canvas is the current local surface, `openhands serve` is legacy, package `@openhands/agent-canvas` 1.24.0, latest release v1.24.0 2026-09-25. The quoted sentence is on the overview page (line 116, not in the top section); `All-Hands-AI/OpenHands` resolves to `OpenHands/OpenHands`.
- Desktop app: appId `dev.openhands.agent-canvas`, productName `OpenHands Agent Canvas`, ad-hoc signed and bundles node and uv (setup page), `startStack()` imports `dev-with-automation.mjs` and runs it in-process, first dmg release v1.6.1 on 2026-07-28, universal dmg first in v1.23.0.
- Agent server launch: `uvx --from openhands-agent-server==<ver> --with ... agent-server --import-modules ... --host 127.0.0.1 --port N`, console script `agent-server = openhands.agent_server.__main__:main`, env `OH_PERSISTENCE_DIR` = parent of the state dir, `OH_CONVERSATIONS_PATH`, `OH_SESSION_API_KEYS_0`. Ports 8000 ingress, 18000 agent-server, 18001 automation (config/defaults.json). `python -m openhands.agent_server --host 127.0.0.1 --port 8000` is on the Local Agent Server docs page.
- State dir `~/.openhands/agent-canvas`, npm/npx/desktop conversations in `dev_conversations`, Docker in `agent-canvas/conversations`.
- CLI install shapes: `uv tool install openhands --python 3.12`, `requires-python ==3.12.*`, PyInstaller one-file `openhands` (spec `name='openhands'`), install.sh picks /usr/local/bin if writable else ~/.local/bin and downloads `openhands-macos-arm64` or `-intel`.
- uv tool shebang on macOS: `head -1 ~/.local/bin/cswap` prints `#!/Users/frikkjarl/.local/share/uv/tools/claude-swap/bin/python`, and `ps` shows `<tool env>/bin/python <script>`. So argv[0] is the interpreter and `path_contains` is the right test.
- `execution_status` values, autosave on public field change, `WAITING_FOR_CONFIRMATION` set when the policy asks, `RUNNING` at run start. Same enum in v1.21.0 and main.
- CLI default `AlwaysConfirm` (textual_app.py:166), headless forces `NeverConfirm`, headless docs say always-approve and require `--task` or `--file`.
- `owner_lease.json` with `owner_pid`, `owner_host`, 45 s TTL, renewed every 15 s, released on graceful shutdown.
- Shell tool: tmux when `tmux -V` works on a dedicated socket named `openhands`, sessions `openhands-<user>-<uuid>`; otherwise a persistent `bash -i` on a PTY. So no `tool_children` or `child_process` signal.
- Hooks: six events, `.openhands/hooks.json` then `~/.openhands/hooks.json` (or `$OH_PERSISTENCE_DIR`), first found wins, PascalCase and `{"hooks": ...}` wrapper accepted, `OPENHANDS_EVENT_TYPE`, `OPENHANDS_TOOL_NAME`, `OPENHANDS_PROJECT_DIR`, `OPENHANDS_SESSION_ID`, no Notification event. Same search order and same six events at v1.21.0.
- OTel: traces only, env vars `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, `_HEADERS`, `_PROTOCOL`, `OTEL_ENDPOINT`, `LMNR_PROJECT_API_KEY`.
- PostHog: agent-server gets a default PostHog key from Agent Canvas unless `DO_NOT_TRACK=1` or `VITE_DO_NOT_TRACK=1`.
- No sleep inhibitor: the cited grep prints nothing (rc 1) over CLI, SDK, tools, agent server, Electron and canvas `src`; `powerSaveBlocker` absent.
- `openhands serve` docker command (`--name openhands-app`, `-p 3000:3000`, image `docker.openhands.dev/...`), from gui_launcher.py.
- Subcommands serve, web, cloud, acp, mcp, login, logout and the listed flags match the command-reference page.
- Local observation: nothing installed or running (`which`, `ls ~/.openhands`, `/Applications`, `mdfind` bundle id, `ps` all empty).

### Corrected

- Session store evidence. The resume docs page does not show `base_state.json` and `events/`; its "Storage Location" tree shows `conversation.json` (stale). The layout comes from the SDK persistence guide and source. Row evidence rewritten.
- Which SDK the CLI runs. The row leaned on SDK main (1.49.6). Release CLI 1.16.0 pins `openhands-sdk==1.21.0` (PyPI requires_dist). The status enum, run/confirm semantics and hook events are the same there, but write behaviour is not (next item).
- "base_state.json is the busiest file". Wrong for the released CLI: at v1.21.0 there is no per-event field, so the file changes at run start and end, on a confirmation, on policy or last-user-message changes. In 1.49.6 `leaf_event_id` changes per event but saves are deferred to the end of the step's `with state:` block, so a long step writes nothing until it ends. `session_store.per_session` now points at `events/event-*.json` (one file per event, `EventLog.append`), which is the write clock; `base_state.json` stays the source of the status field. `transcript_write.meaning` rewritten. The 30 s window is still a guess.
- "waiting_for_confirmation autosaved at once": true at v1.21.0, but in 1.49.6 it is saved when the step's lock block exits. Meaning text adjusted.
- Subcommand list was incomplete: `openhands view <id>` exists (tag 1.16.0 and main), is not in the docs, and prints and exits. It was not vetoed, so it would show as a brief idle tui. Added to `exclude_args`.
- Zed docs use `uvx openhands acp`. The row only matched the uv-tool path, so ACP under Zed with the documented command was missed. Added an ide surface for a python whose args contain `/bin/openhands` and `acp` (shape inferred from the uv tool shebang, not observed).
- Surface order. The ide surface was first with a substring test on `acp`, so any session whose task, path or prompt merely contained `acp` (or a headless run with such text) was filed as ide, and headless lost `oneshot`. Order is now headless, tui (which vetoes the exact token `acp`), ide. Verified with test lines (`-t fix_acpi_driver` stays tui, `--headless -t fix_acpi` stays oneshot).
- `openhands-acp` name removed. The script is in pyproject, but it points at `openhands_cli.acp`, which does not exist in tag 1.16.0 or main (only `acp_impl`), and no doc mentions it.
- Docker gui surface: `args_contain: openhands-app` also matched `docker logs -f openhands-app`, `docker exec`, `docker stop`. Now requires `run`, `--name` and `openhands-app`.
- Daemon surfaces: names now include `python3.14` (agent-server and SDK require `>=3.12`).
- OTel span names. `conversation.run` and `agent.step` are real, but there is no span called `tool.execute` or `llm.completion`: tool spans are named after the tool (span type TOOL), LLM spans have type LLM. Also `conversation.send_message`.
- Local tmux evidence: "no `openhands` socket in /private/tmp/tmux-501" proves nothing for Agent Canvas, which sets `TMUX_TMPDIR=<state dir>/tmux`. The absent `~/.openhands` is the real evidence. Source text corrected.
- Desktop dmg naming: the docs say `Agent-Canvas-<version>-universal.dmg`; the real asset is `OpenHands-Agent-Canvas-1.24.0-universal.dmg`, and every release before 1.23.0 was arm64 only. Source added.
- Notes: CLI repo README says (commit 954f2ba, 2026-08-11) "no longer actively maintained, use Agent Canvas". Added; the earlier "quiet repo" remark in the evidence above is now stronger than that.

### Unsupported

- "stats after each LLM call" as a reason base_state.json is rewritten. `stats` is mutated in place, which does not go through `__setattr__` autosave; no code path found that saves on it. Dropped from the meaning text.
- The CPU floor of 3 percent, the 30 s write window, and the real `ps` shape of uvx-launched processes (including whether uvx execs or spawns). Nothing was observed; they stay guesses and are labelled so in the row.

### Still open, not fixable from here

- The daemon surface (`python` + `/bin/agent-server`) has no second discriminator. Requiring `--import-modules` would lose the hand-run form; left as is and named in notes.
- ACP children of Agent Canvas (`claude-agent-acp`, `codex-acp`, `gemini --acp`) are spawned by the agent-server and would also match their own rows. Needs an ancestor rule in the detector (registry README section 3, case 12). Recorded as a source and in notes.
- `--resume --last` still yields the id `--last`. Harmless (no transcript found) but wrong.
