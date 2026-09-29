# Trae evidence notes (2026-09-29)

Not installed on this Mac, nothing running. Nothing below was seen on a live instance, so confidence is `documented`. Row: `registry/agents/trae.json`, passes `tools/validate_row.py`; `agents_probe.py --row` finds 0 sessions (expected). Process rules were run through the probe's `matches()` on 21 synthetic argv lines (IDE main and helpers, CN, SOLO CN, traecli with and without subcommands, python console script, framework Python, `-m`, `uv run`, look-alikes).

## Trae is four things, not one

```
trae-agent   github.com/bytedance/trae-agent   Python console script `trae-cli`, MIT, research CLI (the hint URL)
TRAE IDE     Trae.app (com.trae.app)           Electron VS Code fork, one process hosts every chat
TRAE CN      Trae CN.app (cn.trae.app)         same, China edition
TraeCode CLI `traecli`                         closed source: 1.0 (yaml) and 2.0 (a codex-rs fork, "TraeX")
SOLO/TraeWork standalone apps                  bundle ids unknown
```

## What I checked

- Cloned trae-agent (shallow, scratchpad, commit e839e55, Feb 2026) and read `cli.py`, `agent/agent.py`, `agent/base_agent.py`, `utils/trajectory_recorder.py`, `tools/bash_tool.py`, `utils/constants.py`, `docs/`. Grepped for hooks, OTel, telemetry, caffeinate, sqlite: nothing.
- Official docs fetched: docs.trae.ai hook configuration reference (IDE); docs.trae.cn TraeCode CLI 2.0 pages (overview, quickstart, command-line parameters, config file, environment variables, status and troubleshooting, plugins/skills/MCP) and CLI 1.0 pages (quickstart, global settings).
- Homebrew cask API for `trae` and `trae-cn` (bundle ids via quit targets, app paths, zap paths).
- Third-party source read for what the vendor does not publish: agentsview (session dirs, parser comments), tmux-scout and CodeIsland (hook setup code, process paths, changelog), OpenViking docs (2.0 plugin and hook trust), an Orca commit (terminal title).
- Local: `ls /Applications`, `which`, `ls ~/.trae*`, `ps`, `pmset -g assertions`, all empty.

## Answers per surface

| | trae-agent | TRAE IDE / CN | TraeCode CLI 2.0 (TraeX) | TRAE CLI 1.0 |
|---|---|---|---|---|
| Process | python + script arg `trae-cli`; `-m trae_agent.cli` | main `/Applications/Trae.app/Contents/MacOS/*` (CN: `Electron`) | native `traecli`, `traex`, `trae-cli` | native `traecli` in `~/.local/bin` |
| Session to process | none (no id anywhere) | none, host process | `--resume[=ID]`, `resume ID`, `fork ID`; fresh session has no id | unknown |
| Store | `trajectories/trajectory_<ts>.json` (or `-t`), JSON | encrypted `~/Library/Application Support/Trae/ModularData/ai-agent/database.db`; legacy `workspaceStorage/*/state.vscdb` | `~/.trae/cli/sessions/` rollout JSONL (third-party, undocumented) | not found |
| Turn in progress | shell child alive (from first bash call to task end); `run`: process alive; trajectory `end_time` empty | hook pair `UserPromptSubmit` then `Stop` (or `Notification` idle_prompt) | rollout `task_started` with no `task_complete` (inferred from Codex); status line `Working...`; title `⠋ traecli` | hooks only |
| Waiting on human | no approvals exist | `Notification` types permission_prompt, ask_user_question, document_review, browser_interaction (official) | `PermissionRequest` hook (third-party) | `permission_request` hook (third-party) |
| Hooks | none | `~/.trae/hooks.json` (official), also imports Claude Code hooks | Codex-compatible, trust step, location disputed | yaml `hooks:` (third-party) |
| OTel | no (source) | not determined | not determined | not determined |

## Could not determine

- Everything live: real `ps` argv, CPU when working and idle, assertions. All CPU floors are guesses.
- Executable name of the international `Trae.app` main binary (CN is reported as `Electron`; CodeIsland's own code disagrees with its test). The row matches the folder, not the name.
- Bundle ids of TRAE SOLO CN and TraeWork Desktop. The SOLO CN rule is inferred from an app-data folder name.
- Whether `sh -c /bin/bash` in trae-agent shows as `sh` or `bash` (either is in the shell set). Not run.
- Whether the IDE holds a power assertion, and any IDE per-session working signal. The chat store is encrypted, so no transcript signal.
- TraeX rollout file naming and the dated subfolder layout: copied from Codex, marked inferred. No fixture I saw was a real Trae file; the TraeX test fixture says `originator: codex-tui`.
- OTel for TraeX and the IDE. The 2.0 config reference does not list an `[otel]` table.
- The 1.0 session store and process shape. The installers (`trae.cn/trae-cli/install*.sh`) return 403 to curl, so I never saw what they install or where.
- TraeCode CLI 2.0 access: docs say only Enterprise flagship customers can use it, so the surface may be rare.

## Contradicts common belief or the obvious approach

1. The hint's start URL is the wrong program for most users. `bytedance/trae-agent` is a research CLI, run by Python. The product terminal agent is closed-source `traecli`. `trae-cli` names both: match argv[0] for the native binary, interpreter plus script argument for trae-agent.
2. trae-agent's "transcript" is one JSON file rewritten in full on every step, not JSONL, and it has no session id. Interactive mode reuses one file and overwrites it per task (`start_recording` resets the data). It is written relative to the launch cwd; with `--working-dir` the process then `chdir`s, so lsof cwd points to the wrong folder.
3. trae-agent has no `caffeinate`, no approvals, no hooks. Its one precise signal is the persistent bash child, which exists only after the first bash tool call and is closed at task end. Thinking before the first shell command reads idle.
4. TraeCode CLI 2.0 is a Codex fork, so it should look like Codex (rollout JSONL, `PermissionRequest`, hook trust), not like Claude Code. Do not expect `caffeinate`.
5. Official and third-party config locations disagree. CLI 1.0 docs say `~/Library/Application Support/trae_cli/trae_cli.yaml`; tmux-scout edits `~/.trae/traecli.yaml`. For 2.0, tmux-scout writes `~/.trae/traecli.toml` (matches the docs config path) while CodeIsland writes `~/.trae/cli/hooks.json`. `TRAE_HOME` moves the config and runtime dir, so any fixed `~/.trae` path is a default only.
6. The IDE's hooks are real and official, but off until enabled (global hooks setting), and the IDE also reads `~/.claude/settings.json` hooks, so a Claude Code hook can fire from Trae too.
7. Docs paths are confusing: `docs.trae.ai/cli` redirects to the IDE page; the CLI docs live on `docs.trae.cn` only. The product has been renamed (TRAE to TraeCode, SOLO to TraeWork), and `TRAE SOLO CN` is a separate app data folder.
8. A "TRAE - AI Work Assistant" app exists on the App Store (TraeWork mobile); it is not a coding agent on the Mac and has no rule.

## Privacy

No session content was read or printed. No Trae store exists on this Mac. The only record keys named come from source code (`TrajectoryRecorder.trajectory_data`) and public docs.

## Verification

Adversarial pass, 2026-09-29. Method: `tools/validate_row.py` (ok before and after), each source re-fetched or re-run (docs pages scraped, trae-agent at e839e55 and agentsview, tmux-scout 24c6353, CodeIsland and the Orca commit cloned, Homebrew cask API, codex issue body), process rules re-run through the probe's `matches()`. Confidence stays `documented` (nothing Trae is installed here, so no higher); the parts that are only inferred are listed below.

| Claim | Result |
|---|---|
| trae-agent: console script `trae-cli = "trae_agent.cli:main"`, requires-python >=3.12 | confirmed (pyproject.toml lines 6 and 45) |
| trae-agent subcommands run, interactive, show-config, tools; `input()` for the simple console | confirmed (cli.py, simple_console.py) |
| Trajectory is one JSON file rewritten in full (`open(..., "w")`) at start, per LLM reply, per step, at finalize; `end_time` empty until finalize | confirmed |
| With `--working-dir` the trajectory path is resolved before `os.chdir` | confirmed (`Agent(...)` at cli.py 352, `os.chdir` at 363; recorder resolves in `__init__`) |
| Bash tool starts lazily, is closed at task end by `_close_tools` (also per task in interactive mode) | confirmed |
| Direct child is `/bin/sh -c /bin/bash` | corrected: on this Mac `create_subprocess_shell('/bin/bash')` shows a direct child named `/bin/bash` (sh execs it). Both names are in the shell set, so `tool_children` still works. Row text fixed; also noted that Docker mode has no local child |
| trae-agent has no hooks, OTel, caffeinate, sqlite outside `tools/ckg`; `~/.trae-agent` only for ckg | confirmed (grep printed nothing; `LOCAL_STORAGE_PATH` used only by ckg_database.py) |
| IDE hooks: paths, six events, five Notification types, `session_id` on stdin, Claude Code hooks import, `idle_prompt` = task finished | confirmed on docs.trae.ai (full page read) |
| "Hooks are off until global hooks are enabled in settings" (item 6 above; row waiting_signals text) | unsupported by the official page. Only CodeIsland's changelog says it. Row reworded to attribute it, source added |
| Homebrew casks: Trae.app / com.trae.app / ~/.trae; Trae CN.app / cn.trae.app / ~/.trae-cn | confirmed (cask API artifacts) |
| Trae CN main binary is `Electron`, helpers `Trae CN Helper (...)`; international binary name unknown | confirmed (CodeIsland test header); international name still unknown (AppState.swift lists `/trae.app/contents/macos/trae`, its own test says Electron). The row matches the folder, so it does not depend on it |
| Modern IDE chat store `ModularData/ai-agent/database.db` is not SQLite (encrypted); legacy `state.vscdb` | confirmed in agentsview `traeEncryptedModularData`, third-party |
| TraeCode CLI 2.0 subcommands (exec, review, resume, fork, acp, app-server, mcp-server, apply, sandbox, doctor, features, ...), `--resume[=ID]`, `--ephemeral`, `--remote` | confirmed on docs.trae.cn command-line page |
| Installer `install_v2.sh`; binary `traecli` | confirmed |
| Only Enterprise flagship customers may use 2.0 | confirmed, but on the "about" page (Chinese text), not on the quick-start page; source evidence now says so |
| Alias `traex` | unsupported by vendor docs. Third-party only (agentsview `resume.go`). Evidence text now says so |
| 2.0 config `~/.trae/traecli.toml`, `TRAE_HOME`, logs `~/.trae/log/`, status strings | confirmed |
| 2.0 is a closed-source codex-rs fork with Codex rollout JSONL under `~/.trae/cli/sessions` | corrected in wording only: agentsview says so (types.go comment and DefaultDirs); vendor says nothing. Layout below the dated tree stays inferred. `documented: false` is right |
| 2.0 hooks Codex-compatible, trust step, `trae-cli plugin` | confirmed on docs.openviking.ai (third-party) |
| TraeX hook events and `[features].hooks = true` in traecli.toml; 1.0 snake_case yaml events | confirmed in tmux-scout traex.js / coco.js. coco.js also probes `~/.trae/coco.yaml` and `~/Library/Application Support/coco/coco.yaml`. CodeIsland's `~/.trae/cli/hooks.json` disagrees, as the row says |
| 1.0 config `~/Library/Application Support/trae_cli/trae_cli.yaml`; `~/.local/bin` | confirmed; breadcrumb reads "TraeCode CLI 1.0" |
| 1.0 `traecli acp serve` | confirmed on docs.trae.cn/cli_agent-client-protocol; was in the daemon label without a source, source added |
| Terminal title `⠋ traecli` while working | corrected: the Orca commit only shows a test fixture treating that title as a Trae CLI title. That the spinner means "working" is inferred. Claim reworded |
| Nothing Trae installed or running here | confirmed again (`ls /Applications`, `which`, `ls ~/.trae*`, `ps`, `pmset -g assertions` all empty) |
| TRAE SOLO CN app at `/Applications/TRAE SOLO CN.app` | unsupported: only a suggestion in codex#22629 ("optional additional target", `.../bin/trae-solo-cn`) plus an agentsview app-data folder name. Stays inferred; source added saying so |
| `telemetry.otel: false` | corrected: false is proven only for trae-agent. The key is removed (rovo-dev precedent) and the text says unknown for the rest |

### Process patterns, false positives

Run through `matches()` with synthetic argv lines (helpers with spaces in the path, other `/Applications/Trae*` apps, traecli with and without subcommands, python lines).

- Fixed: the python console-script surface matched any python whose argument contained `trae-cli`: `python /x/trae-cli-notes/serve.py` and `python -m pip install trae-cli` both matched. Now `args_contain` is `/bin/trae-cli`. Checked with a real shebang script: `ps` shows `<Python> <dir>/bin/trae-cli run ...`, so real runs still match (pip, pipx and uv tool put console scripts in a `bin` dir). After the fix: the two look-alikes no longer match, a console-script run, a framework `Python` run and `-m trae_agent.cli` still do.
- Helpers do not match any surface (IDE, CN, SOLO CN): their argv[0] splits before `MacOS/`, and no argument carries `CN.app/Contents/MacOS/`.
- Other apps (`Trae Something.app`, `TRAE Foo.app`) do not match.
- Not fixable in the schema, left as is:
  - The IDE launchers `trae`, `trae-cn`, `trae-solo-cn` (`--goto file`) are, in VS Code forks, a shell script that runs the app's own Electron binary in node mode on `out/cli.js`. That is a short process whose argv[0] is the main binary, so it would show for a moment as an idle IDE. Inferred from the launcher paths in codex#22629 and VS Code's design; I could not see the script. An exact-token veto on the `cli.js` path would be a guess.
  - `exclude_args` and the `tools` veto on the python surface match whole words, and `ps` is split on spaces, so a prompt that contains such a word (`traecli exec apply the fix`, `trae-cli run "list tools"`) is vetoed and the run is invisible. This follows the registry rule (whole-token deny-list); a brief `traecli update` showing up as idle would be the price of removing it.
  - `traecli --cd /path/with-acp-in-it` matches the `acp` daemon surface first (substring rule), so it is filed as a daemon. Same row, wrong kind.
  - `tool_children` also applies to the IDE surface. A VS Code fork resolves the login shell environment at startup with a direct shell child of the main process, which would read as working for a moment (inferred, not seen).
