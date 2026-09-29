# Google Antigravity: evidence notes (2026-09-29)

Row: `registry/agents/antigravity.json`. Validator: ok. Probe on this Mac: 0 matches (nothing installed, no process). Confidence is `documented`.

```
Antigravity family (all under ~/.gemini, separate data dirs)
  agy (CLI, Go)        ~/.gemini/antigravity-cli   conversations/<id>.db (SQLite) + brain/<id>/.../transcript.jsonl mirror
  Antigravity.app 2.0  ~/.gemini/antigravity       com.google.antigravity
  Antigravity IDE.app  ~/.gemini/antigravity-ide   com.google.antigravity-ide
  Python SDK           spawns Go `localharness`    (Apache-2.0 source, the only public code)
  shared config        ~/.gemini/config/{hooks.json,mcp_config.json,config.json,sidecars/,plugins/}
```

## What I checked

- Official docs, fetched with WebFetch and raw `curl` (HTML stripped to text): `antigravity.google` home and `/download`, `/docs/hooks/`, `/docs/cli/{reference,headless,statusline,title,conversations,troubleshooting,install}/`, `/docs/cli/commands/{resume,title}/`, `/docs/{settings,remote-control,sidecars,faq,changelog}/`, `/docs/ide/overview/`, `/cli/install.sh` (read, not run).
- Auto-update manifest `.../manifests/darwin_arm64.json`: version only, binary not downloaded.
- Homebrew cask JSON for `antigravity`, `antigravity-ide`, `antigravity-cli` on formulae.brew.sh: app names, bundle ids (from `uninstall quit`), zap paths.
- Public source: `google-antigravity/antigravity-sdk-python` (tree, `local_connection.py`, `state_update.proto`, hooks README, CHANGELOG). `google-antigravity/antigravity-cli` repo (tree only: no source).
- Issues and third-party readers: antigravity-cli#366 (OTel), tenequm/pond#201 (store layout, observed 1.1.24), agentgrep backend pages (observed 1.2.1), kunchenguid/quota-axi#164 (IDE process path from real `ps`), gyredeck-macos#66 (plain `agy` in `ps`), CodexBar `docs/antigravity.md`.
- Local: `which agy`, `ls ~/.gemini`, `ls /Applications`, `ps`, `pmset -g assertions`, all empty. Then the row's matchers run through `tools/agents_probe.py` `matches()` against synthetic command lines (agy bare and absolute, IDE main, IDE helper, IDE language server, 2.0 main and helper, a gemini node line): each matched only its own surface or nothing. Synthetic, not live.
- No session store exists here, so no record keys were printed.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| CLI process | `agy`, a Go binary (~160 MB, no Node). `ps` shows bare `agy` when started from PATH. `~/.local/bin/agy`, or Homebrew cask `antigravity-cli` symlink `agy` to Caskroom `antigravity` | install.sh, cask JSON, gyredeck PR |
| Bundle ids | `com.google.antigravity` (Antigravity.app, 2.0), `com.google.antigravity-ide` (Antigravity IDE.app). CLI has none | cask `uninstall quit` |
| Process to session | Only `--conversation <id>` puts an id in argv. `-c` and a plain launch do not. Fallback: cwd through `cache/last_conversations.json` (docs), or the open `.db-wal` via lsof (inferred) | docs resume + headless |
| Store | CLI: `~/.gemini/antigravity-cli/conversations/<uuid>.db`, SQLite, WAL, not vendor-documented. Also `conversation_summaries.db`, `history.jsonl`, and a JSONL mirror `brain/<uuid>/.system_generated/logs/transcript.jsonl` (that path is documented) | pond#201, agentgrep, docs/hooks |
| Turn in progress | Best exact: hook `Stop.fullyIdle`, or statusLine `agent_state`. Best from outside with no setup: sleep-inhibit assertion (FAQ says it exists), then `.db-wal` mtime, then CPU | docs |
| Waiting on human | statusLine `tool_confirmation_pending` (needs a user script). No Notification hook. `PreToolUse` can return `ask`. Opt-in desktop notification and bell | docs |
| Hooks | `hooks.json` (`.agents/`, `~/.gemini/config/`, plugin) or a `hooks` block in `~/.gemini/antigravity-cli/settings.json`. Five events, command type only | docs/hooks |
| OpenTelemetry | CLI and apps: no. SDK: yes (GenAI spans) | #366, SDK changelog 0.1.5 |

## Could not determine

- Anything live. Not installed; I did not download the DMGs or the CLI tarball, so no `Info.plist`, no `strings`, no `--help`, no `--version`.
- Executable names inside both app bundles. `Contents/MacOS/Antigravity` is assumed from the cask app names.
- Whether the 2.0 and IDE apps are Electron. The `ShipIt` cache dirs in the cask zap list point that way; the IDE ships a VS Code style `bin/antigravity-ide`.
- Which mechanism holds the sleep inhibitor (IOKit assertion or a `caffeinate` child), whether it is per turn or per process, and whether every surface does it. The FAQ line is unqualified. This is the single most useful thing to check on a live instance with `pmset -g assertions`.
- Write cadence of the WAL file during streaming and long tool runs. CPU floor is a guess.
- The current primary store for the 2.0 app and IDE 2.5.5. The old IDE (1.104.0) used encrypted-looking `.pb` files in `~/.gemini/antigravity/conversations/`. 2.0 now shares that directory. A 2.0 SQLite import into the CLI exists, which hints 2.0 is SQLite too. Unconfirmed.
- The argv of the LaunchAgent that `agy remote-control start` registers, so the always-on daemon is not separated from a TUI. Plist not inspected.
- Whether `agy` runs helper children (MCP servers, background shells, detached daemons are mentioned in the changelog and CodexBar). This is why `tool_children` is not a working signal.
- An `agy_acp_server` and `localharness_external` in the app bundle were mentioned in a search summary only. Not confirmed, not in the row.
- Whether the `.db` keeps `not_fully_idle` current during a turn.

## Contradicts common belief or the hint

- The hint says "stores under ~/.gemini". True, but this is not Gemini CLI. Gemini CLI is a node process with JSONL in `~/.gemini/tmp/<slug>/chats/`. agy is a Go binary with per-conversation SQLite under `~/.gemini/antigravity-cli/`. Gemini CLI was replaced by agy for individual accounts on 18 June 2026 (third-party summaries and google-gemini/gemini-cli discussion 27274; the discussion page itself I did not read). Keep the two rows from overlapping.
- Not one app. "Antigravity.app" is now the 2.0 agent command center. The editor is a separate app, "Antigravity IDE.app" with its own bundle id and data dir. Older material calling `Antigravity.app` the IDE, and the IDE using `~/.gemini/antigravity`, describes the pre-2.0 layout. Docs now say IDE data lives in `~/.gemini/antigravity-ide`.
- The CLI's conversation store is SQLite, not JSONL. The JSONL `transcript.jsonl` is a regenerated display mirror. The docs only ever mention the JSONL. The SQLite path, per the vendor changelog, is "the CLI's conversation format", but no doc page gives the path.
- Docs are inconsistent about the CLI's `<app_data_dir>`: the prose says `~/.gemini/antigravity-cli`, but the hook and statusLine examples print `~/.gemini/antigravity/brain/...`. Trust the payload's `transcriptPath` at runtime.
- SQLite WAL means the `.db` file's mtime can lag a live turn. A naive "newest .db mtime" reads idle. The row's `per_session` ends in `.db*` for that reason.
- The `agy` process is also the local language server. There is no separate server child for the CLI. In the IDE the language server is a persistent child `language_server_macos_arm`. Child-process signals must ignore it.
- Hooks are not a full lifecycle. No SessionStart, no SessionEnd, and no Notification event, unlike Claude Code. `Stop` is the only end-of-turn event, and it fires for the whole execution loop, with `fullyIdle` telling whether background tasks remain.
- "OpenTelemetry" appears in the docs, but only in the Python SDK changelog. The CLI has an open request (#366) and users report `OTEL_*` variables do nothing. `enableTelemetry` in settings is Google's own collection.
- "Antigravity IDE.app" has a space. `ps` prints the path unquoted, so a parser that splits on spaces sees `/Applications/Antigravity` as argv[0]. That also matches the 2.0 app's parent folder name, so the row's IDE and 2.0 surfaces are told apart by the `IDE.app/Contents/MacOS/` token.
- Version numbers disagree across official sources on the same day: CLI 1.2.13 (manifest, cask) vs 1.2.11 (download page); 2.0 app 2.18.1 vs cask 2.17.0. Do not pin behaviour to a single version string.
- Only the Python SDK is open source. The `antigravity-cli` repo is a changelog and issue tracker, so "public source" for the CLI, 2.0 and IDE is not available; those claims rest on docs and third-party reverse engineering.

## Verification

Adversarial pass on 2026-09-29. Validator: `ok` before and after. Local check: `which agy` printed `agy not found`, `ls ~/.gemini` printed `No such file or directory`, `ps` and `pmset -g assertions` matched nothing, so confidence stays capped at `documented`. Official pages were re-fetched with curl (`--compressed`) and read as text; GitHub sources through `gh api`; forum pages through firecrawl.

Legend: confirmed = source says what the row says. corrected = row edited. unsupported = no source found, left as inferred or removed.

### Claims

| Claim | Result | Basis |
|---|---|---|
| Product family and versions (2.0 v2.18.1, CLI v1.2.11, IDE 2.5.5, SDK v0.1.18); Apple Silicon and Intel | confirmed | `antigravity.google/download` text |
| `agy` is a Go binary installed to `~/.local/bin/agy`; manifest 1.2.13; updater state and `AGY_CLI_DISABLE_AUTO_UPDATE` | confirmed | `install.sh` (`TARGET_DIR="$HOME/.local/bin"`, `BINARY_PATH="$TARGET_DIR/agy"`), manifest JSON, troubleshooting page |
| "about 160 MB, no Node" | corrected | Third-party only (continuumcode.ai). Row wording now says so. `install.sh` also accepts `--dir`, so the path is not always `~/.local/bin`; the `agy` name match covers that |
| Homebrew cask `antigravity-cli` links `agy`; zap `~/.gemini/antigravity-cli` | confirmed | `formulae.brew.sh/api/cask/antigravity-cli.json` |
| Bundle ids `com.google.antigravity`, `com.google.antigravity-ide`; app names; `agy-ide` on PATH | confirmed | Cask JSON `uninstall quit` and `app` |
| "Both apps are Electron/Squirrel style (inferred)" | corrected | IDE is Electron (executable is `Electron`); 2.0 app still inferred |
| Main executable is `Contents/MacOS/Antigravity` for both apps | corrected | IDE is `Contents/MacOS/Electron`: forum TCC log, forum sleep report ("The Electron parent process"), Antigravity-Hans `config.go`. 2.0 app `Antigravity` is third-party only (same `config.go`). Row patterns do not use the executable name, so matching is unchanged |
| IDE runs child `language_server_macos_arm` from `Contents/Resources/app/extensions/antigravity/bin/`, unquoted path in `ps` | confirmed for IDE | quota-axi#164 body (real `ps` line) |
| Same for the 2.0 app ("Both apps" in notes) | unsupported | CodexBar docs say the 2.0 app has an app-local `language_server`; name and path not shown. Notes reworded |
| Plain `agy` shows as `agy` in `ps`; agy is itself the local language server | confirmed | gyredeck-macos PR #66 body; CodexBar `docs/antigravity.md` |
| `--conversation <id>` resumes by id; `-c` carries no id; no `--session-id` flag | confirmed | `/docs/cli/commands/resume/`, `/docs/cli/headless/` flag table; no `session-id` string on the reference or headless pages |
| `-c` resolves through `~/.gemini/antigravity-cli/cache/last_conversations.json` (cwd to id map) | confirmed | Resume page. Use as a cwd fallback is inferred, as the row says |
| Store `conversations/<uuid>.db`, SQLite, WAL sidecars while live | confirmed (third-party) | pond#201 (observed 1.1.24: `-wal`/`-shm` while live), agentgrep (observed 1.2.1, same path). `documented: false` is right |
| Vendor confirms SQLite conversation format; WAL checkpointed on exit | confirmed | Changelog v1.0.4 "Added SQLite (.db) conversation support and will be CLI's conversation format" (the row cites v1.1.26 for the entry introducing `.db`; the `.db` entry is v1.0.4); v1.1.26 "Fixed SQLite database WAL checkpointing on CLI exit" |
| Transcript mirror path and `app_data_dir` per surface | confirmed | `/docs/hooks/` "Common Input Fields". The page's own examples print `~/.gemini/antigravity/brain/...` for all surfaces, as the row notes |
| Legacy IDE 1.104.0 and 2.0 share `~/.gemini/antigravity`, `.pb` files look encrypted | confirmed (third-party) | agentgrep IDE page (observed Antigravity 1.104.0 from a WSL server build). 2.5.5 store still undetermined |
| Five hook events, config locations per surface, stdin fields, `fullyIdle`, decisions, `force_continue` | confirmed | `/docs/hooks/` read in full |
| Hook config in `settings.json` `hooks` block for the CLI; `/hooks` in the TUI | confirmed | Same page |
| Custom Markdown agents list hook files in front matter | corrected | True, but the source is the changelog, not `/docs/hooks/`. Source entry added |
| `ask` "marks about to prompt the human" | corrected | Doc: `ask` prompts but respects Always Allow, so it may not prompt. `force_ask` always does. Waiting signal reworded |
| statusLine payload fields `agent_state`, `tool_confirmation_pending`, `pending_input_count`, `task_count`; `title` key | confirmed | `/docs/cli/statusline/`, `/docs/cli/title/` |
| Engine states `STATE_RUNNING`, `STATE_WAITING_FOR_TASKS`, `STATE_FULLY_IDLE`, `STATE_CANCELLED` | confirmed | `state_update.proto` in antigravity-sdk-python |
| SDK spawns `localharness` (`google/antigravity/bin/localharness`, `ANTIGRAVITY_HARNESS_PATH`) via `Popen` | confirmed | `local_connection.py` lines 761 to 823, 1421 |
| "...and talks to it over stdio" | corrected | stdin/stdout carry a 4-byte length plus protobuf config handshake only; the session runs over a WebSocket on a localhost port (`_connect_websocket`, lines 1371 to 1450) |
| CLI source is not public | confirmed | `gh api repos/google-antigravity/antigravity-cli/contents`: `.github`, `CHANGELOG.md`, `README.md`, `agy-cli-demo.gif`, `examples`. Org has two repos |
| Antigravity holds sleep off while an agent runs | corrected | FAQ line is verbatim. But a user report (discuss.ai.google.dev 180431, IDE 2.5.5, `pmset -g assertions`) shows the IDE parent process holds `NoIdleSleepAssertion "Electron"` for the whole app lifetime, with no agent running. As a working signal it would read the IDE as always working. `power_assertion` removed from `working_signals`. CLI and 2.0 app behaviour still unobserved |
| v1.1.20 fixed the spinner loop, "eliminating idle CPU wakeups" | confirmed | Changelog v1.1.20, August 25, 2026 |
| Remote Control flags; `agy remote-control start` registers a LaunchAgent on macOS; approvals from either side | confirmed | `/docs/remote-control/` |
| Headless `-p` statuses including `WAITING`; `AGY_ERROR` and exit code 3 | confirmed | Headless page status table; changelog "exit with code 3 and print the AGY_ERROR line" |
| `notifications` setting, default false, desktop notification plus bell "when a long-running task completes or requires your attention" | confirmed | Settings page (that wording); reference table only says "upon task completions" |
| No OpenTelemetry in "the apps and the CLI" | corrected | Issue #366 is open and shows the CLI only. Apps not checked. Row and source reworded; `otel: false` kept as "no documented exporter" |
| SDK has OpenTelemetry since v0.1.5 (June 25, 2026); `observability_otel.py` exists | confirmed | Changelog text; file present in the repo |
| `danistrebel/agy-hooks` exists | confirmed | `gh api` returns "Antigravity Hooks for Telemetry" |
| Not installed on this Mac; nothing observed live | confirmed | Re-run today, same empty results |
| Gemini CLI replaced by agy on 18 June 2026 (evidence file, second-hand there) | confirmed | Maintainer post in google-gemini/gemini-cli discussion 28017 and the Google Developers Blog. The earlier note cited discussion 27274 and said it was unread; 28017 is the one read |

### Process patterns and false positives

Run through `tools/agents_probe.py` `matches()` with the probe's space-splitting, on synthetic lines built from the observed paths (nothing live):

| Line | Matched surface |
|---|---|
| `agy`, `/Users/x/.local/bin/agy --conversation abc`, `agy remote-control start`, Caskroom path | tui |
| `/usr/bin/agyx`, `agy-ide` wrapper path, `gemini` node line | none |
| 2.0 main (`Antigravity.app/Contents/MacOS/Antigravity`) | gui |
| 2.0 helper (`.../Frameworks/Antigravity Helper (Renderer).app/...`) | none |
| IDE main (`Antigravity IDE.app/Contents/MacOS/Electron`) | ide |
| IDE Renderer and Plugin helpers, IDE `language_server_macos_arm` | none |
| `.../site-packages/google/antigravity/bin/localharness` | daemon |
| IDE `Electron` running `cli.js` (the `agy-ide` / `antigravity-ide` wrapper, transient) | ide, a false positive |
| `/Applications/Antigravity.app/Contents/MacOS/Electron` (pre-2.0 IDE, same bundle name) | gui, a false positive if a legacy install is present |
| Contrived `/Users/x/Antigravity/tool IDE.app/Contents/MacOS/x` | ide, a false positive |

Findings: the IDE pattern still matches the real `Electron` main process, because it keys on the bundle path, not the executable name. The `path_contains: ["/Antigravity"]` term is broad; only `args_contain` keeps it honest. Under a full-path detector the same pair holds. Accepted limits, recorded in notes: the transient IDE CLI wrapper, a legacy pre-2.0 install under the same bundle name, and the always-on `agy remote-control` daemon being reported by the tui surface (its argv is unknown). No other product named `agy` or `localharness` turned up in searches. The helper lines are synthetic; a live IDE run is the real test.

### Confidence

Stays `documented`, the ceiling for a harness not installed here, and it covers identity, flags, hooks, statusLine and notifications. Not covered: the two remaining working signals (`transcript_write` on the `.db-wal`, `tree_cpu`), which are inferred and unmeasured, and the store mapping for the 2.0 app and IDE, which is undetermined.
