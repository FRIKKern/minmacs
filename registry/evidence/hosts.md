# What the host can tell us about agents running inside it

Date: 2026-09-29. Machine: macOS 24.3.0 (Darwin), cmux 0.64.3 (83) [aea6cfcde], tmux 3.6a, Ghostty core 1.3.2-HEAD (embedded in cmux).
Only cmux and tmux exist on this Mac. iTerm2, Warp, WezTerm, kitty and standalone Ghostty are documentation and source only, and every claim about them says so.

Tags: [L] observed on this Mac, [D] official docs, [S] vendor source, [I] inferred. Source ids (D1, L4 ...) are listed at the end.

## Answer in one screen

```
 agent (claude, codex ...)             MinMacs (separate app, ppid=1, same user)
   |  writes bytes to its pty                     ^
   v                                              |  can it read this?
 +----------------------------------------------+ |
 | HOST: cmux / Ghostty / iTerm2 / kitty /      | |
 |       WezTerm / Warp / tmux                  | |
 |  parses the bytes:                           | |
 |   OSC 0/2   title   ---- host API ---------->--+   yes, if the host lists titles
 |   OSC 9;4   progress --- host API ---------->--+   ONLY tmux 3.7+ (pane_pb_state)
 |   OSC 133   prompt/cmd marks -- host API --->--+   "at prompt or not" (iTerm2, kitty)
 |   OSC 9/99/777 notifications -- banner ------X    no host lists them, except cmux store
 |  plus, host-specific:                          |
 |   cmux hooks -> ~/.cmuxterm/workstream.jsonl ->+   file read, no auth (needs cmux wrapper)
 +----------------------------------------------+
```

Five findings that shape the design:

1. **Escape sequences are one-way.** They go from agent to host. MinMacs is not on the pty, so it can read an OSC signal only if the host re-exposes it through an API. Almost none do (table 2).
2. **OSC 133 cannot separate working from idle for an agent.** It says "a command is running" or "at a prompt". An agent TUI is one long-running command, so it reads "running" for its whole life. It tells you the agent is alive, not busy. [I, from D-OSC133 semantics plus L11: cmux shell integration reports `running` for the shell while claude is up]
3. **Claude Code already emits OSC 9;4 by default.** `terminalProgressBarEnabled:!0`, described "Emit OSC 9;4 progress sequences during long operations" [L9]. This is the only cross-host "busy" signal that needs no hook install. Whether other harnesses emit it is unknown (registry field `emits_osc_9_4`). It is readable from outside only through tmux 3.7+ (`#{pane_pb_state}`, `#{pane_pb_progress}`) [S-T2]. Installed tmux is 3.6a and lacks it.
4. **cmux's socket is closed to MinMacs by default.** `access_mode: cmuxOnly` [L1]. A double-forked process reparented to launchd (ppid=1) running the bundled `cmux ping` got `Failed to write to socket (Broken pipe, errno 32)` [L2]. The user must set `automation.socketControlMode` to `password` or `allowAll` [D5]. The file `~/.cmuxterm/workstream.jsonl` has no such gate.
5. **Hooks are the only "waiting for a human" signal**, and only cmux (and Warp, one-way) collect them. Everything else is process and output evidence.

## 1. Host by host

Columns: what it knows about a running agent / how another program asks / per-harness setup needed / reliability.

| Host | Knows | How to ask | Per-harness setup | Reliability |
|---|---|---|---|---|
| **cmux** | Per session: working, idle, waiting (permission, question, notification), session start/end, cwd, workspace and surface. Per surface: title (with Claude's status glyph), tty, shell state prompt/running, ports. | Files `~/.cmuxterm/workstream.jsonl`, `~/.cmuxterm/claude-hook-sessions.json` (no auth). Socket `~/Library/Application Support/cmux/cmux.sock` (`cmuxOnly`). CLI `cmux tree/top/list-status/rpc`. `events.stream` and `cmux events` exist in docs on main, not in 0.64.3. | Claude Code: none, wrapper injects hooks when started from a cmux terminal [L4]. Others: `cmux hooks setup` per agent (user action, changes their config). | Good for Claude Code, blind spots listed in section 2. Docs describe newer cmux than installed. |
| **Ghostty** | Title, cwd. `pid` and `tty` of the foreground process only in unreleased main. Command finished via OSC 133 (drives its own notification, not exposed). | AppleScript (`tell application "Ghostty"`): windows, tabs, terminals with `id`, `name`, `working directory` (v1.3.0+). No socket, no CLI query. | None. | Thin but stable API. Needs macOS Automation consent (inferred, standard TCC). |
| **iTerm2** | Per session: `is processing` (received output recently), `is at shell prompt` (needs shell integration), `tty`, `name`, contents; Python API adds `jobName`, `jobPid`, `commandLine`, `lastCommand`, prompt and screen-update subscriptions. | AppleScript (documented as deprecated) or Python API over websocket (needs enabling; scripts outside iTerm2 get a permission prompt). | None for process and output recency. Shell integration for prompt state. | Best-featured host for a generic "busy". Output recency is a heuristic. |
| **Warp** | Agent status (working, blocked, completed, errored) shown in tabs, in-app and desktop notifications, for Claude Code, Codex, OpenCode. | Nothing external found. The channel is agent to Warp only: hooks emit OSC 777 to `warp://cli-agent` with JSON. | Yes: Claude Code needs the `warp@claude-code-warp` plugin (auto-install chip) and `jq`. Codex/OpenCode need plugin or config change. | Cannot be read by MinMacs. Absence of an API is an absence of evidence, not proof. |
| **WezTerm** | Title, cwd, per-pane user vars, semantic zones (OSC 133), foreground process (local panes only), `progress` (nightly only). | `wezterm cli list --format json`: window/tab/pane ids, title, cwd, size. Everything richer is Lua inside WezTerm (`pane:get_foreground_process_info()`, `get_semantic_zones()`, events `user-var-changed`, `update-status`). | None for title/cwd. Shell integration for prompt zones and user vars. | Last release 20240203; main still active (commit 2026-09-29). Documentation drifts from the release. |
| **kitty** | Per window: `title`, `pid`, `cwd`, `cmdline`, `foreground_processes`, `at_prompt`, `last_cmd_exit_status`, `is_focused`, `user_vars`, `env`. Progress from OSC 9;4 drawn in tab title (0.39) and a bar (0.47) but not in `ls`. | `kitten @ ls` (JSON) over a socket: needs `allow_remote_control` and `--listen-on` in kitty config. | User config change once, none per harness. Shell integration for `at_prompt`. | Rich and structured. Opt-in is the barrier. `env` in the output is sensitive. |
| **tmux** | Per pane: `pane_pid`, `pane_tty`, `pane_current_command`, `pane_title`, `pane_current_path`, `window_activity`, alerts (`monitor-activity`, `monitor-silence`, `monitor-bell`). 3.7+: `pane_pb_state`, `pane_pb_progress` (OSC 9;4). 3.8 (in rc): `pane_last_output_time`, `pane_last_prompt_time`, hooks `pane-command-started/finished`, `pane-shell-prompt`. | `tmux list-panes -a -F '<formats>'` on the per-user socket, no opt-in. Control mode `tmux -C` for a live `%output`/notification stream. | None. | Deterministic for what it exposes. Only sees what tmux parsed; OSC passthrough is off by default (`allow-passthrough`). |

Standalone Ghostty and cmux are different products with one terminal core: inside cmux `TERM_PROGRAM=ghostty` and `TERM_PROGRAM_VERSION=1.3.2-cmux-...` [L5]. Tell cmux from Ghostty by `CMUX_SURFACE_ID` / `CMUX_SOCKET_PATH` in the process environment or by the app bundle id `com.cmuxterm.app`, never by `TERM_PROGRAM`.

## 2. cmux in detail (the only host with local proof)

### Channels

| Channel | What it gives | Auth | Cost | Notes |
|---|---|---|---|---|
| `~/.cmuxterm/workstream.jsonl` [D1, L6] | Append-only audit of every Feed event. Record keys: `id, workstreamId, source, kind, createdAt, updatedAt, title, cwd, ppid, status, payload, context`. `workstreamId` is `claude-<session uuid>`. | None (mode 644, same-user read). | 70 MB, 44,852 lines; read the tail (3 MB tail parsed in one pass). | `payload`, `context`, `tool_input` and `lastUserMessage` hold private text. MinMacs must read only `kind, createdAt, workstreamId, cwd`. Format keys are not documented, only the path [D1]. |
| `~/.cmuxterm/claude-hook-sessions.json` [D3, L7] | session id to pid, workspaceId, surfaceId, cwd, startedAt, updatedAt, launchCommand, lastSubtitle. | None. | 10 KB. | Stale entries (below). Docs say entries carry a `lifecycle` field; the Claude entries here have none. |
| Socket `feed.list` [L8] | Last 2000 Feed items as JSON. | `cmuxOnly`. | 1.3 MB reply, 22 s wall clock here; one call timed out at 10 s. | Do not poll. Contains `tool_input`. |
| Socket `system.tree`, `system.top`, `list-status`, `sidebar-state` [L3] | Topology, titles, tty per surface, process tree and RSS per surface, sidebar pills. | `cmuxOnly`. | Fast (under 1 s). | `list-status` shows one `claude_code=Running` pill per workspace, not per surface. |
| `cmux events` / `events.stream` [D4] | Reconnectable stream: `agent.hook.<Event>`, `feed.item.*`, `notification.created`, `workspace.prompt.submitted`, sidebar and progress events. | Socket auth. | Live. | Not in 0.64.3: `cmux events` prints `Unknown command 'events'`, `rpc events.stream` returns `method_not_found` [L1]. |
| Notifications OSC 9/99/777 [D2] | cmux stores them and exposes `notification.*` and `list-notifications`. Agent-origin notifications carry `agent.kind/category/pending/isSubagent`. | Socket. | Small. | It suppresses OSC banners on surfaces running a hook-integrated agent and takes the hook path instead. |
| Shell integration [L11] | Per panel `report_shell_state prompt|running`, `report_tty`. | Socket. | Small. | Says running for the whole agent lifetime (finding 2). |

Claude Code hooks injected by the wrapper (read from a live process's `--settings` argument) [L4]: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Notification`, `PermissionRequest`, `Stop`, `SessionEnd`; `Stop` and `PermissionRequest` also go to `cmux hooks feed --source claude`. No `PostToolUse` and no `SubagentStop`. The wrapper also sets `preferredNotifChannel: notifications_disabled`, so Claude's own OSC notifications are turned off inside cmux.

Feed `kind` values seen across the whole log [L6]: `toolUse` 39,158, `stop` 2,661, `userPrompt` 1,486, `sessionStart` 659, `toolResult` 569, `sessionEnd` 230, `question` 87, `permissionRequest` 2. In a 2,000-item slice the 21 `toolResult` items all carried `tool_name: notification`, so `toolResult` here is the Notification hook, not a tool result [I, equal counts].

### The measured comparison (one snapshot, 2026-09-29 ~14:00 local)

Seven Claude Code sessions run inside cmux. Ground truth is the `caffeinate -i -t 300` child that Claude spawns during a turn (already in `registry/agents/claude-code.json`).

| tty | cmux title glyph [L3] | caffeinate child [L10] | last Feed kind and age [L6] | verdict |
|---|---|---|---|---|
| ttys003 (this session) | `◐` | yes | `toolUse`, 0-4 s | all agree: working |
| ttys002 | `◑` | yes | `toolUse`, 479-548 s | working; Feed silent for 8+ min during one long tool call, so age alone would say idle |
| ttys010 | `◑` | yes | `stop`, repeated, 4-61 s | title and caffeinate say working, Feed says stopped: disagreement (session emits repeated Stops; cause not determined) |
| ttys012 | `✳` | no | `toolResult`(notification), 8,568 s | idle; a "toolResult means working" rule would be wrong |
| ttys000, ttys001, ttys007 | `✳` | no | none in the 2,000-item slice | idle |

- **Title glyph vs caffeinate: 7 of 7 agree** (3 animated glyph with caffeinate, 4 `✳` without). Claude Code's code marks it: the tab title component gets `isAnimating: (state==="busy")` [L9]. The glyph is a Claude Code convention, read from the host's title, no setup. Frames `◐`/`◑` seen; the full frame set was not extracted.
- **Feed state by last kind** (`userPrompt`/`toolUse` = working, `stop`/`sessionEnd` = idle, `toolResult`(notification) = waiting) is right for 3 of the 4 sessions that have a recent Feed record (ttys003, ttys002, ttys012) and wrong for ttys010 (repeated Stop while working). It does not depend on age. Age thresholds fail on long tools because `PostToolUse` is not hooked.
- **`claude-hook-sessions.json` is not a state source.** 11 entries, 7 alive; 3 entries (`1c46b214`, `c008b73b`, `d868084f`) share pid 54300 after resume/fork; `lastSubtitle` read `Waiting` for two sessions that were mid-turn (caffeinate present). Use it only for session to pid to surface mapping, and verify the pid is alive and the start time matches.
- **cmux tty attribution collides.** `cmux tree` reports `tty=ttys003` for both surface:4 (workspace 1) and surface:8 (workspace 2) [L3]. `ps` shows one claude on ttys003 and one on ttys009 that matches no surface [L10]. Map by pid from the hooks store, not by tty [I].

## 3. Terminal conventions: who parses them, who exposes them

| Sequence | Meaning | Emitted by harnesses | Parsed by hosts | Readable from outside |
|---|---|---|---|---|
| OSC 0 / 2 | Title. Claude Code sets it, with a busy/idle glyph. | Claude Code [L3, L9]; others unknown | All | Yes: cmux `tree`, Ghostty/iTerm2 `name`, kitty/WezTerm `title`, tmux `pane_title` |
| OSC 9;4 | Progress: 0 clear, 1 percent, 2 error, 3 indeterminate, 4 paused (ConEmu) | Claude Code default on [L9]; hooks may also send it (allowlist accepts 9;4) [L9] | iTerm2 [D-I1], Ghostty (`progress-style`) [S-G1], kitty 0.39+ [S-K3], WezTerm nightly [S-W3, S-W4], tmux 3.7+ [S-T1, S-T2]. cmux: unknown, cmux's own `set-progress` is a separate sidebar bar. | **tmux only** (`pane_pb_state`, `pane_pb_progress`). WezTerm exposes it to Lua only. kitty `ls` has no progress field [S-K2]. |
| OSC 133 A/B/C/D | Prompt start, command input, output start, command end with exit status. Spec: freedesktop semantic-prompts | Shells, via shell integration (iTerm2, kitty, WezTerm, Ghostty, cmux scripts) | Ghostty (notify-on-command-finish, close confirm) [S-G1], iTerm2 (marks, `is at shell prompt`) [D-I4], kitty (`at_prompt`) [S-K2], WezTerm (semantic zones) [D-W1], tmux (3.4 prompt marks; 3.8 hooks) [S-T1] | kitty `at_prompt`, iTerm2 `is at shell prompt`, tmux 3.8. Not useful for working/idle (finding 2). |
| OSC 9 (text), OSC 777 `notify`, OSC 99 (kitty) | Desktop notification. Warp's `warp://cli-agent` rides on 777. | Claude Code (channel `auto`; cmux forces disabled), Warp plugin, Codex `notify` | Ghostty (`desktop-notifications`), iTerm2, kitty (9/777/99), WezTerm (toast on OSC 9), cmux, Warp | cmux store only. Everything else shows a banner and forgets. |
| OSC 1337 SetUserVar | Key/value per pane | Shell integration; a harness could set it | iTerm2, kitty (`user_vars`), WezTerm (`user_vars`) | kitty `ls`, WezTerm Lua/`PaneInformation`. Needs the harness to set a var: per-harness. |

## 4. Per-host evidence notes

### cmux
- Feed is advisory: hooks block at most 120 s; on timeout the agent falls back to its own prompt [D1]. So Feed says "waiting" only while the user has not answered inside cmux and only briefly.
- Hibernation kills idle background agents (SIGTERM) after `idleSeconds`, only when lifecycle is `idle` [D3]. Useful for MinMacs: a vanished agent process may be hibernation, resume command is `claude --resume <id>`.
- Hook integrations exist for 18 agents; list in [D3]. Codex Feed hooks are non-blocking telemetry [D1].
- Docs are for `main`; `cmux sessions`, `cmux events`, `workspace status`, `agent-hibernation` are all missing in 0.64.3 [L1]. Feature-detect through `system.capabilities` (`methods` array) [L1].

### Ghostty
- Config reference: `desktop-notifications` (OSC 9/777), `progress-style` (OSC 9;4), `notify-on-command-finish` since 1.3.0 needs shell integration or OSC 133 [S-G1].
- AppleScript since 1.3.0 [D-G3]. `pid` and `tty` properties are absent from the v1.3.0 and v1.3.1 sdef and present on main [S-G2, L12]. Latest tags: v1.3.1, v1.3.0 [S-G5].
- cmux's own sdef has no `pid`/`tty` [L12].

### iTerm2
- Escape codes page documents OSC 9;4 with states 0-4, `OSC 1337;SetMark`, `CurrentDir`, `SetUserVar`-style custom vars [D-I1]. Its shell integration script emits OSC 133 A/B/C/D and `1337;ShellIntegrationVersion=19` [S-I2].
- AppleScript `session`: `is processing`, `is at shell prompt`, `tty`, `name`, `contents`, `id` [S-I3, D-I5]. Docs page labels AppleScript deprecated in favour of the Python API.
- Python API session variables `jobName`, `jobPid`, `commandLine`, `lastCommand`, `tty` [D-I6]; subscriptions for prompt, screen update, location, custom escape `1337;Custom=` [D-I7].
- Enabling the Python API in Settings was not confirmed in fetched text; docs only say scripts not launched from iTerm2 are prompted for permission [D-I8]. [I]

### Warp
- Auto-detects Claude Code, Codex, OpenCode and shows an "agent toolbelt"; notifications need a one-time plugin or config change [D-P1, D-P2].
- Plugin hooks: SessionStart, Stop, Notification(idle_prompt), PermissionRequest, UserPromptSubmit, PostToolUse, StopFailure. Payload `{v, agent, event, session_id, cwd, project, ...}` to `warp://cli-agent` through OSC 777; version negotiated with `WARP_CLI_AGENT_PROTOCOL_VERSION` [S-P3]. Delivery on Claude Code 2.1.141+ is the hook's `terminalSequence` output field, older versions write `/dev/tty` [S-P3].
- Claude Code accepts `terminalSequence` only for OSC 0/1/2/9/99/777 and BEL, and OSC 9;4 [L9].

### WezTerm
- Shell integration gives OSC 7, OSC 133 zones, OSC 1337 user vars (`WEZTERM_PROG`, `WEZTERM_USER`, `WEZTERM_HOST`, `WEZTERM_IN_TMUX`); tmux needs `allow-passthrough on` for user vars [D-W1].
- `Alert` enum has bell, toast, cwd, titles, palette, user var; no progress alert [S-W4]. Parser has `ConEmuProgress` [S-W4]. `PaneInformation.progress` is marked nightly [D-W3].
- Foreground process info: local panes only, mux panes do not report it [D-W2].
- Releases: latest is 20240203-110809-5046fc22; main commit dated 2026-09-29 [S-W5].

### kitty
- Remote control needs `allow_remote_control` or a password, and `--listen-on` for use from outside [D-K1]. `ls` fields listed in [S-K2]. Match language can select windows by `cmdline:`, `title:`, and user vars [D-K1].
- OSC 133 marks (A, A;k=s, C, D;status) and extras [D-K3]. OSC 99 notification protocol [D-K4]; OSC 9 and 777 handled in `desktop_notify`, and OSC 9;4 is intercepted there as progress [S-K4].
- Changelog: progress in tab title 0.39.0 (2025-01-16), progress bar at window top 0.47.0 (2026-05-19) [S-K3].

### tmux
- 3.4 added OSC 133 prompt marks; 3.7 added OSC 9;4 handling and forwarding to the outer terminal; 3.8 (3.8-rc2 published 2026-09-09) adds hooks for OSC 133 events and monitors (`set-hook -B`) [S-T1, S-T6].
- Format variables `pane_current_command`, `pane_pid`, `pane_tty`, `window_activity` are in the installed 3.6a man page [L13]. `pane_pb_state`, `pane_pb_progress`, `pane_last_output_time`, `pane_last_prompt_time` are in master `format.c` [S-T2], not in the 3.6a man page [L13].
- cmux can run tmux under it (`cmux local-tmux`, remote `mosh-tmux`) [D6]. Hooks inside tmux report to the cmux workspace attached [D3].

## 5. Ranked recommendation: what MinMacs should read first

MinMacs is a separate same-user process. It should prefer signals that need no consent, no host config change and no per-harness install, and use them to confirm the process evidence it already has (caffeinate child, transcript write, tree CPU).

| Rank | Signal | Why | Cost and risk |
|---|---|---|---|
| 1 | **cmux `workstream.jsonl` tail + `claude-hook-sessions.json`** (only when `com.cmuxterm.app` is running) | Only source of `waiting` (question, permissionRequest, notification kinds) and of session to surface mapping. State by last `kind`, never by age. Zero setup for Claude Code under the wrapper. | Read only `kind, createdAt, workstreamId, cwd`; the same file holds prompts and tool inputs. Treat repeated `stop` and multi-minute silence during a tool as "unknown, defer to process evidence". Verify pid alive before trusting a store row. Undocumented record format. |
| 2 | **tmux `list-panes -a -F`** with `pane_pid, pane_tty, pane_current_command, pane_title, window_activity`; add `pane_pb_state, pane_pb_progress` when `tmux -V` is 3.7 or later, `pane_last_output_time` on 3.8 | Works for any harness, any user, no opt-in. Title carries Claude's busy glyph. On 3.7+ it is the only outside-readable OSC 9;4. | Installed 3.6a lacks the progress formats, so feature-detect per format (an unknown format expands empty). `window_activity` is any output, coarse. |
| 3 | **Window/tab title glyph through the host's own list** (iTerm2 `name`, kitty/WezTerm `title`, Ghostty `name`, cmux `tree`) | 7 of 7 agreement with caffeinate on this Mac. No install. | The glyph is a Claude Code convention. Per-harness title rules go in the registry (`title_signal`), not the host code. |
| 4 | **iTerm2 AppleScript `is processing` / `is at shell prompt` / `tty`** | Only host with a built-in generic "recent output" flag for any program. | Documentation-only here. AppleScript is deprecated; needs an Automation consent prompt. `is at shell prompt` false without shell integration. |
| 5 | **kitty `kitten @ ls`** (`foreground_processes`, `at_prompt`, `title`, `user_vars`) | Richest structured data of any terminal. | Needs `allow_remote_control` and `listen-on`, so only read it when the user already enabled it. Do not store `env`. |
| 6 | **cmux socket** (`system.tree`, `system.top`, `list-status`, later `events.stream`) | Gives titles, tty and per-surface process trees, and a live stream once cmux is new enough. | Blocked by `cmuxOnly` for MinMacs [L2]. Offer it as an opt-in (`password` mode), never require it. Never call `feed.list`. |
| 7 | **WezTerm `cli list --format json`** | Title and cwd for any pane. | Nothing about agent state. Progress and prompt zones are Lua-only. Last release is 2024. |
| 8 | **Ghostty AppleScript** | Title and cwd. | `pid`/`tty` only in unreleased main. Detection of cmux vs Ghostty needs `CMUX_*`, not `TERM_PROGRAM`. |
| skip | **Warp**, and all raw OSC sequences (9, 777, 99, 133) | Warp has no outside API found; raw sequences are not readable without being the pty owner. | Record Warp as `host_signal: none`. OSC 133 adds nothing for working vs idle. |

Registry consequences (no code change in the harness rows):
- Add a per-harness `emits_osc_9_4` and a `title_signal` (glyph set and meaning). Claude Code: `emits_osc_9_4: true` [L9]; title busy glyph frames include `◐ ◑`, idle `✳` [L3].
- Treat `waiting` as unavailable outside cmux and Warp. Do not invent it from CPU.
- Keep the process evidence as the anchor and use host signals to raise or lower confidence, since the host can disagree (ttys010 row).

## 6. Not verified

- Every claim about iTerm2, Warp, WezTerm, kitty and standalone Ghostty comes from docs and source only; none is installed here.
- Whether `wezterm cli` and iTerm2 AppleScript work with no opt-in beyond a one-time TCC/mux discovery is inferred.
- Whether Claude Code actually emits OSC 9;4 at runtime and which frames its title spinner uses were not observed on the wire (that needs a pty tap). The setting default and title animation flag are from the binary [L9].
- Whether cmux surfaces OSC 9;4 anywhere in its UI is unknown; no doc mentions it.
- The repeated-`stop` disagreement on ttys010 was seen once. Not tested whether it is a looping or background-task session.
- `cmux.json` was not parsed (JSONC parse failed in a quick check), so the effective `socketControlMode` comes from `system.capabilities` (`cmuxOnly`).
- Side effects of this research, in the interest of full disclosure: one `tmux new-session -d -s __probe_ro` was run by mistake and killed immediately (`tmux ls` then reported no server); one `cmux rpc events.stream` call timed out and a later one returned `method_not_found`. No agent session was started, resumed or messaged. No cmux state was changed. Downloaded docs and scratch files are in the session scratchpad, outside the repo.

## Sources

Local observations (commands run 2026-09-29):
- L1 `cmux capabilities` printed `socket_path ".../Application Support/cmux/cmux.sock"`, `access_mode "cmuxOnly"`, 200+ methods incl. `feed.push/list/permission.reply`, `notification.*`, `surface.report_shell_state`, `surface.report_tty`, `system.top/tree/identify`, `workspace.prompt_submit`; no `events.stream`. `cmux events --help` printed `Unknown command 'events'`. `cmux rpc nonexistent.method` and `cmux rpc events.stream '{"categories":["agent"]}'` printed `Error: method_not_found: Unknown method`. `cmux --version` printed `cmux 0.64.3 (83) [aea6cfcde]`.
- L2 A python double-fork with `setsid` (ppid=1) ran `env -i HOME=... /Applications/cmux.app/Contents/Resources/bin/cmux ping` and `list-workspaces`: both `Error: Failed to write to socket (Broken pipe, errno 32)`. The same commands from this terminal print `PONG` and the workspace list.
- L3 `cmux tree --all`, `cmux top --all`, `cmux list-status` (`claude_code=Running icon=bolt.fill color=#4C8DFF`), `cmux sidebar-state` (`progress=none`, `status_count=1`), `cmux surface-health`, `cmux identify --json`, `cmux list-workspaces`, `cmux list-notifications` (`No notifications`). Titles show `✳`, `◑`, `◐` prefixes.
- L4 `ps -p 3891 -o args=` parsed: `--settings {"preferredNotifChannel":"notifications_disabled","hooks":{SessionStart,Stop,SessionEnd,Notification,UserPromptSubmit,PreToolUse,PermissionRequest}}`, each command `"${CMUX_CLAUDE_HOOK_CMUX_BIN:-cmux}" hooks claude <event>` or `hooks feed --source claude`; timeouts 10/5/1 s and 125 s for PermissionRequest. `head /Applications/cmux.app/Contents/Resources/bin/claude`: "cmux claude wrapper - injects hooks and session tracking", passthrough when `CMUX_SURFACE_ID` unset or `CMUX_CLAUDE_HOOKS_DISABLED=1`.
- L5 `env | grep`: `TERM_PROGRAM=ghostty`, `TERM_PROGRAM_VERSION=1.3.2-cmux-ios-manual-io-minimal-clean-20260501-+22fa801f8`, `CMUX_SURFACE_ID`, `CMUX_WORKSPACE_ID`, `CMUX_SOCKET_PATH`, `CMUX_CLAUDE_PID`, `CMUX_AGENT_LAUNCH_KIND=claude`, `GHOSTTY_SURFACE_ID`.
- L6 `ls -la ~/.cmuxterm`: `workstream.jsonl` 69,836,263 bytes, mode 644; `claude-hook-sessions.json` 9,903 bytes. Key names of the last `workstream.jsonl` record: `status, workstreamId, createdAt, source, title, ppid, updatedAt, cwd, kind, payload, context, id`; `context` keys `allowedPrompts, assistantPreamble, lastUserMessage, permissionMode`. Kind histogram over 44,852 lines computed with python (no content printed). Per-session last kind and age from a 3 MB tail.
- L7 Key names of one `claude-hook-sessions.json` record: `cwd, lastBody, lastSubtitle, launchCommand, pid, sessionId, startedAt, surfaceId, updatedAt, workspaceId`. 11 entries, 7 pids alive, 3 sharing pid 54300. No `lifecycle` key.
- L8 `cmux rpc feed.list '{}'`: 2000 items, keys `created_at, cwd, id, kind, source, status, title, tool_input, tool_name, updated_at, workstream_id`, `status` always `telemetry`; 1,309,894 bytes in 22.0 s (`time`); an earlier call with a 10 s timeout returned nothing.
- L9 `strings -a ~/.local/share/claude/versions/2.1.284`: `terminalProgressBarEnabled:!0` in defaults; `terminalProgressBarEnabled:()=>O().optional().describe("Emit OSC 9;4 progress sequences during long operations")`; `showStatusInTerminalTab` (label "Show status in terminal tab", default false) and `e(t5,{titles:G,isAnimating:Ko,noPrefix:io})` with `Ko=ko==="busy"`; `preferredNotifChannel:"auto"`; `messageIdleNotifThresholdMs:60000`; text "returned a terminalSequence that was rejected by the allowlist (only OSC 0/1/2/9/99/777 and BEL are permitted, and OSC 9 bodies may not begin with a digit unless in the 9;4 progress form)".
- L10 `ps -axo pid=,ppid=,pcpu=,tty=,etime=,args=` filtered to claude and caffeinate: caffeinate children `-i -t 300` on ttys002, ttys003, ttys010 only; claude on ttys000, 001, 002, 003, 007, 009, 010, 012.
- L11 `sed -n 505,535p /Applications/cmux.app/Contents/Resources/shell-integration/cmux-zsh-integration.zsh`: `_cmux_report_shell_activity_state` sends `report_shell_state <state> --tab= --panel=`; called with `running` (preexec) and `prompt` (precmd).
- L12 `grep name="pid" /Applications/cmux.app/Contents/Resources/cmux.sdef` returned 0 matches. Ghostty `macos/Ghostty.sdef` at tags v1.3.0 and v1.3.1: 0 matches for `name="pid"|name="tty"`; on main: 2 (lines 93-94).
- L13 `tmux -V` printed `tmux 3.6a`; `man tmux | col -b` contains `pane_current_command`, `pane_pid`, `pane_tty`, `window_activity`, `next-prompt`, control mode notifications; no `pane_pb_`, `pane_last_output_time` or `pane_last_prompt_time`.

Official docs and vendor source (fetched 2026-09-29):
- D1 https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/feed.md
- D2 https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/notifications.md
- D3 https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/agent-hooks.md
- D4 https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/events.md
- D5 https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/configuration.md ("Automation socket trust boundary") and https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json (`automation.socketControlMode`, enum off/cmuxOnly/automation/password/allowAll/openAccess/fullOpenAccess/notifications/full, default `cmuxOnly`)
- D6 https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/cli-contract.md and https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/local-tmux.md
- S-G1 https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/config/Config.zig (`notify-on-command-finish` lines 1195-1214, `desktop-notifications`, `progress-style`, `confirm-close-surface`)
- S-G2 https://raw.githubusercontent.com/ghostty-org/ghostty/main/macos/Ghostty.sdef
- D-G3 https://ghostty.org/docs/features/applescript
- S-G4 https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/terminal/osc.zig (`conemu_progress_report`, `semantic_prompt`, `show_desktop_notification`, `kitty_desktop_notification`)
- S-G5 https://api.github.com/repos/ghostty-org/ghostty/tags (v1.3.1, v1.3.0, v1.2.3)
- D-I1 https://iterm2.com/documentation-escape-codes.html (OSC 9 and `9;4` states, SetMark, CurrentDir)
- S-I2 https://raw.githubusercontent.com/gnachman/iTerm2/master/Resources/shell_integration/iterm2_shell_integration.zsh (OSC 133 A/B/C/D, `ShellIntegrationVersion=19`)
- S-I3 https://raw.githubusercontent.com/gnachman/iTerm2/master/iTerm2.sdef (`is processing` line 561, `is at shell prompt` 565, `tty` 575)
- D-I5 https://iterm2.com/documentation-scripting.html (AppleScript deprecated; property descriptions)
- D-I6 https://iterm2.com/documentation-variables.html
- D-I7 https://iterm2.com/python-api/notifications.html
- D-I8 https://iterm2.com/python-api/tutorial/running.html
- D-P1 https://docs.warp.dev/agents/cli-agents/claude-code/
- D-P2 https://docs.warp.dev/agents/capabilities/agent-notifications/ and https://docs.warp.dev/agents/cli-agents/overview/
- S-P3 https://github.com/warpdotdev/claude-code-warp (README.md, plugins/warp/hooks/hooks.json, scripts/build-payload.sh, emit-terminal-sequence.sh, should-use-structured.sh)
- D-W1 https://raw.githubusercontent.com/wezterm/wezterm/main/docs/shell-integration.md
- D-W2 https://raw.githubusercontent.com/wezterm/wezterm/main/docs/config/lua/pane/get_foreground_process_info.md and https://raw.githubusercontent.com/wezterm/wezterm/main/docs/cli/cli/list.md
- D-W3 https://raw.githubusercontent.com/wezterm/wezterm/main/docs/config/lua/PaneInformation.md
- S-W4 https://raw.githubusercontent.com/wezterm/wezterm/main/wezterm-escape-parser/src/osc.rs and https://raw.githubusercontent.com/wezterm/wezterm/main/term/src/terminal.rs (`enum Alert`)
- S-W5 https://api.github.com/repos/wezterm/wezterm/releases (latest 20240203-110809-5046fc22) and /commits (2026-09-29)
- D-K1 https://raw.githubusercontent.com/kovidgoyal/kitty/master/docs/remote-control.rst
- S-K2 https://raw.githubusercontent.com/kovidgoyal/kitty/master/kitty/window.py (`as_dict`, lines 2342-2362)
- S-K3 https://raw.githubusercontent.com/kovidgoyal/kitty/master/docs/changelog.rst (0.47.0 progress bar; 0.39.0 progress in tab title)
- D-K3 https://raw.githubusercontent.com/kovidgoyal/kitty/master/docs/shell-integration.rst (OSC 133)
- D-K4 https://raw.githubusercontent.com/kovidgoyal/kitty/master/docs/desktop-notifications.rst (OSC 99)
- S-K4 kitty/window.py `desktop_notify` (OSC 9, 777, 1337, and the 9;4 branch)
- S-T1 https://raw.githubusercontent.com/tmux/tmux/master/CHANGES (3.4 prompt marks; 3.7 progress; 3.8 OSC 133 events, `set-hook -B`, `pane_last_output_time`)
- S-T2 https://raw.githubusercontent.com/tmux/tmux/master/format.c (`pane_pb_progress`, `pane_pb_state`, `pane_last_output_time`, `pane_last_prompt_time`)
- S-T6 https://api.github.com/repos/tmux/tmux/releases (3.8-rc2 2026-09-09, 3.7c 2026-08-17)
- D-OSC133 https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md (linked from Ghostty's osc.zig and WezTerm docs; not fetched, semantics taken from kitty and WezTerm docs)
