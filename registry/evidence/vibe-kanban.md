# Vibe Kanban: evidence notes (2026-09-30)

Row: `registry/agents/vibe-kanban.json`. Validator: ok. Confidence `documented` (source code and vendor pages only). Not installed here, nothing running (`ls /Applications ~/Applications`, `ls ~/.vibe-kanban`, `ls ~/Library/Application Support/ai.bloop.vibe-kanban`, `ps`, `mdfind` for the bundle id: all empty).

## What I checked

- Vendor: GitHub README (says "Vibe Kanban is sunsetting"), `https://www.vibekanban.com/blog/shutdown` (2026-04-10: bloop shut down, project continues open source and community maintained, remote services removed after 30 days, local workspaces keep working), repo `docs/` (settings, agents, sessions).
- Source: shallow clone of BloopAI/vibe-kanban at `d5cbb53` (2026-09-19, tag `v0.1.45-20260919085201`) in the scratchpad, read only. Files read: `npx-cli/src/{cli,download,desktop}.ts`, `crates/tauri-app/{tauri.conf.json,Cargo.toml,Info.plist,src/main.rs}`, `crates/server/src/{main.rs,startup.rs,routes/*,middleware/origin.rs}`, `crates/db/{src,migrations}`, `crates/utils/src/{assets,execution_logs,port_file,shell,approvals}.rs`, `crates/executors/src/executors/*.rs` and `default_profiles.json`, `crates/services/src/services/{approvals,notification,execution_process,container}.rs`, `crates/local-deployment/src/container.rs`, `crates/remote/src/lib.rs`, `.github/workflows/pre-release.yml`.
- Releases: `npm view vibe-kanban version` gives 0.1.44 (modified 2026-09-19); `gh release view` on the latest release lists `Vibe.Kanban_0.1.44_aarch64.dmg` and `_x64.dmg`. I did not download or mount them.
- Tauri docs for the default main binary name (`mainBinaryName`).
- Match test with `tools/agents_probe.py matches()` over 8 made-up command lines: server binary and desktop (both exe names) match only this row; `vibe-kanban-mcp`, `vibe-kanban-review`, the node launcher and `node npx -y @anthropic-ai/claude-code` match nothing; a leaf `claude -p ...` matches `claude-code`.
- No session data read. No content seen.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | Desktop app (Tauri v2, server in-process); browser-mode server binary launched by `npx vibe-kanban`; `vibe-kanban-mcp` and `vibe-kanban-review` helpers (not sessions); VS Code extension (docs only, not looked at); a cloud/remote service being retired | tauri-app main.rs, cli.ts, docs/integrations |
| Bundle id | `ai.bloop.vibe-kanban`, bundle folder `Vibe Kanban.app` | tauri.conf.json |
| Executables | Server: `~/.vibe-kanban/bin/<tag>/macos-arm64/vibe-kanban` (built as `server`, renamed in the zip). Desktop: `Vibe Kanban.app/Contents/MacOS/vibe-kanban-tauri` (INFERRED from Tauri's default, not seen) | pre-release.yml, download.ts, Tauri docs |
| Process to session | It is a host: one process, many workspaces and sessions. Session ids are VK uuids, on no command line. Practical key: an agent child's cwd (`$TMPDIR/vibe-kanban/worktrees/<workspace>/<repo>`) equals `workspaces.container_ref` + repo; its env has `VK_WORKSPACE_ID` and `VK_WORKSPACE_BRANCH`. Claude follow-ups carry `--resume <agent_session_id>` (= `coding_agent_turns.agent_session_id`) | claude.rs, container.rs:1366 |
| Store | `~/Library/Application Support/ai.bloop.vibe-kanban/`: `db.v2.sqlite` (rollback journal, not WAL) and `sessions/<xx>/<session>/processes/<process>.jsonl`. Neither promised by the vendor: `documented=false` | assets.rs, db/lib.rs, execution_logs.rs |
| Turn in progress | Exact: `execution_processes.status='running' AND run_reason='codingagent'`. One process per turn. Same fact over HTTP: `POST /api/workspaces/summaries` `latest_process_status`. Weak: raw log JSONL mtime, tree CPU | execution_process.rs, workspace_summary.rs |
| Waiting on the human | In-memory approval list, pushed on `ws://127.0.0.1:<port>/api/approvals/stream/ws` and as `has_pending_approval` in the summary. Never on disk. Turn row stays `running` while waiting | approvals.rs, approvals routes |
| Hooks | None for users. Per-repo setup, cleanup, archive and dev scripts (`$SHELL -c`), sound and push toggles. VK uses Claude Code's Stop and PreToolUse hook callbacks internally | script.rs, claude/client.rs, docs |
| OpenTelemetry | No, in the local app (Sentry and PostHog). Yes only in the cloud `remote` crate (Application Insights exporter) | remote/src/lib.rs |

## What I could not determine

- Anything from a live run. No process, database or log file was seen; every path and column comes from source at `d5cbb53`. The released 0.1.44 build may differ slightly (source is 0.1.45).
- The real executable name inside the desktop bundle. Inferred `vibe-kanban-tauri`; the row also matches on the `Vibe Kanban.app/Contents/MacOS/` folder so a different name still hits.
- Whether `/bin/sh -c` in the npx wrapper's `execSync` execs in place (bash does for a single command, so probably no extra `sh`). The row does not depend on it.
- How many workspaces a real user runs, so whether tree CPU is worth its floor. Left at 5 percent, uncalibrated.
- The VS Code extension (`docs/integrations/vscode-extension.mdx`): not read for process shape.
- Whether the local HTTP API needs a token in the desktop build: source shows only an Origin check, and only when an Origin header is present.

## Contradicts common belief, or bites a detector

1. **VK is not an agent and does not appear as `claude` or `codex`.** It launches `npx -y @anthropic-ai/claude-code@2.1.119 ...` per turn. On macOS the direct child is usually `node` (npx is a node script, so argv[0] is `node`), which is why `child_process` and `tool_children` are left out of the row. A dev-server script (`zsh -c 'npm run dev'`) also becomes a permanent direct `node` child by exec in place (README case 9), and terminal panes are permanent shell children.
2. **Agent leaves can match other rows.** My probe test: a native `claude -p` leaf matches `claude-code` (its `names: [claude]` is enough by itself). Drop matches under a Vibe Kanban host, per README case 15, or one turn is counted twice and shows as an idle Claude Code.
3. **"Sunsetting" does not mean gone.** The company closed 2026-04-10; the code is community maintained, `main` is at 0.1.45 (2026-09-19) while npm and the GitHub release stop at 0.1.44. The remote features are removed; local workspaces keep working. Expect it to still run on machines.
4. **The app's own `is_running` is not "an agent is working".** It counts setup and cleanup scripts too. Filter on `run_reason='codingagent'`.
5. **A `running` row can be a lie.** After a crash the row stays `running` until the next server start rewrites it to `failed`. Require the server pid to be alive.
6. **Waiting is rare and invisible on disk.** All default profiles skip permissions, and pending approvals live only in memory (10 hour timeout), so no store, hook or process shows a wait. Only the WebSocket or the summary does. The `osascript` and `afplay` children on a wait exist only when notifications are on, and only in browser mode.
7. **`db.v2.sqlite` has no `-wal` file** (journal mode DELETE), unlike Hermes and Conductor, so a WAL mtime check finds nothing; use the main file's mtime, which any write moves.
8. **The port file is browser-mode only.** `$TMPDIR/vibe-kanban/vibe-kanban.port` is written by the standalone server, not by the desktop app; ask `lsof` for the desktop app's listening port.
9. **Name clash.** `mistral-vibe` lists `bin/vibe-kanban` under python as a known false positive of its `/bin/vibe` substring test. My match test of the real server path (`~/.vibe-kanban/bin/<tag>/macos-arm64/vibe-kanban`) hit only this row, because that path has `/bin/<tag>/`, not `/bin/vibe`.
10. The user asked to remember Grok Bot too. That is a separate row (`grok-bot` in `registry/harnesses.json`), not part of this task, and I did not touch it.

## Verification

Adversarial re-check, 2026-09-30. Validator: `ok` before and after. Source re-read from a fresh shallow clone of BloopAI/vibe-kanban at `d5cbb53` (tag `v0.1.45-20260919085201`); vendor pages re-fetched; `npm view` and `gh release` re-run. Confidence stays `documented` (never seen running; the harness is not installed: `~/.vibe-kanban`, `~/Library/Application Support/ai.bloop.vibe-kanban`, /Applications and ~/Applications, `ps` and `mdfind` for the bundle id are all empty).

Match test: `tools/agents_probe.py matches()` over all 63 rows present in registry/agents at that time with 13 made-up command lines. Only this row matched: desktop exe (both possible names, /Applications and ~/Applications) and the server path. Nothing matched for `vibe-kanban-mcp`, `vibe-kanban-review`, the node launcher, the `/bin/sh -c "<bin>"` wrapper, `npx -y @anthropic-ai/claude-code`, a cargo dev binary `server`, a WebKit helper. `mistral-vibe` (`/bin/vibe`) does not collide, because the real path is `/bin/<tag>/macos-arm64/vibe-kanban`. Residual false positive: any other program whose argv[0] basename is exactly `vibe-kanban` (none known; the npm shim runs under `node`).

| Claim | Result | Basis |
|---|---|---|
| Sunsetting; bloop shut down 2026-04-10; project community maintained; remote services removed after 30 days; local workspaces keep working | confirmed | README line 19; https://www.vibekanban.com/blog/shutdown re-scraped (published 2026-04-10, text matches) |
| npm latest 0.1.44 (modified 2026-09-19); GitHub latest release v0.1.44-20260424091429; main at 0.1.45 | confirmed | `npm view`, `gh release list`, `tauri.conf.json` version 0.1.45 |
| Release has `Vibe.Kanban_0.1.44_aarch64.dmg` and `_x64.dmg` | confirmed | `gh release view --json assets` |
| Bundle id `ai.bloop.vibe-kanban`, productName and bundleName `Vibe Kanban`, cargo bin `vibe-kanban-tauri` | confirmed | tauri.conf.json, crates/tauri-app/Cargo.toml `[[bin]]` |
| Executable inside the bundle is `Contents/MacOS/vibe-kanban-tauri` | unsupported (inferred) | Tauri `mainBinaryName` schema: default is the cargo output binary; no CI step or conf sets `mainBinaryName`; no dmg opened. The row still matches on the `/Vibe Kanban.app/Contents/MacOS/` folder, verified with a made-up `Contents/MacOS/Vibe Kanban` name |
| Server runs inside the Tauri process | confirmed | tauri-app main.rs line 206 `server::startup::start()` |
| Browser mode: `npx vibe-kanban` downloads `vibe-kanban` to `~/.vibe-kanban/bin/<tag>/macos-arm64/` and runs it with `execSync`; `--desktop` installs the .app to /Applications, then ~/Applications, and runs `open --wait-apps`; `mcp`/`review` run the helper binaries | confirmed | cli.ts (getPlatformDir, extractAndRun, runMain lines 244-278), download.ts CACHE_DIR, desktop.ts lines 110-139, pre-release.yml (server built as `server`, zipped as `vibe-kanban`) |
| Server binds 127.0.0.1 on an auto port, writes `$TMPDIR/vibe-kanban/vibe-kanban.port`; desktop does not write it; Origin checked only when present | confirmed | server main.rs lines 59-86, port_file.rs line 17; the only writer of the port file is server main.rs; origin.rs line 48 |
| Data dir `~/Library/Application Support/ai.bloop.vibe-kanban`, `db.v2.sqlite` journal DELETE, `sessions/<xx>/<session>/processes/<process>.jsonl` | confirmed | assets.rs, db/lib.rs lines 79-134, execution_logs.rs. Release builds only; debug builds use `<repo>/dev_assets` |
| Tables and columns named in the row (workspaces container_ref, branch, archived; sessions executor, name; coding_agent_turns agent_session_id, prompt, summary, seen; execution_processes status, run_reason, dropped) | confirmed | migrations 20251216142123, 20251221000000, 20260217120312, 20260314000000, 20260107115155 |
| A turn is one `codingagent` execution_processes row; statuses running/completed/failed/killed; orphans marked failed at next start | confirmed | execution_process.rs enums; container.rs `cleanup_orphan_executions`, called from startup.rs line 160 |
| Run reasons | corrected | there are five (`setupscript`, `cleanupscript`, `archivescript`, `codingagent`, `devserver`). The row's SQL filters on `codingagent`, so it is unaffected |
| The app's own `is_running` counts setup, cleanup and coding-agent processes | confirmed, citation corrected | it is in `crates/db/src/models/workspace.rs` lines 518-526, not `execution_process.rs` as the source entry said. Fixed in the row |
| `POST /api/workspaces/summaries {"archived":false}` returns `latest_process_status`, `has_pending_approval`, `latest_session_id`; latest may be a script | confirmed | workspace_summary.rs; `find_latest_for_workspaces` selects `codingagent`, `setupscript`, `cleanupscript` |
| Approvals in memory only, WebSocket `/api/approvals/stream/ws`, 36000 s timeout | confirmed | approvals.rs, routes/approvals.rs line 112, utils/approvals.rs |
| Agents are direct children of the server, per turn, with `VK_WORKSPACE_ID` and `VK_WORKSPACE_BRANCH`; Claude follow-up adds `--resume <id>`; executors launch by `npx -y ...` or native `cursor-agent`, `droid exec` | confirmed | claude.rs lines 65, 360-380, 627-650; container.rs 1366-1367; codex, amp, gemini, copilot, qwen, opencode, cursor, droid executors. Because `npx` is a node script the direct child shows as `node`, so no `child_process` signal (kept out of the row, correctly) |
| Scripts run as `$SHELL -c`; terminals are PTY sessions | confirmed | script.rs line 55, shell.rs lines 17-21 and 183, `portable-pty` in local-deployment Cargo.toml |
| Worktrees under `$TMPDIR/vibe-kanban/worktrees` (or `<custom>/.vibe-kanban-workspaces`); debug uses `vibe-kanban-dev` | confirmed | path.rs `get_vibe_kanban_temp_dir`, worktree_manager.rs lines 515-522 |
| Every default profile skips permission prompts | confirmed | default_profiles.json re-parsed: values as listed in the source entry |
| No OpenTelemetry in the local app; Sentry and PostHog only | confirmed | `grep -rli 'opentelemetry\|otlp\|OTEL_'` hits only crates/remote; utils/Cargo.toml sentry 0.46.2; README env table lists POSTHOG_* |
| Not installed here, nothing running | confirmed | commands above, re-run |
| `osascript` child as a waiting signal | unsupported, removed | container.rs `finalize_task` (lines 238-268) sends "Workspace Complete: <name>" through the same NotificationService when a turn ends, so the helper appears on completion as well as on approval or question. It also needs notifications turned on. It cannot tell waiting from done. The row's other waiting signal (approvals WebSocket, `has_pending_approval`) is unaffected |
| `afplay` only in browser mode | corrected | `play_sound_notification` is in the shared NotificationService, so the desktop app spawns `afplay` too when sound is on. Only `osascript` is browser-mode (or desktop dev fallback) |
| `tree_cpu` floor 5 | corrected to 10 | uncalibrated either way; registry/README.md section 4 sets 10 for desktop hosts and hosts that hold dev servers, and the row's own text says dev servers burn CPU with no turn |
| Session store paths are undocumented by the vendor | confirmed | `documented=false` kept; source read only, nothing observed |

Changes made to `registry/agents/vibe-kanban.json`: `tree_cpu` floor 10; removed the `osascript` waiting signal; fixed the `is_running` citation and the notification claim in the sources; added notes 4b and 4c. Nothing else touched.

Still unproven, so confidence cannot exceed `documented`: the real executable name in the .app, behaviour of the released 0.1.44 build (source is 0.1.45), everything about a live run, and the VS Code extension surface (not read). The user's "remember Grok Bot" is a separate row and is not part of this file.
