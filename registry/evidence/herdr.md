# Herdr: evidence notes (2026-09-29)

Not installed here (no binary, no `~/.config/herdr`, nothing running). Every claim comes from the official docs and the public source (`github.com/herdrdev/herdr`, tag v0.9.1 = latest release, 2026-09-16; master read too and differs). Confidence is `documented`. Nothing was executed and no session data exists locally to read.

## Shape

```
herdr (client, TUI)      ppid = your shell            thin viewer, draws frames the server streams
  '- herdr server        setsid, no double fork       ppid = the spawning client, later launchd
       |- -zsh           one login shell per pane     DIRECT children of the server
       |    '- claude / codex / pi / ...              GRANDCHILDREN: the hosted agents
       '- (no caffeinate, no other helpers)
notifier helper (terminal-notifier / osascript) is a child of the CLIENT, only if ui.toast delivery = "system"
```

Herdr is a multiplexer/host. It is not itself an agent, so "working" means "some hosted agent is working".

## What I checked

- Docs (repo `docs/next/website/src/content/docs/`, same text as herdr.dev/docs): concepts, agents, session-state, persistence-remote, socket-api, plugins, integrations, configuration, install, troubleshooting, cli-reference.
- Source at v0.9.1 via shallow clone: `src/main.rs`, `src/cli.rs`, `src/session.rs`, `src/server/autodetect.rs`, `src/platform/{mod,macos}.rs`, `src/platform/macos/bootstrap.rs`, `src/persist.rs`, `src/persist/io.rs`, `src/config/io.rs`, `src/pane.rs`, `src/api/schema/{common,panes,events}.rs`, `src/detect/manifests/claude.toml`, `Cargo.toml`.
- Release and packaging: `gh api .../releases/latest` (v0.9.1, assets `herdr-macos-aarch64`, `herdr-macos-x86_64`), Homebrew formula JSON (0.9.1, arm64 bottles), `distribution/install.sh` (`~/.local/bin/herdr`).
- Local, read-only: `which herdr`, `ls` of the three install/config paths, `ps | grep herdr`. All empty. `tools/validate_row.py registry/agents/herdr.json` passes. `tools/agents_probe.py --row` finds 0 sessions (expected). I also ran the row's `matches()` over synthetic command lines: `herdr server` is the daemon; bare `herdr`, `herdr --session work`, `herdr session attach work`, `herdr --remote box` are the TUI; `herdr agent list`, `herdr server stop`, `herdr status server`, `herdr session list`, `remote-client-bridge` match nothing.

## Answers

- **Process**: basename `herdr`. Server argv is `<path>/herdr server` (path is `current_exe()`). Client argv is `herdr` plus optional `--session <n>` / `--remote <target>` / `session attach <n>`. No app bundle, no bundle id.
- **Process to session**: client, `--session <name>` only; `session attach <name>` is positional and not readable by `session_id_args`. Server: the name is only in env `HERDR_SESSION`, so use the listening socket (`~/.config/herdr/sessions/<name>/herdr.sock`; default session `~/.config/herdr/herdr.sock`). Inferred that `lsof -p <server pid>` shows it; not run.
- **Store**: `~/.config/herdr/session.json` (default) or `~/.config/herdr/sessions/<name>/session.json`, JSON, documented. It is layout, cwd, focus and agent session refs, not a transcript. Optional `session-history.json` (off by default, holds pane screen text, private). Logs `herdr.log`, `herdr-client.log`, `herdr-server.log` in the same dir. State dir `~/.local/state/herdr`.
- **Turn in progress**: only the API. `agent_status` per pane is `idle | working | blocked | done | unknown` via `pane.list`/`agent.list` on `herdr.sock`, or `pane.agent_status_changed` events. For most agents (Claude Code, Codex, Copilot, Cursor, Droid, Gemini, Amp ...) Herdr derives it by matching the bottom of the pane screen against per-agent TOML manifests, not from hooks. `pane.process_info` gives the pane's shell pid and foreground pid, so a pane can be tied to a process.
- **Waiting on the human**: state `blocked` (same API and event), plugin hook on `pane.agent_status_changed`. Strict: an unrecognised prompt falls back to `idle`.
- **Hooks**: plugin `[[events]]` hooks in `herdr-plugin.toml` (list in the row). No user hook table of its own. `herdr integration install <agent>` writes hooks into the hosted agent's config (Claude: `~/.claude/hooks/herdr-agent-state.sh` + `settings.json`).
- **OpenTelemetry**: none. No `opentelemetry` in `Cargo.toml`/`Cargo.lock`; logging is `tracing` to files.

## Could not determine

- Idle and busy server CPU, so the 3 percent `tree_cpu` floor is a guess.
- Whether Homebrew's `bin/herdr` shows in `ps` as the symlink or the Cellar path (the row matches basename only, so both work).
- Whether the pane shell's argv0 is literally `-zsh` on macOS. The source comment says login shells get the login argv0 convention; not observed.
- Whether the server's listening socket is visible to `lsof` as described; not run.
- Anything about a running instance: no row field is `verified-locally`.

## Contradicts common belief

- **"Agents run as its children"** is wrong by one level. The server's direct children are the pane shells; agents are grandchildren. A `tool_children` or shell-child rule reads every Herdr server as permanently working, so the row omits both. The agents also match their own rows (Claude Code etc.), so they are counted twice unless the Herdr server is treated as a container.
- **"Working/idle/blocked comes from hooks"** is mostly wrong. Hooks are authoritative only for Pi, OMP, Kimi, OpenCode, Kilo, MastraCode. For Claude Code, Codex, Copilot, Cursor, Droid and others the integration only reports the session id, and state is screen-scraped.
- **The server is hidden by the probe while its spawning client lives.** It is a direct fork of the client (setsid, no double fork), and the probe skips a process whose parent matches any surface of the row. So the client is shown, its tree_cpu includes the server subtree, and the server appears alone only after that client detaches.
- **No sleep inhibitor, no OTel, no launchd service.** `git grep` for `caffeinate`, `IOPMAssertion`, `opentelemetry`, `LaunchAgent`, `.plist` finds nothing. The server just runs detached, switched to the per-user Mach bootstrap context so panes survive logout.
- **Docs drift**: master already differs from v0.9.1 (for example Codex falls back to `unknown`, not `idle`, when no rule matches). The row follows v0.9.1.

## Verification

Adversarial pass, 2026-09-29, by a reviewer who did not write the row. Method: `tools/validate_row.py` (ok), re-read of docs and source at tags v0.9.1 and v0.9.2 (`git archive` of each), `gh api` and the Homebrew API for release data, and `tools/agents_probe.py matches()` over 30 synthetic command lines. Local state re-checked: `which herdr` -> not found; `~/.config/herdr`, `~/.local/bin/herdr`, `/opt/homebrew/bin/herdr` all absent; `ps` shows no herdr. Nothing was run, installed or attached, so confidence stays `documented` at best. The body above was written against v0.9.1 and is left as written; where it disagrees with this section, this section wins. The row itself was edited in place.

Important context: the latest release is now **v0.9.2** (2026-09-29T13:19Z, published today). The row was written when 0.9.1 was latest. Process argv, CLI subcommand arms (`src/cli.rs`), main.rs dispatch and `PLUGIN_HOOK_EVENT_KINDS` are identical between 0.9.1 and 0.9.2.

### Confirmed

- Terminal workspace manager, one Rust binary, background server plus attached clients, `ctrl+b q` detach leaves agents running, five agent states (concepts.mdx, README).
- Server spawned as `<current_exe> server`, stdio to /dev/null, `setsid` in pre_exec, plain `spawn` (no double fork): `src/server/autodetect.rs`, `src/platform/mod.rs`.
- Subcommand set (`server api status completion|completions config channel machine workspace worktree tab notification agent terminal pane plugin integration session`, plus `update`, `client`, `remote-client-bridge`, `remote-api-bridge` in main.rs). `client` is hidden and matches the tui surface.
- `herdr session attach <name>` is positional; `--session <name>` and `--session=<name>` both parsed by `session.rs configure_from_args`. `session_id()` in the probe handles both.
- Named sessions: `~/.config/herdr/sessions/<name>/` with `herdr.sock`, `herdr-client.sock`, `session.json`; default session directly in `~/.config/herdr`. Env names `HERDR_SESSION`, `HERDR_SOCKET_PATH`. Config dir is `$HOME/.config/herdr` on macOS (or `$XDG_CONFIG_HOME/herdr`), `herdr-dev` in debug builds; state dir `~/.local/state/herdr` (also `$XDG_STATE_HOME` override, not in the row).
- Plugins: `plugins.json` at the config dir root (`persist/plugin_registry.rs`), state `~/.local/state/herdr/plugins/<id>`, config `~/.config/herdr/plugins/config/<id>` (`plugin_paths.rs`); `HERDR_PLUGIN_EVENT_JSON` on event hooks (plugins.mdx).
- 22 plugin-hook event kinds (workspace x7, worktree x3, tab x5, pane x5 incl. `pane.agent_detected`, `pane.agent_status_changed`); no `pane.output_changed`.
- API: `AgentStatus` = idle, working, blocked, done, unknown; `PaneProcessInfo` fields shell_pid, foreground_process_group_id, tty, foreground_processes; `pane.list`, `pane.process_info`, `agent.list`, `agent.wait`, `events.subscribe` with `pane.agent_status_changed`; `herdr agent wait <target> [--until STATUS]`; `herdr agent explain`; label `default_known_agent_idle_fallback` exists in `detect/manifest.rs`.
- Hooks are the status authority only for Pi, OMP, Kimi, OpenCode, Kilo, MastraCode (0.9.1 agents.mdx table; same six marked "also reports state" or "state requires the integration" in 0.9.2). Claude Code, Codex, Copilot, Cursor, Droid: screen manifest, integration reports session id only.
- macOS foreground detection via `proc_bsdinfo` and `KERN_PROCARGS2` (`platform/macos.rs`).
- `herdr integration install claude` writes `hooks/herdr-agent-state.sh` and updates `settings.json` under `~/.claude` (integrations.mdx, `integration/claude_settings.rs`).
- No `opentelemetry`, `caffeinate`, `IOPMAssertion` in src, Cargo.toml, Cargo.lock at v0.9.1 or v0.9.2; only `tracing` and `tracing-subscriber`. No `LaunchAgent`, `.plist`, `launchctl ` in src or install.sh outside tests. Logs `herdr.log`, `herdr-client.log`, `herdr-server.log`, filter `HERDR_LOG` (configuration.mdx).
- macOS server adopts the per-user Mach context via `HERDR_MACOS_SERVER_CONTEXT=user` (`platform/macos/bootstrap.rs`); `launchctl managername` = `Background` is normal (troubleshooting.mdx).
- Login shells on macOS in shell_mode auto (`pane.rs shell_mode_uses_login_shell`, `CommandBuilder::new_default_prog`); `HERDR_ENV=1` set in `pane.rs`. That the argv0 is literally `-zsh` is still not observed.
- Licence Apache-2.0 (Cargo.toml, GitHub API, Homebrew); homepage herdr.dev answers.
- Not installed and nothing running (re-run, same result).
- `session-history.json` off by default and next to `session.json`; `session-backups/` recovery copies (0.9.1 docs and `persist/writer.rs`).

### Corrected

- **Latest release.** Row said 0.9.1 is latest. `gh api repos/herdrdev/herdr/releases/latest` -> v0.9.2, 2026-09-29T13:19:42Z; assets now include linux and `herdr-windows-x86_64.zip`. Homebrew formula is still 0.9.1. Source entry and notes rewritten.
- **`session-snapshots/`.** Row credited it to v0.9.1 docs. It does not exist in v0.9.1 (no hit in src or docs); it arrives in v0.9.2 (`persist/writer.rs`, session-state.mdx, CHANGELOG #4320, up to 48 snapshots). Claim reworded.
- **`herdr agent list --json`.** Does not exist. Usage is `herdr agent list`, no flags (`cli/agent.rs agent_list` prints usage and exits 2 on any argument); it always prints the JSON response. Fixed in the socket_activity signal.
- **`startup` in hooks.events.** `startup` is a separate `[[startup]]` manifest table (env `HERDR_PLUGIN_EVENT=startup`), not an `[[events]] on` value, and it is not in `PLUGIN_HOOK_EVENT_KINDS`. Removed from `events`, described in `hooks.config`.
- **Default toast delivery.** Row said the default is the in-app toast. The default is `off`: shipped config template says `# delivery = "off"` (`src/main.rs`), `ToastConfig::default` is `Off`, and a unit test asserts it. The terminal-notifier signal is rewritten: with `delivery = "system"` the server sends `SystemToast` to the foreground client, which runs `terminal-notifier` or `/usr/bin/osascript` (`client/notifications.rs`, `platform/macos.rs`). The old "Inferred" tag is replaced by that source.
- **Unrecognised prompt reads idle.** True for known agents except Codex; from 0.9.2 Codex falls back to `unknown` (agents.mdx). Fixed in the socket waiting signal and notes; this is no longer only "master".
- **Daemon false positive (process pattern).** `args_contain: ["server"]` is a substring test, so any client whose argument merely contains `server` matched the daemon rule, which was listed first: `herdr --remote build-server`, `herdr --session my-server`, `--remote=box-server`, `--machine build-server`. All read as daemons. Fix: added exact vetoes `--session`, `--remote`, `--machine`, `--remote-keybindings` (the real daemon argv never has them) and `help` to the daemon rule, and moved the tui surface before the daemon surface so the `=` forms fall to the tui. `herdr server` still resolves to the daemon because the tui rule vetoes the exact token `server`. Probe check after the change: `herdr --remote build-server`, `--session my-server`, `--session=my-server`, `--remote=box-server`, `--machine build-server` -> tui; `herdr server`, `/opt/homebrew/bin/herdr server` -> daemon.
- **Handoff server.** `herdr server --handoff-import <sock> <token>` is a real server (`server/handoff.rs`, `headless/bootstrap.rs`) and matches the daemon rule. Not mentioned before; added to the label. The probe hides it while the old server, its parent, lives.

### Unsupported or unmeasured (kept, marked as such)

- The 3 percent `tree_cpu` floor, idle and busy server CPU: no live instance, unmeasured.
- Pane shell argv0 `-zsh` and whether Homebrew's symlink or the Cellar path shows in `ps`: not observed (matching uses only the basename).
- `lsof -p <server pid>` showing the listening socket: not run. Note `HERDR_SOCKET_PATH` can override the socket location, so the socket to session mapping holds only when it is unset.
- Pane shells being DIRECT children of the server, and agents grandchildren: from source (`pane.rs`, portable-pty) and docs only; no process tree was inspected.

### Still wrong after repair (cannot be fixed with exact-match vetoes)

- A client run as `herdr --remote dev --remote-keybindings server`, or `herdr session attach server` / `--session server` for a session literally named `server`, matches nothing: the tui rule vetoes the exact token `server`, and the daemon rule vetoes the flags. A missed client, not a false one.
- `herdr session attach <name>` where `<name>` equals another vetoed token (`list`, `stop`, `agent`, `status` ...) is missed the same way.
- Other products named `herdr`: none found. Plugin binaries such as `herdr-plus` and `herdr-projects` have different basenames and do not match.

Confidence stays `documented`: every claim traces to docs or source, none was observed on a running instance.
