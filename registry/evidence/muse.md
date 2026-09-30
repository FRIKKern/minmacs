# Muse Code (Meta) - evidence notes

Date 2026-09-30. Muse Code is not installed on this Mac and I ran nothing. Row confidence is `documented`; nothing here was seen working.

## What I checked

- Official docs, fetched with curl and stripped to text: `dev.meta.ai/docs/muse-code` and its subpages `auth`, `permissions`, `interactive`, `workflows`, `configuration`, `extending`, `session-messaging`, `rewind`, `changelog` (releases 1.1.1 to 1.4.1), plus `install.sh` and `https://api.meta.ai/muse-launcher.sh` (read, not run). The docs site blocks Firecrawl and WebFetch only returns a summary, so curl was the way in.
- Public source: `github.com/meta-models/muse-code-sdk` (commit a7c10c5, 2026-09-21). It holds the TypeScript and Python SDK and the generated protocol types. The CLI is closed source (its real binary is called `tbh` in the SDK tests; `TBH_*` env vars).
- Third party that reads the real store: `github.com/skzv/ccmux` (commit 4224543) and `ccmux.ai/docs/muse-code`. This is my only source for the session layout and the lock file.
- Homebrew cask JSON for `muse-code`, and the SigNoz monitoring page (updated 2026-09-13).
- Local: `which muse`, `ls ~/.local/share/muse ~/.config/muse ~/.muse`, `ls /Applications`, `ps` for muse. All empty. `tools/agents_probe.py --row registry/agents/muse.json` finds nothing, as expected. I also fed `matches()` ten synthetic argv vectors (launcher path, plain `muse`, Caskroom path, `exec --session-id U`, `serve`, `mcp login`, `--version`, the bash launcher script). They classify as intended, with the caveats at the end.

## Surfaces

| Surface | Process as `ps` shows it |
|---|---|
| Launcher install (`curl https://dev.meta.ai/install.sh \| sh`) | `~/.local/bin/muse` is a bash script that `exec`s `~/.local/bin/muse-bin-<version>`, so argv[0] is that full path, e.g. `muse-bin-1.4.1-R4503.1`. The name changes each release; only `/muse-bin-` is stable. |
| Homebrew cask | `$HOMEBREW_PREFIX/bin/muse` links `muse-aarch64-macos` or `muse-x86-macos`. argv[0] is whatever was typed, normally `muse`. |
| `muse exec` | One-shot, alive means working, `--json` for JSONL on stdout. |
| `muse serve` | Session-protocol host over stdio for the SDK, ACP adapters (`muse-acp`, Zed) and third-party GUIs. Can hold several sessions. |

No app bundle, no bundle id, no official desktop app or IDE extension. GUIs I saw (Helicon, a VS Code "Unofficial" extension, a "Muse Code GUI") are third party and drive `muse serve`.

## Answers

- **Session mapping.** Only `muse exec --session-id <uuid>` puts an id in argv. `muse resume <id|name>` is positional, which `session_id_args` cannot express. A fresh TUI session has no id anywhere. Inferred side channel: `lsof -p <pid>` should show `.session.lock` open (ccmux takes an exclusive `flock` on it to know a session is active; the changelog says the resume picker names the holding pid). I did not see this on a live process.
- **Store.** `$XDG_DATA_HOME/muse/sessions` or `~/.local/share/muse/sessions`, laid out `YYYY/MM/DD/<uuid>/session.jsonl`, `.session.lock` beside it, subagent logs as nested `session.jsonl`, a derived cache in `sessions/.msp-view-v1/<id>`, and a "session index" database (changelog: "session index unavailable: database is locked"). JSONL, append-only, documented=false because dev.meta.ai never states the path. Record key names: `schema_version, id, stream, sequence, recorded_at (microseconds), record_type, durability, causation_id, payload_type, payload_schema_version, payload`. I read key names from ccmux's synthetic fixture only.
- **Working.** No power assertion and no `caffeinate` child: the words `sleep`, `caffeinate`, `inhibit`, `assertion` appear on none of the docs pages I fetched or in the SDK. So `power_assertion` and `child_process` are out. The exact signal is a hook pair `UserPromptSubmit` (carries `turn_id`) to `Stop`, with `Interrupt` on Esc, but it needs the user to edit `settings.json`. Without hooks the row falls back to a raise-only transcript write, a shell tool child (inferred), and CPU.
- **Waiting on the human.** Hooks `Notification` ("fires when the agent needs your approval") and `PermissionRequest`. `muse serve` clients get an attention flag for a pending approval or input, and `approval/requested` frames, but only when attached. In the store, the changelog says a crash leaves a pending approval "unresolved on resume", so approval records exist; I found no record names. Workspace trust and the auth prompt block at start.
- **Hooks.** 15 events in the docs list plus `Interrupt` (changelog only). Config: `hooks` block in `~/.config/muse/settings.json`, project `.muse/hooks.json` after trust, managed file via `managed_hooks_path`. Command hooks get JSON on stdin and a scrubbed environment; they run outside the sandbox.
- **OpenTelemetry.** No documented native switch, so `otel: false`. SigNoz says Muse "ships its own OpenTelemetry exporter" but gives no setting, and builds its integration on hooks. Muse attaches a W3C `meta.traceparent` to each model call. `TBH_DISABLE_TELEMETRY=1` turns off product telemetry; `MUSE_TRANSPORT_TRACE=1` prints provider lines to stderr. Hook runs are logged locally under `~/.local/share/muse/local-tracing/bootstrap/*.log` (SigNoz).

## Could not determine

- Any live behaviour: process tree during a turn, whether shell tools are direct children or sit under `sandbox-exec`, CPU, whether the store is quiet during a long model call.
- The record that closes a run in `session.jsonl`. The fixture shows `runtime.session` / `run` / `started`, `model_completed`, `assistant_message_committed`; no terminal kind.
- Whether `StopFailure` (used by the SigNoz script) is a real event, and whether a question to the user fires `Notification`.
- Whether the process holds `.session.lock` open for the whole session, and the short-form flags (`-V`, `-h`).
- The Intel artifact name in a launcher install (Homebrew calls it `muse-x86-macos`; the launcher only says `x86_macos`).

## Contradicts common belief

- The hint "launcher execs muse-bin-<version>" is right, but the name is versioned, so `names: ["muse"]` only catches the Homebrew form. A name-only row would miss every launcher install; a path-only row would miss brew.
- "Meta's CLI is open source": only the SDK is. Its source calls the binary `tbh`.
- SigNoz says a project `.muse/hooks.json` is "silently ignored"; the official docs say project hooks load from it after trust. Unresolved.
- Sessions are not under `~/.muse` or `~/.config/muse`; they are dated directories under `~/.local/share/muse/sessions`.
- The docs call sessions an "event log"; on disk it is one `session.jsonl` per session and per subagent.
- Muse runs four background observer agents by default (memory, skill, goal, verification), and `/goal` queues follow-up turns after a turn ends. A process can make model calls with no visible turn, and a goal can restart work after `Stop`.
- The `muse serve` surface uses `args_contain: ["serve"]`, which the probe matches as a substring, so `muse exec "observe the repo"` gets the daemon label (same row and signals, so only the label is wrong). `exclude_args` is an exact match on any word, so a session named `config` is hidden.
- The Apple-silicon macOS package does not include the workflow engine, so `/workflows` is absent there (docs).
- "Grok Bot", mentioned in the request, is not covered by this row. `registry/agents/grok-build.json` already exists and I did not touch it.

## Verification

Independent re-check, 2026-09-30. `tools/validate_row.py registry/agents/muse.json` printed `ok` before and after. I re-fetched every URL with curl (install.sh, muse-launcher.sh, channel manifest, cask JSON, all docs pages incl. /auth, SigNoz page), re-cloned `meta-models/muse-code-sdk` (a7c10c5) and re-read `skzv/ccmux` (4224543). Muse Code is not installed here, so confidence stays at most `documented`; nothing was observed on a live process.

Confirmed
- Product description, `muse` / `muse exec` / `muse serve` / `muse schema`, native binary on path, no desktop app documented (/docs/muse-code).
- Launcher: `install_dir=${MUSE_INSTALL_DIR:-$HOME/.local/bin}`; `target="$dir/muse-bin-$version"`; final `exec "$binary" "$@"`; version pattern `^[0-9]+\.[0-9]+\.[0-9]+-R[0-9]+(\.[0-9]+)?$`; stable channel prints `1.4.1-R4503.1`. The update candidate `$work/muse-bin` is never executed and has no trailing dash, so it cannot match `/muse-bin-`. The background update runs in a bash subshell, so argv[0] is bash and does not match.
- Homebrew cask: `muse-aarch64-macos` (Apple silicon) and `muse-x86-macos` (Intel variations), both linked as `muse`; zap paths `~/.config/muse` and `~/.local/share/muse`.
- Settings at `~/.config/muse/settings.json`, `schema_version` must be 1, hooks block and `managed_hooks_path`; auth at `~/.config/muse/auth.json`, `MUSE_AUTH_PATH` override (launcher lines 19-25).
- Store path and layout `sessions/YYYY/MM/DD/<uuid>/session.jsonl` (ccmux `SessionDir` requires exactly 5 path parts), `.session.lock`, `.msp-view-v1/<id>`, nested subagent logs. The glob therefore matches parents only. `documented=false` is right.
- `muse exec --session-id <uuid>` (docs, /extending); `--no-session-log` disables resume (docs, /configuration); append-only event log (/interactive).
- 15 hook events, three sources, Notification "fires when the agent needs your approval", hooks outside the sandbox, no `muse hooks` family; Interrupt hook added in changelog 1.4.0; project hooks load after trust; `muse serve` attention flag (changelog).
- Seatbelt on macOS verified once at startup, `/bin/bash` in the denial example (/permissions).
- Four observer agents and `/goal` follow-up turns (/extending, /interactive); Apple-silicon package lacks the workflow engine (/workflows).
- `muse serve` is how the SDK spawns the host (`["serve"]` in the Python SDK docstring); `turn/started`, `turn/completed`, `approval/requested` cases in `facade/session.ts`; `TBH_DISABLE_TELEMETRY`, `TBH_CREDENTIAL_BACKEND`, `TBH_DISABLE_FEATURE_CONFIG`, `XDG_DATA_HOME` in `qa/recorder.ts`; `MUSE_TRANSPORT_TRACE` in the SDK CHANGELOG.
- ccmux `muse.toml` rules (workspace trust prompt, `◇/◆ Thinking` working, `⟩` composer), captured from 1.0.3, third party.
- SigNoz: "ships its own OpenTelemetry exporter", hook-based script, `meta.traceparent`, `StopFailure` handled by the script, local-tracing log path.
- Exclusion subcommands that exist in the docs: `auth`, `config`, `export`, `init`, `login`, `logout`, `mcp`, `schema`, `skills`, `trace`, `workflows`.

Corrected
- Session record shape: the ccmux fixture's first line is a retained-frame wrapper (`retained_frame`, `frame_schema_version`, `children`), not a record. Only lines 2-8 have the record keys. Source claim rewritten. The fixture is synthetic.
- Resume source: the /extending page only says `muse resume` is interactive. Positional `<id>` and `<name>` come from the changelog. Evidence field fixed.
- No-sleep claim: the SDK does contain the word sleep (`asyncio.sleep` in tests and spawn helper), so "no hits in the SDK" was false as written. Reworded to what is true: no docs mention, SDK says nothing about system sleep, CLI closed source. Kind changed to official-docs. This is absence of documentation, not proof.
- SigNoz page date is "Last updated September 14, 2026", not 09-13.
- `tbh` path: the SDK searches `target/debug/tbh` and `target/release/tbh`; claim no longer names only release.
- Hook payload: JSON on stdin and the field names come only from the third-party SigNoz script; official docs describe only "a cleared environment with a small allowlist". `hooks.config` now says so and records the unresolved `.muse/hooks.json` contradiction.
- Process patterns: the daemon surface `args_contain: ["serve"]` is a substring test, so `muse exec "how does serve work"` matched the daemon surface (score 2 beat the TUI's 1). Fixed by adding `exec`, `resume` and the TUI subcommand list to the daemon `exclude_args`. Re-tested with `agents_probe.matches` on synthetic argv: `muse exec "how does serve work"` now TUI only; `muse serve`, launcher `serve` and Caskroom `serve` still daemon.

Unsupported (kept, marked inert or inferred)
- `-h`, `-V`, `--help`, `--version` in exclude_args: dev.meta.ai does not print them. `plugins`: only a `/plugins` slash command is documented, no `muse plugins`. Harmless vetoes.
- `tool_children`: shell as a direct child is inferred; the sandbox may add a wrapper. Not seen live.
- `transcript_write` window, `tree_cpu` floor, and the `PermissionRequest` timing: guesses or undocumented.
- Whether the process holds `.session.lock` for its whole life, and whether the `⟩` composer text is still current after 1.0.3.

False-positive review of the patterns
- `names: ["muse"]` compares the base name of argv[0] only, so any unrelated program named `muse` (a music tool, a shell alias run by full path) matches the TUI surface. The command line cannot tell them apart. Row notes already say to confirm with an open `.session.lock` via lsof. This is the weakest part of the row.
- `path_contains "/muse-bin-"` is a substring: a directory such as `/opt/x/muse-bin-tools/run` would match. Only the launcher's versioned file has been seen. Kept because a version-agnostic exact form is not expressible.
- The Caskroom fragments only match when the real path is executed; the normal `muse` symlink shows argv[0] `muse` and matches by name.
- `muse mcp`, `muse auth`, `muse export` and friends are vetoed on both surfaces; `muse resume` and `muse exec` are TUI-labelled by design.
- Verdict: row is trustworthy at `documented` for launcher and Homebrew installs, with the bare-name collision risk stated. Confidence unchanged.
