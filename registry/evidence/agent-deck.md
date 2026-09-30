# Agent Deck

Confidence: documented (public source and docs, no live instance). Not installed here, not running.

## What was checked

- Shallow clone of https://github.com/asheshgoplani/agent-deck at tag v1.16.22 (commit 035fd60, 2026-09-28), which is also the latest release (GitHub API, 2026-09-30). Read `cmd/agent-deck/main.go`, `hook_handler.go`, `internal/tmux/{tmux,controlpipe,pipemanager,socket}.go`, `internal/session/{instance,claude_hooks,hook_watcher,config,store_root,conductor}.go`, `internal/statedb/statedb.go`, `internal/agentpaths/paths.go`, `internal/telemetry/env.go`, `internal/update/tuiheartbeat.go`, `docs/{status-detection,events,daemon-protocol,macapp-core}.md`, `TELEMETRY.md`, README, `skills/agent-deck/references/config-reference.md`, `.goreleaser.yml`, `install.sh`, `go.mod`.
- Local: `which agent-deck` (none), `ls ~/.agent-deck ~/.local/share/agent-deck ~/.cache/agent-deck ~/.config/agent-deck` (all absent), `ps` (no agent-deck process), `tmux -V` (3.6a). The Homebrew formula was fetched with curl (`depends_on "tmux"`, `bin.install "agent-deck"`). Nothing was installed, started or attached; no tmux command was run.
- The row passes `tools/validate_row.py`. I also ran `agents_probe.matches()` on twelve made-up argv lists: bare `agent-deck`, `-p work`, `web` and the Homebrew path are the TUI; `web --no-tui`, `notify-daemon` and `daemon serve` are their daemon surfaces; `hook-handler`, `session send-worker`, `list --json`, `--version`, `add . -c claude` match nothing.

## Shape

```
agent-deck (TUI, Go, 1 binary)  ---- tmux -u -C attach-session -t agentdeck_x   (control client per connected session, long-lived)
   |                            ---- tmux capture-pane / list-sessions            (short-lived)
   |                            ---- bash -lc <cmd>                               ([interval_hooks.*], transient)
   '-- new-session -d -s agentdeck_<title>_<suffix> -c <dir> bash -c '...; exec claude --session-id <uuid>'
                                        |
                                 tmux SERVER (default server, or -L <socket_name>)
                                        '-- claude / codex / gemini / opencode / pi / hermes ...   <- the agent, NOT under agent-deck

launchd: com.agentdeck.transition-notifier -> agent-deck notify-daemon      (writes state.db status, nudges, desktop banners)
         com.agentdeck.web                 -> agent-deck web --no-tui       (127.0.0.1:8420)
         com.agentdeck.autoupdate          -> /bin/sh (daily updater)
optional: agent-deck daemon serve -> <data dir>/runtime/profiles/<profile>/daemon.sock
```

- Process: `agent-deck`, arm64 or amd64 Go binary. Homebrew `/opt/homebrew/bin/agent-deck` (symlink into the Cellar), install.sh `~/.local/bin/agent-deck`. `install.sh --name` can rename it, which the row cannot see. No `.app`, no bundle id. A Mac app is announced ("upcoming Mac app" in the changelog and `docs/macapp-core.md`) but is not in the repo or the release assets.
- Surfaces in the row: TUI (includes `agent-deck web`), `notify-daemon`, `web --no-tui`, `daemon serve`. Short-lived CLI calls (`hook-handler`, `session send-worker`, `mcp-proxy`, every other subcommand) are excluded from the TUI by a denylist of exact argument tokens, built from the `case` list in `main.go` at v1.16.22.
- Process to session: the tmux session name `agentdeck_<title>_<suffix>` and the pane environment `AGENTDECK_INSTANCE_ID` / `AGENTDECK_PROFILE`. Neither is in the command line of the agent. For Claude Code the pane argv carries `--session-id <uuid>` or `--resume <uuid>`, so the `claude-code` row already maps it to `~/.claude/projects/*/<uuid>.jsonl`. The `bash -c` wrapper (its argv holds `AGENTDECK_INSTANCE_ID=<id>`) stays as parent only for tools that are not `exec`ed.
- Store: `<data root>/profiles/<profile>/state.db`, SQLite in WAL mode. `<data root>` is `~/.local/share/agent-deck` (fresh install) or `~/.agent-deck` (legacy, chosen by which one already holds `profiles/`). Default profile `default`. Tables: `instances` (id, title, project_path, group_path, command, tool, status, tmux_session, tmux_socket_name, created_at, worktree_*, account, ...), `groups`, `instance_heartbeats`, `session_claims`, `cost_events`, `watchers`, `recent_sessions`, `metadata`. Also `<data root>/hooks/<instance id>.json` (status files), `<data root>/bus/<profile>/active.ndjson` (event bus), `<data root>/logs/`, `<cache dir>/tui/<pid>.json` (TUI heartbeat), `~/.config/agent-deck/config.toml`. It holds no conversation text of its own; transcripts are the agent's (Claude `~/.claude/projects`, Codex rollouts). Key names only were read from the source; no store exists here to open.
- Working: Agent Deck's own status `running` (green) is the only turn signal it has, and it is derived, in order, from (1) a fresh hook verdict (Claude: `UserPromptSubmit` running, `Stop` waiting, fresh 2 min; Codex only after `agent-deck codex-hooks install`; Gemini, pi, Hermes hooks), (2) a Braille spinner in the tmux pane title, (3) screen patterns on the last 25 lines of the pane. Read it with `agent-deck list --json` / `session show --json`, `events follow --json --kind session.status,session.turn` (needs `[macapp] status_events = true`), or the daemon socket (needs `[core] daemon = true`). For a passive check use the hosted agent's own row on the pane process.
- Waiting: hook file `event` (`PermissionRequest`, `Notification` with matcher `permission_prompt|elicitation_dialog`) or the status `waiting` plus substate (`interactive-menu`, `auth-401`, `usage-limit`, ...). Pane cues (`Enter to select`, `Allow once`) read conversation text and are last resort.
- Hooks: it installs other tools' hooks (Claude `settings.json`, Codex notify, Cursor `~/.cursor/hooks.json`, Gemini, Hermes, pi extension, tmux hooks). Its own: `[interval_hooks.*]` (timer, not event), worktree setup and destruction scripts (approval-gated), the event bus, `[notifications]` (`transition_events`, `desktop`). No hook that reports a turn from Agent Deck itself, so `hooks.supported` is false with the list in `config`.
- OpenTelemetry: none. `go.mod` has `go.opentelemetry.io/otel*` only as `// indirect`; no Go file imports it; `OTEL_` strings appear only in two test files. Its own usage telemetry is opt-in, anonymous, PostHog EU, off by default.
- Grok: no Grok preset. Supported tools per README: claude, gemini, opencode, codex, copilot (organization and launch only), crush, muse, cursor, hermes, pi, dsh, omp, plus custom `[tools.*]` with `busy_patterns`. A Grok CLI would run as a custom tool or a shell session, and the pane text patterns would be the user's own.

## Could not determine

- The real `ps` shape of the TUI, `notify-daemon` and `web --no-tui` on macOS, idle and busy CPU of the TUI (the 5% floor is a placeholder), and whether argv[0] under launchd is the Cellar path or the symlink. The match uses the basename, so both work.
- Whether a `bash -c` wrapper stays as parent for every non-Claude tool. Source says `exec` is used for Claude; other tools were not traced.
- The exact on-disk shape of `state.db` on a real install (source read only), and how long a hook file stays fresh for tools other than Claude and Codex.
- Whether `agent-deck web` without `--no-tui` shows different CPU from the plain TUI.
- Tool sessions on `--ssh` remotes and conductor sessions: they run through the same tmux path, not traced separately.

## Contradicts common belief

- "Agent Deck runs your agents." It does not. The agents are children of the tmux server. CPU, children and caffeinate of the `agent-deck` process say nothing about a turn. Only the agent's own row on the pane process does, or Agent Deck's own status via its CLI.
- "`waiting` means blocked on a permission prompt." Agent Deck's `waiting` (yellow, "Needs your input") also covers a finished turn at an empty prompt: Claude `Stop` and `SessionStart` both map to `waiting`. The permission case is the hook `event` or the `interactive-menu` substate. `idle` means the user has already looked at it, not that nothing is happening.
- "Status comes from hooks." Only where hooks are installed and fresh. Claude hooks give no signal between `UserPromptSubmit` and `Stop`, so after 2 minutes the pane text decides; Codex is pane-only without `codex-hooks install`; OpenCode's SSE feed is TUI-owned. The doc's own blind-spot list says a Claude turn that redraws without its spinner for over 6 s can read as waiting.
- "The child-process rule works." The TUI has permanent direct tmux control clients, so a shell-child or any-child rule reads every Agent Deck as always working.
- "Agent Deck has a Mac app / OTel." An unreleased Mac app is announced; there is no bundle id today. No OpenTelemetry export exists, despite otel modules in `go.mod` (indirect only).
- README's `[tmux]` socket-migration note gives the DB path as `~/.local/share/agent-deck/<profile>/state.db`. The code is `<data root>/profiles/<profile>/state.db`. Trust the code.
- The name `agent-deck` is unique (no Coursier-style clash), but the TUI match is a denylist: a subcommand added after v1.16.22 would read as a TUI until the row is updated.

## Verification

Adversarial re-check, 2026-09-30. Method: fresh shallow clone of `asheshgoplani/agent-deck` at tag v1.16.22 (`git describe --tags` printed v1.16.22, commit 035fd602eda5), GitHub API and Homebrew formula re-fetched, local absence re-checked, `tools/validate_row.py` (ok, before and after), and `agents_probe.matches()` run on 26 hand-made argv lists before and after the repairs. Nothing installed, run or attached. Confidence stays `documented` (the ceiling: not installed here, never seen running).

Confirmed:
- Latest release is v1.16.22 (2026-09-28T08:24:11Z), assets `agent-deck_1.16.22_darwin_{amd64,arm64}` and linux, `checksums.txt`; formula has `depends_on "tmux"` and `bin.install "agent-deck"`; `.goreleaser.yml` `binary: agent-deck`, `CGO_ENABLED=0`. No `.app`, no bundle id.
- Not installed: `which agent-deck` printed "agent-deck not found"; `ls -d` on `~/.agent-deck`, `~/.local/share/agent-deck`, `~/.cache/agent-deck`, `~/.config/agent-deck` printed No such file for all four; `ls ~/.local/bin | grep -i deck` empty; `ps -axo pid,args | grep -i '[a]gent-deck'` matched only the shell running that check itself; `tmux -V` printed `tmux 3.6a`.
- `install.sh`: `INSTALL_DIR="${HOME}/.local/bin"`, `BINARY_NAME="agent-deck"`, `--name` overrides it. `go install .../cmd/agent-deck@latest` (README line 65) puts it in `~/go/bin`, which the row does not list; the name match is by basename so it still works.
- tmux: `SessionPrefix = "agentdeck_"`, `new-session -d -s <name> -c <dir>`, `[tmux] socket_name` default empty (shared default server), `-L <name>` otherwise.
- Control-mode client: `tmuxExec(socketName, "-u", "-C", "attach-session", "-t", sessionName)` in `controlpipe.go`; PipeManager holds one per active session, so the TUI has permanent direct tmux children.
- Claude hooks injected: SessionStart, UserPromptSubmit, Stop (sync), PermissionRequest (sync), Notification (matcher `permission_prompt|elicitation_dialog`), SessionEnd, PreCompact (`hookEventConfigs`). `mapEventToStatus`: UserPromptSubmit running, Stop, PermissionRequest, SessionStart waiting, SessionEnd dead; the handler exits silently when `AGENTDECK_INSTANCE_ID` is unset. Hook file keys `status, session_id, event, ts` confirmed. Freshness numbers (Claude 2 min, Codex 20 s and 5 s) are stated in `docs/status-detection.md`; I read them there, not in code.
- Status model, cadence (2 s backing off to 10 s), `list --json` and `session show` write nothing: `docs/status-detection.md` table.
- Event bus (`session.status`, `session.turn`, `[macapp] status_events`), daemon (`daemon.sock` 0600, uid peer check, `[core] daemon = false` default, `subscribe`): `docs/events.md`, `docs/daemon-protocol.md`, `docs/macapp-core.md`.
- State store: `<data root>/profiles/<profile>/state.db`, WAL, tables `metadata, instances, groups, instance_heartbeats, session_claims, recent_sessions, cost_events, watchers, watcher_events`; `DefaultProfile = "default"`; XDG root for a fresh install, `~/.agent-deck` legacy. README line 1021 does give the path without `profiles/`, as the row says.
- The subcommand denylist equals `commandRegistry` (main.go line 1464) and the `case` list in `main()`; `web` falls through to the TUI unless `--no-tui`; `notify-daemon` and `daemon serve` are long-running and have their own surfaces.
- No OpenTelemetry: `go.opentelemetry.io/otel*` and otelgrpc/otelhttp are all `// indirect`; `grep -rIln 'OTEL_\|otlp\|go.opentelemetry' --include='*.go'` printed only `internal/telemetry/upload_test.go` and `internal/session/spawn_failure_redaction_test.go` (and `spawn_failure.go` mentions OTEL only to redact header values).
- Usage telemetry: opt-in, PostHog EU, never asked inside an agent-deck session or under a coding agent (`TELEMETRY.md`, `internal/telemetry/env.go`).
- Desktop notification backends cmux, osascript (macOS), notify-send (Linux); interval hooks run `bash -lc`; TUI heartbeat file `<cache dir>/tui/<pid>.json`; the "upcoming Mac app" line is at CHANGELOG.md line 137.
- No Grok preset: `grep -rli grok` over the whole clone printed only `cmd/agent-deck/assets/skills/watcher-creator/SKILL.md` and `internal/session/issue1112_remote_waiting_status_test.go`. The README tool table and `internal/harness/table.go` (claude, codex, gemini, opencode, pi, hermes) have none.

Corrected (row edited in place):
- Pane shape. The row said `claude` is the pane process itself. Source: for every tool except `shell`, tmux is given `bash -c "cd -- <dir> && bash -c 'stty susp undef; export ...; exec claude ...'"` (`cwdAssertCommand`, then `wrapIgnoreSuspend`). The inner `exec` replaces the inner bash, so argv[0] is still `claude` and the match is right, but an outer `bash -c` may remain as its parent; bash exec-optimisation of `a && b` was not checked and no live pane exists here. A `shell`-tool session is a login shell fed by send-keys (`RunCommandAsInitialProcess = IsSandboxed() || Tool != "shell"`). Label and source text now say so.
- Hook file status values. The row listed `running|waiting|dead|starting`. No `starting` is written by the handler or listed in `HookStatus`; removed.
- `-no-tui`. `web` flags go through Go's `flag.NewFlagSet`, which accepts one or two dashes. Before: `agent-deck web -no-tui` matched the TUI surface (a headless daemon labelled as a TUI). After: the daemon surface keys on `-no-tui` (substring of `--no-tui`) and the TUI denylist carries `-no-tui`. `--no-tui=true` already resolved to the daemon by score.
- `creds-refresh`. A hidden stub in `main()` (line 343, not in `commandRegistry`) that prints and exits; it read as a TUI. Added to the denylist.
- launchd. The row said `com.agentdeck.web` runs `web --no-tui`. The source generates only `com.agentdeck.transition-notifier` (notify-daemon) and `com.agentdeck.autoupdate` (`/bin/sh -c 'exec "$0" update --unattended --trigger timer'`). `com.agentdeck.web` is named in CHANGELOG line 196 and `update_cli.go` as a headless web daemon but no plist template exists, so it is a user-written agent. Source claim reworded. The `web --no-tui` surface itself stays correct (README lines 1142 and 1239, config-reference "macOS launchd hygiene").
- "Holds no conversation text of its own" (Shape section above) is too strong. `instances` has `title`, `project_path`, `command`, `tool_data` and `auto_name_description`, the last cleaned pane title of the Claude task. No transcripts, but conversation-derived text. Notes and a new source entry say to read the status column only.
- Tool list. Label now includes `copilot` and `muse` from the README table; `hermes` is "organization and launch" there, not full status detection.
- session_store glob covers only the XDG root; notes now name the legacy `~/.agent-deck/profiles/*/state.db`.

Unsupported (kept, flagged as such, no evidence added):
- Every CPU number. `tree_cpu` floor 5 is a placeholder; an idle TUI polling every 2 s may exceed it and read as permanently working. Peer manager rows (`claude-squad`, `herdr`) do the same.
- The real `ps` shape of the TUI, `notify-daemon` and `web --no-tui` on macOS, and Cellar-versus-symlink argv[0].
- Whether a bash wrapper stays as parent for non-Claude tools, and whether outer bash exec-optimises `cd && bash -c`.
- That the exact-token denylist misfires only in the known ways: a profile, project or flag value equal to a subcommand (`-p list`, `web --token daemon`) hides a real TUI.

False-positive check on the process patterns:
- TUI surface: matches only argv[0] basename exactly `agent-deck`. Helpers `agent-deck hook-handler`, `session send-worker`, `update --unattended` and `version` (spawned by the agents or the TUI via os.Executable) and `mcp-proxy` and `remote-agent` (started by agents and over ssh) all start with a denylisted token, so none is reported. No self-re-exec creates a second TUI match (in-place restart uses exec, same pid). `web` matched alone is a real TUI plus HTTP server, correct.
- Daemon surfaces: `notify-daemon` needs that exact word in some argument; `daemon serve` needs both substrings and the TUI denylist has `daemon`, so `daemon status|stop` match nothing. `daemon serve --no-tui` matches the daemon surface, harmless.
- Other products: a web search found a Stream Deck key plugin also called "Agent Deck" and a fork named `agent-desk`. Neither is known to ship a binary named `agent-deck`; the basename requirement makes a false match unlikely, not impossible.
- Grok Bot: it is a Cursor-hosted desktop client (`grok-bot` row, matched by `.../Grok Bot.app/Contents/MacOS/Grok Bot`), so it cannot be an Agent Deck pane process and this row does not touch it. Agent Deck has no Grok preset.
