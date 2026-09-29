# Windsurf (now Devin Desktop): evidence notes (2026-09-29)

Row: `registry/agents/windsurf.json`. Validator: ok. Probe on this Mac: 0 matches. Nothing is installed (no app, no CLI, no data dirs, no process, no assertion), so no live turn was seen and every working signal is inferred. Confidence `documented` covers identification and hooks only.

```
"Windsurf" the product name is gone (2026-06-02). Now:

Devin.app  (bundle id STILL com.exafunction.windsurf, VS Code fork, one Electron main for all chats)
 |- Devin Local agent = `devin acp` child (Devin CLI binary, ACP over stdio)      <- the agent, since Cascade was removed 2026-09-08
 |- ACP agents (third party), cloud Devin sessions (no local process)
 |- language server (legacy: language_server_macos_arm --ide_name windsurf)        <- completion/context, not the agent
~/.local/bin/devin  or  brew cask devin-cli  = the same harness in a terminal
~/.codeium/windsurf/bin/{devin-desktop,surf,windsurf}  = shell launchers, not agents
```

## What I checked

- docs.windsurf.com and every deep link I tried return HTTP 307 to docs.devin.ai/desktop/... Read from docs.devin.ai: `devin-desktop-faq`, `devin-local`, `cascade/hooks` (raw markdown via firecrawl, maxAge 0), `agent-command-center`, `troubleshooting/logs`, `acp`, the Devin Desktop and Devin CLI changelogs, CLI `hooks/overview`, `hooks/lifecycle-hooks`, `essential-commands`. Searched the whole `llms-full.txt` (3.1 MB) for otel, caffeinate, sleep, wake lock, session store paths.
- Homebrew cask JSON: `devin-desktop`, `devin-desktop@next` (old token `windsurf@next`), `devin-cli`. The old `windsurf` cask JSON no longer exists (404).
- Public source: none. `Exafunction/codeium` is an issue tracker only; the Devin CLI is closed Rust. Third-party readers used for the session DB schema: `kenn-io/agentsview` (`internal/parser/devin.go`, `types.go`) and `YosefHayim/agent-session-pack` README.
- Local: `ls /Applications`, `which`, `ls` of every candidate data dir, `ps -axo`, `pmset -g assertions`: all empty. Then the row's matchers run through `tools/agents_probe.py` `matches()` on synthetic command lines: `Devin.app/.../MacOS/Devin` and `Windsurf.app/.../MacOS/Electron` match `ide`; a `Devin Helper (Renderer)` line matches nothing; `devin acp` and `devin -r brisk-otter` match `tui` (session id `brisk-otter` extracted); `devin --version` and `claude` match nothing. Synthetic, not live.
- No session store exists here, so no record keys were printed.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| App / process | `Devin.app` (Next: `Devin - Next.app`), legacy `Windsurf.app` whose main binary was `Contents/MacOS/Electron`. Main executable name inside `Devin.app/Contents/MacOS/` not found anywhere | FAQ, cask, third-party for legacy |
| Bundle ids | `com.exafunction.windsurf`, Next `com.exafunction.windsurfNext`. URL schemes `devin` and `windsurf` | cask `uninstall quit`, user report codex#30046 |
| Agent process | `devin acp` (Devin Local); CLI `devin` at `~/.local/bin/devin` or Homebrew `bin/devin` | docs acp page, cask |
| Process to session | CLI: `-r/--resume <id>` only (`-c` and plain start carry none). `devin acp`: nothing in argv, id arrives over ACP `session/new` or `session/load`. Fallback idea, untested: `lsof` on the process for the open `sessions.db` does not separate sessions either | docs essential-commands, changelog |
| Session store | Devin Local and CLI: SQLite `cli/sessions.db` under the data dir, tables `sessions`, `message_nodes`. Not vendor-documented (`documented=false`). Legacy Cascade: `~/.codeium/windsurf/cascade/*.pb`, reported encrypted | third-party |
| Turn in progress | Nothing exact found. Best guess: recent write to `sessions.db`/`-wal`, then CPU of the `devin` process tree, then non-MCP children of it | inferred |
| Waiting on human | Hook `PermissionRequest` (Devin Local); opt-in OS notification `devin.agentNotifications`; UI greys a session while its agent runs | docs |
| Hooks | Devin Local: `.devin/hooks.v1.json`, `"hooks"` in `.devin/config.json` / `~/.config/devin/config.json`, also Claude Code files. 8 events. Cascade (legacy): `hooks.json` at system, `~/.codeium/windsurf/`, `.devin/` levels, 12 events | docs |
| OTel | Devin CLI only, since v3000.11.1 (2026-09-21): `otel` block or `OTEL_EXPORTER_OTLP_*` | CLI changelog |

## Could not determine

- Whether Devin.app holds a power assertion or spawns `caffeinate` during a turn. No doc or changelog mentions it. Check `pmset -g assertions` on a machine mid-turn. This would be the best signal if it exists.
- Whether Desktop runs one `devin acp` process per session or one shared. Matters for double counting against the `ide` surface and for "which session is working".
- The real macOS data dir for `sessions.db`: `~/.local/share/devin` (vendor docs place the CLI logs there on macOS) or `~/Library/Application Support/devin` (agentsview probes both). Row records the first.
- Whether Desktop-hosted `devin acp` reads the CLI `otel` config, and whether the session-lock ("session is locked by another process" in the changelog) is a file, flock or DB row. A lock would be a per-session signal worth finding.
- Main executable name in `Devin.app/Contents/MacOS/`, and whether the `language_server_macos_*` binary still ships under that name.
- Path-with-space limitation: `probe.processes()` splits `ps` args on spaces, so `/Applications/Devin - Next.app/...` yields exe `/Applications/Devin` and the Next matchers cannot fire. Same limit hits any bundle with a space (Antigravity IDE). Stable `Devin.app` is unaffected.

## Contradicts common belief

- Windsurf is no longer called Windsurf. Since 2026-06-02 it is Devin Desktop, `Devin.app`. A registry that looks for `Windsurf.app` finds nothing on an updated Mac. `docs.windsurf.com`, the row's `start_at`, redirects to `docs.devin.ai`.
- The bundle id did not change (`com.exafunction.windsurf`), so a bundle-id match still works while a name match does not.
- Cascade is gone. Removed in Desktop v3.9.19 (2026-09-08); Devin Local, the Devin CLI harness, is the only agent. The FAQ page still says Cascade stays 'through July', which is stale. The Cascade hooks page is still published and still applies to the JetBrains plugin, but a Desktop user's hooks now live in the Devin CLI format, not `hooks.json` with `pre_run_command` etc.
- The Windsurf agent is not a Windsurf-specific process any more: it is the same `devin` binary the terminal CLI uses. There is no separate `devin` row in `harnesses.json`; this row absorbs it, and a second row would double count.
- `~/.codeium/` is still the config root (MCP for legacy Cascade, user settings, launchers), even though the product is Devin. Only new data goes to `~/Library/Application Support/Devin` and `~/.devin`.
- Cascade transcripts were not readable: `.pb` files are reported encrypted per conversation, and only a hook (`post_cascade_response_with_transcript`) produced JSONL, capped at 100 files.
- `docs.devin.ai` has `llms.txt` and `llms-full.txt`; searching them beat navigating the site.

## Verification

Independent refutation pass, 2026-09-29. Validator `tools/validate_row.py registry/agents/windsurf.json`: ok before and after repair. Probe `--row`: 0 agent sessions (nothing installed). Confidence stays `documented` (the ceiling here, because the harness is not installed); identification, hooks and CLI flags are documented, all working signals remain inferred. Sources re-fetched: docs.devin.ai FAQ, devin-local, acp, agent-command-center, CLI hooks pages and `llms-full.txt` (changelogs, commands, logs, credentials); Homebrew cask JSON for `devin-desktop`, `devin-desktop@next`, `devin-cli`; agentsview `devin.go` and `types.go`; agent-session-pack README; openusage windsurf.md; codex#30046, gemini-cli#2016, Exafunction/codeium#127. The reddit thread could not be fetched.

### Confirmed

- Rename on 2026-06-02 (FAQ; Desktop changelog v3.0.12 "Windsurf is now Devin Desktop"). `Devin.app`, `devin-desktop` replaces `surf`, legacy `surf`/`windsurf` still in `~/.codeium/windsurf/bin/`.
- Bundle id `com.exafunction.windsurf` (cask `uninstall quit`; codex#30046 also lists URL schemes `devin`, `windsurf`). Next: `com.exafunction.windsurfNext`, app `Devin - Next.app` (cask `devin-desktop@next`, old token `windsurf@next`).
- Data dirs `~/Library/Application Support/Devin`, `~/.devin` (cask zap); legacy read paths and `~/.codeium/` unchanged (FAQ table).
- Cascade removed in v3.9.19, 2026-09-08; new conversations never start on Cascade; FAQ "through July" text is stale (both quoted on the pages).
- Devin Local shares the Devin CLI harness (devin-local page). CLI cask `devin-cli`, binary `bin/devin`, `~/.local/bin/devin` (FAQ).
- Resume flags `-c/--continue`, `-r/--resume <SESSION_ID>` (commands reference, essential-commands).
- Devin Local / CLI hooks: 8 events, all config locations, `.devin/hooks.v1.json` as whole-file object, `.claude/*` read by default, exit code 2 blocks, `session_id` and per-turn `prompt_id` in stdin, Restricted Mode disables hooks. `PermissionRequest` and `Stop` semantics match the lifecycle page.
- Legacy Cascade hooks: exactly 12 events, three merged locations with the Windsurf fallbacks, common fields `agent_action_name`, `trajectory_id`, `execution_id`, `timestamp`, `model_name`; transcript path, 0600 and 100-file cap.
- OTel: only mention in the whole docs corpus is CLI changelog v3000.11.1 (2026-09-21); config-file reference has no section.
- `devin.agentNotifications`, off by default, one notification per session; sessions locked while agent runs (quoted sentence present).
- Session DB: tables and columns in agentsview `devin.go`; path `<root>/cli/sessions.db`; roots `Library/Application Support/devin` and `.local/share/devin`; agent-session-pack README gives `~/.local/share/devin/cli/sessions.db`. Vendor: "Session history is now cached in SQLite", ACP saves on a dedicated database thread, CLI logs at `~/.local/share/devin/cli/logs/devin_<timestamp>_<pid>.log`.
- Legacy `Windsurf.app/Contents/MacOS/Electron` (gemini-cli#2016 quotes the alias); language server recipe and `--ide_name` values (openusage windsurf.md).
- JetBrains plugin in maintenance mode, Cascade being deprecated there (FAQ). Cloud sessions run on Devin VMs (Command Center).
- Local observation: no app, no binary, no data dirs, no process, no assertion (re-run; same output).

### Corrected

- **"One main process hosts every agent session in the window" (ide label, notes): unsupported, removed.** No page says so, and it conflicts with the row's own `devin` surface. Label now says the local-agent process model under Devin.app is undocumented.
- **"Devin Desktop launches Devin Local as `devin acp`": narrowed.** The ACP page says it only for the sample local-registry config. The devin-local page calls the bundled agent something Desktop "fetches from the server" and gives no launch command or path. Process name `devin` for the bundled agent is now labelled inferred in the surface label, source claim and notes.
- **`path_contains: "/.local/bin/devin"` removed from the `devin` surface (false positive).** It is a substring test, so `/.local/bin/devin-desktop` matched as an agent (reproduced with `matches()`); the basename `names: ["devin"]` already covers the real binary. Kept `/Caskroom/devin-cli/`.
- **`sessions.db-wal` mtime: unsupported.** Nothing documents WAL journaling. Signal name and meaning now say "only if WAL is used, unverified". Added the `XDG_DATA_HOME` override (vendor credentials table shows the data dir follows it) and noted that the probe's `transcript_write` check needs `per_session`, so this signal does nothing in `agents_probe.py` today.
- **"`devin acp` takes no session id in argv": downgraded to inferred.** The cited changelog line only says ACP clients can pass MCP servers in `session/new` or `session/load`. Also added that bare `devin --resume` opens a picker and the probe returns `--model` as the id for `devin -r --model x`.
- **Cascade `.pb` "encrypted, entropy 7.95-7.98": partly unsupported.** Issue #127 comments say protobuf with no public schema, "they are encrypted", "Encryption is per-UUID". The entropy numbers and the exact `cascade/<uuid>.pb` path were not found on the page; claim reworded, path marked unverified.
- **Command Center "Kanban columns show working / blocked / ready": reworded** to the page's "in flight / needs your attention / finished". The Local/Worktree/Cloud picker comes from Desktop changelog v3.9.19, not the Command Center page.
- **Reddit citation for `Windsurf.app/Contents/MacOS/Electron` dropped** (page not fetchable); gemini-cli#2016 alone supports it.
- Telemetry and tree_cpu wording no longer assumes Desktop launches a `devin acp` child.

### Unsupported or still inferred (left as is, labelled)

- Every working signal: `transcript_write`, `tree_cpu`, `tool_children`, `power_assertion`. No live turn was observed. The docs corpus has no hit for caffeinate, sleep inhibitor or wake lock.
- Whether Devin.app ships `language_server_macos_*` under that name today; main executable name in `Devin.app/Contents/MacOS/`.
- Whether the Desktop-hosted agent reads the CLI `otel` config.

### Process pattern false-positive review (synthetic argv through `matches()`, not live)

| argv | result |
|---|---|
| `Devin.app/Contents/MacOS/Devin` | ide, as intended |
| `Devin Helper (Renderer)`, `Devin Helper --type=utility` | no match (path has `/Contents/Frameworks/`) |
| `devin`, `devin acp`, `devin -r id`, `devin -p fix` | tui, as intended |
| `devin --version`, `ssh devin@host` | no match |
| `/.local/bin/devin-desktop .` | matched before repair, no match now |
| `devin mcp list`, `devin auth status`, `devin list`, `devin ls`, `devin forward`, `devin ssh`, `devin --cloud` | tui: still match. Not local agent turns. Not excluded because the probe splits args on spaces and matches `exclude_args` by exact element, so excluding `list` or `ssh` would hide a real session started with a prompt containing that word |
| `/Applications/Devin - Next.app/...`, `/Applications/Windsurf - Next.app/...` | never match under `probe.processes()` (space split); the two Next path entries are dead there |
| the electron-as-node CLI wrapper (`devin-desktop .` running `Contents/MacOS/Devin cli.js`) | would match `ide` if it runs from the bundle path; unverified, short-lived |

### Candidate signals found while checking (not added, unverified)

- Per-process log `~/.local/share/devin/cli/logs/devin_<timestamp>_<pid>.log` is vendor-documented and carries the pid, so it could map a process to a file and give an mtime signal.
- CLI v3000.11.1 sets `AI_AGENT=devin_<version>_agent` in agent shell commands, which could identify tool children (environment only, not visible in `ps` args).
