# Factory Droid: evidence notes (2026-09-29)

Not installed here (no `droid`, no `Factory.app`, no `~/.factory`, nothing running, no power assertion). Everything below comes from docs, the vendor install script, Homebrew cask metadata, the one readable vendor SDK (Python), and one third-party read of the 0.218.2 binary's embedded JS. Latest release today: CLI 0.229.0, Factory App 0.186.0. Row confidence is `documented`, not `verified-locally`.

## Shape

```
Factory App (Electron, Factory.app, bundle ai.factory.desktop [inferred])
  '- agent host unknown: droid child? droid daemon? in-process?   <- not documented

terminal:  droid  (Bun single-file binary, ~/.local/bin/droid)
             '- droid exec --input-format stream-jsonrpc --output-format stream-jsonrpc
                (agent loop; third-party bundle read, 0.218.2)      <- always a child of the TUI
scripts/SDK/CI:  <parent> -> droid exec [...]   (SDK adds stream-jsonrpc both ways)
Zed / JetBrains: editor -> droid exec --output-format acp
daemon:          droid daemon [--remote-access]   (many sessions; SDK example ws://127.0.0.1:37643)
cloud:           Droid Computers, Slack/Linear/Jira delegation -> no local process

sessions: ~/.factory/sessions/-<cwd-with-dashes>/<id>.jsonl
          ~/.factory/sessions/-<cwd-with-dashes>/<id>.settings.json   (rewritten during session)
config:   ~/.factory/{settings.json,settings.local.json,hooks.json}, .factory/... per project
logs:     ~/.factory/logs/
```

## What I checked

- Docs (docs.factory.ai, via `llms.txt` index): hooks, CLI reference, quickstart, settings, IDE integrations, BYOM, Droid Computers, telemetry (index and data reference), missions reference, Factory App overview/quickstart, full changelog.
- Vendor install script `https://app.factory.ai/cli`, read not run: binary `droid`, `~/.local/bin`, `pkill -x droid`, version 0.229.0.
- Homebrew cask JSON for `droid` and `factory` (paths, zap lists, versions).
- Public source: `Factory-AI/droid-sdk-python` (`transport.py`, `_high_level/discovery.py`, `schemas/enums.py`), `Factory-AI/droid-sdk-typescript` (docs and examples only), `Factory-AI/factory` (docs only), `Factory-AI/factory-zed-extension` (manifest only).
- Third-party: rimz `droid-reference.md` (reads the 0.218.2 bundle), `cli-continues` Droid parser and schemas, Agent Safehouse report (docs-derived, no source; used only to note it repeats the `projects/` path).
- Local: `command -v droid`, `ls`/`mdfind` for the app and `~/.factory`, `ps`, `pmset -g assertions`, `tools/agents_probe.py --row registry/agents/droid.json` (0 sessions, correct for nothing running). Process rules also tested on 13 synthetic argv lines: TUI, resume, exec, SDK exec, ACP, daemon match the intended surface; `update`, `--version`, `mcp`, `droid-foo` and the Factory.app binary match nothing.
- Row validated: `tools/validate_row.py registry/agents/droid.json` passes.

## Could not determine

- **Any live behaviour.** No process, session file, hook payload or assertion was seen. All signal thresholds (transcript 30 s, CPU 5%) are guesses, not measurements.
- **What process runs the agent in the Factory App**, and its real bundle id. `ai.factory.desktop` is inferred from the cask zap list (also a legacy `com.electron.factory.plist`). The DMG is 236 MB and I did not download or open it. Hence no process rule for the app.
- **TUI architecture.** rimz (bundle read, 0.218.2) says the TUI spawns a child `droid exec` stream-jsonrpc. The changelog talks of a "TUI daemon session" (v0.105.0) and a "background daemon" (v0.106.0). Either both are the same child, or newer builds route through `droid daemon`. Needs one `ps` on a live TUI.
- Whether the Bun binary's argv[0] is plain `droid` in `ps` (assumed from the installer and `pkill -x droid`).
- Whether the daemon's default port is 37643 (only an SDK doc example) and where it records pid or port.
- Exact power-assertion name/type for Missions and for the app's keep-awake setting, and whether the app setting is on by default.
- Record key names of a real session file: none exists here. Shapes come from the Python SDK (first record `session_start` with `title`, `cwd`, `owner`) and third-party schemas (`message`, `compaction_state`, `todo_state`; settings keys `model`, `tokenUsage`, `assistantActiveTimeMs`, `archivedAt`).
- Whether `assistantActiveTimeMs` in `<id>.settings.json` ticks live during a turn (a possible precise signal). Unverified.
- Whether `~/.factory/projects/` is used by any current build (see below).
- Whether Zed's or JetBrains' `droid exec --output-format acp` writes the same session files (Zed docs say sessions are not restored in the panel).

## Against common belief

1. **Transcript path is contested.** Hooks docs show `transcript_path` as `/Users/.../.factory/projects/.../session.jsonl`, and Agent Safehouse and numbat repeat `~/.factory/projects/`. The vendor Python SDK (last commit 2026-09-24) and the rimz bundle read use `~/.factory/sessions/<cwd-key>/`. `cli-continues` scans both. The row uses `sessions/` with `documented: false`; the hook's `transcript_path` is the only pointer Factory publishes.
2. **No general sleep inhibitor.** Unlike Claude Code's `caffeinate`, Droid's CLI holds a keep-awake only during Missions (`keepSystemAwakeDuringMissions`, default true), and the Factory App has its own keep-awake setting. A missing assertion does not mean idle.
3. **One TUI is two processes.** The TUI always has a `droid exec` child, so "has children" or `tool_children` is always true. Use tree CPU on the outermost `droid`; the probe already keeps the outermost match.
4. **`-r` changes meaning**: `--resume` in the TUI, `--reasoning-effort` in `droid exec`. Do not put `-r` in the exec session-id args. `droid exec` uses `-s/--session-id`, and `--fork` yields a new id, not the current one.
5. **A fresh TUI has no session id in argv.** Only a hook (or the cwd plus newest file) reveals it. Because the probe splits args on spaces, a prompt word equal to `exec` or `daemon` can misroute a TUI.
6. **The best working signal needs setup.** The agent's true state (`idle`, `thinking`, `streaming_assistant_message`, `waiting_for_tool_confirmation`, `executing_tool`, `compacting_conversation`) is only emitted over stream-jsonrpc to the process that owns the exec stream, not to a bystander watching a TUI. For a bystander the options are hooks (`UserPromptSubmit` on, `Stop` off) or file/CPU heuristics.
7. **Interrupt is special.** `Stop` does not fire when the user cancels; the docs say a `Notification` with `idle_prompt` fires instead. The bundle read says `idle_prompt` fires only then (no timed idle), and `auth_success` has no call site. `PostToolUse` fires only on success. A hook-only tracker that waits for `Stop` will hang after a cancel.
8. **`SessionStart` may fire in the child, not the TUI.** Third-party bundle read: skipped when the process mode is `terminal-ui`.
9. **Telemetry is not standard OTEL env.** Variables are `OTEL_TELEMETRY_ENDPOINT` / `OTEL_TELEMETRY_HEADERS` (standard `OTEL_EXPORTER_OTLP_*` are only fallbacks). Metrics only by default, HTTP only; spans only with your own collector and content logging on; no logs signal documented (a third-party report says "metrics, traces, logs"). Factory's own collector receives metrics in parallel. Org settings override the machine. It is a reporting feed, not a live state feed.
10. **Public "source" is mostly docs.** `Factory-AI/factory` is docs-only; the TypeScript SDK repo no longer holds `src/` (only docs and examples). The CLI is a closed-source Bun binary. The Python SDK is the only readable client code.
11. **Homebrew `droid` is a cask, not a formula**, and depends on `ripgrep`. The desktop app is a second cask, `factory`, with its own version line (0.186.0 vs CLI 0.229.0).
12. **Sessions sync to the cloud by default** (`cloudSessionSync: true`), so local files are not the only copy, and archived sessions are marked by `archivedAt` in the settings file, not by moving the transcript.

## Privacy

No session content exists on this Mac and none was read. Third-party and SDK material was read for schema and key names only.

## Verification

Adversarial pass, 2026-09-29. Method: re-fetched every cited URL or command, read the vendor SDK source, the npm tarball and the Zed manifest, and ran the row's process rules through `tools/agents_probe.py` `matches()` on 23 synthetic argv lines. `tools/validate_row.py` passes before and after. Droid is still not installed here, so confidence stays `documented` at most; nothing below was seen on a live process.

Result: 1 process rule repaired, 4 claims corrected in wording, 5 sources added to the row, everything else confirmed. Repairs are in the row (`registry/agents/droid.json`).

### Confirmed

- Executable `droid`, `~/.local/bin`, `pkill -KILL -x "droid"`, VER 0.229.0, download URL layout: install script lines 61-66, 106, 113.
- Cask `droid` (binary to `$HOMEBREW_PREFIX/bin/droid`, zap `~/.factory` and `~/.local/bin/droid`, depends on ripgrep, 0.229.0) and cask `factory` (Factory.app, 0.186.0, auto_updates, zap list including `ai.factory.desktop`). Bundle id remains inferred from the zap list.
- Hook events (nine), notification types, `Stop` not firing on cancel, common stdin fields, `transcript_path` example under `~/.factory/projects/`: docs.factory.ai/harness/hooks.
- Hook locations `~/.factory/hooks.json`, `.factory/hooks.json`, legacy `.factory/hooks/hooks.json`, `hooks` key in settings.json, plugin `hooks/hooks.json`, `allowManagedHooksOnly`, `hooksDisabled`, `showHookOutput`, `/hooks`.
- CLI reference: `droid --resume [id]` (alias `-r`), `--fork`, `droid exec -s/--session-id`, `-r` = `--reasoning-effort` in exec, `daemon`, `update`, `search`/`find`, `mcp`, `plugin`, `computer`, `rules`, `-v/--version`, `--list-tools`, install via curl, `brew install --cask droid`, `npm install -g droid`.
- Zed and JetBrains args `["exec","--output-format","acp"]`; VS Code extension `Factory.factory-vscode-extension`; `~/.factory/logs/`; Zed does not restore sessions.
- BYOM: `droid daemon --remote-access`, `relay.factory.ai`, Factory App Remote Access toggle stays connected while the app runs.
- TypeScript SDK doc: `ws://127.0.0.1:37643`, daemon sessions "can run turns concurrently".
- Python SDK: `_DEFAULT_EXEC_ARGS`, `asyncio.create_subprocess_exec`, `_sessions_root()`, slug rule (`"-" + resolved path with / to -`), `session_start` filter, sibling `<id>.settings.json`, `archivedAt`, root-level `.jsonl` scan; `DroidWorkingState` six values and `droid_working_state_changed`.
- Telemetry: `OTEL_TELEMETRY_ENDPOINT`/`_HEADERS` with `OTEL_EXPORTER_OTLP_*` fallback, `{endpoint}/v1/metrics`, metrics only by default, spans need a customer collector plus `OTEL_LOG_MESSAGE_CONTENT`, org `telemetry` block wins and is ignored elsewhere, delta temporality, 60000 ms, `genai` format replaces `droid.*`, `service.name=cli`. No logs signal appears in the docs.
- Keep-awake: `keepSystemAwakeDuringMissions` default true; changelog CLI v0.60.0, v0.178.0 / Desktop v0.135.0, v0.176.0.
- Settings: `cloudSessionSync` default true, `awaitingInputSound`, `completionSound`, `settings.local.json` merge.
- Third-party: rimz reference (0.218.2 bundle read: exec child of TUI, SessionStart skipped in `terminal-ui`, `idle_prompt` only after interrupt, `visibility` values, `AskUser` tool_use, session paths); cli-continues (`session_start`, `message`, `todo_state`, `compaction_state`, settings `assistantActiveTimeMs`/`model`/`tokenUsage`, scans both `projects/` and `sessions/`).
- Public source is thin: `Factory-AI/factory` tree is `.github .gitignore README.md docs`; `Factory-AI/droid-sdk-typescript` has docs, examples, scripts and config but no `src/`.
- Local: `command -v droid` empty, no `~/.factory`, no `Factory.app`, no `~/.local/bin/droid`, zero matching processes.

### Corrected

- **Process rule, TUI surface (false positive).** `path_contains: "/.local/bin/droid"` is a substring test: `/Users/x/.local/bin/droidcam` and `/Users/x/.local/bin/droid-helper` both classified as a Droid TUI. The entry was redundant (`names: ["droid"]` already covers the installed binary), so it is removed. `/Caskroom/droid/` stays because it ends in a slash.
- **Hook config location.** The row listed `settings.local.json` as a hooks location. The hooks docs name only `settings.json`. Reworded as inferred from the settings merge hierarchy, not documented.
- **`transcript_write` meaning.** It said the newest write to the `.jsonl` or the sibling `.settings.json` counts. The probe only stats the `per_session` `.jsonl`. Reworded so a detector does not assume the settings file is watched; whether the settings file ticks live stays unverified.
- **Gotcha 1 ("every TUI has an exec child").** Stated as fact. It rests on one third-party bundle read of 0.218.2, and the official changelog speaks of a "TUI daemon session" (v0.105.0) and "TUI-spawned daemon" (v0.60.0). Reworded as expected, unverified; harmless to the probe either way because the child is dropped when its parent matches.
- **Gotcha 4 (misrouting).** Understated. `args_contain` is a substring test, so `droid execute the plan` matches the exec surface and `droid explain the daemon design` matches the daemon surface; and `exclude_args` is an exact-element test, so `droid fix the search bug` matches nothing (a live TUI is missed). Reworded with the real rule. Cannot be repaired in the row; it needs a probe change.

### Added (evidence the row was missing)

- npm `droid` is a node shim (`#!/usr/bin/env node`, `spawnSync` of the platform binary; postinstall may hard-link the binary instead). `node .../bin/droid` is not matched, the native `droid` child is. No detection gap.
- Zed's extension downloads its own pinned CLI 0.96.0 and runs `./droid exec --output-format acp` (argv[0] `./droid`, matches on basename). An ACP process under Zed may be an old build.
- `droid resume` and `droid doctor` exist (rimz `droid --help` read on 0.218.2), but the official CLI reference lists neither. The row's use of both is now cited as third-party.

### Unsupported (kept, flagged as guesses)

- `transcript_write` within 30 s and `tree_cpu` floor 5%: no measurement exists. The row already says so; they stay guesses.
- Power-assertion name for Missions and for the app's keep-awake: not documented, not observed.
- Bundle id `ai.factory.desktop`: inferred from the cask zap list, never read from an Info.plist.
- What runs the agent inside the Factory App, and the app's own `droid` child or daemon: undocumented. The changelog mentions app daemon reconnect fixes, which hints at a local daemon; not proven. No process rule for the app, correct.
- `argv[0]` of the Bun binary in `ps` is plain `droid`: supported by `pkill -x droid` (comm name) and the Zed `./droid` invocation, not observed.
- Daemon default port 37643: SDK doc example only.
- Any record shape, `assistantActiveTimeMs` behaviour, AskUser-without-result transcript signal: from third-party schemas, unverified on a live file.
- `droid resume` in the TUI label and `resume` as a session-id word: third-party only.

### Confidence

`documented`, unchanged and at the ceiling. The static facts (install path, process name, subcommands, hooks, telemetry, session layout per vendor SDK) are backed by vendor docs or source; every runtime behaviour is unobserved.
