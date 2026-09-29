# JetBrains Junie: evidence notes (2026-09-29)

Not installed on this Mac. Nothing below was seen on a running instance. Row confidence is `documented`. I did not install or run any Junie binary; I read release archives by HTTP range and parsed class constants in the scratchpad.

## What I checked

- Local: `which junie`, `ls ~/.junie ~/.local/share/junie ~/.local/bin/junie`, `ps | grep [j]unie`, `ls /Applications` for JetBrains, Junie, Air. All empty. `tools/agents_probe.py --row registry/agents/junie.json` finds 0 sessions, as expected. `tools/validate_row.py` prints `ok`. The row's surfaces were also run through `probe.matches()` on synthetic `ps` lines (tui, resume, headless, `--acp=true` relative and absolute, gateway, bash shim, npm node wrapper, `junie update`, unrelated name): each lands on the intended surface or none.
- Official docs (junie.jetbrains.com/docs): quickstart, CLI reference, environment variables, config.json, hooks, remote mode, parallel sessions, ACP, IDE plugin, headless. JetBrains Air docs: supported agents, select agents, set up. JetBrains AI Assistant ACP page.
- Public source: `github.com/JetBrains/junie` (installers, shims, update feeds only; the agent itself is closed) and `agentclientprotocol/registry` `junie/agent.json`.
- Vendor artifact: the macOS release zips `junie-release-3419.7-macos-aarch64.zip` (stable) and `junie-eap-3479.2-macos-aarch64.zip` (EAP), read with `curl -r` range requests for the central directory, `Info.plist`, `Contents/MacOS/junie` and the 258 MB application jar. Read in the jar: constant pools of about 30 classes, the bundled docs file `bundled-agents/junie-cli-docs.md` and the bundled skill `agent-skills/session-history/SKILL.md`. No JDK here, so no disassembly; I used a small constant-pool reader.
- Third party: `ingo-eichhorst/Irrlicht` Junie adapter (`pid.go`, `parser.go`, `junie_cwd.go`, fixtures). Read for key names and state values only, never message text. Homebrew cask JSON for IDE and Air bundle ids. npm `@jetbrains/junie` 3110.7.0 tarball (unpacked, not installed).

## Answers per surface

| Surface | Process | Session mapping |
|---|---|---|
| CLI TUI and headless | `~/.local/share/junie/versions/<build>/Applications/junie.app/Contents/MacOS/junie`, name `junie`, bundle id `com.intellij.ml.llm.matterhorn.ej.app.cli.standalone`, one process (jpackage launcher, JVM loaded in-process, inferred). The bash shim `~/.local/bin/junie` and Homebrew's bootstrap `exec` into it; npm's node wrapper is the parent. | `--session-id` on resume only. Otherwise `~/.junie/processes/<pid>-<session>-<hash>.json`. |
| ACP agent (JetBrains IDE AI Chat, Air, Zed) | Same binary with `--acp=true`. Hooks are not run. | Sidecars as above; the session id is not in argv. |
| Gateway daemon (Nightly only) | Same binary with `--__run-gateway`, state in `~/.junie/gateway/`. | Not needed. |
| Air app | `com.jetbrains.air` (from the Homebrew cask plist name). A host only. | Its Junie child is the ACP process. |
| Legacy IDE plugin tool window | Not determined. | Not determined. |
| Cloud | GitHub Action, GitLab CI, Air cloud tasks: nothing local. | None. |

- Store: `~/.junie/sessions/<sessionId>/events.jsonl` (JSONL, append), sibling `state.json`, `summary.json`, `transcript.md`, `subagents/`, `<taskId>/`; root `~/.junie/sessions/index.jsonl` with `sessionId, createdAt, updatedAt, projectDir, taskName` and a nullable `status`, `lifecycle`. `JUNIE_HOME` moves the whole tree. Vendor-documented in files shipped inside the binary; the public docs only mention `events.jsonl` and `transcript.md` in passing.
- Turn in progress, most precise: (1) sleep assertion named `Junie is working` (bytecode, default on, user can switch off); (2) `events.jsonl` open task: `TaskStartedEvent` with no later top-level `TaskState`, last `SessionA2uxEvent.event.state` = `IN_PROGRESS`; (3) a direct shell child (`bash -lc`, perl/nohup exec'd); (4) CPU as a guess.
- Waiting on the human: last `event.state` = `INPUT_REQUIRED`, cleared by a response event, cancel or `TaskState`. The TUI shows `Working…`, `Awaiting input`, `Ready` per live session. A terminal notification `Junie needs your input` (OSC 9/777/99). A `PermissionRequest` hook exists but is a gate, not an observer.
- Hooks: `hooks` object in `~/.junie/config.json` or a `--config-location` file: `SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, Stop, StopFailure, SessionEnd`. Command hooks only, TUI and batch hosts only.
- OpenTelemetry: none found.

## What I could not determine

- Everything about live behaviour: the exact assertion name string in `pmset` (mapping from `reason` to assertion name is inferred from the call shape), whether it is dropped while a task waits for approval, whether ACP hosts feed the same task counter (the counter is wired in `JunieSession` and the batch host; the ACP path was not traced), and CPU at idle and during a turn.
- Where the JetBrains IDE and Air unpack the ACP download. A support thread says an `acp-agents` folder in the IDE caches directory; nothing official. Whether the IDE runs one `junie --acp=true` per chat (its log says a process handler is stopped per chat) or one per IDE window (the Irrlicht adapter says one process serves every session of a window). Air's own process names and storage.
- The legacy Junie plugin tool window: in-process or child, and where it stores sessions. Not covered by the row.
- What `index.jsonl` `status` and `lifecycle` hold; whether `state.json` carries a usable running flag (its content is encrypted in part per the bundled docs). What gates the terminal notification (focus, a setting) and whether the OSC 0 title carries a status glyph.
- Whether `bash -lc '<one command>'` execs the command so the child carries the tool's name instead of `bash` (then `tool_children` misses it).
- Linux and Windows were out of scope.

## Contradicts common belief or earlier notes

- Irrlicht's adapter says Junie "exposes no hook system" and is observe-only. Wrong now: seven shell-command hook events exist in `config.json`. The docs page is tagged Early Access, but the class `HooksConfiguration` with all seven events is in the stable 3419.7 jar. Hooks are not run by ACP hosts, so IDE, Air and Zed sessions have none.
- The same adapter says no env var relocates `~/.junie`. `JUNIE_HOME` does (official environment-variables page and the bundled storage doc). `JUNIE_DATA` is the install store under `~/.local/share/junie`.
- "The IDE agent" is not an IDE-internal process any more: the AI Chat runs the same `junie` binary as `--acp=true`. So the IDE, Air and Zed surfaces are found by command line, and one row rule covers CLI and IDE. JetBrains Air is a host for several agents, not a Junie surface of its own.
- Many assume a coding agent this new holds no sleep assertion, and the remote-mode doc even says the machine must stay awake. The binary carries a keep-awake service that is on by default.
- A `PermissionRequest` hook that exits 0 approves the action and skips the dialog. Using it as a "waiting" notifier would silently turn on auto-approve. There is no `Notification` or idle hook (unlike Claude Code), so the transcript `INPUT_REQUIRED` state is the observer-safe wait signal.
- `--resume` is a boolean; only `--session-id` takes a value, and it also accepts a `junie://sessions/<id>` link, which a naive probe would read as a wrong file name.
- One process is not one session: `/new` keeps earlier sessions running in the same process, and a sidecar stays behind after the process exits (only the newest `startedAt` per pid is current).
- `-p` is `--project`, not "print"; headless runs are `junie "task"` or `--task`.
- Probe limits, not Junie limits: the probe keeps only the outermost matching process (a Nightly gateway spawned by a live TUI is hidden), and splits `ps` on spaces (an install under `Application Support` would lose both the name and the path match).

## Verification

Adversarial re-check on 2026-09-29 by a second reader. `tools/validate_row.py registry/agents/junie.json` prints `ok` before and after the repairs. Method: refetched every docs page and repo file cited, downloaded the 3419.7 macOS release zip, inflated the application jar into the scratchpad (nothing installed or run), read class constant pools with a small reader (no JDK on this Mac), and ran the row's process specs through `tools/agents_probe.py` `matches()` on synthetic `ps` lines. Confidence stays `documented`: the harness is not installed here (`which junie`, `~/.junie`, `~/.local/share/junie`, `~/.local/bin/junie` and `ls /Applications` all empty; no junie process).

### Confirmed

- Not installed on this Mac (re-ran the commands).
- Install layout: shim `~/.local/bin/junie` `exec`s `$binary` (install.sh lines 888 and 944); `JUNIE_DATA`, `EJ_RUNNER_PWD` exported; versions under `~/.local/share/junie/versions/<build>/Applications/junie.app/Contents/MacOS/junie`. README lists curl, `brew tap jetbrains-junie/junie` and `npm install -g @jetbrains/junie`. The Homebrew formula installs a bootstrap that `exec`s the real shim.
- npm wrapper: `bin/index.js` uses `spawnSync(exe, ..., {stdio:'inherit'})`, so node is the parent (tarball 3110.7.0, the current npm `latest`).
- Bundle id `com.intellij.ml.llm.matterhorn.ej.app.cli.standalone`, `CFBundleExecutable junie`, version 3419.7 (Info.plist read from the zip). `MacOS/junie` is a 198,928-byte arm64 jpackage launcher (`JvmLauncher.cpp`, `dlopen`); its undefined symbols contain no fork, spawn or exec, and `junie.cfg` names `MainKt` on the jar, so one process with the JVM in-process.
- ACP command: registry entry `junie/agent.json` (3419.16.0) cmd `./Applications/junie.app/Contents/MacOS/junie` args `--acp=true` on macOS; the Zed page shows the same; the ACP doc shows `junie --acp true` (space form). The `ide` surface matches both forms.
- IDE AI Chat runs Junie as ACP agent `acp.registry.junie`, one process handler stopped per chat, session ids of the form `session-YYMMDD-HHMMSS-xxxx` (support thread log, read through a scraper because a plain fetch is blocked). The IDE docs say the agent is downloaded automatically.
- Air supports Junie (supported-agents page). IDE bundle ids from the Homebrew cask `uninstall.quit` values (intellij, pycharm, WebStorm, goland, com.google.android.studio).
- Home layout, `JUNIE_HOME` order (env var, `junie.home` property, `~/.junie`), `sessions/index.jsonl`, `sessions/<id>/{events.jsonl,state.json,summary.json,conversation-summary.md,checkpoints,<taskId>/terminal-output}`, log file names, `settings.json`: all in the bundled `bundled-agents/junie-cli-docs.md`. Public docs mention only `events.jsonl` and `transcript.md` in passing, so `session_store.documented=true` rests on vendor docs shipped in the binary.
- Event state enum `A2uxTaskState` = IN_PROGRESS, INPUT_REQUIRED, COMPLETED, FAILED, CANCELED (class constants); `SessionLiveStatus` WORKING, AWAITING_INPUT, READY and `liveStatusOf`; the docs table shows `Working...`, `Awaiting input`, `Ready`, `Cross-process sessions`, and `/history` switches live sessions. Record kinds and the INPUT_REQUIRED open/close rules match the Irrlicht `parser.go` source (read for names only).
- Keep-awake: `MacKeepAwakeService.acquire(reason)` calls `IOPMAssertionCreateWithName` with `PreventUserIdleSystemSleep`; `KeepAwakeController` (`WAKE_LOCK_REASON`, and `holdWakeLock`) holds the string `Junie is working`; `KeepAwakeMode.WhileTaskRunning`; `JunieSettings.keepAwakeMode`; settings text "Prevent system sleep while Junie is working". All in the stable 3419.7 jar.
- Shell tool calls: `SessionDetachWrapper` holds the perl prefix `use POSIX qw(setsid); setsid() or die ...; exec @ARGV or die ...` plus setsid and nohup alternatives; `BashShellType` holds `-lc '` and `</dev/null`; markers `___JVMSPAWN_STATE_MARKER___`, `MATTERHORN_SESSION_ID`, `MATTERHORN_TASK`, `JUNIE_TMPDIR`. Still inferred that these show up as direct shell children in `ps`.
- Terminal notifications: `TerminalNotifier` has `* Junie needs your input`, `Junie finished`, OSC 9, 99, 777 (`]777;notify;`) and a title writer.
- Gateway: `--__run-gateway` in `GatewayLauncher` and `MainKt`; the Nightly-only message in `JunieCli`; `--gateway`, `--gateway-status`, `--gateway-stop` in `SystemOptionsGroup`.
- Hooks: seven events in `HooksConfiguration`; config in `~/.junie/config.json` or `--config-location`; project hooks ignored; exit 0 on PermissionRequest approves; exit 2 or `decision: deny` denies; other non-zero falls back to the dialog; ACP and server hosts run no hooks; hook stdin carries `session_id`, `cwd`, `project_path`.
- No OpenTelemetry: `unzip -Z1 junie.jar | grep -c '^io/opentelemetry'` printed 0 for 3419.7 (91,128 entries). EAP 3479.2 not re-checked.
- Parameters: `--session-id` takes an id or `junie://sessions/<id>`; `--resume` resumes the last session or the one named by `--session-id`; `--version`, `--help`/`-h`, `update` documented. Remote mode: tunnel to the web app, "Your machine must stay awake"; `/new` starts another live session in the same instance and earlier ones keep running.
- `events.jsonl` growth: JUNIE-5070 title and "459 GB" example seen in a search result; the deprecation thread exists (search result).

### Corrected

- Process patterns. The bare `names: ["junie"]` claimed any executable called `junie` (`/usr/bin/junie` matched the tui surface). Removed; every documented launch form carries `/junie.app/Contents/MacOS/junie`. The tui surface also matched the short-lived control invocations `junie --gateway`, `--gateway-status` and `--gateway-stop`; all three are now excluded. Verified on 22 synthetic `ps` lines: tui, resume, headless, `--acp=true`, `--acp true`, relative ACP path, IDE cache path and gateway land on the intended surface; bash shim, node wrapper, `--version`, `--help`, `update`, `Junie` (capital), and `junie-tool` match nothing.
- Hooks are Early Access per the docs page ("To try it, install the Early Access version"). The stable jar has the class, but an `Env.hooksEnabled` flag exists and its Release value was not determined. `UserPromptSubmit` is TUI-only; the docs disagree with themselves on whether batch runs `PermissionRequest`. Row text softened.
- Session id: not only `--session-id`; a positional `junie://sessions/<id>` link also names a session, and `session_id_args` cannot read it. Noted.
- Sidecar lifetime: Irrlicht says sidecars are not cleaned up on exit, but the binary has "Removed process latch" and stale-latch cleanup strings. Claim softened to "usually survive"; a missing file proves nothing.
- Reddit source URL pointed at "ACP was a bad idea" (`1w15gno`); the deprecation thread is `1t672zs`. Fixed.
- `acp-agents` folder: the support thread's path is a Linux `~/.cache/JetBrains/GoLand2026.1/acp-agents/cursor/...` path for the Cursor agent. The Junie location and macOS path are inferred, not seen.
- "Present in stable 3419.7 and EAP 3479.2": only 3419.7 was re-read here; the EAP claim is unrechecked.

### Unsupported or unproven

- `com.jetbrains.air` bundle id: inferred from the cask zap plist name only.
- The assertion name seen in `pmset` is `Junie is working`: inferred from the call shape (reason string goes to `createCFString` and `IOPMAssertionCreateWithName`). Not observed live.
- The assertion in `--acp=true` processes: `AcpSettingsState` carries `keepAwakeMode`, and ACP uses `JunieProject` (which holds the `TaskActivityTracker`), but no ACP class references the tracker directly. Unproven.
- Whether IDE AI Chat starts `junie --acp=true` per chat or per window, where it unpacks on macOS, and whether the command line is exactly as in the registry: inferred.
- Zed installs under `~/Library/Application Support/Zed/...`; the probe splits `ps` on spaces, so this path is not matched (a probe limit, listed in README case 11).
- The 3% CPU floor on a JVM Compose UI; whether `bash -lc '<one command>'` execs into the tool name; whether the gateway flag works on Nightly (only the stable gate message was read); the LLM-26664 YouTrack page and the IDE thread's Junie-specific paths could not be fetched.
