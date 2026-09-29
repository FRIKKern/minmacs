# Continue CLI (`cn`) evidence notes (2026-09-29)

Not installed on this Mac. Nothing below was seen on a running instance. Confidence is `documented`. Sources: docs.continue.dev (CLI section), a shallow clone of continuedev/continue at 5522c6f (2026-07-20, read-only, in the scratchpad), and the published npm tarball `@continuedev/cli` 1.5.47 (2026-06-18, fetched with curl, not installed).

## What I checked
- Local: `which cn` (not found), `ls ~/.continue` (absent), `ls ~/.vscode/extensions | grep -i continue` and `ls /Applications | grep -i continue` (empty), `ps` for `continuedev` or `/bin/cn` (empty).
- Docs: quickstart, tui-mode, headless-mode, configuration, tool-permissions. `https://docs.continue.dev/cli/overview` (the URL in the task) now redirects to `/docs/cli/quickstart` and returns 404; the live pages are `/cli/quickstart` etc. Docs say nothing about `cn serve`, hooks, OpenTelemetry or where sessions are stored.
- Surfaces: interactive TUI (`cn`, Ink/React), headless (`cn -p`/`--print`, one-shot), `cn serve` (hidden HTTP daemon, used by Continue's cloud devbox agents), short subcommands `ls`, `checks`, `review` (`review` forks a `--internal-review-worker` node child). The Continue IDE extensions (VS Code, JetBrains) are a separate agent; only the session store code is shared.
- Process shape: `dist/cn.js` is `#!/usr/bin/env node` and runs the CLI in the same process. npm and the shell installer both end in `npm install -g @continuedev/cli`, so ps should show `node <prefix>/bin/cn [flags]`. No bundled binary, no `process.title`, no relaunch child except the auto-updater (detached `node <entry> <same args>`, parent stays).
- Session id: never in argv for the TUI. `--resume` is a boolean (most recent session), `--fork <id>` names the source session. Only `cn serve --id <id>` makes the id the session id.
- Store: `~/.continue/sessions/<uuid>.json` (whole file rewritten, pretty JSON) plus an index `sessions.json`. Keys from the code: sessionId, title, workspaceDirectory, history, mode, chatModelTitle, usage. Rewritten on every history change (user message, finished assistant message, tool result), not per streamed delta.
- Working signals: direct `$SHELL -l -c <cmd>` child while the Bash tool runs; session-file write; CPU (spinner at 150 ms only while a response is pending). No caffeinate, no power assertion anywhere in the CLI source. For `serve`: `GET /state` gives `isProcessing` exactly.
- Waiting: TUI permission and AskQuestion prompts are in-process only. `serve`: `pendingPermission` in `/state`.
- Hooks: see below. OTel: metrics only, env-gated.

## Could not determine
- Real `ps` args on a Mac. `node <prefix>/bin/cn` is inferred from node's argv[1] behaviour and the bin symlink. Volta, pnpm and bun-global shims may show a different path; the `@continuedev/cli` surfaces are the fallback.
- CPU when working or idle. The 3 percent floor is a guess.
- The exact session file cadence in a real turn (tool-heavy turns write per tool result by reading the code, not by watching mtimes).
- Whether a plain TUI session can be mapped to its file other than by cwd. No pid registry, no runtime sidecar. The fallback is the newest file whose `workspaceDirectory` (from `sessions.json`) equals the process cwd, which is ambiguous when two sessions share a directory.
- Whether newer npm releases than 1.5.47 exist beyond what `npm view` shows (latest tag is 1.5.47; the repo HEAD is 0.0.0-dev and may be ahead).
- Whether the JetBrains plugin has a matchable process on Mac (it runs the core binary; not inspected).
- Whether anyone runs `cn serve` on a Mac. It is aimed at Linux devboxes; the surface exists in the row for completeness.

## Contradicts common belief or the obvious approach
- Hooks look supported and are not. The CLI declares 17 Claude-Code-compatible hook events, loads `~/.claude/settings.json` and `~/.continue/settings.json` (and project and `.local` variants) and registers a HookService, but nothing calls `fireStop`, `fireNotification`, `fireUserPromptSubmit` or any other fire function. The 1.5.47 bundle contains no `stop_hook_active` or `last_assistant_message` string. The `PreToolUse` and `PostToolUse` literals in the bundle belong to a git-ai checkpoint service. So a hook written for Claude Code and dropped into `~/.claude/settings.json` will not fire under `cn`. AGENTS.md describes the system as if live. The row says `supported: false`.
- No sleep inhibitor, unlike Claude Code and Qwen Code. Do not look for `caffeinate`.
- The quickstart says the shell installer "bundles its own runtime". The script installs fnm and Node 20.20.1, then runs npm install. The process is plain `node`.
- `cn login` is in the quickstart, but no `login` command is registered in `src/index.ts`; the latest commit message says the login flow was retired.
- `-p` (the documented headless flag) cannot be matched: `args_contain` is a substring test and `-p` hits `--prompt`, `--port` and any path with `-p`. The row matches `--print` only and vetoes `-p` (exact) from the TUI surface, so `cn -p ...` runs are simply not listed. A one-shot shown as an idle TUI would be worse than not shown.
- The name `cn` collides with `cnpm`, `cnvm` and similar under a `/bin/cn` substring test. The interpreter is `node`, so a name match on `cn` alone finds nothing.
- The OTel spec file says the export interval default is 60000 ms; the code defaults to 20000. Setting only `OTEL_METRICS_EXPORTER` (any value) enables telemetry with the console exporter as default, which prints metrics to the terminal.
- Sessions are not JSONL. One rewritten JSON file per session, and the glob `~/.continue/sessions/*.json` also matches the `sessions.json` index that changes on every save.

## Verification
`python3 tools/validate_row.py registry/agents/continue.json` printed `ok   registry/agents/continue.json`. `python3 tools/agents_probe.py --row registry/agents/continue.json` ran and found 0 sessions (nothing installed).

## Verification

Adversarial re-check on 2026-09-29 by a second agent. Method: `python3 tools/validate_row.py registry/agents/continue.json` (ok before and after edits); a fresh clone of continuedev/continue (HEAD is still 5522c6f, 2026-07-20); the npm tarball `@continuedev/cli` 1.5.47 fetched with curl and unpacked in a scratchpad (nothing installed); docs pages fetched with curl; `tools/agents_probe.py` `matches()` run over synthetic ps lines. Nothing was started, no session store was read. Confidence stays `documented` (cannot be higher: no cn on this Mac).

### Confirmed
- Docs: quickstart lists `cn`, `npm i -g @continuedev/cli`, `--resume` ("Resume the most recent session"), Node.js 20+, and says the shell installer "bundles its own runtime". headless-mode: `cn -p`, tools that would prompt are excluded, `--allow` needed, `cn -p --resume` works. tui-mode and tool-permissions: approval prompt, `~/.continue/permissions.yaml`. configuration: `~/.continue/config.yaml`. None of the pages mention `serve`, hooks, OpenTelemetry or `~/.continue/sessions`, so `documented=false` for the store is right.
- npm: latest 1.5.47, dist-tags beta 1.5.43-beta.20260203, published 2026-06-18, bin `{ cn: 'dist/cn.js' }`; `dist/cn.js` is exactly `#!/usr/bin/env node`, `import { runCli }`, `await runCli()`. No `process.title` is set by the CLI.
- Installer: install.sh has REQUIRED_NODE_VERSION 20.20.1, fnm install, `npm install -g "$PACKAGE_NAME"` (line 277). The docs sentence about a bundled runtime is misleading, as the notes say.
- index.ts: Ink TUI default, `-p, --print`, `--resume` boolean, `--fork <sessionId>`, hidden `serve [prompt]` with `--timeout`, `--port` (default 8000) and `--id <storageId>`, plus `ls`, `checks`, `review`; no `login` command is registered. `review` forks `process.argv[1]` with `--internal-review-worker`.
- Session store: `core/util/history.ts` writes keys sessionId, title, workspaceDirectory, history, then mode, chatModelTitle, usage, with `JSON.stringify(..., undefined, 2)`, and maintains `sessions.json` on every save; `CONTINUE_GLOBAL_DIR` moves the root (session.ts line 48-51). `cn serve --id X` uses X as session id (serve.ts 150-154).
- Bash tool: `spawn($SHELL, ['-l','-c', command])` (runTerminalCommand.ts line 66-87, 192); background jobs spawn the same way (BackgroundJobService.ts line 68). No `caffeinate` and no power assertion anywhere in `extensions/cli/src`.
- serve: `/state` `/message` `/permission` `/pause` `/diff` `/exit`; `isProcessing` true at line 457, false in `finally` at line 533 and in `/pause`; `pendingPermission` set on a permission request; inactivity shutdown after `--timeout` (default 300) and each `/state` resets it.
- Hooks: 17 event names in `types.ts`, loader reads the six settings paths, `HookService.fireEvent` exists, but every `fire*` helper in `fireHook.ts` has no caller anywhere else in `src`. In the 1.5.47 bundle `stop_hook_active` and `last_assistant_message` are absent and the only `hook_event_name:"PreToolUse"/"PostToolUse"` literals are in the git-ai checkpoint code. Row says unsupported: correct.
- OTel: metrics only (logs are `TODO: Implement OTLP logs export`), gated on an OTEL env var, `CONTINUE_METRICS_ENABLED=0` and `CONTINUE_CLI_ENABLE_TELEMETRY=0` disable, exporter default `console`, interval default 20000 in code and 60000 in `spec/otlp-metrics.md`, service name `continue-cli`. Ships in the bundle.
- Auto-updater relaunch: `spawn(process.execPath, [process.argv[1], ...args], { detached: true })`, parent waits for the child (UpdateService.ts line 195-235).
- `which cn` not found; `~/.continue` absent; no continue app or VS Code extension; `ps` shows no cn process.

### Corrected
- Process pattern, false positives (probe `matches()`): `node /usr/local/bin/cnpm install x`, `node /usr/local/bin/cnvm use 20`, `node <dir>/bin/cn-build.js` all matched the TUI surface. Cannot be narrowed with substring `args_contain` and exact `exclude_args`; now stated in the label.
- Process pattern, package-path surfaces: bare `@continuedev/cli` also matched `node npm-cli.js install -g @continuedev/cli` and `npm view @continuedev/cli`. Both package-path surfaces now require `@continuedev/cli/dist/cn.js`. Verified after the edit: the npm command matches nothing, a pnpm-style `.../node_modules/@continuedev/cli/dist/cn.js` still matches (surface 4, or 1 with `serve`).
- The labels claimed npx cache and other shims were covered. They are not: npx and project-local installs run `.../node_modules/.bin/cn`, and `.bin/cn` does not contain the substring `/bin/cn` (probe: no match on either surface). Labels now say so. Not added as a surface because the ps shape for npx is inferred.
- `serve` is a substring test on every space-split token, so a TUI started as `cn observe the logs` is misfiled as the daemon surface; and exact tokens `review`, `checks`, `serve`, `-p` inside a prompt drop a TUI session from the list. Both now in the labels.
- `transcript_write`: the file is also rewritten on tool status changes and usage updates, not only message boundaries.
- `tool_children`: the earlier claim "the only spawn sites are git, shells, git-ai helper, update relaunch, review worker" was wrong. `exec()` (which runs `/bin/sh -c`) is also used for `git-ai --version` at startup, `open "<url>"` and, on macOS while the input box is enabled (idle), `osascript -e "clipboard info"` every 2 s (UserInput.tsx 699, useClipboardMonitor.ts, util/clipboard.ts 21). The meaning now lists these and the exec-in-place caveat.
- `tree_cpu` floor raised from 3 to 10 because of that idle osascript child (ps reports a short-lived child's CPU over its own lifetime). Still an unmeasured guess; recorded as inferred.
- `/state` meaning: the body includes the full conversation `session`, so a monitor must read only two fields; polling also keeps the server alive. Added.
- Source 1: `https://docs.continue.dev/cli/overview` returns HTTP 200 with an empty app shell to curl, not a 404 or visible redirect. Reworded.

### Unsupported (kept, marked inferred)
- Real `ps` args `node <prefix>/bin/cn`. Consistent with Node behaviour and the bin symlinks here (`~/.nvm/.../bin/pi -> ../lib/node_modules/.../cli.js`) but no symlinked node bin was running to compare. Not observed.
- Whether `$SHELL -l -c '<one command>'` shows a shell child or the command itself, and whether the idle osascript poll appears as `sh` or `osascript`. Both need a run; only read-only commands were allowed.
- The CPU floor (10) and the 30 s transcript window: no measurement.
- Volta, bun and yarn global layouts matching `/bin/cn`.
- Cadence of file writes in a real turn (read from code, not watched).
