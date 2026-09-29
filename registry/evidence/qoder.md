# Qoder evidence notes (2026-09-29)

Not installed on this Mac, nothing was started. Every process shape below is read from docs and from vendor artifacts I downloaded into the scratchpad and inspected without running them (`strings`, `file`, `plutil -p`, `unzip`, a python parse of `app.asar`). No session store exists locally and none was opened. Confidence `documented`. Qoder is not open source, so there is no public source path to cite; the binary strings and the shipped desktop bundle stand in for source, and each claim in the row says which.

## What I checked
- Local: `ls /Applications/*Qoder*`, `ls ~/.qoder`, `which qoder qodercli`, `ps -axo pid,args | grep -i qoder` all empty.
- Docs index `https://docs.qoder.com/llms.txt`, then the `.md` form of: `cli/installation`, `cli/sessions`, `cli/cli-reference`, `cli/hooks`, `cli/settings-reference`, `cli/config-scope`, `cli/acp`, `cli/remote-control`, `cli/cross-session-messaging`, `qoder/hooks`, `extensions/hooks`, `qoder/install-macos`, `qoder/data-import`, `qoderwork/hooks`, `release-notes/qoder`, `release-notes/quest-retirement-notice`. `https://docs.qoder.com/cli/using-cli` (my first guess) is a 404.
- Product map from `product-series/quick-start.md`: Qoder (new desktop app, 0.4.x), Qoder IDE, JetBrains plugin, Qoder CLI, Agent SDK, Cloud Agents, Mobile and Web, QoderWork, QoderWake.
- CLI binary: manifest at `https://qoder-ide.oss-accelerate.aliyuncs.com/qodercli/channels/manifest.json` (latest 1.1.64, 2026-09-25). Downloaded `qodercli-darwin-arm64.tar.gz`, sha256 matched the manifest (`68287d5a...15a9`), extracted to the scratchpad, `file` says Mach-O arm64, 161 MB. Ran `strings -a` only. The install script `https://qoder.com/install` was read, not run.
- npm: `curl https://registry.npmjs.org/@qoder-ai%2fqodercli` gave bins `qoder` (`bundle/qoder-npm-dispatcher.cjs`) and `qodercli` (`bundle/qodercli.js`).
- Desktop app: the download page JS lists the real URLs. Downloaded `Qoder-Installer-mac-arm64.zip`, read `installer-manifest.json`, unzipped the nested `Qoder-0.4.3-mac-arm64.zip`, read `Info.plist`, `build-manifest.json`, `bundled-resources/manifest.json`, parsed `app.asar` by hand and read `out/main/index.js` and the bundled `@qoder-ai/qoder-agent-sdk`. Nothing launched, nothing copied to /Applications.
- IDE dmg (`https://download.qoder.com/release/latest/Qoder-IDE-darwin-arm64.dmg`, 268 MB) downloaded but not opened: extracting a dmg means mounting it, which the ground rules do not allow. Its bundle id and name come from the installer manifest instead.
- Probe: ran my `process` specs through `tools/agents_probe.py matches()` on 22 synthetic ps lines (CLI native and npm, subcommands, `--acp`, `--sdk`, `--print`, desktop main, desktop worker, desktop and IDE helpers, IDE main, unrelated node). Results as intended, see Verification.

## Findings

Surfaces and process shapes
- CLI native: Bun-compiled executable, `qodercli` in the archive, documented as `qoder`. argv[0] is whatever the shell typed, so the row matches both names. The `install` subcommand places a versioned binary and an entry point; the layout was not readable (strings only show a `.local/bin/__BRAND_CLI_BIN__` template).
- CLI npm (legacy): node running `bin/qoder` (dispatcher) or `bin/qodercli`. Node >= 20.
- Modes: `--acp` (ACP server for Zed etc.), `qoder remote-control` (daemon for the mobile app, spawns `--remote-control <id>` workers), `--sdk` (Agent SDK daemon over stdin/stdout, env `QODER_AGENT_SDK_DAEMON=1`), `--print/-p` (one turn). Per the docs a bare positional prompt is also non-interactive, and argv cannot tell it from a TUI.
- Desktop app `Qoder.app`, bundle `com.qoder.app`, executable `Qoder`, Electron 43.1.1, version 0.4.3, macOS 12+ per Info.plist (docs say 14+). It has no CLI binary inside. It runs the agent as `process.execPath <...>/qoder-worker-runtime.obf.mjs --sdk` with `ELECTRON_RUN_AS_NODE=1` (Agent SDK 1.0.50, CLI 1.1.64), talking over stdio, idle timeout 30 min. That child is what the row matches.
- IDE: `Qoder IDE.app`, bundle `com.qoder.ide`, version 1.32.0 (installer manifest). Two workspaces: Editor and Quest; Quest is retired 2026-10-15.
- Also: JetBrains plugin (Marketplace 28926), QoderWork (macOS/Windows), QoderWake (`qoderwake` CLI plus a resident daemon on port 19820), Cloud Agents, mobile app. Only the first four matter for local detection; the rest are labelled in the row without a process spec.

Session mapping and stores
- CLI: `~/.qoder/projects/<processed-project-path>/<session-id>.jsonl` and `<session-id>/state.json` (documented). Root moves with `QODER_CONFIG_DIR` or `--config-dir`. State.json is AES-256-GCM encrypted in the binary. Record shape is Claude-Code-like (uuid, parentUuid, type user/assistant/system/tool_result, isSidechain, agentId).
- Session id on argv: `--session-id`, `--resume/-r <id>`. `--continue` and a plain launch carry none.
- pid to session without argv: `~/.qoder/sessions/<pid>.json`, keys `pid, procStart, startedAt, cwd, sessionId, name, kind, status, messagingSocketPath, peerProtocol`, but only with `QODER_FEATURE_CROSS_SESSION=1` (beta).
- Desktop app writes the same `projects/<project>/<sessionId>.jsonl` (its diagnostics bundle reads them) and keeps its own task database in userData (`main.sqlite`, `chat-session-turn-payload-buffer.sqlite`).
- IDE (Quest) store: `~/Library/Application Support/Qoder/SharedClientCache/cache/db/local.db` (from the desktop app's import adapter). QoderWork: `~/Library/Application Support/QoderWork/data/agents.db`, transcripts `~/.qoderwork`.

Working signal (most precise first)
- No sleep inhibitor in the CLI: zero hits for `caffeinate`, `IOPMAssertion`, keep-awake in the 1.1.64 binary. Not the Claude Code trick.
- Exact and free of setup: hooks. `UserPromptSubmit` opens a turn, `Stop` closes it.
- Exact, opt-in: `~/.qoder/sessions/<pid>.json` status `busy|waiting|shell|idle` (feature flag, CLI only).
- Exact, free, read from the terminal: OSC title. `◇ ... | Ready`, `✦ ... | Working`, `▲ ... | Action Required`, rewritten every second while not idle. Same state variable as the registry.
- Row `working_signals`: direct shell child (inferred), transcript write within 30 s, CPU 3%. These are the fallbacks.
- Desktop app: an Electron power blocker `prevent-app-suspension` exists but is taken only around Automation (scheduled) runs or when the user sets Prevent sleep. It belongs to the Electron main, not the worker. Not a chat-turn signal.

Waiting on the human
- Hooks: `Notification` with `permission_prompt`, `PermissionRequest`, `Notification` `idle_prompt`, `Elicitation`.
- Registry `status: "waiting"`, title `Action Required`, SDK stream `session_state_changed: requires_action` (parent only).

Hooks
- Config: `~/.qoder/settings.json`, `<project>/.qoder/settings.json`, `<project>/.qoder/settings.local.json`, all merged; plugin `hooks/hooks.json`; `--settings`. CLI and desktop: 23 events, handler types command, http, prompt, agent. IDE and JetBrains: 12 events, command and http only. QoderWork: `~/.qoderwork/settings.json`.
- Exit 2 blocks on the events marked blockable. Env `QODER_PROJECT_DIR`, `QODER_PLUGIN_ROOT`, `QODER_PLUGIN_DATA`.

OpenTelemetry
- Not exposed to users. No docs page mentions OTel or OTLP. The runtime bundles the OpenTelemetry SDK for its own telemetry to Qoder (`privacy.usageStatisticsEnabled`, default true, is the only documented switch); the desktop app posts tracking events to `<base>/otel/v1/logs`. An internal config block (`enabled, target, otlpEndpoint, otlpProtocol, outfile`) exists in the code but is not in the settings schema. Row says `otel: false`.

## Could not determine
- Real `ps` output on a Mac for any surface. All argv shapes are from code and docs. In particular: how the native entry point is invoked after `qodercli install` (path, symlink or wrapper), and whether the npm `qoder` dispatcher execs the native binary or runs the JS bundle.
- Whether the CLI's Bash tool runs each command as a direct shell child. `tool_children` is inferred.
- Whether the TUI's render process (`ui.renderProcess`, default true) is a child of the same executable and what its argv looks like. If it matches a CLI surface the probe keeps the outermost, so the effect should be nil, unchecked.
- Transcript flush cadence during a long stream or tool call.
- Whether `Stop` fires on interrupt.
- Whether the desktop worker is one per app or per task, and whether it writes the `sessions/<pid>.json` registry (feature flag on) — the code path is the CLI runtime, but I did not see the app set the flag.
- Desktop app userData directory name (default Electron would be `~/Library/Application Support/Qoder`, which is also where the IDE keeps its data; not confirmed).
- IDE executable name, and how the IDE runs its agent (extension host, in-process, or a bundled binary). Docs troubleshooting still points at `Qoder.app/Contents/Resources/app/resources/bin/<arch>/Qoder`, which is an older layout. Whether the IDE installs a `qoder` shell command (a third-party changelog says `which qoder` finds one) that would share the CLI's name.
- JetBrains plugin process shape. QoderWork bundle id and executable name. QoderWake process shape.
- `pmset -g assertions` name of the automation power blocker.
- Real CPU when working or idle. `tree_cpu` 3% is a guess.

## Contradicts common belief or the obvious approach
- Third-party pages (and an automation script on GitHub) say the IDE is `/Applications/Qoder.app`, binary `Electron`, bundle `com.qoder.Qoder`. The vendor's own installer manifest says the IDE is `Qoder IDE.app`, `com.qoder.ide`. `/Applications/Qoder.app` with `com.qoder.app` is the newer, separate desktop app. Do not match `Qoder.app` as the IDE.
- The command name is not settled. The npm package, install script, release archive and older docs say `qodercli`; current docs say `qoder`. Both exist as npm bins. Match both.
- "Qoder desktop wraps the Qoder CLI binary" is wrong. The desktop bundle has no CLI executable; it runs the runtime through its own Electron binary as node (`ELECTRON_RUN_AS_NODE`). So the agent process is named `Qoder`, same as the app, and only its arguments tell them apart.
- Matching the Electron main process of the desktop app would hide the agent: under the probe's parent-drop rule the worker is dropped, and the main's direct children are the worker and helpers, never tool shells. The row matches the worker and gives the GUI surface no process spec.
- The CLI looks like Claude Code on disk (JSONL under `projects/`, `settings.json` hooks, same hook event names, Claude-shaped records) but has no `caffeinate` sleep inhibitor. A detector copied from the `claude-code` row would read every Qoder CLI session as idle.
- The pid-to-status registry exists (`~/.qoder/sessions/<pid>.json`) but is not in the docs and is off by default. The docs only describe the feature it serves, cross-session messaging. It is in the binary, not in any doc.
- The desktop app's power blocker is for scheduled Automations, not for chat turns, so a `pmset` check would mark a busy chat idle and an idle scheduled run working.
- `.qoder` is also the name of a per-project folder (`<project>/.qoder/`) and the desktop app, IDE and CLI share `~/.qoder` for hooks, skills and rules, so a `~/.qoder` hit does not say which surface ran.
- `qoder status` is a subcommand that prints session status, not a session. It is vetoed in the row along with the other subcommands.

## Verification
- `python3 tools/validate_row.py registry/agents/qoder.json` printed `ok   registry/agents/qoder.json`.
- Synthetic ps lines through `agents_probe.matches()`: `qoder`, `/Users/x/.local/bin/qoder --resume abc` (session abc), `qodercli -r 123` (session 123), `node /opt/homebrew/bin/qodercli --resume s1` (session s1), `node .../@qoder-ai/qodercli/bundle/qodercli.js`, `qoder --print hi` match a tui surface; `qoder --acp` ide; `qoder remote-control`, `qoder --remote-control 9`, `qoder --sdk` daemon; the desktop worker line (`/Applications/Qoder.app/Contents/MacOS/Qoder <...>qoder-worker-runtime.obf.mjs --sdk`) daemon; `/Applications/Qoder IDE.app/Contents/MacOS/Electron` ide. No match: `qoder login`, `node .../bin/qoder status`, the desktop main process, desktop and IDE helper processes, `node server.js`, `claude`. `qoder -p hello` matches the plain tui surface (documented in the row: `-p` cannot be matched by substring).
- `python3 tools/agents_probe.py --row registry/agents/qoder.json` prints `0 agent sessions` (nothing running).

## Verification (independent refutation pass, 2026-09-29)

Method: re-fetched every doc page cited, re-downloaded the CLI 1.1.64 darwin-arm64 archive (sha256 matches the manifest and the Homebrew cask), the npm tarball @qoder-ai/qodercli 1.1.64 and the desktop installer (parsed `app.asar` by hand), ran `strings -a`, `file`, `plutil -p`, `unzip`. Nothing was run or installed, no mount. `tools/validate_row.py` prints `ok` before and after. Synthetic `ps` lines were pushed through `agents_probe.matches()` (parent-drop rule included) both before and after the edit. Nothing Qoder is installed or running here (`ls /Applications | grep -i qoder`, `which qoder qodercli`, `ls ~/.qoder` all empty), so confidence cannot exceed `documented`.

### Corrected
- **npm `qoder` matched at the wrong level.** The row matched `node .../bin/qoder`. That bin is `bundle/qoder-npm-dispatcher.cjs`, which does `spawnSync(process.execPath, [<pkg>/bundle/qodercli.js, ...args], {stdio:'inherit'})`. Parent and child both matched, the probe kept the parent, and the parent's only direct child is the child node, so `tool_children` could never fire (synthetic run: kids `['node']`, shell invisible). Fix: surface now matches `bin/qodercli` only; the child matches the `@qoder-ai/qodercli/` surface, its shells are direct children, and it carries the same argv (session id read correctly).
- **False positives on the npm path, reproduced then fixed.** `node bin/qoder status`, `login`, `--version` were vetoed on the parent but their child `node .../qodercli.js status|login` matched the second npm surface, which had a short exclude list, so a short-lived subcommand showed as an idle session. `node /opt/tools/bin/qoder-sync.js` matched on the substring `bin/qoder`. Both surfaces now carry the full exclude list and the substring is `bin/qodercli`. All five synthetic cases now return nothing.
- **"argv[0] is whatever the shell typed".** The native `qoder` is a bash dispatcher (template embedded in the binary, lines 408984-409100) that ends in `exec "$cli" "$@"`, with `$cli` from `type -P qodercli`, `~/.local/bin/qodercli` or `~/.qoder/bin/qodercli/qodercli`. So `qodercli` is the expected basename. Both names stay matched. The dispatcher sends `ide`, `chat`, `serve-web`, `tunnel` and any existing path to the IDE launcher, not the CLI. Label rewritten.
- **`tool_children` "inferred, not observed".** Now supported by code: `bashProvider` spawns each command as its own detached `<shell> -c [-l] <cmd>` child (`getSpawnArgs`), in the CLI binary, the npm bundle and the desktop worker runtime (`qoder-worker-runtime.obf.mjs`, version 1.1.64). Still not seen on a running process. Added the caveat that a background Bash task stays a live shell child.
- **Source claim "github.com/qoderAI is a separate harness-engineering platform" was wrong.** It is the vendor's own org: `homebrew-qoder` (cask `qodercli`), `changelog-CLI`, `changelog-QoderWork`, `qoder-action`, SDK and ACP demos. Only its `better-harness` repo is the harness platform. "Not open source" stands only as an absence finding: no repo holds CLI or app source. Source entry rewritten; the Homebrew cask (same archive and sha256) is a new install path, matched by the `qodercli` name.
- Session registry: docs also allow the flag in `~/.qoder/.env`, not only the environment. Added.

### Confirmed
- Session store `~/.qoder/projects/<processed-project-path>/<session-id>.jsonl` and `<session-id>/state.json`, `QODER_CONFIG_DIR`, flags `--session-id`, `-r/--resume`, `-c`, `-n`, `--fork-session` (docs cli/sessions.md, cli/cli-reference.md).
- state.json encrypted (`aes-256-gcm`, `SessionStateCryptoError` in the binary). Transcript record shape (`parentUuid`, `isSidechain`, `compact_boundary`) read from reader code only; no session file was opened (unchanged, weak).
- CLI is a Bun-compiled Mach-O arm64, 161398432 bytes, archive member `qodercli`; install.sh runs `qodercli install --force`; sha256 `68287d5a...15a9` matches manifest 1.1.64.
- npm bins `qoder` -> `bundle/qoder-npm-dispatcher.cjs`, `qodercli` -> `bundle/qodercli.js`, node >= 20 (package.json from the tarball).
- No sleep inhibitor: 0 hits for `caffein|IOPMAssertion|prevent.?sleep|keep.?awake` in the binary. `pmset -g batt` is in a hardware-fingerprint helper only.
- OSC title states and glyphs; `ui.dynamicWindowTitle` default true (settings schema in the binary).
- Session registry `~/.qoder/sessions/<pid>.json`, status list `busy|shell|idle|waiting`, kind list, off unless `QODER_FEATURE_CROSS_SESSION` (docs cross-session-messaging.md: beta, macOS and Linux only).
- Hooks: 23 events (count and names match cli/hooks.md), config locations, exit 2 blocks, `permission_prompt`/`idle_prompt`/`elicitation_dialog`; IDE/JetBrains 12 events incl. `PermissionRequest` and `Notification`; desktop app "same event and handler types as the CLI" (qoder/hooks.md); plugin `hooks/hooks.json` (cli/plugins.md); `--settings` (cli-reference).
- `--acp` (Zed `agent_servers` runs `qoder --acp`), `qoder remote-control` daemon, `--remote-control <id>` worker: the worker spawn is now confirmed in the binary (`process.execPath` plus `['--remote-control', id]`, detached, env `QODER_REMOTE_CHILD=1`); the docs alone only describe the flag.
- Desktop app: `com.qoder.app`, `Qoder.app`, executable `Qoder`, 0.4.3, Electron 43.1.1, `LSMinimumSystemVersion` 12.0. IDE `com.qoder.ide`, `Qoder IDE.app`, 1.32.0 (installer-manifest.json). Worker command `process.execPath <runtime .mjs> --sdk` with `ELECTRON_RUN_AS_NODE=1` (SDK `zu()` builds it when the runtime path ends in .js/.mjs), `QODER_AGENT_SDK_DAEMON`, idle timeout `30*6e4`. The bundled script is at `Contents/Resources/app.asar.unpacked/node_modules/@qoder-ai/qoder-agent-sdk/dist/_worker/qoder-worker-runtime.obf.mjs`, so `qoder-worker-runtime` matches as a substring.
- Desktop power blocker `prevent-app-suspension` only around scheduled runs or the Prevent-sleep setting (`acquirePreventSleep` at the automation run; not a row signal).
- Desktop shares `~/.qoder/projects/<project>/<id>.jsonl` (session migration target `vze`, `wfe()` config dir). Read from code; a live write was not seen.
- Quest retirement 2026-10-15 23:59 UTC+8 (docs). `otel/v1/logs` tracking path in the app. No OTel key in cli/settings-reference.md (0 hits).
- Process-pattern check for false positives: desktop main and its `Qoder Helper (Renderer|Plugin)` helpers do not match (argv[0] path stops at `/Frameworks/Qoder`; no `--sdk`); IDE helpers do not match (no `IDE.app/Contents/MacOS/` argument); QoderWork and the old `Qoder.app` IDE do not match; `qoder --acp`, `--sdk`, `--print`, `remote-control`, orphan `--remote-control` worker, brew `qodercli --resume s1` classify as intended.

### Unsupported or still open (row keeps these as inferred or unlabelled)
- Real `ps` output for any surface: none observed. `ui.renderProcess` child argv, worker count per app, IDE agent process, JetBrains, QoderWork and QoderWake process shapes remain unknown.
- IDE surface: the IDE dmg was not opened (no mount), so `Qoder IDE.app/Contents/MacOS/Electron` is inferred from VS Code fork convention; the pattern is exe-agnostic. The pre-rename IDE lived at `/Applications/Qoder.app` (the dispatcher keeps a legacy path for it) and is not matched. The `bin/code` launcher (the dispatcher's IDE entry) probably runs the Electron binary as node with `cli.js`, as VS Code's does (not read), which would then match the IDE surface briefly.
- Blind spots left in the native surface: `-p` or a bare prompt shows as an idle session (docs: non-interactive); `-n "<name with a vetoed word>"` is missed because `ps` output is split on spaces; `qoder --remote "<task>"` (cloud) may show as a short idle session. npm installs are not detected for `--acp`, `--sdk`, `--print`, `remote-control` (argv[0] is node), only vetoed.
- `QoderWork Dev` is a second data-folder name in the migration code next to `QoderWork` (`agents.db`); not in the row.
- `transcript_write` cadence, `Stop` on interrupt, and the 3% CPU floor are unmeasured guesses, as the row already says.
