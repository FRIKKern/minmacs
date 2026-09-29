# What the remaining hosts can tell us about agents running inside them

Date: 2026-09-29. Machine: macOS 15.3 (Darwin 24.3.0, build 24D60), arm64.
Extends `registry/evidence/hosts.md` (cited below as `hosts`), which covers cmux, Ghostty, iTerm2, Warp, WezTerm, kitty and tmux. Nothing from `hosts` is repeated: its findings 1 to 5 (escape sequences are one-way, OSC 133 cannot tell working from idle, Claude Code emits OSC 9;4 and a busy glyph in the title, cmux socket closed by default, hooks are the only "waiting" signal) still apply and are referred to by number.

Installed here, of the hosts in this file: Terminal.app 2.14 (not running) and Cursor 3.15.6 (running). Not installed: Herdr, Zellij, Alacritty, VS Code proper (`/usr/local/bin/code` is a dangling symlink to `/Applications/Visual Studio Code.app`), any JetBrains IDE [L1]. So Herdr, Zellij, Alacritty, JetBrains and Terminal.app's scripting behaviour are documentation and source only. Every claim carries a tag.

Tags: [L] observed on this Mac, [D] official docs, [S] vendor source (read in a clone, or fetched raw), [T] third-party report, [I] inferred by me. Source ids are at the end.

## Answer in one screen

```
 agent (claude, codex ...)  -- writes to its pty -->  HOST
                                                       |
   MinMacs (separate app, same user, ppid=1)           |
        |                                              v
        |   Herdr      unix socket, 0600, JSON lines: per-pane working/blocked/idle/done   YES, no consent
        |   Zellij     CLI over a 0700 socket: title, command, cwd, focus; no state        yes, no consent
        |   Terminal   AppleScript: tty, busy, processes, title; scrollback too (private)  yes, Automation consent
        |   VS Code    nothing outside the app (extension API is in-process only)          no
        |   Cursor     same as VS Code                                                     no
        |   JetBrains  nothing read-only (MCP server is opt-in and its terminal tool runs commands)  no
        |   Alacritty  nothing (its socket only creates windows and edits config)         no
```

Six findings:

1. **Herdr is the first host with a first-class, machine-readable agent state that needs no consent and no per-agent install.** Every pane carries `agent_status` in `idle | working | blocked | done | unknown`, exposed over a same-user Unix socket, with push events [D1, S1]. This is `hosts` finding 5 answered for a new host: Herdr computes "blocked" itself, from screen manifests, without hooks. It is not ground truth (finding 4 below).
2. **Herdr's detector is the same signal we already have, read from the terminal.** For Claude Code, Codex and most others its state authority is a "screen manifest": rules over the terminal title, OSC 9;4 progress and the bottom of the screen [D2, S3]. Hooks are used only for Pi, OMP, OpenCode, Kilo, Kimi, MastraCode [D2]. So Herdr and the title glyph in `hosts` finding 3 are one signal, not two independent ones.
3. **Herdr's public detection manifests are the best source we found for per-harness title and progress conventions.** Table in section 3. It confirms `hosts` finding 3 (Claude Code emits OSC 9;4) from a second, independent source and supplies the busy-glyph frame set that `hosts` section 6 says it did not extract.
4. **Only Terminal.app, Herdr and Zellij can be asked without installing anything into the host.** None of the other three (Alacritty, VS Code family, JetBrains) exposes a read path to a foreign process.
5. **A multiplexer hides the outer terminal.** Under Herdr and Zellij the agent's parent chain ends at the multiplexer's server, not at the terminal app, and the outer terminal's title, tty and busy state belong to the client TUI. Same class as tmux in `hosts`. [I, from D3 concepts and S8 `--server`]
6. **"busy" in Terminal.app means "a non-shell process is in the tab", not "the agent is working".** Same limit as OSC 133 in `hosts` finding 2. [D-sdef + T1 for the definition, I for the agent consequence]

## 1. Host by host

Columns: what it knows about a running agent / how another same-user process can ask / consent or configuration / reliability.

| Host | Knows | How to ask | Consent or setup | Reliability |
|---|---|---|---|---|
| **Herdr** 0.9.1 (2026-09-16), Rust, Apache-2.0 [D1, L2] | Per pane: `agent` label, `agent_status` (idle, working, blocked, done, unknown), `workspace_id`, `tab_id`, `pane_id`, `cwd`, `foreground_cwd`, `terminal_title` (latest OSC 0/2) and `terminal_title_stripped` (one leading spinner glyph removed), optional `agent_session` id, `state_change_seq`, `interactive_ready`. Per pane on request: shell pid, foreground pgid, foreground processes with pid, name, argv, cwd [S1, D3]. | Unix socket `~/.config/herdr/herdr.sock`; named sessions `~/.config/herdr/sessions/<name>/herdr.sock` (config dir is `$XDG_CONFIG_HOME/herdr` if set, else `$HOME/.config/herdr`) [D3, S4]. Newline-delimited JSON: `{"id":"1","method":"agent.list","params":{}}`. Also CLI `herdr agent list`, `herdr api snapshot`, push events `pane.agent_status_changed` via `events.subscribe` [D3]. | None for the socket: mode 0600 set by the server [S5], no peer-credential check found in `src` (grep for `peer_cred`, `SO_PEERCRED`, `getpeereid`, `LOCAL_PEERCRED` returned nothing) [S5]. The user must run their agents inside Herdr panes. No per-agent install for Claude Code state: it comes from the screen manifest. `herdr integration install claude` adds session identity only and edits `~/.claude/settings.json` [D4]: do not run it. | Not measured against `caffeinate` (not installed). Design is strict about "blocked": only when the visible approval UI matches, else falls back to `idle`; Codex falls back to `unknown` and can stay there after a response [D2]. Pre-1.0, 1,773 commits, API protocol 22 [S2, L2]: expect method churn. Ignore unknown fields; unknown methods return normal errors [D3]. |
| **Terminal.app** 2.14, build 455 [L3] | Per tab: `tty`, `busy`, `processes` (list of names), `custom title`, `title displays custom title`, visible `contents`, whole `history`; per window: `name` = "the full title of the window", `id`, `frontmost`, `visible` [D-sdef]. | AppleScript or ScriptingBridge to `com.apple.Terminal`. Tab `tty` joins to `ps` tty directly [I]. | Automation consent, the standard TCC prompt on the first Apple event [I; MinMacs already handles this for browsers: `Sources/Browser.m:38` prints the "Allow MinMacs under Automation" message]. Sending an Apple event to a target that is not running launches it [I, standard Apple event behaviour]: check it is running first and address it by pid, as invariant 2a in `AGENTS.md` already does for browsers. | `busy` is true while any process other than the shell and the profile's "clean commands" runs [D-sdef text, T1 dump: an idle fish tab shows `busy status:false`, processes `{login, -fish}`, clean commands `{screen, tmux}`]. An agent is one long-running process, so it reads busy for its whole life. Whether Claude Code's glyph title lands in window `name` was not observed [I]. Never read `contents` or `history`: that is the conversation. |
| **Zellij** 0.45.1 (2026-08-28) [L4] | Per pane (`zellij action list-panes --json --all`): `id`, `is_plugin`, `is_focused`, `is_fullscreen`, `is_floating`, `is_suppressed`, `title` (from OSC 0/2), `exited`, `exit_status`, `is_held`, `terminal_command` (command panes only), `pane_command` and `pane_cwd` (looked up from the pty, 100 ms timeout per pane), plus `tab_id`, `tab_position`, `tab_name` [S6, S7]. No pid, no tty, no agent notion. | CLI over a per-session Unix socket. Server process is `zellij --server <socket path>` [S8]. Shipped in 0.44.0 (2026-03-23) [S9]. Session flag: `zellij --session <name> ...` [S10, I for `action` combined with it]. | None. Socket file gets mode 0o1700 [S11]. Location: `$TMPDIR/zellij-<uid>/contract_version_1/<session>` on macOS, override `ZELLIJ_SOCKET_DIR` [S12; the macOS `runtime_dir` being empty is I]. | Structured and stable, but only title and command. OSC 9;4 is parsed and thrown away: ConEmu sub-commands 1 to 12 are excluded from the notification path and stored nowhere [S13]. So the title glyph is the only busy signal that survives. Joining to a `ps` row is weak: cwd plus command, no pid [I]. `zellij subscribe --pane-id` streams pane content [S9]: never use. |
| **Alacritty** 0.17.0 (2026-04-06) [L5] | Nothing about processes. | `alacritty msg` over a socket in `$TMPDIR`: only `create-window`, `config`, `get-config` [S14]. No AppleScript dictionary in the bundle template: `Info.plist` has no `NSAppleScriptEnabled` and no `OSAScriptingDefinition` [S15]. | n/a | Not a source. Its `NSAppleEventsUsageDescription` is worded for programs running inside it, not for Alacritty scripting [S15]. Title (OSC 0/2) is in the window server only: reading it would need Accessibility or Screen Recording consent [I]. |
| **VS Code and forks** (Cursor 3.15.6 = VS Code 1.128.0 [L6]; VS Code latest 1.139.1, 2026-09-25 [S16]) | Inside the app: every terminal's name, pid, cwd, exit status, shell-integration state, each command line and exit code (`window.terminals`, `Terminal.processId`, `onDidStartTerminalShellExecution`, `onDidEndTerminalShellExecution`) [S17]. None of it leaves the extension host. | No external API. The CLI (`cursor --help`) lists `--status` (process usage and diagnostics), `--locate-shell-integration-path`, `--list-extensions`; nothing about terminals or agents [L6]. `~/Library/Application Support/Cursor/3.15-main.sock` is the CLI hand-off socket, undocumented [L7]. | An extension you install would be needed to read the API and relay it. Out of scope: install. | Not a source. See section 5 for what the process tree gives. Terminal OSC handlers registered in Cursor 3.15.6: 633, 1337, 133, 7, 9, 99; the OSC 9 handler is the ConEmu "9;9 cwd" one, no `9;4` progress handler found [L6]. |
| **JetBrains IDEs** (terminal tool window, "Junie", "Claude Code", "Codex" in the AI Agents dropdown) | Inside the app: terminal sessions, and it knows when Claude or Codex starts in one (it shows a setup banner) [D5]. | Built-in MCP server since 2025.2 for external clients [D6]. Its terminal tool is `execute_terminal_command` only: it runs a command and returns output [D6]. No tool that lists terminals or reports agent state. | Opt-in: Settings, Tools, MCP Server, "Enable MCP Server", with a dialog about third-party access. "Brave mode" removes per-command confirmation [D6]. | Not a source. The one terminal tool changes state, so it is off the table. Tab title can be set by OSC 0 [D5] but is not readable from outside [I]. |

## 2. Herdr in detail (the one that changes the design)

### What was read

- Repo `herdrdev/herdr`, HEAD `fc86d866aa7a` (2026-09-29 14:33 +0200), 41.4k stars, 3.2k forks, releases 91, latest stable v0.9.1 (2026-09-16) [L2]. Runtime is "one Rust binary": a background **server** owns every pty; the **client** TUI attaches and detaches [D3 concepts, D1]. Detach with `ctrl+b q`; the agents keep running.
- Process shape: `herdr` (client TUI), `herdr server` (headless server, `args[1] == "server"`), hidden `herdr client` and `herdr remote-client-bridge` [S19]. Pane processes are children of the server [I, from "server owns panes"].
- Agent states: `blocked`, `working`, `done`, `idle`, `unknown`. `done` = idle and not yet seen; seen state is tracked per client, so a client's Done badge can differ from the API's `agent_status` [D3 concepts, D7].
- State authority per pane: first the foreground process is recognised, then either lifecycle hooks (only when installed and reporting for that pane) or TOML manifests evaluated on the bottom of the screen buffer. Manifests can also match the terminal title and OSC progress [D2]. Local override: `~/.config/herdr/agent-detection/<agent>.toml`; remote manifest updates come from herdr.dev unless `[update] manifest_check = false` [D2].
- Claude Code: "screen manifest", integration role "session" only [D2, D4].
- `herdr agent explain <target>` and the socket method `agent.explain` return the matched rule and evidence [D2, D7]. That is a debugging aid for accuracy checks once Herdr is installed.

### Read-only requests MinMacs would use

```
{"id":"1","method":"ping","params":{}}                          -> {"result":{"type":"pong"}}
{"id":"2","method":"agent.list","params":{}}                    -> AgentInfo[]
{"id":"3","method":"pane.process_info","params":{"pane_id":"w1:p1"}}   -> shell pid, foreground pids, names, argv, cwd
{"id":"4","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.agent_status_changed"}]}}   (optional push)
```

`AgentInfo` keys [S1 schema]: `agent, agent_session, agent_status, completion_seq, cwd, display_agent, focused, foreground_cwd, interactive_ready, launch_pending, name, pane_id, revision, screen_detection_skipped, state_change_seq, state_labels, tab_id, terminal_id, terminal_title, terminal_title_stripped, title, tokens, workspace_id`. There is no pid: get it from `pane.process_info` and join to `ps` by pid. `PaneInfo` has the same identifiers plus `scroll` and `restore_error`.

Read only `pane_id, agent, agent_status, state_change_seq, terminal_title_stripped, cwd`. `title`, `terminal_title` and `tokens` can carry the user's own text (a Claude Code session title is one example) [I]. Never call `agent.read`, `pane.read`, `agent.prompt`, `agent.send_keys`, `pane.send_*`, `pane.run`, `agent.start`, or any close, split, move, `integration.*`, `plugin.*`, `server.stop` method: they either read the screen or change host state [D3].

### Where it can go wrong

- **Not per-turn truth.** `blocked` needs a known approval prompt on screen; an unknown prompt reads `idle` [D2]. A Herdr `working` from the title glyph is the same signal as `hosts` finding 3, so agreement between the two is not evidence.
- **Config dir lookup.** MinMacs is not started by the user's shell, so `XDG_CONFIG_HOME` may differ from what Herdr's server saw [S4, I]. Probe both `$HOME/.config/herdr` and every `sessions/*/herdr.sock`, connect, and treat a refused connection as a stale file. The server's own `HERDR_SOCKET_PATH` override is in its environment and not visible from `ps` [D3, I].
- **Stale-server check.** A socket file with no `herdr server` process is stale [I].
- **Wrapper agents.** A host-visible wrapper (VM, sandbox) hides the real agent; the user sets `HERDR_AGENT=<agent>` on it [D2]. Herdr does not look inside a tmux started in a pane; it sees `tmux` [D2].
- **Private state on disk.** `session.json` (layout, cwd, agent session ids) and, if the user enabled `[experimental] pane_history = true`, `session-history.json` (pane output) sit next to the socket [D8]. Do not read either.
- **Ancestry.** An agent in a Herdr pane has the server, not the terminal app, as ancestor (finding 5). To show "this Claude runs in Herdr", match `herdr server` in the ancestor chain, or use `pane.process_info` pids.

### Process-shape rule that holds under "command line only"

Server: `names: ["herdr"]`, `args_contain: ["server"]`. `args_contain` is a substring match on any argument, so a client started as `herdr --session server-x` also matches. How a named-session server is launched was not read, so add no `exclude_args`; treat the socket as the truth and the process as a hint [I, from `probe` `matches()`].

## 3. New cross-host finding: harness title and progress conventions, read from Herdr's manifests

Source: `src/detect/manifests/*.toml` in the Herdr repo [S3]. These are Herdr's rules for reading each harness's terminal output, not a wire capture by us. Fields are what the rule matches on. Claude row cross-checks `hosts` (glyph frames `◐ ◑` and idle `✳` were observed there [hosts L3]).

| Harness | Busy | Idle | Blocked | OSC 9;4 use in the rule |
|---|---|---|---|---|
| Claude Code (manifest 2026.09.11.1) | Title starts with a Braille glyph U+2800 to U+28FF (up to 2.1.227) or U+25D0 to U+25D3 `◐ ◑ ◒ ◓` (2.1.228 and later), then a space | Title starts with `✳` (U+2733) then a space; or progress `4;0` | Screen only (no title rule) | `4;0` (clear) = idle. So Claude Code sends 9;4 |
| Codex | Title has one of `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` | none: title and composer look the same in and out of a turn, state stays `unknown` | Title contains `Action Required` | none |
| Qwen Code | Title starts with `◐` (needs `ui.showStatusInTitle`) | screen composer | Title starts with `✳` | `4;3` = working while a tool runs, only in terminals that advertise progress |
| Amp | Title starts with a Braille glyph | Title contains ` - amp - ` | Title contains `Plugin confirmation needed` | none |
| Hermes | Title starts with `⏳` | Title starts with `✓` | Title starts with `⚠` | none |
| Grok CLI | Title has a Braille glyph U+2801 to U+28FF; progress `4;1;-1` | Title ends `grok`; progress `4;0;0` | Title contains `Action Required` | `4;1;-1` working, `4;0;0` idle |
| Kiro CLI | Title starts with `◐ ◓ ◑ ◒` or one of the characters slash, bar, backslash, dash, then ` kiro:`; progress `4;3` | screen | screen | `4;3` working |
| Letta Code | Title has a Braille glyph | screen | Title `[ ! ] Action Required` or `[ . ] Action Required`; progress `4;3` | `4;3` = blocked |

Consequences for the registry (none written here):
- `emits_osc_9_4`: true for claude-code, qwen-code (only during a tool, only if the terminal advertises support), grok, kiro, letta. Claude Code is now supported by the binary string in `hosts` L9 and by Herdr's rule.
- `title_signal` for claude-code: busy = first character in U+25D0..U+25D3 or U+2800..U+28FF, idle = U+2733. Qwen Code reverses the meaning of `✳` (blocked, not idle): a shared glyph table would misread it, so key the glyph meaning per harness.
- The Claude busy frame set changed between 2.1.227 and 2.1.228 [S3 comment]. The local Claude is 2.1.284 [hosts L9], so the half-circle set applies here.

## 4. Terminal.app and Zellij: specifics worth keeping

### Terminal.app
- The dictionary is `/System/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.sdef` (24,153 bytes, dated 2025-01-16) [L3]. The `sdef` command itself failed here: `xcode-select: error: tool 'sdef' requires Xcode`, because only Command Line Tools are active [L3]. I read the XML file directly.
- Read-only properties of interest: window `name`, `id`, `frontmost`, `visible`; tab `busy`, `processes`, `tty`, `custom title`, `title displays custom title`, `selected`, `number of rows/columns` [D-sdef]. Dangerous or private: tab `contents`, `history`, and the command `do script` (runs a command) and `make`, `open`, `close` [D-sdef].
- The window title is built from profile options (`title displays device name`, `shell path`, `window size`, `settings name`, `custom title`) [D-sdef]. Which of those a program's OSC 0/2 title occupies was not observed [I]. T1 shows a window `name` of the form `<path> - <shell> <cwd> - <tty>`.
- Terminal.app was not running when checked (`pgrep -lf` found no match) and no Apple event was sent [L3].

### Zellij
- Process shape: `zellij --server <socket path>` for the server [S8]; `zellij` for clients. Rule under "command line only": `names: ["zellij"]`, `args_contain: ["--server"]` [I].
- `list-panes` needs a pane's pty for `pane_command`, and gives up after 100 ms per pane [S7]: expect blanks when the server is busy.
- Zellij treats OSC 133 markers only as a selection aid [S13]; it exposes no prompt state.
- Plugins are WASM and need a permission grant inside Zellij [I]; not used here.

## 5. IDE terminals: what the process tree and lock files give

Observed on this Mac with Cursor running [L8]: main process `/Applications/Cursor.app/Contents/MacOS/Cursor`, and a helper whose `ps` args column is the retitled string `Cursor Helper: terminal pty-host` (parent = the main process). It had no children when checked, because no integrated terminal was open, so the shell child shape under it was not observed.
- Under the probe's space-split rule that helper's argv[0] is `Cursor`, and `terminal` and `pty-host` are separate arguments. A match written as `names: ["Cursor"]`, `args_contain: ["terminal", "pty-host"]` would hit it; the main process does not contain those arguments [I, from `matches()`].
- The agent's ancestors in an integrated terminal are: agent, login shell, `pty-host`, main app [I; standard VS Code layout, `pty-host` seen but not with a child].
- A directory `$TMPDIR/<user>-cursor-zsh` exists [L7]; it is consistent with zsh shell-integration injection, whose mechanism is documented [S17] but not confirmed here [I].

Claude Code's IDE integration, from another direction: the IDE plugin writes `~/.claude/ide/<port>.lock` and the CLI reads it. Reported fields: `pid`, `workspaceFolders`, `ideName`, `transport`, `authToken` [T2 shows the shape; the path is confirmed by a vendor issue, S18]. The Claude Code binary contains `CLAUDE_CODE_SSE_PORT` [L9]. A reader would get "IDE with pid P has workspaces W and a Claude connection", never a working or idle state. **Never read `authToken`.** Not present on this Mac: `~/.claude/ide` does not exist [L8]. The lock directory ignores `CLAUDE_CONFIG_DIR`: it is always `~/.claude/ide` [S18].

## 6. Observed or read in a primary source, versus inferred

Observed or read in a primary source ([L], [D], [S]):
- Herdr: states, status authority, manifest mechanism, socket paths and 0600 mode, method names, `AgentInfo` keys, process subcommands, per-harness title and progress rules, session-state and screen-history files.
- Terminal.app: property names and definitions in the sdef; version 2.14 (455); not running.
- Zellij: `list-panes` and `subscribe` in the CLI source and changelog; `PaneInfo` and `PaneListEntry` fields; OSC 0/2 and 9 handling; socket permission mode; `--server` argv.
- Alacritty: three IPC messages; no scripting definition in the template plist; macOS `login` process chain in `tty/unix.rs`.
- Cursor: version, VS Code base version, CLI options, registered OSC handlers, `pty-host` helper, main socket path, zsh injection directory.
- VS Code: terminal and shell-integration extension API, OSC 633 documentation.
- JetBrains: MCP server enabling, the single terminal tool, agent dropdown.

Inferred ([I]):
- The consent prompt for Terminal.app Apple events, and the launch-if-not-running behaviour.
- That `busy` reads true for the whole life of an agent.
- That pane processes are children of `herdr server` and `zellij --server`, so ancestry stops there.
- That a Herdr or Zellij title carries Claude's glyph unchanged.
- That the macOS Zellij socket directory is `$TMPDIR/zellij-<uid>/...` (from `consts.rs` and standard `directories` behaviour).
- Joining Zellij panes to processes by cwd and command.
- The IDE terminal ancestor chain (agent, shell, `pty-host`, app).
- Anything said about JetBrains process names and reading its title from outside.

## 7. Ranked recommendation: what MinMacs should adopt first

Same rule as `hosts` section 5: prefer signals that need no consent, no host config change and no per-harness install, and use them to raise or lower confidence on the process evidence the detector already has (caffeinate child, transcript write, tree CPU). Host data never overrides an alive/dead fact from `ps`.

| Rank | What | Why | Cost and risk |
|---|---|---|---|
| 1 | **Registry only: copy the title and progress conventions from section 3** into `title_signal` and `emits_osc_9_4` for claude-code, codex, qwen-code, amp, hermes, grok, kiro, letta | Zero runtime cost. Fills the field `hosts` section 5 asked for. Gives the frame set `hosts` did not extract. Makes the existing host reads (cmux `tree`, iTerm2 `name`, kitty `title`, tmux `pane_title`) usable for eight harnesses instead of one. | Source is Herdr's reading of the harnesses, not a wire capture. Frame sets change by harness version (Claude 2.1.228). Glyph meaning must be per harness (Qwen `✳` is blocked). |
| 2 | **Herdr socket** when a `herdr server` process exists: `ping`, then `agent.list`, then `pane.process_info` for pids; optionally subscribe to `pane.agent_status_changed` | Only new source of per-pane working/blocked/idle with no consent and no per-agent install. Direct pid join. Cheap: one Unix socket, JSON lines. `blocked` is something we cannot get elsewhere without hooks. | Not verified against a live turn. Herdr is pre-1.0. Whitelist keys (titles can hold private text). Correlated with the title glyph, so do not count it as a second vote. Read nothing else from `~/.config/herdr`. |
| 3 | **Terminal.app tab list through ScriptingBridge**: per tab `tty`, `busy`, `processes`, `custom title`, plus window `name`, only when Terminal is running | It is on every Mac. Gives `tty` to tab mapping and the title glyph for any harness that sets one, on the default terminal of most users. Reuses the consent path already built for browsers. | Needs Automation consent (a prompt the user must accept). `busy` means "alive", not "working". Never read `contents` or `history`. Do not send it while Terminal is not running. Not tested here. |
| 4 | **Zellij `action list-panes --json --all`** for each live `zellij --server` | No consent. Title glyph, focus, exited and command per pane. | No pid or tty: join by cwd and command only. Needs the `zellij` binary path (a Finder-launched app has a short PATH; taking it from the server's argv[0] is not verified). OSC 9;4 is dropped by Zellij, so only the title signal survives. Small user base compared with tmux [I]. |
| 5 | **IDE terminals: ancestry only.** Label an agent as "in Cursor/VS Code terminal" when its ancestor is a `pty-host` helper; optionally read `~/.claude/ide/*.lock` for IDE pid and workspaces (without `authToken`) | Fixes host attribution, which matters because case 15 in `registry/README.md` section 3 says an Electron IDE tree is noisy. | No state signal at all. Do not build a reader for the VS Code extension API: it needs an installed extension. |
| skip | **JetBrains, Alacritty** | JetBrains: nothing read-only; the only terminal MCP tool runs commands and the server is opt-in. Alacritty: its socket cannot report anything about processes. | Record both as `host_signal: none`, as `hosts` did for Warp. |

Registry consequences (no code change in the harness rows):
- Add `host_signal` values `socket` (Herdr, Zellij), `applescript` (Terminal.app), `none` (Alacritty, VS Code family, JetBrains).
- Mark hosts that own their ptys (Herdr, Zellij; tmux from `hosts`) so ancestry stops at the server and the outer terminal is not asked about that agent.
- Record the caveat from `hosts` finding 2 for Terminal.app: "busy" is alive, not working.

## 8. Not verified

- None of Herdr, Zellij, Alacritty, JetBrains or VS Code proper is installed here. Nothing about them was run. The Herdr socket, `agent.list` shape, `pane.process_info`, and event stream were read in docs, schema and source only. A first live test should compare Herdr's `working` with the `caffeinate` child on a real Claude Code turn, including one `blocked` case.
- No Apple event was sent to Terminal.app. Unverified: that a consent prompt appears and its wording, what `processes` prints for a Claude Code tab (the argv0 of the versioned binary is a path such as `.../versions/2.1.284`), whether `busy` is true for the whole session, and whether the glyph title appears in window `name`. Terminal.app was not running.
- `sdef Terminal.app` did not run on this Mac (needs Xcode). The XML file was read directly instead; that is the same dictionary but not the tool's rendering.
- Zellij: `--session` combined with `action` was inferred from usage strings; the macOS socket directory was inferred; nothing was executed.
- Cursor: `pty-host` was seen without a child. Whether the integrated-terminal shell is a direct child of `pty-host` on macOS was not observed. `cursor --status` was not run (it talks to the running app; the output would also name workspaces). VS Code 1.139 was not compared with Cursor's 1.128 bundle.
- The Cursor bundle grep found no OSC 9;4 handler. That is absence in a 40 MB minified file, checked with three patterns (`ConEmu`, `9;4`, `registerOscHandler(N`); it is strong but not proof.
- JetBrains: docs only. Process names, the terminal child chain, whether it recognises OSC 9;4, and any REST endpoint on the built-in web server were not checked. `TERMINAL_EMULATOR` and similar env markers were not looked up.
- Herdr manifest rules are Herdr's interpretation. They were not compared with real Claude Code, Codex or Qwen output on the wire. Manifest versions are dated 2026-08-14 (Qwen) and 2026-09-11 (Claude) and may already be outdated.
- `~/.claude/ide/*.lock` fields come from a third-party post and a vendor bug report, and the directory does not exist on this Mac.
- Warp, iTerm2, WezTerm, kitty and standalone Ghostty were not revisited. Their status in `hosts` is unchanged.

### Side effects of this research

- Clones and downloads went to the session scratchpad, outside the repo: Herdr (`fc86d866aa7a`), Zellij (`a79e15e178`), Alacritty (`d692748d3f`), VS Code `vscode.d.ts`, JetBrains help pages, Herdr docs. The Herdr clone directory already existed there; `git log` in it matched the current `master` HEAD.
- Local commands were read-only: `command -v`, `ls`, `ps`, `pgrep`, `lsof -U -p`, `plutil -p`, `strings`, `sw_vers`, `mdls`, and `cursor --help` (prints help; it starts the Electron CLI, not a window). `sdef` failed as noted. No Apple event was sent, no host state was changed, no multiplexer session was created, no hook or integration was installed, no agent session was touched, and no message content was read or printed.
- Only file written: `registry/evidence/hosts-2.md`.

## Sources

Local observations (2026-09-29):
- L1 `ls /Applications ~/Applications`: `Cursor.app`, `cmux.app`, `Claude Code URL Handler.app`, `Insomnia.app`, `MinMacs.app`; no Alacritty, Herdr, Zellij, JetBrains, VS Code. `command -v herdr zellij alacritty` printed nothing. `ls -l /usr/local/bin/code` printed a symlink to `/Applications/Visual Studio Code.app...`, and `ls -d "/Applications/Visual Studio Code.app"` failed. `ls -d ~/.config/herdr ~/.config/zellij ~/.config/alacritty`: all absent. `ls "$TMPDIR" | grep -i zellij`: empty.
- L2 In the Herdr clone: `git log -1` printed `fc86d866aa7ae9d801d158b93a2ebe7b76eff562 Tue Sep 29 14:33:20 2026 +0200`. The GitHub page (fetched) showed 41.4k stars, 3.2k forks, 91 releases, latest v0.9.1 2026-09-16, license Apache-2.0. `docs/next/api/herdr-api.schema.json` top-level keys `protocol` = 22, `schema_version` = 1.
- L3 `mdls -name kMDItemVersion /System/Applications/Utilities/Terminal.app` printed 2.14; `plutil -p .../Info.plist` printed `CFBundleVersion` 455, `NSAppleScriptEnabled` 1, `OSAScriptingDefinition` "Terminal.sdef", `CFBundleIdentifier` com.apple.Terminal. `sdef /System/Applications/Utilities/Terminal.app` printed `xcode-select: error: tool 'sdef' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`. `ls -la .../Contents/Resources/Terminal.sdef`: 24153 bytes, Jan 16 2025. `pgrep -lf 'Terminal.app'` printed nothing. `strings -a .../MacOS/Terminal | grep`: `noWarnProcesses`, `scriptBusy`, `scriptProcesses`, `scriptTTY`, `scriptCleanCommands`.
- L4 Zellij clone HEAD `a79e15e178cd30b77b057db59ef0f05f2318c9f9` (2026-09-28); GitHub releases API: v0.45.1 2026-08-28, v0.45.0 2026-08-20, v0.44.3 2026-05-13.
- L5 Alacritty clone HEAD `d692748d3f61253ebe9f5094320120d22f6a046f` (2026-08-31); releases API: v0.17.0 2026-04-06.
- L6 `/Applications/Cursor.app/Contents/Resources/app/bin/cursor --version` printed `3.15.6 / a1f686545fd0ce8917bbd2449f733551a9bce420 / arm64`. `product.json`: `vscodeVersion` 1.128.0, `applicationName` cursor, `darwinBundleIdentifier` com.todesktop.230313mzl4w4u92. `cursor --help` sections and options as listed. A python scan of `out/vs/workbench/workbench.desktop.main.js` (40,733,665 bytes): `registerOscHandler(` arguments 633, 1337, 133, 7, 9, 99, 633; the OSC 9 handler is `_doHandleSetWindowsFriendlyCwd`; 0 matches for `ConEmu`, `9;4`, `enableProgress`; setting names `terminal.integrated.shellIntegration.{decorationsEnabled,enabled,environmentReporting,history,showCommandGuide}`.
- L7 `lsof -a -U -p 70991`: `/Users/frikkjarl/Library/Application Support/Cursor/3.15-main.sock`. `ls -la "$TMPDIR"`: `vscode-git-e1c530fbd0.sock` (srwxr-xr-x) and directory `frikkjarl-cursor-zsh` (drwx-----T).
- L8 `ps -axo pid=,ppid=,tty=,args=`: `72098 70991 ?? Cursor Helper: terminal pty-host`; no process has ppid 72098. `ls -la ~/.claude/ide`: `No such file or directory`.
- L9 `strings -a ~/.local/share/claude/versions/2.1.284 | grep -o` matched `CLAUDE_CODE_SSE_PORT` and `autoConnectIde`.

Docs and source (fetched 2026-09-29; Herdr paths are under `docs/preview/website/src/content/docs/` on master):
- D1 https://github.com/herdrdev/herdr (README: "every pane is marked working, blocked, or idle", server keeps terminals running on detach, "one rust binary")
- D2 Herdr `agents.mdx` (status authority, manifests, blocked strictness, overrides, `HERDR_AGENT`, tmux-in-pane, `agent explain`)
- D3 Herdr `socket-api.mdx` (methods, transport, socket paths and resolution order, event subscriptions, pane and agent fields, `pane.process_info`) and `concepts.mdx` (states, client and server)
- D4 Herdr `integrations.mdx` (Claude Code section: hook role, `~/.claude/settings.json`, `hooks/herdr-agent-state.sh`)
- D5 https://www.jetbrains.com/help/idea/terminal-emulator.html (AI agent session, rename tab by OSC 0)
- D6 https://www.jetbrains.com/help/idea/mcp-server.html (enable MCP server, brave mode, terminal tool `execute_terminal_command`, setup banner)
- D7 Herdr `agent-automation.mdx`, `cli-reference.mdx` (`herdr agent list`, `herdr api snapshot`, `herdr status`)
- D8 Herdr `session-state.mdx` (`session.json`, `session-snapshots/`, `[experimental] pane_history`, `session-history.json`)
- D-sdef `/System/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.sdef`, lines 206 to 256 (window), 320 to 335 (`do script`), 413 to 448 (tab `busy`, `processes`, `tty`, `contents`, `history`)
- S1 Herdr `docs/next/api/herdr-api.schema.json` (`AgentInfo`, `PaneInfo`, `AgentStatus` enum)
- S2 https://github.com/herdrdev/herdr/blob/master/docs/next/CHANGELOG.md (0.9.1 entry, 2026-09-16)
- S3 https://github.com/herdrdev/herdr/tree/master/src/detect/manifests (`claude.toml`, `codex.toml`, `qwen.toml`, `amp.toml`, `hermes.toml`, `grok.toml`, `kiro.toml`, `letta.toml`)
- S4 Herdr `src/session.rs` (`api_socket_path_for`, `active_api_socket_path`) and `src/config/io.rs` (`config_dir`, `platform_config_dir`)
- S5 Herdr `src/api/server.rs` (`SOCKET_PERMISSION_MODE = 0o600`, `restrict_socket_permissions` at line 90) and `src/ipc.rs`; grep of `src` for peer-credential calls: no match
- S19 Herdr `src/main.rs` lines 555 to 600 (`server`, `client`, `remote-client-bridge`, `update`)
- S6 Zellij `zellij-utils/src/data.rs` (`PaneInfo` line 2629, `PaneListEntry` line 2684, `ClientInfo`)
- S7 Zellij `zellij-server/src/route.rs` lines 3146 to 3200 (`enrich_pane_with_running_command`, `enrich_pane_with_cwd`, 100 ms timeout)
- S8 Zellij `zellij-client/src/lib.rs` line 489 to 491 (`spawn_server`, `--server <socket path>`)
- S9 Zellij `CHANGELOG.md` lines 157 and 185 (under 0.44.0, 2026-03-23): `list-panes`, `subscribe`
- S10 Zellij `zellij-utils/src/cli.rs` lines 176 to 216 (`subscribe` usage string with `--session`, `SubscribeCli`), 1495 to 1528 (`ListPanes` flags)
- S11 Zellij `zellij-server/src/lib.rs` line 1182 (`set_permissions(&socket_path, 0o1700)`)
- S12 Zellij `zellij-utils/src/consts.rs` lines 222 to 256 (`ZELLIJ_TMP_DIR`, `ZELLIJ_SOCK_DIR`, `CLIENT_SERVER_CONTRACT_DIR`) and `envs.rs` (`ZELLIJ_SOCKET_DIR`)
- S13 Zellij `zellij-server/src/panes/grid.rs` lines 4626 to 4637 (OSC 0/2 to title), 4940 to 4957 (OSC 9, ConEmu sub-commands excluded), and the test `an_osc_9_conemu_progress_report_is_not_a_notification` in `panes/unit/grid_tests.rs`; OSC 133 fields `osc133_markers_seen`, `osc133_command_selection`
- S14 Alacritty `alacritty/src/cli.rs` lines 254 to 266 (`SocketMessage`), `alacritty/src/polling/ipc.rs` lines 148 to 200 (socket dir on macOS = `env::temp_dir()`), `extra/man/alacritty-msg.1.scd`
- S15 Alacritty `extra/osx/Alacritty.app/Contents/Info.plist` (no `NSAppleScriptEnabled` or `OSAScriptingDefinition`; `NSAppleEventsUsageDescription` "An application in Alacritty would like to access AppleScript."), `alacritty_terminal/src/tty/unix.rs` lines 168 to 191 (macOS: `/usr/bin/login -flp <user> /bin/zsh -fc "exec -a -zsh ..."`)
- S16 https://api.github.com/repos/microsoft/vscode/releases (1.139.1 2026-09-25, 1.139.0 2026-09-23)
- S17 https://raw.githubusercontent.com/microsoft/vscode/main/src/vscode-dts/vscode.d.ts (`Terminal.processId` line 7682, `TerminalShellIntegration` 7831, `TerminalShellExecution` 7947, `window.terminals` 11164, `onDidChangeTerminalShellIntegration` 11198, `onDidStartTerminalShellExecution` 11205, `onDidEndTerminalShellExecution` 11212); https://code.visualstudio.com/docs/terminal/shell-integration (OSC 633, 133, 1337; automatic injection; `--locate-shell-integration-path`)
- S18 https://github.com/anthropics/claude-code/issues/34800 (IDE lock files in `~/.claude/ide/`, written by the IntelliJ and VS Code plugins, read by the CLI, ignoring `CLAUDE_CONFIG_DIR`)
- T1 https://stackoverflow.com/questions/50902777/identifying-terminal-window-in-applescript (a `get` dump of a live Terminal window and tab: `tty`, `busy status`, `process` list `login`, `-fish`, `clean commands` `screen`, `tmux`, window `name` `~ - fish  /Users/CK - ttys001`; old macOS, 2018)
- T2 https://extensions.panic.com/extensions/ca.okapi/ca.okapi.claudecode-nova/ and https://www.reddit.com/r/ZedEditor/comments/1tukeq5/ (lock file shape `pid, workspaceFolders, ideName, transport, authToken`, file 0600, dir 0700)
