# Orca: evidence notes (2026-09-30)

Row: `registry/agents/orca.json`. Validator: ok. Confidence is `documented`: Orca is not installed here (`ls /Applications | grep -i orca`, `ls ~/Library/Application Support | grep -i '^orca'`, `which orca`, `ps`, `mdfind` for `com.stablyai.orca`, `ls -d ~/.orca`: all empty). `tools/agents_probe.py --row registry/agents/orca.json` finds 0 sessions, as expected. Nothing was installed, run or messaged.

## Shape

```
Orca (main, Electron)   /Applications/Orca.app/Contents/MacOS/Orca        bundle com.stablyai.orca
 |- Orca Helper (Renderer | GPU | ...)   under Contents/Frameworks, --type=...   different name, no match
 |- /usr/bin/caffeinate -i -s            DIRECT child, only while Keep computer awake = Agent and a pane is working
 |- Orca .../daemon-entry.js --socket .. terminal daemon, same exe as node, detached, owns every PTY
 |    '- -zsh -l                         login shell per terminal (permanent)
 |         '- claude | codex | grok | ... the agent, typed into the shell (matches its own row)
 |- Orca -e <script>                     provider supervisor (structured chat), parent of claude / codex app-server
 |- Orca .../plugin-host ...             plugin hosts (ELECTRON_RUN_AS_NODE)
 '- ssh ...                              one per SSH target (agents there are off this Mac)

shell:   orca (bash shim) -> exec Orca .../app.asar.unpacked/out/cli/index.js <args>     client, not a session
headless: orca serve      -> Orca --serve [--serve-json ...]                             same tree, no window
```

Orca is a host. It has no model loop. "Working" means a hosted agent is working.

## What I checked

- Repo: the hint URL `github.com/orca-agents/orca` is a 404. The project is `github.com/stablyai/orca` (found by search). Shallow clone at `d74388f8` (2026-09-30, package.json 1.4.214); GitHub API latest release is v1.4.217 (2026-09-29, `Orca-1.4.217-arm64-mac.zip`).
- Docs: `onorca.dev/docs/{model/agents-sessions, settings, telemetry, remote-servers, ways-to-run, agents/hooks-memory, agents/session-history, agents/supported, agents/native-chat, cli/reference}` (the MDX sources sit in `docs/site/content/docs`), plus `docs/reference/{agent-status-store,orcad-operations}.md`.
- Source, read in full or at the relevant function: `config/electron-builder.config.cjs`, `Casks/orca.rb`, `resources/darwin/bin/orca`, `src/cli/runtime/{launch,metadata}.ts`, `src/main/daemon/{daemon-launched-child-spawn,daemon-launch-paths}.ts`, `src/main/daemon/pty-subprocess/shell-launch-plan.ts`, `src/main/codex/codex-app-server-posix-supervisor.ts`, `src/main/agent-awake-service.ts`, `agent-awake-status-lease.ts`, `macos-system-sleep-assertion.ts`, `src/shared/{computer-awake-mode,default-global-settings,agent-status-types,agent-status-osc,agent-title-status}.ts`, `src/main/agent-hooks/{managed-agent-hook-registry,installer-utils}.ts`, `src/main/agent-hooks/server/{server-runtime-env,server-constants,server-persistence,server-types}.ts`, `src/main/claude/{claude-managed-hook-events,hook-settings,hook-script}.ts`, `src/main/grok/{grok-hook-config,hook-service}.ts`, `src/shared/agent-hook-listener/{listener-event,endpoint-publication}.ts` and `providers/claude-events.ts`, `src/main/observability/*`.
- Probe check: ran the row's `matches()` over synthetic command lines. Main app matches as `gui`; the daemon matches as `daemon` (score 31 over 30); `--serve` matches `daemon` over `gui`; a renderer helper, the `orca` CLI script at its /Applications path, a supervisor (`-e`), `caffeinate` and a bare `/usr/bin/orca` do not match.
- Telemetry: `grep -rniI otlp src docs config` matches only a test; `package.json` has `posthog-node` and no OpenTelemetry package; `grep -rn 'CLAUDE_CODE_ENABLE_TELEMETRY\|OTEL_' src resources config` is empty.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Executable | `/Applications/Orca.app/Contents/MacOS/Orca`. The same binary is the daemon, CLI runtime, supervisor and plugin hosts (ELECTRON_RUN_AS_NODE) | electron-builder config, `resources/darwin/bin/orca`, spawn code |
| Bundle id | `com.stablyai.orca` for stable, rc, hourly and daily channels | electron-builder config comments, cask zap list |
| Process to session | None in argv. Session key is the pane: `ORCA_PANE_KEY` = `${tabId}:${leafId}` in the agent's environment (env only). The agent's own session id is stored as `providerSession` in the pane's status row, which maps it to the agent's transcript | `buildPtyEnv`, `listener-event.ts` |
| Store | `~/Library/Application Support/orca/agent-hooks/last-status.json`, JSON v2, `entries[paneKey].payload.state`. Orca has no transcripts of its own: agents keep theirs, Orca's AI Vault scans them. Also `orca-data.json` / profile SQLite (workspace state) and `terminal-history/` (scrollback), not read | `server-persistence.ts`, session-history doc |
| Turn in progress | Exact: pane `payload.state == 'working'` (hook-driven; `orca worktree ps --json` reads the live store). Process table: `caffeinate -i -s` direct child of Orca, but only in mode Agent | `agent-awake-service.ts`, docs |
| Waiting on the human | Pane state `waiting` (Claude `PermissionRequest`, AskUserQuestion `PreToolUse`; other agents' notification and question events). `blocked` is failure or interruption, not waiting | `claude-events.ts`, agents-sessions doc |
| Hooks | Consumer: 19 installers write into the agents' user-global configs, on by default, script `~/.orca/agent-hooks/<agent>-hook.sh` curl-POSTs to a loopback server. Provider: `orca.yaml` `scripts:` setup, archive, issueCommand (worktree lifecycle only) | registry, hooks-memory doc |
| OpenTelemetry | No. PostHog (opt-out), local NDJSON trace | grep, telemetry doc |

## Could not determine

- Real `ps` output for any Orca process: not installed. The main executable name comes from the cask's `app "Orca.app"` and the CLI shim's `$CONTENTS/MacOS/Orca`; helper names are electron-builder defaults; the `--socket` argv is from source.
- Idle and busy CPU, so the 10 percent floor is a guess.
- The pmset assertion name of the Electron `powerSaveBlocker` fallback. `power_assertion` is left out of the row for that reason.
- Whether the daemon's login shell appears as `-zsh` or `zsh -l` in `ps`: source passes `-l` to the shell (`shellArgs ?? ['-l']`), so the probe's SHELLS set covers either form.
- Whether `orca serve` on macOS runs the .app binary directly or through `open`: `serveOrcaApp` uses `resolveForegroundOrcaExecutable()`; not traced further.
- How the hook script reaches the server when `curl` is missing, and how quickly `last-status.json` reflects a turn (250 ms debounce is the floor).
- Whether the rc and hourly channels change the userData folder name. The config says they keep the release identity; only the dev build uses `orca-dev`.
- Remote Orca Servers, SSH and cloud VM state: invisible from this Mac by design.

## Contradicts common belief or the hint

- **The repo in the hint does not exist.** `orca-agents/orca` is a 404; the project is `stablyai/orca`. The GNOME screen reader also called Orca owns `/usr/bin/orca`, and Orca's own Linux CLI is `orca-ide` for that reason. A bare name match on `orca` is wrong on any platform.
- **The orchestrator is not "per-agent processes".** Orca runs agents as ordinary terminal children (login shell, then the CLI) behind one detached daemon. There is no wrapper process per agent, and nothing in an agent's command line says it is Orca's.
- **The agents are grandchildren of the daemon, not children of the app.** Direct-child rules on the Orca pid see helpers, the daemon, supervisors and `caffeinate`. The daemon's direct children are permanent shells, so `tool_children` reads working forever.
- **The daemon outlives the app.** After a restart or an update it is adopted (parent pid 1) and keeps the PTYs; those agents have no Orca ancestor. The detached daemon also matches the Orca executable, so it needs its own surface.
- **There is a sleep inhibitor, but it is opt-in and aggregate.** Default is Off. In Agent mode it is a direct `caffeinate -i -s` child that means "some agent works". In On mode it is held forever and cannot be told from Agent mode by argv. It also drops while a pane is `waiting`, so no `caffeinate` does not mean idle.
- **Hooks are user-global, not per worktree.** The docs say Orca "reads each repo's `.claude/` and `.codex/`"; the installer writes into `~/.claude/settings.json` and the other agents' home configs, on by default, and leaves them behind. Every Claude Code session on the Mac then carries Orca hook entries. They stay no-ops outside an Orca pane.
- **Status source is stated two ways.** The user docs say state comes from "OSC title sequence and agent hooks"; the type file's header says status is "never inferred from terminal titles" and a title-based lane is a fallback (`agent-title-status.ts` has the spinner rules). Treat hooks as authoritative and titles as fallback.
- **Two folder spellings.** The CLI resolves `~/Library/Application Support/orca`; the cask zap list and the logs helper say `Orca`. Same folder on a default case-insensitive volume, different on a case-sensitive one.
- **Docs and cask are stale on their face.** `Casks/orca.rb` pins 1.3.24 and `orca@rc.rb` 1.4.36-rc.3 while the latest release is 1.4.217; both are auto-updating, so the pin is not the installed version.
- **Orca pre-applies permission-bypass flags** (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`, `--yolo`) to hosted agents by default, so a hosted Claude rarely reaches a permission prompt; `waiting` then comes mostly from AskUserQuestion and idle-input events.
- **Grok.** Orca hosts Grok Build (hook file `$GROK_HOME/hooks/orca-status.json`, default `~/.grok/hooks/`, events listed in `src/main/grok/grok-hook-config.ts`); a Grok Build pane matches the `grok-build` row, not this one. Neither is the "Grok Bot" desktop app listed separately in `registry/harnesses.json` (`grok-bot`). That harness was not part of this task and has no row from this run.

## Verification

Independent refutation pass, 2026-09-30. Validator: `tools/validate_row.py registry/agents/orca.json` prints `ok`, before and after the edits. Confidence stays `documented` (harness not installed here, so no higher). Re-checked against a shallow clone of `stablyai/orca` at `d74388f8` (package.json 1.4.214), the live docs pages and the GitHub API. Not installed, re-run: `ls /Applications | grep -i orca`, `ls ~/Library/Application Support | grep -i '^orca'`, `which orca` (not found), `ls -d ~/.orca` (No such file), `mdfind` for `com.stablyai.orca` (empty), `ps` (no Orca process).

Claims from `sources`:

| Claim | Verdict | Check |
|---|---|---|
| `orca-agents/orca` is a 404; project is `stablyai/orca`; clone at d74388f8, 1.4.214; latest v1.4.217 on 2026-09-29 with `Orca-1.4.217-arm64-mac.zip` | confirmed | scrape of the hint URL returned 404; clone `git log -1` = d74388f8 2026-09-30, remote stablyai/orca; `api.github.com/repos/stablyai/orca/releases/latest` gives tag v1.4.217, published_at 2026-09-29T19:40:43Z, that zip asset |
| Not installed here | confirmed | commands above, all empty |
| appId `com.stablyai.orca`, productName `Orca`, executableName only in `win` (Orca) and `linux` (orca-ide), all channels carry the release id; cask `app "Orca.app"` | confirmed | `config/electron-builder.config.cjs` lines 35-41, 77, 175, 435, 599; `Casks/orca.rb`, `orca@rc.rb` |
| Daemon is the app binary as node on `daemon-entry.js` with `--socket ...`, detached, cwd userData; CLI shim runs it on `out/cli/index.js`; supervisors use `-e` | confirmed | `daemon-launched-child-spawn.ts` (ELECTRON_RUN_AS_NODE '1', detached true, args list); `daemon-launch-paths.ts`; `resources/darwin/bin/orca`; `codex-app-server-posix-supervisor.ts` line 165 |
| `orca serve` starts the app binary with `--serve` and related flags | confirmed | `src/cli/runtime/launch.ts` serveOrcaApp (spawns `process.execPath` or ORCA_APP_EXECUTABLE) |
| Agents are grandchildren of the daemon via a login shell | confirmed for the shape, unobserved for the process table | `shell-launch-plan.ts`: `shellArgs = ... ?? ['-l']`, command typed after shell-ready. Corrected the label: argv[0] may be `zsh` or `-zsh`, not observed |
| Daemon is adopted by launchd after an app quit | unsupported by observation (inferred) | source says detached + unref and warns terminals persist across quit; parent pid 1 is standard Unix, never seen. Label now says "should be" |
| Only sleep inhibitor is a direct `/usr/bin/caffeinate -i -s` child of main, modes on/auto, default off, 2 h lease, waiting drops it, `powerSaveBlocker` only on caffeinate failure | confirmed | `macos-system-sleep-assertion.ts`, `agent-awake-service.ts` (shouldBlock), `agent-awake-status-lease.ts` (working only, 2 h), `default-global-settings.ts` line 229; only those two files mention caffeinate or powerSaveBlocker; docs/settings.mdx line 64 (On, Agent, Off) |
| Status states working/blocked/waiting/done; hooks primary, OSC 9999 and title lane as fallback | confirmed | `agent-status-types.ts` lines 2 and 51; `agent-status-osc.ts`; live agents-sessions page |
| Claude events and PermissionRequest / AskUserQuestion PreToolUse map to waiting | confirmed | `claude-managed-hook-events.ts`, `providers/claude-events.ts` lines 103-125 |
| Grok hook events and `$GROK_HOME/hooks/orca-status.json` | confirmed | `grok-hook-config.ts`, `grok/hook-service.ts` line 46-50 |
| 19 installers, on by default, scripts in `~/.orca/agent-hooks/<agent>-hook.sh`, PTY env names | corrected | 19 and default true confirmed (`managed-agent-hook-registry.ts`, `default-global-settings.ts` line 223, `isAgentStatusHooksEnabled`). Amp and Hermes install plugin code, not the shared script: row corrected. `buildPtyEnv` sets only the ORCA_AGENT_HOOK_* names; ORCA_PANE_KEY, TAB_ID, WORKTREE_ID, TERMINAL_HANDLE, AGENT_LAUNCH_TOKEN come from the PTY launch helpers (`local-pty-launch-helpers.ts`): same effect, different source than the evidence line names |
| `last-status.json`: v2, 250 ms debounce, atomic write, skip if identical, 7-day hydrate, rows keyed by paneKey with payload.state | confirmed, with a gap | constants and `server-persistence.ts` as stated; `restoredUnconfirmed` set at hydrate (`server-hydration.ts` line 106); packaged path has no namespace (`server-runtime-env.ts`). Gap: native-chat rows (`structuredHost`) are skipped by `serializeStatusFile`, so the file is not the whole app. Row corrected |
| `providerSession` is the agent's session id | corrected | it is an object `{key, id, transcriptPath?}` (`agent-session-resume.ts`); row now says so |
| userData `~/Library/Application Support/orca` (CLI) vs `Orca` (cask zap, logs comment); dev uses `orca-dev`; `ORCA_USER_DATA_PATH` override | confirmed | `cli/runtime/metadata.ts`, `logs-directory.ts`, `Casks/orca.rb` zap, `configure-process.ts` line 221. Case difference stays an open risk on a case-sensitive volume |
| Orca keeps no transcripts, reads each agent's own store | confirmed | docs/agents/session-history.mdx line 56 (live page fetch not repeated; source MDX read) |
| Remote servers, SSH, cloud VMs run terminals off this Mac; host badge | confirmed | docs/remote-servers.mdx line 101; agents-sessions.mdx line 36 |
| No OpenTelemetry, PostHog only, local NDJSON trace 10 MB x 10 | confirmed | `grep -rniI otlp src docs config` hits only `crash-reporting.test.ts`; package.json has `posthog-node`, no opentelemetry; `local-file-sink.ts` DEFAULT_MAX_BYTES 10 MB, DEFAULT_MAX_FILES 10; live telemetry page says PostHog Cloud US, DO_NOT_TRACK, ORCA_TELEMETRY_DISABLED. A crashpad capture module and an explicit diagnostic-bundle upload exist; neither is OTel |
| Hooks doc line "reads each repo's .claude/ and .codex/" vs user-global install | confirmed | live hooks-memory page says "Per-repo hooks"; installer writes `~/.claude/settings.json` (`hook-settings.ts` getConfigPath), also `~/.openclaude`, `~/.qoder`, `~/.codebuddy` |

Process patterns (probe `matches()` run over synthetic argv, nothing running):

| argv | Result |
|---|---|
| `/Applications/Orca.app/Contents/MacOS/Orca` (no args) | gui, 30 |
| daemon (`daemon-entry.js --socket ...`) | daemon, 31; gui vetoed by `--socket` |
| `Orca --serve --serve-json` | serve surface 31 beats gui 30 |
| `Orca .../out/cli/index.js status` from /Applications | no match (vetoed) |
| same CLI from `/Users/x/Applications/Orca.app/...` | gui 30: false positive, corrected in label and notes |
| `Orca -e script` (supervisor) | no match |
| `Orca Helper (Renderer)` | no match (path has `Orca Helper (Renderer).app`, not `/Orca.app/`) |
| plugin host, parcel watcher and other same-exe Node children | gui 30, but the probe drops them because the parent also matches |
| `/usr/bin/orca`, GNOME Orca, `python3 /usr/bin/orca --serve`, `OrcaSlicer.app` | no match |
| any other `.../Orca.app/Contents/MacOS/Orca` | gui 30: cannot be told from Stably's app by argv; the detector must check bundle id `com.stablyai.orca` (noted in the row) |

Not proven and left as stated: real `ps` shapes (not installed), the `power_assertion` name of the Electron fallback (left out of the row), the 10 percent CPU floor (a guess, and the row says so), `orca serve` and update handoff on a real Mac.

Grok Bot: Orca hosts Grok Build through hook file `orca-status.json`; a hosted `grok` pane belongs to the `grok-build` row. Orca's docs list only "Grok" (xAI CLI); nothing in Orca's source or docs mentions the Grok Bot desktop app, which has its own row (`registry/agents/grok-bot.json`) and needs no change here.
