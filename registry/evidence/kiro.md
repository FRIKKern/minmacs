# kiro: evidence notes (2026-09-29)

Row: `registry/agents/kiro.json`. Validator: ok. Confidence `documented`. Kiro is not installed here and nothing was running, so no surface was classified live. Versions read: Kiro CLI 2.25.0 (stable manifest), Kiro IDE 1.1.70 (extension kiro.kiro-agent 1.1.158), `@kiro/agent` 0.66.11.

The CLI source is not public (Reddit thread, and the Q CLI repo `aws/amazon-q-developer-cli` is only the old ancestor). "Public source" here means: the vendor's own release binaries and bundles, read statically, plus the open-source Kiro Crew repo. Nothing was executed or installed.

## What I checked

- Docs: `kiro.dev/llms.txt` index, then the `.md` twin of about 30 pages (installation, cli/*, cli/v3/*, hooks/*, reference/cli-commands and settings, ide/chat/notifications, enterprise OpenTelemetry, crew/*, cloud-sessions, how-kiro-works).
- `https://cli.kiro.dev/install` read as text. It mounts `Kiro CLI.dmg`, copies the app to `/Applications`, then `open -g -a ... --args --no-dashboard`.
- Downloaded both macOS DMGs to the scratchpad, mounted them read-only (`hdiutil attach -readonly -nobrowse`), read `Info.plist`, `product.json`, `ls`, `file`, `codesign -dv`, `strings -a`; detached both. That is the one deviation from the plain read-only list: a read-only mount was the only way to see the bundle ids and the executables. No binary was run, not even `--version`.
- Carved the embedded zstd frames out of a thin arm64 copy of `kiro-cli-chat`: `tui.js` (13.4 MB bun bundle), a bun and a node Mach-O, and a tar with `node_modules/@kiro/agent`. Read as text only.
- Kiro Crew: docs, GitHub API tree of `kirodotdev/KiroCrew` (Apache-2.0), `website/electron/package.json`, `src/kiro_crew/acp/harness/kiro.py`.
- Third-party: two GitHub issues with real process trees, and the `awslabs/cli-agent-orchestrator` Kiro provider doc for screen states.
- Local: `ls /Applications`, `which kiro kiro-cli`: nothing. Probe run with `--row`: zero sessions.
- Matching tested with 23 made-up `ps` lines through `tools/agents_probe.py` `matches()` and `session_id()` (results in the row's sources).

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | Terminal CLI; the CLI as an ACP server (`kiro-cli acp`); `Kiro CLI.app` wrapper; Kiro IDE; Kiro Crew (desktop app + Gateway daemon); cloud (Web, Mobile iOS, `--cloud`) | docs, DMGs |
| CLI executables | `kiro-cli` (launcher), `kiro-cli-chat` (engine and host), `kiro-cli-term` (shell PTY wrapper), `kiro_cli_desktop` (menu-bar helper, LSUIElement). Bare `kiro-cli` = chat | `ls Contents/MacOS`, cli-commands.md |
| CLI bundle id | `com.amazon.codewhisperer` (legacy Amazon Q id), app `/Applications/Kiro CLI.app` | Info.plist |
| IDE | `/Applications/Kiro.app/Contents/MacOS/Kiro`, bundle id `dev.kiro.desktop`, helpers `Kiro Helper (GPU/Plugin/Renderer)`. Agent runs inside the extension host as `kiro.kiro-agent` | Info.plist, product.json |
| Crew | bundle id `com.amazon.kiro.crew`, product name `KiroCrew` (inferred path `/Applications/KiroCrew.app/...`), Gateway on `127.0.0.1:5476`, launchd on macOS, spawns `kiro-cli acp --agent <a>` per session | Crew docs, repo |
| Process to session | CLI: only `--resume-id <ID>` puts an id in argv; a fresh session has none. `KIRO_SESSION_ID` is set for shell commands and hooks. IDE and Crew: one process, many sessions | cli-commands.md, strings |
| Store, V2 (default) | `~/.kiro/sessions/cli/<id>.json` + `<id>.jsonl`, UUID ids, single-process lock. Documented (ACP page) | acp.md |
| Store, V3 and IDE | `~/.kiro/sessions/<bucket>/sess_<id>/{session.json,messages.jsonl,sub-executions/*.jsonl}`; bucket `_global` or 16 hex of sha256(workspace path). Not documented | `@kiro/agent` bundle, extension.js |
| Turn in progress, best signal | Undocumented turn-marker file, one per running turn: `<KIRO_TURN_MARKER_DIR>/<pid>-<startms>.json`, refreshed every 30 s, deleted at turn end. Not expressible in the schema, so it is in `notes` and sources, not `working_signals` | bun bundle function `IO`, Rust `turn_marker.rs` strings |
| Turn in progress, what the row uses | `transcript_write` 30 s (needs `--resume-id`), then `tree_cpu` 3 percent (guess) | inferred |
| Waiting on the human | No hook. Terminal: OSC 9;4;4;100 progress (only in a few terminals), BEL/OSC 9 notification when enabled. IDE: native "Action Required" notification. ACP clients: `session/request_permission` | terminal-ui.md, settings.md, bundle source |
| Hooks | `.kiro/hooks/*.json` (CLI 3.0, IDE 1.x, and `~/.kiro/hooks/` per IDE 1.0 page); CLI 2.x: `hooks` block in `~/.kiro/agents/*.json` or `.kiro/agents/*.json`. `Stop` = end of the agent's turn | hooks docs |
| OpenTelemetry | Docs: enterprise admin export of daily aggregates from Kiro's servers. Undocumented: the CLI reads `KIRO_TELEMETRY_OTEL`, `KIRO_TELEMETRY_OTLP_ENDPOINT`, `KIRO_TELEMETRY_EXPORT_INTERVAL_MS` and exports OTLP metrics. Neither is a live turn signal | opentelemetry.md, strings |
| Sleep inhibitor | None found (no `caffeinate`, no IOPMAssertion in any CLI binary or bundle) | grep counts, all 0 |

## Could not determine

- Real `ps` output on macOS. The tree `kiro-cli` -> `kiro-cli-chat chat` -> `bun tui.js` + `kiro-cli-chat acp` is from a Linux report on kiro-cli 2.1.1. On 2.25 the launcher may `exec` instead of spawn, and V3 adds a `node` KAS server child that I only know from strings.
- Where the turn-marker directory is. Rust says it comes from a run dir picked from `XDG_RUNTIME_DIR` or `TMPDIR` and names a `turn-markers` folder, and the env var is handed to the bun process, but the parent folder name is not in the strings. Read it from the bun process's environment or check `$TMPDIR` on a live run.
- Whether the marker exists on the V2 path. The code I read is the TUI (`session_interface: "interactive_cli"`, field `engine`), which is shared, so it probably does, but I did not see V2 and V3 values.
- Where binary pinning puts the copy (`pinned_bin`, run dir, `chat-cli-*.heartbeat`), so the real `argv[0]` of `kiro-cli-chat` on macOS. The row matches on base name only for that reason, but `Kiro CLI.app` has a space, so a `ps` parser that splits on spaces can lose the name for the copy that runs from inside the bundle.
- Where the bun and node runtimes are extracted on macOS. Linux shows `~/.local/share/kiro-cli/`; macOS is probably `~/Library/Application Support/kiro-cli/` (the binary contains that string), not confirmed.
- Real key names of a session record. There are no sessions on this Mac, so I could not print keys; I only know `session.json` is validated by a zod schema and `messages.jsonl` holds one JSON event per line.
- Whether a V2 `.jsonl` is written during a model stream or only at message end. The floor of 30 s and the CPU floor are guesses.
- Whether `PreToolUse` fires before or after the permission prompt.
- Kiro Crew process shapes (Gateway python path, Electron executable name): inferred from docs and `package.json`, never seen. Crew probably deserves its own row; I kept it as two lean surfaces because `kiro-cli crew` ties it to the CLI and Crew runs `kiro-cli acp` for every session.
- Kiro Web and Mobile: cloud, nothing local. `kiro-cli --cloud` stores sessions in the cloud store.

## Contradicts common belief, the hint, or the docs

- The hint says Kiro CLI is the successor to Amazon Q Developer CLI. True, and it shows: the macOS bundle id is still `com.amazon.codewhisperer`, and the installer upgrades an existing `q` install and writes `q` wrapper scripts.
- The CLI is no longer one Rust binary. A launcher, a Rust engine, an embedded bun running a TypeScript TUI, and on V3 an embedded node server. Session state is not in the process you would match: the matched `kiro-cli` has one direct child, `kiro-cli-chat`, so "direct children only" hides the shell tools and MCP servers, which are grandchildren.
- Docs disagree on where sessions live: session-management says "SQLite database in `~/.kiro/`", the ACP page says JSON and JSONL files in `~/.kiro/sessions/cli/`. The V3 engine and IDE use a third layout. Old Q-era chats were in `data.sqlite3` (that filename is still in the binary).
- Docs disagree on `Stop`: the hooks table and hook-types page say it fires when the agent finishes responding; the CLI 3.0 migration page says "Session ends". The agent's own built-in prompt says end of an agent execution, so I read it as turn end.
- Docs for hooks list `~/.kiro/hooks/` only on the IDE 1.0 page, and the hooks reference itself does not. The loader has global hook directories, so it is real, but the exact global path for the CLI is not documented.
- Trust flags changed: V3 replaces `--trust-all-tools` with `permissions.yaml`, and untrusted workspaces run without a shell. A detector should not assume shell children exist.
- The CLI docs say sessions are per-directory, but the V3 dashboard `/sessions` lists local sessions from all workspaces.
- `KIRO_SKIP_BINARY_PINNING` in the setup docs shows the running binary can be a session-specific copy, so an install-path rule can miss it.
- The IDE does not run one agent process per chat. It is the extension host of an Electron app, so CPU and children cannot name a session.
- OpenTelemetry is not what it looks like: the only documented export is enterprise and server-side, once a day. The CLI's own OTLP export is undocumented, metrics only.
- Kiro's TUI turns on OSC 9;4 progress when `HERDR_ENV=1`, which means it knows about Herdr; it does not for Ghostty, kitty, Terminal.app or cmux by that test.
- Crew is a separate open-source product on the same harness family, launched from `kiro-cli crew`. A `kiro-cli acp` process can belong to Crew or to an editor, not to a person in a terminal.

## Verification

Adversarial re-check on 2026-09-29 by a second reader. Validator: `ok` before and after. Confidence stays `documented` (nothing of Kiro is installed or running here, so nothing can be `verified-locally`). Method: re-fetched the vendor docs and the install script, re-read the manifest, the Crew and third-party sources, and downloaded the Linux aarch64 CLI zip (BUILD_VERSION 2.25.0) and the Linux arm64 IDE tarball (1.1.70) to the scratchpad to read them statically (`unzip`, `strings`, `zstd -dc` on the embedded frames, `tar -x`). Nothing was run, installed or mounted. The macOS DMGs were not re-mounted, so macOS-only facts are marked as such.

Legend: confirmed = re-derived from the cited source; corrected = the row was wrong or overstated and was edited; unsupported = source does not show it, or could not be re-checked.

### Sources, one by one

| Claim | Result | Note |
|---|---|---|
| Installer mounts `Kiro CLI.dmg`, copies to `/Applications`, `open -g -a ... --args --no-dashboard`; Homebrew unsupported | confirmed | install script lines 20-26, 512, 529; installation.md line 68 |
| CLI bundle id `com.amazon.codewhisperer`, v2.25.0, LSUIElement, four Mach-O in Contents/MacOS | partly confirmed | Manifest: macOS `Kiro CLI.dmg`, universal, 360741857 bytes, version 2.25.0 (exact match). The id string is present in the Linux `kiro-cli` binary. LSUIElement, the bundle plist and the MacOS listing were not re-read (DMG not mounted): unsupported by this re-check |
| IDE bundle id `dev.kiro.desktop`, applicationName `kiro`, dataFolderName `.kiro`, urlProtocol `kiro`; agent extension `kiro.kiro-agent` 1.1.158 | confirmed | `product.json` and extension `package.json` in the Linux 1.1.70 tarball (`darwinBundleIdentifier`). Executable name `Kiro` and helper names are from the earlier DMG read, not re-checked |
| IDE agent runs in the extension host, no per-session process | corrected to inferred | The extension bundle holds the session server (`sessionsPath`), which fits. But how-kiro-works.md says the harness is "a standalone process" that clients reach over stdio, so a child process is not ruled out. Label in the row rewritten |
| Linux process tree: `kiro-cli` > `kiro-cli-chat chat` > (`bun tui.js`, `kiro-cli-chat acp`) | confirmed, wording fixed | Issue 7918 shows exactly this, with the bun TUI and the engine as siblings under `kiro-cli-chat chat`. Issue 3820 gives the bun path. Notes said MCP servers and shell tools were "grandchildren"; they are at least three levels below `kiro-cli` (parent inferred to be the engine). macOS shape still not observed |
| bun TUI, node KAS server, `KIRO_AGENT_ENGINE`, `KIRO_KAS_*`, "Bun TUI runtime", "KAS agent engine" embedded in `kiro-cli-chat` | confirmed | Linux build: strings hit; zstd frames carved: tui.js (`#!/usr/bin/env bun`), two ELF files, a tar with `@kiro/agent` 0.66.11 |
| Turn marker file `<KIRO_TURN_MARKER_DIR>/<pid>-<startms>.json`, refreshed every 30 s, deleted at turn end, key names | confirmed, one part corrected | Function `IO` in tui.js read verbatim: keys, 30000 ms, `unref`, `rmSync`. Rust strings present. Corrected: the code is a no-op when the variable is unset, and nothing shows the host always sets it. "Passed in by kiro-cli-chat" was inferred. Directory still unknown |
| V2 sessions in `~/.kiro/sessions/cli/<id>.json` + `.jsonl`, UUID ids, one process per session; docs also say SQLite | confirmed | acp.md "Session storage"; session-management.md says "Local database (~/.kiro/)" and "SQLite"; tui.js has `KIRO_TEST_SESSIONS_DIR??ja("sessions","cli")`; `data.sqlite3` string in the binary. The conflict is real, so the row's `transcript_write` meaning now says the interactive path is unproven |
| V3 and IDE layout `~/.kiro/sessions/<bucket>/sess_<id>/{session.json,messages.jsonl}`, bucket `_global` or 16 hex of sha256 | confirmed | `acp-server.js`: `sessionsPath`, `"messages.jsonl"`, `"session.json"`, `_global`, `sess_`; the IDE extension has the prompt string "Sessions persist to ~/.kiro/sessions/<workspaceHash>/sess_<sessionId>/messages.jsonl". v3new.md: "~/.kiro/sessions/"; v3.md: session format not backward-compatible |
| Hooks: standalone `.kiro/hooks/*.json` in CLI 3.0 and IDE 1.x; CLI 2.x camelCase in agent config; `~/.kiro/hooks/` global; Stop disagreement | confirmed | hooks.md, hooks/types.md, hooks-migration.md ("Session ends"), configuration-reference.md, ide/whats-new-v1/hooks.md (line 86, global hooks). JSON on stdin with `session_id` and `cwd`: hooks/types.md examples |
| No Notification-style hook for "waiting on the human" | confirmed | Trigger tables in hooks.md, idehooks.md, hooks-migration.md have none |
| Terminal state channels: OSC 0 title, OSC 9;4 progress, BEL/OSC 9 notifications with three strings | corrected | OSC 9;4 and the gating (`iTerm.app`, `WezTerm`, `WT_SESSION`, `HERDR_ENV=1`, ConEmu, `KIRO_NO_PROGRESS`) re-read in tui.js (`A1t`, `m1t`, `mT`). Corrected: when idle with context usage at or above 60 percent (`mCn=60`), the TUI sends `9;4;4;<context percent>`, so state 4 alone is not a wait signal; only percent 100 is, and a full context at idle also gives 100. Docs (terminal-ui.md) name iTerm2, WezTerm, Windows Terminal, ConEmu and no sequences. Notification strings "Permission required", "Input required", "Response complete" confirmed in tui.js; setting names confirmed in settings.md |
| IDE native notifications: Action Required, Success, Failure | confirmed | ide/chat/notifications.md |
| No sleep inhibitor (no caffeinate, no IOPMAssertion, no powerSaveBlocker in the agent) | unsupported on macOS, supported for shared code | Zero hits in tui.js, `acp-server.js` and the IDE extension (shared code). Zero hits in the Linux Rust binaries too, but that proves nothing for macOS-only code paths. The macOS Mach-O files were not re-read. Keep as "none found", not "none" |
| Third-party screen states and spinner about 10 times a second (kiro-cli 2.11) | confirmed | cli-agent-orchestrator docs/kiro-cli.md "kiro-cli 2.11+ Notes" |
| Issue 7918: engine asleep with zero I/O while the TUI keeps animating | confirmed, meaning of the CPU signal corrected | The same report shows the bun TUI in state R while the engine hung. The row said a stalled turn "shows almost none" CPU; the evidence says the opposite for a hung engine, so `tree_cpu` can read a hung turn as working. Text rewritten |
| OpenTelemetry: enterprise export is server-side daily aggregates; CLI reads `KIRO_TELEMETRY_OTEL`, `_OTLP_ENDPOINT`, `_EXPORT_INTERVAL_MS`, metric names | confirmed | opentelemetry.md (02:00 UTC, gRPC or HTTP/protobuf, `service.name = kiro-enterprise`); the three variables and both metric names are in the Linux `kiro-cli-chat` strings. The `service kiro-cli` and `/v1/metrics` detail was not re-checked |
| Subcommand list; bare `kiro-cli` means chat; `kiro-cli acp` is the ACP server; `--resume-id`; `--v3`; `KIRO_SESSION_ID` | corrected | All subcommands and flags are on cli-commands.md except: `acp` is documented on acp.md only, and `KIRO_SESSION_ID` appears in no doc I fetched (only as a string in the binary, three hits). Source entry split; hooks.config now says undocumented |
| Kiro Crew: Electron `com.amazon.kiro.crew`, productName `KiroCrew`, Gateway 127.0.0.1:5476, launchd, spawns `kiro-cli acp --agent`, hooks in `~/.kiro/crew/hooks/`, `kiro-cli crew`, Apache-2.0 | confirmed | electron `package.json` (appId, productName), `kiro.py` (`acp`, `--agent`, `--model`), crew docs (port 5476, launchd, pipx or `~/.kiro/crew-venv`, hooks path), cli-commands.md `kiro-cli crew`, repository LICENSE |
| One harness for IDE, CLI 3.0, Web and Mobile; V3 opt-in early release, V2 default; Web, iOS TestFlight and `--cloud` are cloud | confirmed | v3.md, how-kiro-works.md, cli-commands.md (`--v2` overrides a saved value), cao doc ("v2 is the default"), installation.md and mobile.md (TestFlight), cloud-sessions.md (`kiro-cli --cloud`) |
| Matching test on 23 made-up ps lines | rerun, extended | Re-run with 36 lines; result in the last source entry of the row |

### Process patterns: false positives and negatives found

- Corrected: `kiro-cli chat --list-sessions`, `--list-models` and `--delete-session <id>` are documented one-shot commands and matched as idle sessions. Added as whole-token exclusions.
- Corrected: `kiro .` runs the IDE binary as node on `out/cli.js` for a moment (the shim does `ELECTRON_RUN_AS_NODE=1 "$ELECTRON" "$CLI"`, confirmed on the Linux tarball) and matched the IDE surface. Excluded for the default `/Applications` path; the macOS path is inferred from the Linux shim and harmless if wrong.
- Not fixable with the schema, recorded in notes and the TUI label: the whole-token deny-list drops a real session whose prompt contains a bare word such as `mcp`, `agent`, `login`, `help` or `update`. `acp` is a substring test on the ACP surface, so `--agent capacpity` is listed under both surfaces (harmless: same process, wrong label).
- Not fixable: undocumented or legacy subcommands (`kiro-cli launch`, `setup` in the test) match the terminal surface. `kiro-cli --cloud` is a local client of a cloud session and matches too.
- Not fixable: a `kiro-cli-chat` launched from inside `Kiro CLI.app` has a space in argv[0]; the row matches on base name and the space-split ps line loses it. The outer `kiro-cli` launcher normally matches first, so this only bites when the launcher execs.
- Checked and fine: the engine child `kiro-cli-chat acp` under `kiro-cli-chat chat` matches the ACP surface but the probe drops it because its parent matches; `kiro-cli-term`, `kiro_cli_desktop`, the bun process and the IDE's `Kiro Helper (...)` processes match nothing. `kiro-cli` and `kiro-cli-chat` are not shared with an unrelated program (the old Amazon Q `q` command is a different name).
- Crew rules stay inferred: a pipx home under `Library/Application Support` breaks on the space; the Gateway bundled in the desktop app has no rule.

### Still unsupported after this pass

- Everything macOS-specific: bundle plists, real `ps` output, whether the launcher execs, the pinned copy's argv[0], where bun and node are extracted, where the marker directory is.
- Write cadence of a V2 `.jsonl` during a stream; both floors (30 s window, 3 percent CPU) remain guesses.
- Whether `PreToolUse` fires before the permission prompt.
- The Herdr gate is real in the shipped TUI code (`HERDR_ENV==="1"`), but no Herdr session was run to see the sequences arrive.
