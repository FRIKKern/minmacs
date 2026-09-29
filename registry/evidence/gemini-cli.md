# Gemini CLI evidence notes (2026-09-29)

Not installed on this Mac. Nothing below was observed on a running instance. Everything comes from a shallow clone of google-gemini/gemini-cli (main at fe63502, package 0.63.0-nightly.20260923), spot-checked against tags v0.46.0 (Homebrew stable) and v0.61.0 (npm latest), plus geminicli.com docs (all URLs returned 200). Confidence is `documented`, not `verified-locally`.

## What I checked
- Local: `which gemini`, `ls ~/.gemini`, `ps | grep gemini` all empty.
- Install shapes: npm `@google/gemini-cli` (bin `gemini` -> `bundle/gemini.js`, node shebang), Homebrew (depends on node, stable 0.46.0), MacPorts, standalone SEA binary `gemini` built for darwin (unsigned CI artifact `gemini-darwin-<arch>`).
- Process shape: `relaunch.ts` re-executes the CLI as a child node process with `GEMINI_CLI_NO_RELAUNCH=true`. Expect two nested node processes per session. Parent args show the bin symlink path, child args show the real `.../gemini-cli/bundle/gemini.js` path plus memory flags.
- Session id: only in argv for `--session-id <id>` or `--resume/-r <value>`. The resume value can be `latest` or an index, not an id.
- Store: `~/.gemini/tmp/<slug>/chats/session-<YYYY-MM-DDTHH-mm>-<first 8 of id>.jsonl`. Line 1 is metadata, then message records, then `{"$set":...}` patch lines. Subagents nest in `chats/<parent id>/<id>.jsonl`. Slug map is `~/.gemini/projects.json` (path -> slug). `GEMINI_CLI_HOME` moves the home. Hook stdin also carries `transcript_path` and `session_id`.
- Write cadence: appended at prompt accepted, model message complete, tool calls complete. Not mid-stream.
- Waiting: `Notification` hook (`ToolPermission` only), terminal title `✋  Action Required`, opt-in OSC 9/BEL notifications.
- Hooks: 11 events, command type, `hooks` in settings.json (user, project, system `/Library/Application Support/GeminiCli/settings.json`).
- OTel: built in, off by default, OTLP grpc/http, local file or GCP.
- Power assertions: grepped packages for caffeinate, IOPM, powerSave, wake lock. Nothing.

## Could not determine
- Real idle and working CPU of the Ink UI. `tree_cpu` at 3 percent is a guess.
- Whether the transcript shows a pending permission prompt. Tool call records are written when tools finish; I did not find a write for `awaiting_approval`.
- Exact `ps` args on a real Mac (symlink vs realpath, Homebrew wrapper shape). The `bin/gemini` and `gemini-cli/bundle/gemini.js` needles are inferred from the npm layout. A Homebrew or nvm install may differ.
- Actual record key names from a real file. Keys listed come from the TypeScript types, not from reading a file.
- Whether a "Gemini Code Assist agent mode" in VS Code runs the CLI as a separate process. Not in this repo. The `vscode-ide-companion` package is an MCP bridge, not an agent.
- No macOS app bundle id exists in the repo. There may be none.
- Whether headless `-p` and `--acp` sessions write transcripts the same way. Assumed yes, unchecked.

## Contradicts common belief or the obvious approach
- Docs say `<project_hash>`. Code now uses a readable slug from `projects.json`. The docs are stale.
- The file name holds only 8 characters of the session id, so a full-uuid glob finds nothing.
- Sessions do not expose their id in argv by default. Only hooks get `GEMINI_SESSION_ID`.
- No sleep inhibitor, unlike Claude Code. There is no caffeinate child to look for.
- `tool_children` (any non-caffeinate child) is wrong for this harness with the current probe: the relaunch child node and MCP stdio servers are always children. Left out on purpose.
- The transcript is a weak busy signal: silence during a long stream or long shell command.
- Best turn-state signal is the OSC 0 terminal title (Ready / Working / Action Required), which is outside what `ps` sees.
- Homebrew lags: stable 0.46.0 vs npm latest 0.61.0. Both use the JSONL store and the same relaunch code.
- The probe's `path_contains` only checks argv[0]. For node-run scripts the identifying path is in argv[1], so this row uses `names: ["node"]` with `args_contain`. That can false-match any node process whose args contain `bin/gemini`.

## Verification
Adversarial re-check, 2026-09-29. Fresh shallow clone of google-gemini/gemini-cli at fe63502, tag v0.61.0 fetched, docs re-fetched live (maxAge 0), `tools/validate_row.py` printed `ok` before and after repair. Local: `which gemini` printed `gemini not found`, `ls ~/.gemini` printed no such directory, `ps` showed nothing, so confidence stays at most `documented`. Synthetic argv lines were run through `matches()` in `tools/agents_probe.py`; no real process was inspected.

### Confirmed
- Package bin `gemini` -> `bundle/gemini.js` (package.json main and v0.61.0; npm `latest` 0.61.0 also prints `{'gemini': 'bundle/gemini.js'}`).
- Homebrew formula depends on node, stable 0.46.0 (formulae.brew.sh API).
- Standalone binary is named `gemini` (scripts/build_binary.js line 413), unsigned macOS builds at `dist/darwin-<arch>/gemini`.
- No macOS bundle id, no Info.plist in the repo (`git ls-files` finds none); `packages/` has a2a-server, cli, core, devtools, sdk, test-utils, vscode-ide-companion.
- `--resume`/`-r`, `--session-id`, `--session-file` exist and are mutually exclusive (config.ts lines 242-248, 401, 421, 426).
- Transcript path and name: `<global runtime dir>/tmp/<projectIdentifier>/chats/session-<UTC YYYY-MM-DDTHH-mm>-<first 8 of sanitized id>.jsonl` (chatRecordingService.ts lines 479-521). Subagents nest under `chats/<parent id>/<id>.jsonl`. Record types include `{"$set":...}` (line 647) and `{"$rewindTo":...}` (line 951, not in the row). Append-only via `fs.appendFileSync` (line 561).
- Write cadence: user prompt (geminiChat.ts 547/565), final model message after the stream ends with thoughts and tokens flushed first (1636-1652), tool calls after they finish (1715). Nothing written mid-stream.
- Terminal title strings and OSC 0 write (windowTitle.ts; AppContainer.tsx 2096); `ui.hideWindowTitle` and `ui.dynamicWindowTitle` exist and the docs list them (defaults false and true).
- No sleep inhibitor: grep for `caffeinate|IOPM|powerSave|powerSaveBlocker|wake.?lock` over packages returned nothing. Inferred from absence, stated as such.
- Shell tool uses `@lydell/node-pty` (shellExecutionService.ts line 16).
- Hooks: eleven events, type `command` only, `hooksConfig` in settings, Notification carries only `ToolPermission`, observability only, base stdin schema, `GEMINI_SESSION_ID` env (hookRunner.ts 353). Docs at geminicli.com/docs/hooks/ and /hooks/reference/ agree.
- Settings paths: macOS system path in settings.ts lines 105-115 and on /docs/reference/configuration/; `GEMINI_CLI_SYSTEM_SETTINGS_PATH` override.
- Telemetry: off by default, env names and `gemini_cli.*` event names match /docs/cli/telemetry/; default endpoint `http://localhost:4317` (docs/cli/telemetry.md line 43, telemetry/index.ts line 13); default target `local`.
- Notifications: opt-in, OSC 9 with BEL fallback, events "Action required" and "Session complete" (/docs/cli/notifications/, marked experimental).
- Docs say `<project_hash>` for the chats directory; the code uses a project identifier resolved through `projects.json`. The row's wildcard covers both.

### Corrected
- Relaunch source was wrong. `relaunchAppInChildProcess` in relaunch.ts has no call site. The real supervisor is `run()` in `packages/cli/index.ts` (lines 54-131), skipped when `GEMINI_CLI_NO_RELAUNCH` or `SANDBOX` is set. The two-process shape still holds. Cite fixed in the row.
- Relaunch child argv was misdescribed above ("child args show the real .../bundle/gemini.js"). `getSpawnConfig` passes `process.argv[1]` through unchanged, so on a symlinked npm/Homebrew install the child shows the same `.../bin/gemini` as the parent and matches surface 1. The bundle-path surface only matches direct `node .../bundle/gemini.js` runs. The standalone binary relaunches as a second `gemini` process, and its memory flag goes through NODE_OPTIONS. Surface labels fixed. The probe already keeps the outermost match, so counts are unaffected.
- The ACP surface never matched the deprecated flag: `--acp` is not a substring of `--experimental-acp`, and the public docs list only `--experimental-acp` (`--acp` is in docs/cli/acp-mode.md and the source). Split into two surfaces. Both now also require a `gemini` needle, because the old surface matched any node process with `--acp`, for example qwen-code (a fork that takes the same flag). Synthetic check: `node .../qwen-code/cli.js --acp` now matches nothing.
- Release asset name: `gemini-darwin-<arch>-unsigned.zip` (GitHub releases/latest, v0.61.0, alongside `gemini-cli-bundle.zip`), holding the file `gemini`. Label fixed.
- `--session-id` was cited to /docs/cli/cli-reference/. That page does not list it (or `--acp`). Source only. Cite fixed.
- `session_store.documented` changed true to false. The docs promise `<project_hash>` and never name the JSONL format or file names (the hook reference calls the transcript "JSON"). The observed path comes from source, not a vendor promise.
- Homebrew: formula is deprecated (2026-06-18, unsupported, replacement cask antigravity-cli, disable date 2026-12-18). Added to sources and notes.
- Missing context added: Gemini CLI stopped serving consumer accounts on 2026-06-18 (Google blog May 19, 2026; docs banner). Those users moved to Antigravity CLI (`agy`, Go), a separate product with no `gemini` binary in its install script. Enterprise and paid-API use continues. Noted in the row; Antigravity needs its own row.

### Unsupported (kept, flagged)
- `tree_cpu` at 3 percent: no measurement exists. The row already says so.
- Whether Zed or another editor passes `--acp` or `--experimental-acp`, and what argv it uses: not verified, hence both spellings.
- `~/.gemini/projects.json` fallback mapping and the `chats/*` newest-file heuristic: read from source only, never observed.
- Exact `ps` argv on a real Mac (Homebrew wrapper shape, nvm): not observed.
- Record key names come from the TypeScript types, not from a real file.
- Under `--sandbox` on macOS the runtime dir moves to `~/.cache/.gemini` (storage.ts lines 92-101) and the CLI spawns through sandbox-exec (`SANDBOX=sandbox-exec`, sandbox.ts line 306). Not reflected in the glob. Not tested.

### Process-pattern false positives
- `args_contain: ["bin/gemini"]` is a substring test. Synthetic `node /a/node_modules/.bin/gemini-mcp` matches surface 1, so any gemini MCP server launched from a `.bin` shim looks like a session. It cannot be tightened with the current probe, since `exclude_args` is exact match. Also matches `/usr/local/bin/gemini-anything`.
- `names: ["gemini"]` matches any unrelated executable called `gemini`. The Gemini macOS app binary is `Gemini` (capital G) and does not match; the name test is case sensitive.
- Headless `-p` runs match and count as working for their lifetime.
- `-r latest` or bare `--resume` puts a non-id into the session id slot.
