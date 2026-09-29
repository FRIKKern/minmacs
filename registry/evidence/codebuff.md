# codebuff: evidence notes (2026-09-29)

Row: `registry/agents/codebuff.json`. Validator: ok. Confidence `documented`. Codebuff is not installed here and nothing was running (`which codebuff cb freebuff` all "not found"; no `~/.config/manicode`; `ps` empty), so no surface was classified live. Versions researched: repo HEAD `97654d3` (2026-09-29), npm `codebuff` 1.0.688, npm `freebuff` 0.1.6, Freebuff Desktop 0.0.152.

## What I checked

- Shallow clone of `CodebuffAI/codebuff` (redirects to `CodebuffAI/freebuff`) into the scratchpad, read with grep and sed only: `cli/src` (cli-args, project-files, chat-history, run-state-storage, chat-meta, logger, terminal-watchdog, terminal-command-broker, entry, status-indicator-state, freebuff-instance-owner, freebuff-session-relaunch), `cli/release-core/launcher.js`, `sdk/src` (run.ts, tools/run-terminal-command.ts, run-file-change-hooks.ts), `agents/`, `docs/`. Not built, not run.
- Docs: `codebuff.com/docs` quick start (binary path), `freebuff.com/desktop` (download page, "not code-signed").
- `npm view` for both packages (metadata only).
- Freebuff Desktop 0.0.152 mac-arm64 zip from the public GitHub release: HTTP range reads of the zip's central directory, `Info.plist`, `app-update.yml`, `app.asar` and `orchestrator/orchestrator.js`. Nothing was downloaded whole, mounted, installed or run. Read with `plistlib`, `strings -a`, `grep`. From the database schema I read table and column names only; no message content exists here to read.
- Synthetic `ps` lines run through the probe's own `matches()`, `session_id()` and `classify()`: CLI and Freebuff CLI match; `node .../codebuff/index.js` launcher, `node .../bin/cb`, the broker helper, the `/bin/sh` watchdog, the Electron main process and its helpers match nothing; the Desktop orchestrator matches `gui`; `--continue <id>` yields the id; a `codebuff` child plus the CLI parent classifies working, the watchdog alone classifies idle.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | Codebuff CLI (TUI), Freebuff CLI (TUI, same code with `FREEBUFF_MODE=true`), Freebuff Desktop (Electron), Freebuff Web / Cloud / Chat (hosted). `@codebuff/sdk` is a library embedded in other programs: no process signature | README, cli/src, desktop zip |
| CLI process | Bun-compiled binary `~/.config/manicode/codebuff` (or `freebuff`), argv[0] is that full path. npm bins `codebuff` and `cb` are a Node launcher that stays alive as the parent | launcher.js, quick-start docs |
| Bundle ids | Desktop `com.freebuff.desktop`, exe `Freebuff.app/Contents/MacOS/Freebuff`. CLI has none | Info.plist |
| Desktop process | Matched on `Freebuff.app/Contents/Resources/bun/bun .../orchestrator/orchestrator.js`, one per app, listening on 127.0.0.1 | app.asar `resolveOrchestrator`, orchestrator.js `Bun.serve` |
| Process to session | CLI: only `--continue <id>` gives an id; otherwise cwd (`lsof`) gives the project folder basename and the newest chat directory there is a guess. Desktop: one process, many threads, no per-thread argv | cli-args.ts, project-files.ts |
| Store, CLI | `~/.config/manicode/projects/<cwd basename>/chats/<ISO time, ':' as '-'>/chat-messages.json` (JSON array), `run-state.json`, `chat-meta.json`, `log.jsonl`. Not promised by the vendor: `documented: false` | project-files.ts, run-state-storage.ts |
| Store, Desktop | SQLite `<project root>/.freebuff/desktop-v2.db` | orchestrator.js line 180067 |
| Turn in progress, CLI | Direct child that is the same executable with `--terminal-command-broker` (only during shell tool calls); chat files rewritten about every 5 s during a run (`STATE_SNAPSHOT_INTERVAL_MS`) | terminal-command-broker.ts, run.ts |
| Turn in progress, Desktop | `threads.turn_state = 'running'` in the project database; fallback direct `bash` child | orchestrator.js lines 195543, 195652, 129861 |
| Waiting on human | Nothing external for the CLI. Desktop has `attention_reason` (`failed`, `merge-conflict`, `auto-stopped`), which is not a prompt | status-indicator-state.ts, orchestrator.js |
| Hooks | None | sdk run-file-change-hooks.ts, grep |
| OpenTelemetry | No. PostHog and an Axiom log sink | grep, bun.lock |

## Contradicts common belief or the generic rules

1. **The npm command is not the process.** `codebuff` and `cb` on PATH are `node index.js` launchers; the agent is a different binary under `~/.config/manicode/`. Matching on the name `codebuff` in argv[0] finds the binary and skips the launcher, which is what we want. Matching on the path of the installed npm package would find the wrong process.
2. **The generic "ignore a child with the same executable as its parent" rule is wrong here.** On the CLI every shell tool call spawns `codebuff --terminal-command-broker` as a direct child, and bash is that helper's child. The same-executable child is the tool signal, and a shell child of the main process is not. README section 4 says to count shells and skip same-executable children; for this row it is the reverse.
3. **`tool_children` would mark every idle CLI as working.** On POSIX the CLI keeps a detached `/bin/sh -c "cat >/dev/null...; printf ..." terminal-reset-watchdog` as a direct child for its whole life (when stdout is a TTY and `CODEBUFF_NO_TERMINAL_WATCHDOG` is unset). The row uses `child_process` by name instead.
4. **No sleep inhibitor.** No `caffeinate`, no IOKit assertion, in the CLI, the SDK or the Desktop app (`powerSaveBlocker` absent). Signal 1 of the README's recommended order does not exist for this harness.
5. **The CLI store is keyed by folder name, not path.** `projects/<basename of cwd>`: two projects called `app` share a folder. Claude Code encodes the whole path. The chat id is a timestamp that never appears in argv, so unlike Claude Code there is no `--session-id`; `--continue` is the only flag.
6. **Codebuff and Freebuff share one store** and nothing in it says which binary wrote a chat. `prior-art.md` already noted this.
7. **Desktop keeps state in the project, not in Application Support.** Each opened project gets `.freebuff/desktop-v2.db` (and `.freebuff/worktrees/`). It has an exact per-thread `turn_state`, a stored working flag like Cline's `sessions.status` or T3 Code's thread projection. Reading it needs a `sqlite_row` signal kind that the schema does not have.
8. **The public repo is now Freebuff.** `github.com/CodebuffAI/codebuff` redirects to `CodebuffAI/freebuff`, README is Freebuff-first, while `cli/release/package.json` still publishes the npm package `codebuff`. The Desktop source (`freebuff-desktop/`) is referenced in comments but not in the public tree; I read the shipped bundle instead.
9. **Desktop runs other harnesses.** Threads carry `harness_id`; claude and codex CLIs run as children of the orchestrator (marker `FREEBUFF_ORCHESTRATOR_PID` is in their environment, so it is invisible to a command-line matcher). They will also match `claude-code` and `codex` rows (README case 12).

## Could not determine

- Real `ps` output for any surface. Everything above is from source and shipped bundles.
- Idle and busy CPU, so the `tree_cpu` floor of 3 is a guess. The Freebuff TUI polls for ads and may never be at 0.
- Whether Bun retitles or rewrites argv on macOS for the compiled binary. Nothing in the source sets `process.title`.
- Whether the Desktop native engine (`harness_id = 'codebuff'`) runs in-process in the orchestrator. The bundle contains the SDK's terminal tool code, so I inferred yes; I did not trace it.
- Whether Desktop pending questions or permission requests are persisted anywhere. The schema has no table for them and `deps.questions` looks in memory, so waiting is probably invisible from disk. Inferred.
- The Electron `userData` directory contents (`~/Library/Application Support/Freebuff`?) beyond `browser-recordings` and `browser-captures` names in the asar.
- Whether the `--terminal-command-broker` design exists in every release of the npm package. I read HEAD only; 1.0.688 is the published version and HEAD may be ahead.
- Freebuff Desktop on Intel (I read arm64 only; the layout is expected to match).
- Which agent-approval prompts exist in the Codebuff CLI. I found none for shell commands in `cli/src`, which fits the product's history but was not tested.
- How the launcher looks in `ps` while it restarts the binary for an update (`stoppedForUpdate` path): a brief second child may appear.

## Verification

Second reader, 2026-09-29. Method: `tools/validate_row.py` (ok before and after); shallow clone of `CodebuffAI/codebuff` at HEAD `cf26785` (the first pass read `97654d3`, same day); `npm view`; `curl` against freebuff.com, codebuff.com docs and the release redirects; the shipped codebuff 1.0.688 darwin-arm64 binary downloaded and read with `strings` only (not run); Freebuff Desktop 0.0.152 arm64 zip re-read by HTTP range (central directory, `Info.plist`, `app.asar`, `orchestrator.js`; nothing installed or run); synthetic `ps` lines through the probe's own `matches()` and `session_id()`. Nothing was running here, so no surface was classified live; confidence stays `documented`.

Source entries, in row order:

| # | Claim | Result |
|---|---|---|
| 0 | Repo redirects to CodebuffAI/freebuff, Freebuff-first README | Confirmed (`curl -sIL` gives 301 to github.com/CodebuffAI/freebuff; README table lists Desktop, CLI, Web, Cloud, Chat). |
| 1 | npm versions and bins | Confirmed (`npm view`: codebuff 1.0.688 with codebuff and cb; freebuff 0.1.6 with freebuff; both `#!/usr/bin/env node` launchers). |
| 2 | Launcher path, argv[0], CODEBUFF_LAUNCHER_PID | Confirmed (launcher.js createConfig, spawn of `CONFIG.binaryPath`, env line 1847). The launcher never executes the binary to read its version (reads a metadata JSON), and has no smoke run. |
| 3 | Docs give the binary path | Confirmed (the quick-start page text contains `~/.config/manicode/codebuff`). |
| 4 | CLI flags | Confirmed (cli-args.ts). Freebuff variant has no `--agent`. |
| 5 | Chat store layout | Confirmed (project-files.ts basename, ISO id with ':' as '-', config-dir.ts, chat-meta.ts schema, logger.ts). Extra: the config dir gets a `-<env>` suffix outside prod, irrelevant to users. |
| 6 | 5 s state snapshots | **Corrected.** The 5 s timer skips a tick unless `messageHistory` was replaced (step boundary), so nothing is written during one slow model call. Row meaning and source reworded. |
| 7 | Broker is a direct same-executable child, bash a grandchild | Confirmed for normal runs (terminal-command-broker.ts, entry.ts, run-terminal-command.ts) and re-confirmed in the shipped 1.0.688 binary. **Corrected** for sponsored (ads) turns: `sponsored-run.ts` passes a sandbox broker, so the shell runs under `sandbox-exec` and the broker child is absent. |
| 8 | Permanent `/bin/sh` watchdog child | Confirmed (terminal-watchdog.ts line 166, index.tsx line 457; string present in the 1.0.688 binary). |
| 9 | No sleep inhibitor | Confirmed (no caffeinate, powerSave or IOPM in cli/sdk source; 0 hits in the 1.0.688 binary; 0 `powerSaveBlocker` in Desktop `app.asar`; orchestrator `caffeinate` hit is a command-prefix parser table, not a spawn). |
| 10 | Status states, ask_user | Confirmed (use-message-queue.ts, status-indicator-state.ts). |
| 11 | Freebuff owner and live files | Confirmed (OWNER_FILE, LIVE_PREFIX). `freebuff-live-` is absent from the codebuff binary, as expected. |
| 12 | No hooks | Confirmed (`run_file_change_hooks` is a no-op in the SDK; no `fileChangeHooks` config reader outside tool definitions). |
| 13 | No OpenTelemetry | Confirmed (only bun.lock and evals/ json; 0 in the binary and in `app.asar`; the orchestrator bundle has `@opentelemetry/api` and `OTEL_` strings from the bundled Claude Agent SDK, 4 each). |
| 14 | Desktop packaging | Confirmed and narrowed. Bundle id, exe, version, unsigned notice, GitHub release redirect all re-read. The download page offers `mac-arm64` and `mac-intel`; the row said "x64" and only arm64 was inspected. Claim reworded. |
| 15 | Orchestrator command line | Confirmed (`resolveOrchestrator()` in `app.asar` lines 139540-139552; zip has `Resources/bun/bun` and `orchestrator/orchestrator.js`; `bun-baseline` variant exists in baseline installers and still matches the path substring; the app also runs `bun --version` as a probe, which the `orchestrator.js` arg requirement excludes). |
| 16 | Desktop SQLite and `turn_state` | Confirmed (DB_FILENAME, schema, `turn_state` default 'idle', `attention_reason`). |
| 17 | Desktop shell is a direct `bash -c` child, no broker | Confirmed (0 broker strings, `spawnDirectTerminalCommand`, `shell = "bash"` / `-c`). Caveats added below. |
| 18 | Not installed, nothing running | Confirmed again (`which` not found for codebuff, cb, freebuff; no `~/.config/manicode*`; no `/Applications/*uff*`; no matching process). |

Added sources: the 1.0.688 binary strings check (closes the doubt that the broker might only exist at HEAD); the Desktop embedded terminal and startup script.

Other claims in the row:

- **Process patterns and false positives. Confirmed, two limits.** Run through `matches()`: the CLI, Freebuff CLI and Desktop orchestrator (also the `bun-baseline` one) match; the npm launcher, `cb`, the broker helper, the `/bin/sh` watchdog, `bun --version`, the Electron main process, `tail ... codebuff.log` and the staged download path `.codebuff-download-temp/codebuff` do not, except that the staged copy would match on the bare name `codebuff` (the launcher does not run it, so inert). A relocated binary (FREEBUFF_CONFIG_DIR) still matches on the name. A path with spaces in argv[0] breaks all of this (README case 11).
- **`--continue` id parsing: corrected in notes.** `session_id()` returns the next argument even when it is another flag or a prompt, so `--continue --cwd X` gives `--cwd`. It maps to no chat directory, so it is harmless; the note says to accept only an ISO-timestamp-looking value.
- **Working signal `bash` on Desktop: weakened, not removed.** The orchestrator also spawns the user's interactive shell for an embedded terminal panel (`$SHELL -l`; bash variant uses `--rcfile ... -i`) and `bash -lc <script>` for a project startup script (up to 120 s). With SHELL=/bin/bash and the panel open the signal reads permanently working. The schema has no argument filter for `child_process`, so the row keeps the signal and says so in its meaning. Removing it would leave Desktop with no per-turn signal until the proposed `sqlite_row` kind exists.
- **`bash` signal on the CLI: corrected.** The row said bash is never a CLI direct child. During a sponsored turn it is one (via `sandbox-exec`, inference), so the signal also fires there, correctly.
- **`transcript_write` meaning: corrected** (see source 6). Still valid as a raise-only signal.
- **Waiting signals: unsupported beyond what the row says.** "No external signal" is a negative finding from source reading; the Desktop bundle has a command permission classifier (read-only command tables), so approval prompts probably exist there, in memory only [inferred]. The row already marks this inferred.
- **`tree_cpu` floor 3: unsupported (a guess)**, as the row says.
- **Freebuff 0.1.6 CLI binary:** not fetched; the Freebuff CLI claims rest on the shared source tree.
- **Sponsored `sandbox-exec` execs into bash:** inferred from how `sandbox-exec` works; not observed.

Remaining doubts: no live `ps` output for any surface (Bun-compiled binary argv[0] on macOS, real CPU levels); Intel Desktop build unread; whether Desktop threads show a `sandbox-exec` child at all before it execs.
