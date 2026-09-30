# Autohand Code (autohandai/code-cli), research notes

Date 2026-09-30. Confidence `documented`. Autohand is not installed on this Mac, so nothing was seen running. Sources: the public repo autohandai/code-cli at main a248656 (2026-09-29, shallow clone, read only, never built or run), tag v0.9.8 spot-checked through `gh api`, npm metadata, the GitHub release assets, https://docs.autohand.ai/working-with-autohand-code/cli. Nothing was installed, started or messaged.

## What I checked

- Local: `which ah autohand agent` (none), `ls ~/.autohand` (absent), `ls /Applications | grep -i autohand` (nothing), `ls ~/.local/bin` (no `agent`, no `ah`). No store, so no record key names were printed from a real file. Key names in the row come from source types.
- Package: `npm view autohand-cli` says latest 0.9.8 (2026-09-22 release, npm modified 2026-09-23), alpha 0.9.9-alpha.ae34d3f, bins `ah`, `agent`, `autohand`, `autohand-code`, node >=22.
- Install channels (three): npm (node runs `dist/index.js`), `install.sh` / Windows script (Bun-compiled Mach-O `autohand` plus `ahtraces` in `~/.local/bin`, symlinks `autohand-code`, `agent`, `ah`), Homebrew tap `autohandai/code`, formula `autohand-code`. Release v0.9.8 assets include `autohand-macos-arm64` (85 MB), its `.tar.gz`, `ahtraces-macos-arm64`.
- Surfaces: terminal CLI (TUI, `-p` one-shot, pipe mode), `--mode rpc` and `--acp` (Zed, JetBrains, JetBrains Air; VS Code extension `AutohandAI.vscode-autohand` "powered by Autohand CLI"), `--mode teammate` child processes, cloud (Autohand Code Web transfer, iOS app via `/go`). No desktop app with its own bundle id was found. Identifiers that exist: `ai.autohand.computer-use` (the `Autohand Computer Use.app` helper, not a session), Chrome native host `ai.autohand.rpc`.
- Process to session: argv never carries a session id for a plain launch (`autohand resume <ref>` is positional, `--fork <ref>` takes a reference). The map is `~/.autohand/active-agents/<sessionId>.json`, whose `pid` is the CLI's own pid (source: `ActiveAgentRegistry.ts`).
- Session store: `~/.autohand/sessions/<uuid>-<ms>/conversation.jsonl` (one message per line, appended per committed message), `metadata.json`, `state.json`, root `index.json`. Only the directory is promised in the README, so `documented: false`. `AUTOHAND_HOME` moves everything.
- Turn in progress, most precise first: heartbeat `status == "working"` (true from the start of an instruction to its end), refined by `activity.phase`. Then a direct `/bin/sh -c` child (run_command spawns with `shell: true`), then a fresh `conversation.jsonl` write (raise only), then CPU.
- Waiting on the human: heartbeat `activity.phase == "waiting_input"` (permission prompt or `ask_followup_question`), hooks `permission-request` and `notification` (reason `confirmation`, `question`, `task_complete`), and the terminal title marker `◐`.
- Hooks: 45+ events, configured in `~/.autohand/config.json` (or toml/yaml), `<project>/.autohand/config.json`, `<project>/.autohand/settings.local.json`, or `--config`. Command hooks get JSON on stdin and `HOOK_*` env vars. Project hooks need workspace trust. `--bare` skips them.
- OpenTelemetry: none. Its own telemetry is off by default; automatic error reports and a version ping are on by default (`AUTOHAND_SKIP_PING=1`, `autoReport.enabled=false`).
- Sleep inhibitor: no assertion, no per-turn `caffeinate`. One `caffeinate -dims -w <pid>` child exists after `/go` pairing.
- Ran `tools/validate_row.py registry/agents/autohand.json` (ok) and `matches()` from `tools/agents_probe.py` on synthetic argv lists (no process started):

| argv | result |
|---|---|
| `Autohand Code` (retitled, with or without empty trailing args) | tui |
| `node /opt/homebrew/bin/autohand`, `node ~/.nvm/.../bin/autohand --acp`, `node .../bin/autohand-code -p "fix it"` | tui (node surface) |
| `autohand`, `autohand resume --last`, `autohand -p hi -y`, `ah`, `autohand-code`, `/opt/homebrew/bin/autohand`, `~/.local/bin/autohand --acp` | tui |
| `autohand --version`, `autohand upgrade`, `autohand agents --once`, `autohand traces status`, `node .../bin/autohand login`, `node .../bin/autohand --version` | none |
| bare `agent`, `~/.local/bin/agent`, `ahtraces status`, `~/.local/bin/ahtraces`, Cursor's `node .../cursor-agent/versions/.../index.js`, `Autohand Computer Use` | none |
| `node .../bin/ah` | none (by design, see below) |
| `~/.grok/bin/agent`, `grok` | grok-build, not autohand |

## Contradicts common belief

- The hint says three bins. There are four: `autohand-code` too. The real default is not npm: the documented quick install is a Bun-compiled binary from `install.sh`, and the npm package is a fallback.
- `agent` does not just "collide with Cursor". Autohand's installers (`install.sh`, the Windows script, the Homebrew formula's `post_install`) walk every writable directory on PATH and `rm -f` then relink any existing `agent` to Autohand, with no prompt. The README says so ("if another tool's agent command stops working after installing Autohand, this is why"). The code comment names Grok as a competitor. So on a Mac with Autohand installed, the `agent` a user types can be Autohand while Cursor's CLI and Grok Build's `~/.grok/bin/agent` are the other claimants. Bare `agent` in argv[0] cannot be attributed by command line, so the row does not match it (same rule as `grok-build`).
- There is no sleep assertion and no per-turn `caffeinate`, unlike Claude Code, Codex and Grok Build. A `caffeinate -dims -w <pid>` child does exist, but only after the iOS pairing (`/go`, `keepAwakeByDefault: true`), and it lives for the whole pairing. Counting it would read a paired idle session as working forever.
- `status: "working"` is not "busy on its own": it stays `working` while a permission prompt or a question is open. Only `activity.phase` (`waiting_input`) and the terminal title (`◐`) separate the two. Same trap as `grok-build` and `hermes` in README section 3, case 4.
- The tool shell is `/bin/sh -c`, whatever the user's login shell is (the source comment says "the user's shell", Node's `shell: true` uses `/bin/sh`). It is a direct child, so the probe's `tool_children` works, but macOS `sh` may exec a lone simple command in place (README case 9). Hook commands are also `shell: true` children, so configured hooks add short-lived shell children.
- The process retitles itself: line 2 of `src/index.ts` is `process.title = 'Autohand Code'`. With a space. If it behaves like the `kimi` and `openclaw` rows, `ps` then shows only that title and the flags (`--acp`, `-p`, `--mode rpc`, `--mode teammate`) are gone. The probe's `ps` space-split fallback would see `Autohand` and `Code` as two words; the real KERN_PROCARGS2 argv is fine.
- Node's `process.argv[1]` for an npm install is the bin symlink (`.../bin/autohand`), not `autohand-cli/dist/index.js`, so a path match on the package folder never fires. The node surface matches `/bin/autohand`.
- Docs disagree with themselves: docs.autohand.ai says Node 18 or newer, `package.json` says `>=22`; the README says Bun >=1.0 to build; `docs/rpc-protocol.md` shows `args: ['--rpc']` for the VS Code client but the CLI defines only `--mode rpc` (and `--acp`). The repo's `package.json` says 0.8.2 while npm says 0.9.8; versions are stamped by CI, so do not read the source version as the shipped one.
- The repo docs (`docs/telemetry.md`, `docs/traces.md`) list 19 harnesses that the `ahtraces` companion reads. Autohand is a reader of other agents' stores as well as an agent; `ahtraces` (a separate sidecar binary, stays idle until consent) is not a session and the row does not match it.

## Could not determine

- Everything about real behaviour: no live process, so no CPU numbers (floor 3% is a guess), no write gaps in `conversation.jsonl`, no proof that the heartbeat flips to `working` and `waiting_input` on a real turn, no check that the file mode and location are as the source says.
- Whether `process.title` retitles the compiled Bun binary on macOS. If it does not, argv[0] is the name typed (`autohand`, `ah`, `autohand-code`) and the third surface applies; if it does, the first one does. Both are listed. I did not run any Node or Bun process to test it, to stay within read-only commands, and rely on the `kimi` row's observation for libuv.
- Whether libuv truncates the title on a short `node <path>` launch (title is cut to the original argv span). Unlikely in practice, not checked.
- Whether an `--ephemeral` run or `-p` one-shot still writes a heartbeat file. The heartbeat starts from the lifecycle runner and needs `getSession()`; ephemeral sessions have an in-memory session, so it probably does, unverified. The answer-only RPC profile constructs no agent, so it does not.
- How long the pre-retitle window lasts (ESM imports evaluate before line 2). Inferred to be sub-second to a couple of seconds.
- Whether the VS Code extension bundles its own CLI (the vsix was not fetched) and whether Zed or JetBrains launch `autohand` by absolute path (the ACP guide says they should).
- Whether `ahtraces` or the Computer Use helper appear as long-lived children of a session. The installers start `ahtraces` detached; not observed.
- The `squad` and `queue` subcommands (`autohand squad`, `autohand queue`): purpose read only from the command list, so they are not in `exclude_args`.
- Whether the probe should grow a JSON-field signal. The best Autohand signal (`status`, `activity.phase`) needs one. The row records it as the first `transcript_write` entry with a long meaning, as `cline` and `fx` do, and states the probe cannot fire it.

## Privacy note

`active-agents/*.json` carries `activity.instruction` and `activity.command` (prompt and command text, truncated to 200 characters). A reader must take only `pid`, `sessionId`, `status`, `activity.phase`, `updatedAt`. Session stores were never opened (none exist here).

## Verification

Date 2026-09-30, independent refutation pass. `tools/validate_row.py registry/agents/autohand.json` printed `ok` before and after the repairs. Re-checked against a fresh shallow clone of autohandai/code-cli (main a248656, `git ls-remote` shows tag v0.9.8 at 55f07f8), `npm view`, `gh release view -R autohandai/code-cli v0.9.8`, and fetched pages (docs.autohand.ai CLI overview, autohand.ai/cli, the VS Code Marketplace listing). Nothing was installed, run or started. Confidence stays `documented` (the harness is not installed here; retitle behaviour, heartbeat behaviour and CPU are unobserved).

Confirmed
- npm: latest 0.9.8, alpha 0.9.9-alpha.ae34d3f, modified 2026-09-23; bins ah, agent, autohand, autohand-code; node >=22; ink 7.1.1, node-pty 1.1.0, @agentclientprotocol/sdk 1.3.0.
- `src/index.ts` line 1 is the shebang, line 2 is `process.title = 'Autohand Code';`.
- Release v0.9.8 assets: autohand-macos-arm64 (85341760 bytes), its tar.gz, ahtraces-macos-arm64, install.sh.
- Heartbeat constants: 5_000 ms interval, 15_000 ms stale; stale means pid dead (EPERM counts as alive) or updatedAt older than 15 s; files at `<AUTOHAND_HOME>/active-agents/<sessionId>[.<instanceId>].json`, directory 0700, file 0600, atomic write; removed on stop.
- `derivePhase()`: idle when no turn, waiting_input when awaiting input, then running_command, editing, thinking. `beginAwaitingInput()` wraps `confirmDangerousAction` and the followup question path and sets the terminal title to waiting.
- Terminal title: OSC 0, markers spinner, ◐, ✓, ✗, format `<marker> <name> · Autohand` or `<marker> Autohand Code`; not written without a TTY or with --json, --acp, --mode rpc/acp, --answer-only, --setup-only.
- Sessions: `conversation.jsonl` via `fs.appendFile`, `metadata.json`, index.json; session id `<uuid>-<Date.now()>`; SessionMetadata and SessionMessage key names match; `--ephemeral` option text says no session files; README says only `~/.autohand/sessions/`.
- run_command goes through `spawn(cmd, [], {shell: true})` in src/actions/command.ts via actionExecutor.ts; hook commands use `shell: true, detached` (src/core/HookManager.ts line 992). Not observed running.
- Caffeinate: only in src/mobile/KeepAwakeController.ts (`/usr/bin/caffeinate -dims -w <pid>`), enabled through the /go mobile relay; no other caffeinate, pmset, IOPM or powerSaveBlocker in src.
- Installers: install.sh installs autohand and ahtraces, symlinks autohand-code, agent, ah, and reclaims `agent` on PATH; the Homebrew formula generator does the same in `post_install`; README lines 54-60 say so. docs.autohand.ai lists curl, `brew tap autohandai/code && brew install autohand-code`, npm, PowerShell.
- Subcommands in `exclude_args` all exist in src/index.ts: login, logout, config, mcp, completion, update, upgrade, sessions, init, import, traces, computer (src/computer/cliCommand.ts), agents, experiments, auto-research. `squad` and `queue` also exist and are correctly left out; `resume` is registered separately and left out.
- ACP: docs/guides/ACP.md `command: /absolute/path/to/autohand`, `args: --acp`. Teammate children: `spawn(process.execPath, [process.argv[1], '--mode', 'teammate', '--team', ...])` in src/core/teams/TeammateProcess.ts.
- No OpenTelemetry: the grep over src, docs, package.json, config.example.json, schema, scripts, README printed nothing. Telemetry is opt-in (docs/telemetry.md); version ping stops with AUTOHAND_SKIP_PING=1; automatic error reports on unless `autoReport.enabled` is false.
- `ai.autohand.computer-use` and `ai.autohand.rpc` identifiers exist in source.
- Not installed here: `which ah autohand agent` printed not found for all three, `ls ~/.autohand` printed No such file or directory, `ps` shows no autohand process.
- Process names do not collide with any other registry row (checked every row's names, args_contain and path_contains against these names); grok-bot matches only `/Grok Bot.app/...` paths. Bare `agent`, `ahtraces` and `Autohand Computer Use` do not match.

Corrected
- Hook event list: the row listed 46 events; `type HookEvent` in src/types.ts has 59. The 13 `autoresearch:*` events (init, start, before, run, log, decision, after, rescore, replay, prune, pause, complete, error) were added. The earlier "45+" in this file is superseded by 59.
- Working signal: the row said to read `status == "working"`. Source shows `status` is a cached value: the 5 s timer calls `update()` with no argument, which re-sends the last status, and only `emitStatus()` supplies a new one (no call after `isInstructionActive` is cleared in InstructionRunner.ts or SimpleChatHandler.ts). `activity.phase` is rebuilt from live `isInstructionActive` on every write. The signal now says to read `activity.phase != idle` and treat status as secondary. This is a source reading; runtime not observed.
- Heartbeat `mode`: the type lists interactive, command, rpc, acp, teammate, but `resolveActiveAgentMode()` returns only interactive, command or rpc. Row text corrected.
- VS Code extension: the row said the bundled CLI question was undetermined. The Marketplace README says release VSIX builds bundle the CLI for macOS arm64 and x64 (fallback to PATH), so the IDE child may run from the extension folder. Install count is 210 at version 0.1.5 (the row said 192). Row label and source updated. Whether that bundled binary's argv[0] matches a tui surface is still unknown.
- Source kinds: the npm command entry was labelled official-docs and is now local-observation; the install-layout entry is now source-code.

Unsupported (kept, marked inferred or unobserved in the row)
- That libuv retitling on macOS applies to Autohand under Node: inferred from the kimi row's local check with node 22; not run here. Whether the Bun-compiled binary retitles at all is unknown, which is why surface 3 matches the typed name.
- That the pre-title window (ESM imports before line 2) is sub-second: guess.
- That `/bin/sh -c` is a direct child of the CLI in a real turn, and that macOS sh does not exec in place: source only.
- That the heartbeat file flips to working and waiting_input in a real turn, and the 5 s lag: source only.
- The 30 s transcript window and the 3% CPU floor: guesses, no measurement.
- The `notification` hook still runs while the terminal is focused: focus gate not traced.
- Whether an `--ephemeral` run or an `-p` one-shot writes a heartbeat: not traced.

Residual matching risks (documented in notes, not fixable with the current schema)
- Node surface `args_contain: "/bin/autohand"` is a substring: `node /Users/me/bin/autohand/server.js` matched in the synthetic run. Real npm launches use `.../bin/autohand`, so it is kept.
- `exclude_args` is an exact match on any argument: `autohand -p update` and `node .../bin/autohand -p init` are vetoed although they are real sessions (README section 3 case 16).
- The retitled `Autohand Code` process also covers `--version`, `upgrade`, `agents --once`, teammate children and `--mode rpc` helpers, so short-lived ones can show as brief idle sessions (README section 3 cases 13 and 15).
