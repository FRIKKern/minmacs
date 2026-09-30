# freebuff: evidence notes (2026-09-30)

Row: `registry/agents/freebuff.json`. Validator: ok. Confidence `documented`. Freebuff is not installed here and nothing was running (`which freebuff codebuff cb` not found; no `~/.config/manicode*`; no `/Applications/*uff*`; `ps` empty), so no surface was classified live. Versions: npm `freebuff` 0.2.1 (published 2026-09-30 09:09Z; the `codebuff` row read 0.1.6), repo `CodebuffAI/freebuff` HEAD `41d91a7` (2026-09-30), Freebuff Desktop 0.0.154 (the `codebuff` row read 0.0.152).

The `codebuff` row already holds Freebuff surfaces. This row is the dedicated one and re-checked them against today's releases; it does not copy them blind.

## What I checked

- npm `freebuff` 0.2.1 tarball fetched with curl into the scratchpad and unpacked: launcher only (`index.js`, `launcher.js`, `http.js`), no binary.
- The darwin-arm64 CLI tarball from the launcher's download URL (codebuff.com redirect to a GitHub release asset), sha256 equal to `binaryChecksums`. Extracted, `strings` read, and run for `--version` and `--help` only, with `HOME` and `FREEBUFF_CONFIG_DIR` pointed at scratch dirs (it wrote only `settings.json` there). No session started.
- Shallow clone of `CodebuffAI/freebuff` at `41d91a7`: `cli/src` (cli-args, project-files, config-dir, chat-meta, logger, terminal-watchdog, terminal-command-broker, freebuff-instance-owner, freebuff-session-relaunch), `sdk/src/run.ts`, `cli/release-core/launcher.js`. Not built, not run.
- Freebuff Desktop 0.0.154 mac-arm64 zip from the public GitHub release, downloaded to the scratchpad; only `Info.plist`, `app.asar` and `Resources/orchestrator/` extracted. Read with `plistlib`, `strings -a`, `grep`, `sed`. From the SQLite schema I read table and column names only. Nothing installed, mounted or run.
- freebuff.com home and `/desktop` pages, the repo README, a web search of freebuff.com and codebuff.com docs for hooks and telemetry.
- The row's surfaces run through the probe's own `matches()`, `session_id()` and `classify()` with synthetic argv lists (results below).

## Answers per field

| Field | Answer |
|---|---|
| Surfaces | CLI (TUI); Desktop (Electron, macOS arm64 and x64, Windows, Linux); Web, Cloud, Chat (hosted, no local process). Five products per the README |
| CLI process | Bun-compiled Mach-O `~/.config/manicode/freebuff`, argv[0] is that full path. The `freebuff` on PATH is a Node launcher and stays alive as the parent |
| Bundle id | Desktop `com.freebuff.desktop`, executable `Contents/MacOS/Freebuff`. CLI has none |
| Desktop process to match | `Freebuff.app/Contents/Resources/bun/bun` with argv `.../orchestrator/orchestrator.js`, no other args. One per app, all threads of all open projects |
| Process to session | CLI: only `--continue <id>`; otherwise cwd basename plus newest chat mtime, a guess. Desktop: no per-thread argv |
| Store, CLI | `~/.config/manicode/projects/<cwd basename>/chats/<ISO time, ':' as '-'>/chat-messages.json` (JSON array), `run-state.json`, `chat-meta.json`, `log.jsonl`. Not promised by the vendor, `documented: false`. `FREEBUFF_CONFIG_DIR` (absolute path) moves the base |
| Store, Desktop | SQLite `<project root>/.freebuff/desktop-v2.db` per project |
| Turn in progress, CLI | Direct child `freebuff --terminal-command-broker` (shell tool calls only); chat files rewritten about every 5 s at step boundaries |
| Turn in progress, Desktop | `threads.turn_state = 'running'` with a fresh `turn_alive_at` (30 s heartbeat); fallback direct `bash` child (weak) |
| Waiting on the human | Nothing external in the CLI. Desktop: `attention_reason` (`failed`, `stopped`, `merge-conflict`, `auto-stopped`) is not a prompt; questions and sudo elevation requests are in memory only |
| Hooks | None for users. Desktop uses Claude Code hooks internally for its Claude threads |
| OpenTelemetry | No. PostHog for analytics; the Desktop bundle carries OTel names only via the Claude Agent SDK |

Probe check on synthetic argv (score per surface, freebuff row): CLI 27; CLI with `--continue <ISO id>` 27 and returns the id; `login`, `--version`, the broker helper, the npm launcher (`node .../freebuff/index.js`, `node .../bin/freebuff`), the `/bin/sh` watchdog, `bun --version`, the Electron main and its Helper all 0; Desktop orchestrator 43 (was 42 before the verification pass added a second `args_contain` entry; `codebuff.json` scores 42), also with `bun-baseline`. A CLI with a broker child classifies working; with only the `sh` watchdog it classifies idle.

## Contradicts common belief or the generic rules

1. **Freebuff is not a Codebuff mode of the same binary name.** It is its own npm package, binary (`~/.config/manicode/freebuff`) and, since the repo rename, the primary product; the public repo `github.com/CodebuffAI/codebuff` now redirects to `CodebuffAI/freebuff`, while the npm package `freebuff` points at a private repo.
2. **The npm command is not the process.** `freebuff` on PATH is `node index.js`; matching the launcher would find the wrong process, and the launcher's package path contains `freebuff` too.
3. **README section 4's rule "ignore a child with the same executable as its parent" is backwards here.** The CLI's tool signal is exactly a same-executable direct child (`--terminal-command-broker`); a shell child is not there (it is a grandchild). The generic `tool_children` rule is also wrong: a permanent `/bin/sh` watchdog child would make every idle CLI look busy.
4. **No sleep inhibitor anywhere.** No `caffeinate`, no IOKit assertion, no `powerSaveBlocker` in CLI, SDK, Desktop main or orchestrator. The only `caffeinate` string in the CLI binary and in `orchestrator.js` is a flag table in the shell-command parser.
5. **The CLI store is keyed by folder name, not path**, and the chat id (a timestamp) never appears in argv. Two projects both called `app` share a folder. Codebuff and Freebuff CLIs share the store, so a chat file cannot say which one wrote it.
6. **Desktop has an exact turn state, not a guessed one.** `turn_state` plus `turn_alive_at` (new since the earlier read: a 30 s heartbeat, refreshed only for live turns, and a crashed `running` is reset to `idle` at boot) is better than any process signal. The schema has no signal kind that can read it.
7. **Desktop is a host in disguise.** One orchestrator, many threads, and claude and codex children with the marker `FREEBUFF_ORCHESTRATOR_PID` in their environment only. They match the `claude-code` and `codex` rows and must be dropped by ancestry.
8. **Desktop Claude threads never wait for approval.** They run with `permissionMode: bypassPermissions` behind an elevation guard hook, so "waiting for permission" does not exist there; questions and sudo elevation live in memory.
9. **Two rows now claim the same processes.** `codebuff.json` lists the Freebuff CLI and Desktop surfaces with identical patterns, so `probe` gives a tie and keeps the row sorted first (`codebuff`). I did not edit `codebuff.json` (out of scope). The verification pass fixed the Desktop tie inside this row (43 against 42); the CLI tie (27 against 27) cannot be broken from this row, so remove the Freebuff surfaces from `codebuff.json`.

## Could not determine

- Real `ps` output for any surface: whether Bun leaves argv[0] as the full path on macOS for this compiled binary (the launcher spawns it with that path, so it should).
- CPU when idle and when busy, so the `tree_cpu` floor of 3 is a guess. The TUI polls for ads and admission and may never be at 0.
- Whether a pending Desktop question or elevation is exposed anywhere outside the orchestrator process. Its local HTTP server is authenticated with a one-time secret sent on stdin, so I treated it as unreadable from outside.
- The Electron `userData` and logs paths on macOS (`~/Library/Application Support/Freebuff`, `~/Library/Logs/Freebuff/orchestrator-stderr.log`) are inferred from `app.getPath('userData'|'logs')` in the asar and the product name; not observed.
- That `lsof -p <orchestrator pid>` lists each open project's `desktop-v2.db`: inferred from how SQLite works, not observed.
- Desktop on Intel (read arm64 only; the download page lists an x64 dmg and zip with the same layout expected).
- Whether a sponsored (ads) CLI run leaves `bash` as a direct child (inferred from sandbox-exec exec semantics).
- The Windows and Linux launchers were not read; the row is macOS only.

## Grok Bot (asked for in the request, not part of this row)

Grok Bot is a different product: xAI/SpaceXAI's "always-on agents" that run on their own cloud computer, announced 2026-08-11, delivered as a desktop and iOS app (the announcement links a Linux build hosted under `api2.cursor.sh`) and sold through SuperGrok and Cursor plans (https://x.ai/news/introducing-grok-bot, https://x.ai/bot). Freebuff only relates to it in that Freebuff's model catalogue lists `x-ai/grok-*` models and the freebuff.com chat page uses the Grok favicon as a competitor. It needs its own row (`grok-bot`), separate from `grok-build`; I did not research its local surfaces or write it, since this task names two files only.

## Verification

Adversarial pass, 2026-09-30, by a second agent that did not write the row. Method: `tools/validate_row.py` (ok before and after); fresh `npm pack freebuff@0.2.1` (tarball unpacked, not installed); fresh shallow clone of `CodebuffAI/freebuff` (HEAD had moved to bc54be8, 2026-09-30T16:02Z; `git diff 41d91a7 HEAD` on every CLI file cited below is empty); the darwin-arm64 CLI tarball and Freebuff Desktop 0.0.154 mac-arm64 zip re-downloaded; `strings`, `grep`, `sed`, `plistlib`, `unzip -l`; the binary run for `--version` and `--help` only, with HOME and FREEBUFF_CONFIG_DIR in scratch dirs; `freebuff.com`, `/desktop` and `codebuff.com/docs` fetched; synthetic argv run through the probe's `matches()` and `session_id()`. Nothing installed, nothing started, no session store read. Confidence stays `documented`: the harness is not installed here.

### Claims

| # | Claim | Result |
|---|---|---|
| 1 | npm `freebuff` 0.2.1, bin `index.js`, launcher-only package, modified 2026-09-30T09:09:30Z | confirmed (`npm view`; tarball holds README.md, http.js, index.js, launcher.js, package.json; `cli/release-core/launcher.js` in the repo is byte-identical to the packaged launcher) |
| 2 | Launcher spawns `~/.config/manicode/freebuff` with argv[0] = that path and the user's args; sets `CODEBUFF_LAUNCHER_PID` | confirmed (launcher.js lines 357-367, 1836-1848). The config-dir override is a test-only product option, not an env var, so the path is stable. Same path for darwin-x64 and its baseline build |
| 3 | Download redirect chain, GitHub asset, sha256 equals `binaryChecksums`, Mach-O arm64 | confirmed (301, 302, 302, 200, 33862900 bytes; sha256 b3a81a39...ea14 equals package.json; `file` says Mach-O 64-bit executable arm64) |
| 4 | Binary flags and `login` only | confirmed (`--version` 0.2.1; `--help` lists `-v`, `--continue [conversation-id]`, `--cwd`, `--trust-agents`, `-h`, command choice `login`; cli-args.ts lines 53-71 for the Freebuff branch) |
| 5 | `--continue` optional id, no other session flag | confirmed. Caveat added to notes: a bare `--continue` followed by a flag makes `session_id()` return that flag |
| 6 | Chat store layout under `projects/<basename>/chats/<ISO with : as ->/`, four files, `FREEBUFF_CONFIG_DIR` absolute override | confirmed (project-files.ts 38-61, 106; chat-meta.ts; run-state-storage.ts saveChatState writes run-state.json, chat-messages.json, then chat-meta.json; logger.ts `log.jsonl`; config-dir.ts). `chat-messages.json` appears twice in the binary. Still no vendor doc: `documented=false` is right |
| 7 | 5 s snapshot, skipped unless message history replaced | confirmed (run.ts 328, 962-985; the code comment says the same) |
| 8 | Shell tool calls go through a detached self-exec broker as a direct child | confirmed (terminal-command-broker.ts 18, 345-351, 395; entry.ts dispatches; flag and `freebuff-terminal-command-broker-` in the binary). The broker's own child is `detached: false`, so the shell is a grandchild of the CLI |
| 9 | Permanent detached `/bin/sh` terminal-reset-watchdog child, skipped with `CODEBUFF_NO_TERMINAL_WATCHDOG` | confirmed, with one addition: it is also skipped when stdout is not a TTY (line 524), which never applies to the interactive TUI |
| 10 | No sleep inhibitor in CLI, SDK or Desktop | confirmed (no `caffeinate`, `powerSaveBlocker`, `IOPM` in cli/src, sdk/src, freebuff, packages; binary has 0 for `powerSave` and `IOPMAssertion`; the single `caffeinate` in the binary is the parser table `caffeinate:["-t","-w"]`) |
| 11 | Desktop 0.0.154 facts: bundle id, executable `Freebuff`, min macOS 11.0, unsigned, bundled bun, arm64 and x64 | confirmed (Info.plist read with plistlib; `unzip -l` shows `Resources/bun/bun` 62246912 bytes and `Resources/orchestrator/orchestrator.js`; /desktop lists macOS Apple Silicon and Intel and says the builds are not code-signed; 0.0.154 is still the latest). x64 zip not opened |
| 12 | Orchestrator started as bundled bun with one argument, absolute `orchestrator.js` | confirmed (app.asar `resolveOrchestrator`, `spawn(bun, args, {cwd, env, stdio: pipe x3})`) |
| 13 | A `bun-baseline` variant is matched by the path prefix | confirmed and sharpened: the baseline is `Resources/bun/bun-baseline` (a sibling file inside `bun/`), which contains the substring `/Resources/bun/bun`. It is not in the arm64 zip (only `bun/bun`); it is chosen when the standard runtime fails to start |
| 14 | Desktop SQLite at `<project>/.freebuff/desktop-v2.db`; `turn_state`, `turn_alive_at`, 30 s heartbeat, crashed running rewritten to idle | confirmed (orchestrator.js lines 180241, 180272, 180566, 201514, 203754-203781, 180320; raw-file line numbers, not `strings` numbers) |
| 15 | `attention_reason` is raised only for `failed`, `merge-conflict`, `auto-stopped` | **corrected**: also `stopped` (line 196844, paused queue stopped by the user). The four values are `failed`, `stopped`, `merge-conflict`, `auto-stopped`. Row and this file fixed. The conclusion (none of them is a question or approval) stands |
| 16 | Questions and elevations are in-memory maps; Claude threads use `bypassPermissions` plus an elevation hook | confirmed (lines 194012-194013; 176300-176335; `claude-elevation-hook.js` is 4133 bytes) |
| 17 | Desktop shell calls run `bash -c` directly (no broker); terminal panel runs `$SHELL -l`; startup script `bash -lc` up to 120 s | confirmed (`terminal-command-broker` count 0 in orchestrator.js; spawnDirectTerminalCommand 130442, shell `bash` args `-c` 130517-130519, used unless a broker is passed at 130534; `[env.SHELL \|\| "/bin/sh", "-l"]` at 210429; `Bun.spawn([bash, "-lc", script])` 198184; `STARTUP_SCRIPT_TIMEOUT_MS = 120000`) |
| 18 | Children carry `FREEBUFF_ORCHESTRATOR_PID` in the environment only | confirmed (orchestrator.js 174310; app.asar comment block) |
| 19 | No user hooks, `run_file_change_hooks` is a no-op | confirmed (repo grep finds only React hooks and unrelated docs; `hooks.json` count 0 in the binary; the codebuff.com/docs sidebar has no hooks page; /desktop has none) |
| 20 | No OpenTelemetry, PostHog for analytics | confirmed (repo grep hits only bun.lock and evals; binary 0 for `opentelemetry`, `OTEL_EXPORTER`, `otlp`; `NEXT_PUBLIC_POSTHOG_API_KEY` present) |
| 21 | Instance-owner and live files in `~/.config/manicode` | confirmed (freebuff-instance-owner.ts, freebuff-session-relaunch.ts; both names in the binary) |
| 22 | Product family of five, repo redirect, private npm repository URL, text ads | confirmed (README; freebuff.com home; `curl -I` gives 301 from CodebuffAI/codebuff to CodebuffAI/freebuff; `npm view freebuff repository.url` prints freebuff-private) |
| 23 | Not installed here, nothing running | confirmed again at verification time (`which` all three not found, no `~/.config/manicode*`, no `/Applications/*uff*`, `ps` empty) |
| 24 | Sponsored (ads) CLI run has no broker child and leaves `bash` as a direct child | unsupported beyond inference, left marked `[inferred]`. Source shows the sponsored broker spawns `/usr/bin/sandbox-exec ... <request.executable>` directly, so no `freebuff` broker child appears; that the executable is a `bash -c` command is inferred from the Desktop code path, not observed |
| 25 | Desktop `tree_cpu` floor 3 | unsupported, an unmeasured guess, already labelled so |

### Process patterns, false-positive check

Run through the probe's own `matches()` with synthetic argv. CLI binary 27; with `--continue <id>` 27 and returns the id. Zero for: `freebuff login`, the `--terminal-command-broker` helper, `node .../freebuff/index.js`, `node .../bin/freebuff`, the `/bin/sh` watchdog, `vim ~/.config/manicode/freebuff`, the Electron main `Freebuff`, `Freebuff Helper`, and `bun --version` from the app. Desktop orchestrator 43 for both `bun/bun` and `bun/bun-baseline`, also under `~/Applications`; a relative `orchestrator.js` no longer matches (real argv is always absolute). Residual risks, all stated in the row: the CLI matches by name too, so any program named `freebuff` outside that directory is a false positive (none known); `exclude_args` is exact-match on any word, so a directory named `login` passed to `--cwd` hides a session; the case-sensitive name compare is what keeps `Freebuff` (Electron) out.

### Repairs made

1. `attention_reason` values: `stopped` added (row `waiting_signals`, source claim, this file).
2. Desktop surface: second `args_contain` entry `/Contents/Resources/orchestrator/orchestrator.js`, so the probe scores it 43 against `codebuff.json`'s identical surface at 42 and reports Freebuff Desktop as Freebuff. The CLI tie (27 against 27) cannot be broken from this row and is documented in `notes`.
3. `notes`: tie text rewritten to say exactly what holds now, the bare `--continue` limitation added, the HEAD move recorded. Confidence left at `documented`.

### Grok Bot section above

Checked against https://x.ai/news/introducing-grok-bot: dated Aug 11, 2026; always-on agents with their own cloud computer; SuperGrok, SuperGrok Plus, SuperGrok Heavy, Cursor Pro, Pro+, Ultra and Cursor Teams plans; desktop and iOS; Linux download at `api2.cursor.sh`; the page is branded SpaceXAI. Confirmed. `https://x.ai/bot` answered `curl -I` with 403 (bot protection), so it is unverified; the claims stand on the news page alone. The Freebuff side is confirmed too: `common/src/constants/freebuff-models.ts` defines `x-ai/grok-4.7`, `4.6`, `4.5`, `4.20`, and the freebuff.com Chat section lists Grok among "paid tools" it replaces (favicon `x.ai`). Grok Bot has no bearing on this row; its own row is `registry/agents/grok-bot.json`.
