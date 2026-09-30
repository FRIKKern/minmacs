# Devin CLI: evidence notes (2026-09-30)

Row: `registry/agents/devin.json`. Validator: ok. Probe on this Mac: 0 sessions (nothing installed, nothing running). Confidence `documented`: identification, hooks, OTel and store layout are read from vendor docs and from the vendor's own release binary. No live turn was seen, so every working signal is inferred.

```
terminal                                   editor / Desktop
   |                                            |
 devin  (Rust REPL, thin ACP client)        Zed, JetBrains, Xcode, Devin.app
   |  spawns its own binary                     |  spawns
   +-- devin acp   (agent, DB writer) <---------+
          |-- bash (tool shells; persistent per shell_id, else one-shot)
          |-- stdio MCP servers
          `-- writes ~/.local/share/devin/cli/sessions.db (SQLite, WAL)

devin --cloud  -> REPL + `devin acp --cloud` relay; the agent runs on a Devin VM
```

## What I checked

- docs.devin.ai `llms.txt` and `llms-full.txt` (3.1 MB, saved to the scratchpad and grepped): CLI quickstart, essential commands, commands reference, config file, read-config-from, hooks overview and lifecycle, subagents, troubleshooting, ACP pages for Zed and Xcode, stable changelog.
- `https://cli.devin.ai/install.sh` (read whole) and `https://static.devin.ai/cli/current/manifest.json`. Downloaded the 3000.11.3 aarch64-apple-darwin tarball to the scratchpad. Not installed, not executed. sha256 equals the manifest. It holds one Mach-O (171 MB), 192 man pages and the docs. Ran `strings -a`, `nm -u`, `otool -L`, `file` on it.
- Homebrew cask JSON `devin-cli`. PyPI `devin-cli` (a different program, see below).
- Third-party readers of the store: `DatekWireless/ai-usage-monitor` docs, `stablyai/orca` issue 21330 (real files from CLI 3000.10.27).
- Read the existing `windsurf` row and its evidence. It already folds this harness in; I did not edit it.
- Local: `ls /Applications`, `which devin`, `ls` of `~/.local/share/devin`, `~/.config/devin`, `~/.devin`, `ps`: all empty. Nothing to print from a session store, so no record keys were printed.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Process name | `devin`, one Rust binary. Same name for the REPL, the `devin acp` child, `-p` runs, and every management subcommand | install.sh, man page |
| Paths | `~/.local/share/devin/cli/_versions/<ver>/bin/devin` (symlink `~/.local/bin/devin`); Homebrew `Caskroom/devin-cli/<ver>/bin/devin` (symlink `$HOMEBREW_PREFIX/bin/devin`). argv[0] is `devin` when run by name; Xcode needs an absolute path | install.sh, cask JSON, Xcode docs |
| Bundle ids | none for the CLI. Devin Desktop is `com.exafunction.windsurf`, covered by the `windsurf` row | windsurf evidence |
| Process to session | `-r/--resume <id>` only. `-c`, a fresh start and `devin acp` carry no id. Candidate, unverified: a per-session lock file (`session_locks`, `.lock`) held open by the agent, findable with `lsof`. Per-run log `devin_<timestamp>_<pid>.log` maps a pid to a log, not to a session | commands doc, binary strings, troubleshooting doc |
| Session store | `~/.local/share/devin/cli/sessions.db`, SQLite, WAL. Tables `sessions`, `message_nodes`, `tool_call_state`, `subagent_heads`, `prompt_history`, `rendered_commits`, `app_state`. Not vendor-documented (`documented=false`). Also ATIF JSON `transcripts/<session_id>.json` (third-party, cadence unknown) and `session_exports/` for `--export` | binary DDL, third-party readers |
| Turn in progress | Nothing exact. Best: an open hook bracket `UserPromptSubmit` to `Stop` (shared `prompt_id`), or OTel `user_prompt` events; both opt-in. Passive fallback: `sessions.db-wal` mtime, then tree CPU | docs, binary |
| Waiting on the human | Hook `PermissionRequest`; hook `Stop` (turn over); terminal BEL, OSC 9, OSC 777 from the `notify` setting (default `smart`: only when unfocused) | docs |
| Hooks | 8 events: `PreToolUse`, `PostToolUse`, `PermissionRequest`, `UserPromptSubmit`, `Stop`, `PostCompaction`, `SessionStart`, `SessionEnd`. Files: `.devin/hooks.v1.json`, `"hooks"` in `.devin/config.json`, `~/.config/devin/config.json`, plus Claude Code files | docs |
| OTel | Yes since v3000.11.1 (2026-09-21). `otel` block or `OTEL_EXPORTER_OTLP_*`; logs and metrics, http/protobuf. Metrics include `devin.active_time.total` and `devin.token.usage` | changelog, binary |

## Could not determine

- Whether the REPL really shows a `devin acp` child in `ps`. The evidence is the binary's own help text and log strings ("the in-process ACP server the REPL spawns (a `devin acp` child that inherits the env)"), not a live process. Check `ps -axo pid,ppid,args | grep devin` during a turn.
- Every live signal: CPU while working, `-wal` write cadence, whether a persistent `bash` child stays after a turn, what an idle REPL costs.
- Where the session lock file lives and whether the holder keeps it open.
- Whether `Stop` fires on interrupt. Whether `otel` is on by default. Exact OTel event names (field names were read, event names are inferred: `session_start`, `session_end`, `user_prompt`, `api_request`, `api_error`, `assistant_response`, `tool_result`, `tool_decision`, `compaction`).
- Whether Devin Desktop launches `devin acp` from the same install path. The docs show only a sample `devin acp` registry entry.
- The `-p` short flag cannot be matched without a substring hazard; only `--print` gets its own one-shot surface.
- Public source: none. The CLI is closed Rust (crates `chisel-*`, `local-agent`, `agent-ext`). "Public source" here means the vendor's shipped binary and docs.

## Contradicts common belief

- The visible `devin` process is not the agent. It is a client of a `devin acp` child, so the bash tool calls are grandchildren of the REPL. A "direct shell child" rule never fires for a terminal session. It can fire for an editor-spawned `devin acp`, but a persistent `shell_id` shell can outlive a turn.
- No `caffeinate`, no power assertion. `nm -u` shows IOKit imports for registry reads only. This is the opposite of Claude Code, Codex and Grok Build.
- Hooks are not private to Devin. With `read_config_from.claude` on (default), `~/.claude/settings.json` hooks run in Devin sessions too. There is no `Notification` event, so a Claude Code "waiting" hook does not carry over: Devin waits are `PermissionRequest`.
- Windsurf, Devin Desktop and Devin CLI are one agent. The windsurf row's `devin` surface and this row both match `devin` by name; on a tie the probe takes the first row in file order. Until windsurf drops its tui surface, `devin mcp list`, `devin worker` and `devin --cloud` are claimed by it.
- Two unrelated programs share the name. The community PyPI `devin-cli` (Devin REST client) also installs a `devin` command and also reads `~/.config/devin/config.json`. As a Python script its argv[0] is the interpreter, so the name match does not hit it, but a config-path check would. Separately, `~/.devin` is also the Desktop and Homebrew-zap path.
- The `devin` docs and the man page describe `--cloud` as the same REPL: it is a local process whose agent is remote, so "idle" locally means nothing.

## Verification

Independent refutation pass, 2026-09-30. Validator: `ok`. Confidence stays `documented` (ceiling: the harness is not installed or running here; `which devin`, `ls /Applications`, `~/.config/devin`, `~/.devin`, `~/.local/share/devin` and `ps` all empty, re-run). Method: re-fetched `https://docs.devin.ai/llms-full.txt`, `install.sh`, the cask JSON, the manifest, the ACP registry and the PyPI JSON; re-hashed the saved 3000.11.3 tarball (sha256 c08cc3f3...0df2, equals the manifest); re-ran `strings -a` on its Mach-O; drove `tools/agents_probe.py matches()` and `session_id()` with synthetic argv against every registry row. Nothing was installed, run or started.

Result: 0 claims refuted, 4 corrected, 2 unsupported-as-worded, rest confirmed.

### Confirmed

- Installer layout (`_versions/<ver>/bin/devin`, `current` symlink, `~/.local/bin/devin`, legacy `cognition/` and `chisel/` migration): install.sh lines 5-12, 142-164, 211-243.
- Cask `devin-cli` 3000.11.3, `bin/devin` to `$HOMEBREW_PREFIX/bin/devin`, zap `~/.devin`; tarball URL equals the manifest URL.
- Tarball: `bin/devin`, `share/man`, `share/devin`; Mach-O arm64, 171232496 bytes; man header `devin 3000.11.3 (9c803229faa4)`.
- Thin ACP client: two independent strings in the binary, 'the in-process ACP server the REPL spawns (a `devin acp` child that inherits the env)' and 'so the `devin acp` child the REPL spawns picks it up too', plus `resolving current executable for \`devin acp\``, `spawned ACP agent child`, `chisel-acp-client/src/{bootstrap,child}.rs`; man page for `--cloud`. Still not seen in a live `ps`.
- Subcommands and flags: man page SUBCOMMANDS (auth mcp models doctor rules skills plugins cloud desktop list rm ssh forward update version migrate sandbox setup uninstall acp help), `ls` alias and `airgap doctor`, `worker`, `shell remove` in the docs; `self-manage`, `generate-man`, `post-install-setup` present in the binary. `-c`, `-r [SESSION_ID]`, `-p/--print [PROMPT]`, `--cloud`, `--export` in the commands page.
- No sleep inhibitor: 0 hits for `caffeinate|IOPMAssertion|PreventUserIdleSystemSleep|IOPMLib|pmset` in the binary strings; `nm -u` shows only IORegistryEntryCreateCFProperty, IORegistryEntryGetName, IOServiceGetMatchingService(s), IOServiceMatching.
- Session store: seven CREATE TABLE statements (`sessions`, `message_nodes`, `tool_call_state`, `subagent_heads`, `prompt_history`, `rendered_commits`, `app_state`), the `journal_mode` `WAL` `synchronous` `NORMAL` `busy_timeout` string run, `sessions.db`, `-wal`, `-shm`, legacy `cli_sessions.db`, `session_exports`, `ATIF-v1.7`. The `tool_call_update_json` nullable-column comment supports the in-flight guess (inferred, kept as inferred). `documented=false` is right.
- Path `~/.local/share/devin/cli/sessions.db` and `transcripts/<session_id>.json`: ai-usage-monitor `docs/providers/devin.md` (transcripts and sessions.db, macOS settings window), agentsview `devin.go` (`<root>/cli/sessions.db`), orca issue 21330 (ATIF-v1.7 files from CLI 3000.10.27; `sessions.id` equals the transcript file name). Note ai-usage-monitor documents ATIF-v1.4; the row's v1.7 follows orca and the binary.
- Process to session: only `-r`/`--resume` carries an id. Session-lock strings present (`Session ' is already open in another process` x3, `Failed to lock session`, `session_locks`); changelog v3000.11.1 'Session-lock errors identify the process holding the lock, including over ACP'. Lock location still unobserved.
- Hooks: eight events, matcher regex on `tool_name`, `session_id` and `prompt_id` in every payload, `DEVIN_PROJECT_DIR`, exit code 2 blocks, file locations incl. `.devin/hooks.v1.json`, `~/.config/devin/config.json`, Claude-format files loaded while `read_config_from.claude` is on (default), `/hooks`. No `Notification` event. No doc says whether `Stop` fires on interrupt.
- OTel since v3000.11.1 (2026-09-21); every env var, config key, metric name and attribute the row lists is present in the binary. Event names in this file's "Could not determine" list remain inferred.
- `notify` (`never|smart|always`, default `smart`) and the BEL, OSC 9, OSC 777 wording: config reference page plus the binary string `]777;notify;Devin;`.
- Per-run log `~/.local/share/devin/cli/logs/devin_<timestamp>_<pid>.log` (troubleshooting page); `AI_AGENT=devin_<version>_agent` (changelog v3000.11.1; the literal is not in the binary, so this rests on the changelog alone).
- Shell tool strings (bash by default, persistent shell per `shell_id`, one-shot without) and 'moves it to the background' in the essential-commands page.
- Devin Local in Devin Desktop is this harness: changelog v3000.3.x 'Devin Local (the CLI hosted in Windsurf)'; windsurf row overlap reproduced (below).
- PyPI `devin-cli` 1.5.1 (revanthpobala): `[project.scripts] devin = "devin_cli.cli:app"`, README `devin create-session`, `devin configure`, `~/.config/devin/config.json`, Homebrew tap. Under probe rules its argv[0] is the Python interpreter (shebang), so neither `names` nor `path_contains` matches: synthetic argv gives no match. No false positive from it.

### Corrected in the row

1. Source 'Session store': the quote 'Session history is now cached in SQLite' is from the Devin Desktop changelog (v3.7.1003), not the CLI changelog. Replaced with the CLI changelog lines that do exist (v3000.3.22 database thread, v3000.10.21 SQLite corruption fixes) and attributed the Desktop line correctly.
2. `PermissionRequest` meaning: the documented decisions are `approve` and `block`, not 'deny'.
3. IDE surface: added that Zed and JetBrains install Devin from the ACP registry, which runs `./bin/devin acp` from an editor-managed directory. The `names` match still fires (score 2, checked on synthetic argv) but `path_contains` cannot. Added a source entry with the registry JSON. This was a gap, not a wrong claim.
4. Cloud surface label said 'report the client as a client'. The matchers do the opposite: `devin --cloud` and `devin acp --cloud` are vetoed and this row reports nothing for them. Label now says so. Left as a deliberate choice (a local idle state would mislead).

### Unsupported as worded, now flagged

- Overlap with windsurf: the row already said this row wins ties. Reproduced with synthetic argv: `devin mcp list`, `devin worker start`, `devin --cloud`, `devin acp --cloud`, `devin -V` are not claimed by this row (excluded) and fall through to the windsurf tui surface at score 1. So the exclude_args vetoes do nothing visible until windsurf is fixed. Added to notes.
- Desktop-hosted `devin acp`: a Devin.app parent matches the windsurf row, not this one, and the outermost rule checks the same row only, so the child can be listed twice. Inferred from `agents_probe.py`; no live process was seen. Added to notes as inferred.

### Process-pattern review (false positives and misses)

- `names: ["devin"]` is an alternative to `path_contains`. Only the Cognition binary and the PyPI wrapper use this name; the wrapper's argv[0] is Python, so it does not match. `devin worker start` runs a separate `devin-remote` binary cached under `~/.devin/worker/cache`, which matches nothing here.
- `path_contains` `/devin/cli/_versions/` and `/Caskroom/devin-cli/`: the version directory holds only `bin/devin`. Nothing else matches. They only raise the score; a bare `devin` (score 1) is still found by name.
- Score logic checked: `devin acp` scores 2 on ide (tui vetoed by `acp`); `--print` scores 2 on the oneshot surface; `-p` falls to the tui surface at 1 and is not flagged one-shot (already in notes). `devin --continue --print` is one-shot.
- Accepted trade-off, not changed: `exclude_args` is an exact match against any word, and many veto words are common English (`list`, `update`, `help`, `setup`, `shell`, `rules`, `cloud`, `models`, `version`). An unquoted prompt such as `devin -- update the list` hides a real session. The notes already say this; README case 16 has the same limit. Dropping the words would show short subcommands as idle sessions instead. Left for the owner of the detector to decide.
- `session_id`: `-r <id>`, `--resume=<id>` work; `-r --model opus` returns `--model` (in notes).
