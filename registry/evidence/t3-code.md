# T3 Code: evidence notes (2026-09-29)

Row: `registry/agents/t3-code.json`. Validator: ok. Probe on this Mac: nothing running, nothing installed. Confidence is `documented`, not `verified-locally`.

## What I checked

- Upstream `https://github.com/pingdotgg/t3code` (v0.0.42 latest stable, Sep 16 2026; nightly 0.0.43-nightly.20260929 exists). Read from raw GitHub into the scratchpad: README, `docs/user/{install,background-service,permission-modes,providers-claude,providers-codex,project-settings,mobile-notifications,telemetry}.md`, `docs/internals/{overview,providers}.md`, `docs/operations/observability.md`.
- Source: `scripts/build-desktop-artifact.ts`, `scripts/install.sh`, `apps/desktop/package.json`, `apps/desktop/src/backend/DesktopBackendConfiguration.ts`, `DesktopBackendManager.ts`, `DesktopEnvironment.ts`, `apps/server/src/{config,os-jank,serverRuntimeState,serviceLauncher}.ts`, `cli/config.ts`, `persistence/Layers/Sqlite.ts`, migrations 005 and 023, `provider/Layers/{ClaudeAdapter,CodexSessionRuntime,codexLaunchArgs}.ts`, `observability/Layers/Observability.ts`, `orchestration/Layers/ProviderRuntimeIngestion.ts`, `packages/contracts/src/{orchestration,agentSessions}.ts`.
- Homebrew cask JSON for `t3-code` and `t3-code@nightly` (app names, zap paths).
- The published `@anthropic-ai/claude-agent-sdk` 0.3.284 tarball, downloaded and unpacked in the scratchpad only (not installed), to see exactly how the SDK spawns `claude`.
- Local: `ls /Applications`, `ps`, `ls ~/.t3`, `ls ~/Library/LaunchAgents`, `which t3`, `claude --version` and `--help`. All empty for T3. No session data read.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces on macOS | Electron desktop app; `t3` CLI (`t3`, `t3 serve`, launchd service); `npx t3`. Also a web app (app.t3.codes) and iOS/Android apps, which are clients with no local process | README, install.md |
| Bundle id | `com.t3tools.t3code` for stable and nightly | build script constant, cask zap paths |
| App bundle / exe | `/Applications/T3 Code (Alpha).app` (stable), `T3 Code (Nightly).app`. Mach-O name inferred equal to productName | package.json, cask |
| Desktop process tree | Electron main, plus a backend child that is the same exe with `ELECTRON_RUN_AS_NODE=1` running `.../apps/server/dist/bin.mjs --bootstrap-fd 3`, plus Electron helpers | DesktopBackendConfiguration.ts |
| CLI process | `t3` at `~/.t3/runtime/versions/<v>/t3`, symlink `~/.local/bin/t3`. Service: `t3 __service-launcher` supervising `t3 serve`; plist `~/Library/LaunchAgents/com.t3tools.t3code.service.plist` | install.sh, serviceLauncher.ts, background-service.md |
| Process to session | T3 processes carry no session id. Provider children do. Claude: `--session-id=<uuid>` or `--resume=<uuid>`. Codex: `codex app-server`, thread id is protocol-level, not in argv | SDK 0.3.284, ClaudeAdapter.ts, CodexSessionRuntime.ts |
| Store | `~/.t3/userdata/state.sqlite` (WAL): event log plus projections. Not one file per session. Underlying Claude transcripts stay in `~/.claude/projects`, Codex in `~/.codex/sessions`. T3 can also import those histories | config.ts, Sqlite.ts, agentSessions.ts |
| Turn in progress | Exact: `projection_thread_sessions.status='running'` with `active_turn_id` set, or `projection_turns.state='running'`. From outside without SQL: state.sqlite-wal mtime, then CPU of the tree. For the Claude child: its own JSONL transcript writes | source; the last two inferred |
| Waiting on human | `projection_threads.pending_approval_count` or `pending_user_input_count` above 0; `projection_pending_approvals.status='pending'`. Invisible in ps | migrations 005, 023 |
| Hooks | None of its own. Claude Code hooks should still fire because T3 loads user, project and local Claude settings | ClaudeAdapter.ts settingSources; inferred |
| OpenTelemetry | Yes, opt-in OTLP HTTP, three signals from `t3code-server`, traces and logs from `t3code-desktop`. Env in the launching shell only | observability.md, Observability.ts |

## Could not determine

- Real `ps` output for any T3 process. Not installed, and I may not install or run anything. The Mach-O name inside `Contents/MacOS/` is inferred from electron-builder's default.
- Idle CPU of the T3 backend and Electron helpers, so the `tree_cpu` floor of 5 percent is a guess.
- Whether `state.sqlite-wal` is written often enough during a streaming turn to serve as a 10 second signal. Deltas become orchestration events, but `resolveResponseStreamingMode` can batch by paragraph or message, so gaps are possible.
- Whether Claude Code's `caffeinate` sleep inhibitor runs under the SDK's stream-json mode. The strings sit next to TUI code (spellcheck, scroll), so I would not rely on it for T3-spawned sessions. Not tested.
- Whether Claude Code hooks (Notification, Stop) fire when the permission prompt is answered through the SDK `canUseTool` callback rather than a terminal.
- Whether the local Codex session files exist per T3 thread with the shadow-home layout; I did not inspect `~/.codex`.
- Whether provider children are killed when a thread idles (a `ProviderSessionReaper` exists; its timing was not read).
- Exact `ps` form for `npx t3` (the `.bin/t3` argv is inferred from package.json `bin`).

## Contradicts common belief or the hint

- The hint says "GUI that drives Codex and Claude Code sessions". Today it also drives Cursor, Grok Build, OpenCode and Antigravity, and it is mainly a server (`t3`) with desktop, web and mobile clients. Detection has to cover the headless `t3 serve`, not only the app.
- T3's own docs (observability.md) show the app at `/Applications/T3 Code.app/Contents/MacOS/T3 Code`. The shipped stable app is `T3 Code (Alpha).app`, so a match on that documented path misses it. The path also contains spaces and parentheses, which breaks any matcher that splits `ps args` on spaces (agents_probe.py does).
- A T3-spawned `claude` uses the equals form, `--session-id=<uuid>` and `--resume=<uuid>`. `tools/agents_probe.py` `session_id()` looks for the flag as its own argv token, so it returns no session id for these. The claude-code row lists `--session-id` and `--resume` as separate flags; that will not map T3-driven sessions to transcripts until the parser also accepts `flag=value`.
- These T3-driven `claude` processes already match the claude-code row (`/.local/bin/claude` or `/claude/versions/`), so the probe will list them as plain Claude Code sessions with no tty. Nothing in the schema expresses "parent is T3", so attribution needs a parent-chain check.
- `tool_children` would be wrong for T3: provider processes live between turns, so a child always exists.
- T3 "working" can outlast the turn: background subagents or workflows keep a thread marked working or monitoring after the turn settles, and a Claude turn held by an exhausted usage window keeps showing working (providers-claude.md).
- The default permission mode is Full access, so on a default install nothing ever waits on an approval; only agent questions block.
- "Hooks" in T3 Code means git hooks and project actions in `t3.json`, not agent lifecycle hooks. Its own trace file records finished spans only, so it cannot show an in-flight turn.

## Verification

Adversarial re-check, 2026-09-29. Re-fetched every cited file from raw GitHub `main` (v0.0.42 is the latest stable; nightly 0.0.43 exists), the Homebrew cask JSON, the npm `t3` 0.0.42 tarball and `@anthropic-ai/claude-agent-sdk` 0.3.284 tarball (unpacked in scratchpad, not installed). `tools/validate_row.py` passes before and after. Confidence stays `documented` (ceiling: T3 Code is not installed here). Any earlier text above that conflicts with this section is superseded by it.

### Confirmed

- Product scope: Electron desktop, web, iOS/Android, `t3` CLI; drives Claude Code, Codex, Cursor, Grok Build, OpenCode, Antigravity (README).
- Bundle id `com.t3tools.t3code` (`DESKTOP_APP_ID`, build-desktop-artifact.ts:57; cask zap lists the plist for stable and nightly).
- App names `T3 Code (Alpha).app` / `T3 Code (Nightly).app` (package.json productName, resolveDesktopProductName, cask `app` stanzas).
- Backend child = same executable, `ELECTRON_RUN_AS_NODE=1`, `apps/server/dist/bin.mjs --bootstrap-fd 3` (DesktopBackendConfiguration.ts:571-586, DesktopEnvironment.ts:222).
- Claude via Agent SDK with the user's `claude` binary: `pathToClaudeCodeExecutable`, `settingSources` user/project/local, `resume` xor `sessionId` (ClaudeAdapter.ts:4913-4943). SDK 0.3.284 emits `--output-format stream-json --verbose --input-format stream-json`, `--resume=<id>`, `--session-id=<id>` (equals form) and sets `CLAUDE_CODE_ENTRYPOINT=sdk-ts`.
- Codex via `codex app-server` (codexLaunchArgs.ts:13).
- State layout: `~/.t3` default, `T3CODE_HOME`/`--base-dir` override, `userdata` vs `dev`, `state.sqlite`, `logs/server.trace.ndjson`, `server-runtime.json` (config.ts, os-jank.ts, cli/config.ts); WAL pragma (Sqlite.ts:20).
- Status vocabularies and tables: session status idle/starting/running/ready/interrupted/stopped/error; turn state running/interrupted/completed/error; approvals pending/resolved; `projection_thread_sessions.status/active_turn_id`, `projection_turns.state`, `projection_pending_approvals.status`; `projection_threads.pending_approval_count/pending_user_input_count` added by migration 023 and written by ProjectionPipeline.ts (lines 582-599).
- Activity kinds approval.requested/resolved and user-input.requested/resolved (ProviderRuntimeIngestion.ts).
- Docs quotes: turn completion section (overview.md), usage-limit "can keep showing as working" (providers-claude.md), Full access default (permission-modes.md), service plist path and `t3 __service-launcher` (background-service.md, serviceLauncher.ts), install.sh layout, OTLP env names, service names `t3code-server`/`t3code-desktop`, desktop exports traces and logs only, `T3CODE_TELEMETRY_ENABLED=false` (docs/user/telemetry.md), trace file holds completed spans only (observability.md:8, 37).
- Hooks: T3 has no agent hooks; `t3.json` holds actions and worktree settings (project-settings.md).
- Not installed locally: re-run of the earlier local commands was not needed; nothing was started.

### Corrected

- npx form. The old row said the node surface was "inferred from package.json bin" (`./dist/bin.mjs`, the monorepo file). The published `t3` package's bin is `bin/t3.js`, a node launcher that `spawnSync`s the native `t3` from `@t3code/t3-darwin-arm64`. So under npx the server is a native `t3` child of node; the loose node entry matches the outer launcher only. Label and sources fixed.
- Process patterns, tested with `agents_probe.matches()` on synthetic argv:
  - `/.local/bin/t3` in `path_contains` also matched `/.local/bin/t3d`; redundant with the `t3` name match. Removed.
  - One-shot CLI subcommands (`service`, `app`, `auth`, `connect`, `pair`, `project`, `theme`, `triage`) matched as if they were servers. Added to `exclude_args` (each confirmed as a Command in apps/server/src/cli/).
  - Still open: `/Applications/T3` is a prefix match and would hit another app under that prefix; `/node_modules/.bin/t3` also matches `.bin/t3-*`. Cannot be tightened with the space-splitting probe; recorded in notes.
- Release evidence: v0.0.42 date is from the GitHub releases API (2026-09-16T04:59:02Z), not the README.
- Hooks under T3: upgraded from pure inference to documented for the SDK (Anthropic SDK hooks doc says settings-file shell hooks load for enabled settingSources). Still not observed under T3; Notification behaviour with `canUseTool` remains unknown.
- WAL working signal: wording softened from "is appended" to "expected to be appended", since `responseStreamingMode` can buffer deltas.

### Unsupported (kept, flagged as inferred)

- Mach-O name inside `Contents/MacOS/` for the Alpha and Nightly apps. Only corroborated by the older documented path `/Applications/T3 Code.app/Contents/MacOS/T3 Code` (executable named after productName).
- `state.sqlite-wal` mtime within 10 seconds as a working signal, and `tree_cpu` floor of 5 percent. No measurement exists.
- A T3-spawned `claude` having no TTY and exact `ps` argv (argv0 may be `claude` or a resolved path). Follows from SDK stdio piping; not observed.
- Whether Claude's `caffeinate` inhibitor runs in stream-json mode; whether provider children are reaped promptly (ProviderSessionReaper sweep default 5 minutes, idle policy not read).
- Anything about a running instance: none was available.
