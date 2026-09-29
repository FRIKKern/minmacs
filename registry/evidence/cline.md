# Cline standalone (CLI 3.x, Desktop, SDK hub): evidence notes (2026-09-29)

Not installed here, nothing running. Confidence is `documented`: docs and public source only, no live turn seen, no real `ps` line seen. Row: `registry/agents/cline.json`, passes `tools/validate_row.py`.

## Shape

```
npm i -g cline
  node .../cline/bin/cline            (wrapper, argv[0] = node, not matched)
    '- .../@cline/cli-darwin-arm64/bin/cline   or  .../cline/bin/.cline (hard link)
         = compiled Bun binary: TUI / one-shot / --acp

Cline.app (bot.cline.app)  Contents/MacOS/cline-app  (Tauri)
    '- Contents/MacOS/code-sidecar   (Bun, hub client, serves the webview)

either binary, when it needs the hub, spawns DETACHED:
    <same binary> --cline-hub-daemon --cwd <ws>      env CLINE_RUN_AS_HUB_DAEMON=1
    = hub daemon: singleton, 127.0.0.1:25463, runs the agent loop for hub sessions
        '- /bin/bash -c ...   (run_commands tool, direct child of the DAEMON)

all of them:  ~/.cline/data/db/sessions.db            (SQLite, WAL, live status + pid)
              ~/.cline/data/sessions/<id>/<id>.messages.json
```

Who runs the turn (source: `host.ts`, `session-runtime.ts`, `run-agent.ts`):

| Launch | Loop runs in |
|---|---|
| `cline`, `cline "prompt"`, `--json` with a compatible hub already up | hub daemon; CLI is a client |
| same, no hub yet | the CLI process (hub is prewarmed in the background) |
| `--yolo`, `--data-dir` (sandbox) | the CLI process, always |
| `--zen` | hub daemon; CLI exits at once |
| Desktop | hub daemon (`strategy: require-hub`); sidecar is a client |
| `--acp` | same choice as the TUI |

## What I checked

- Read first: `registry/schema.json`, `registry/agents/claude-code.json`, `tools/agents_probe.py`, `registry/README.md` (sections 3 and 4), `tools/validate_row.py`, and the existing `vscode-agents` row and evidence (it already covers Cline 4.x in VS Code).
- Fetched the whole `cline/cline` tree (GitHub API tree, 4866 paths) and read raw files: `apps/cli` (bin/cline, postinstall, program.ts, main.ts, index.ts, doctor.ts, session-runtime.ts, run-agent.ts, hub.ts, CHANGELOG, DISTRIBUTION), `apps/examples/desktop-app` (tauri configs, Cargo.toml, main.rs, macos_notification.rs, sidecar/index.ts, ARCHITECTURE.md, notifications, CHANGELOG), `sdk/packages/core` (hub daemon, host.ts, local-runtime-host.ts, persistence-service.ts, bash executor, hooks, telemetry), `sdk/packages/shared` (paths, db schema, session records, hub-daemon-env, telemetry-config), and the docs pages `docs/cli/cli-reference.mdx`, `docs/customization/hooks.mdx`, `docs/sdk/plugins.mdx`, `docs/sdk/architecture/hub-spoke.mdx`, `docs/enterprise-solutions/monitoring/opentelemetry.mdx`.
- npm registry (`cline`, `@cline/cli-darwin-arm64`) and GitHub releases API for versions and dates.
- Local, read-only: `which cline`, `ls ~/.cline ~/Documents/Cline /Applications/Cline.app`, `ps | grep`, `mdfind` for the bundle id. All empty.
- Synthetic probe check (`tools/agents_probe.py` `matches()` and `session_id()` on hand-written ps lines, cwd `minmacs`):

| ps line | Result |
|---|---|
| `.../@cline/cli-darwin-arm64/bin/cline` | tui |
| same `--id 1790000000000_abcde` | tui, session id `1790000000000_abcde` |
| same `--yolo fix the tests` | tui |
| same `update the readme` | tui (word subcommands are deliberately not vetoed) |
| `.../cline/bin/.cline` | tui |
| `.../bin/.cline --cline-hub-daemon --cwd /Users/x/proj` | daemon (hub) |
| `.../bin/cline --cline-hub-daemon ...` | daemon (hub) |
| `.../bin/cline --acp` | ide (ACP) |
| `.../bin/cline --version`, `--zen refactor` | none |
| `node .../cline/bin/cline --id abc` (wrapper) | none, correct |
| `node .../cline/dist/cli.mjs` (CLI 2.x) | none, by design |
| `/Applications/Cline.app/Contents/MacOS/cline-app` | gui |
| `.../Cline.app/Contents/MacOS/code-sidecar` | daemon (sidecar) |
| `.../code-sidecar --cline-hub-daemon --cwd ...` | daemon (hub) |
| `/Applications/Cline Beta.app/Contents/MacOS/cline-app` | none (space splits argv[0]) |
| `claude --session-id z`, `/bin/bash -c ls` | none |

  `agents_probe.py --row registry/agents/cline.json` on this Mac: 0 sessions.

## Answers by question

- **Process names and paths**: TUI/ACP/daemon binary base names `cline` (npm platform package) and `.cline` (postinstall hard link); Desktop `cline-app` and `code-sidecar`. Bundle ids `bot.cline.app`, `.beta`, `.nightly`, `.dev`.
- **Process to session**: `--id <session-id>` only on resume; a fresh session has no id in argv. `sessions.db` holds `pid`, `cwd`, `source`, but `pid` is the daemon's for hub sessions, and the daemon serves many sessions. So process to session is by pid+cwd from the DB, and ambiguous for the daemon.
- **Store**: SQLite index/status `~/.cline/data/db/sessions.db`; JSON transcript `~/.cline/data/sessions/<id>/<id>.messages.json`. Shared with the VS Code extension and JetBrains (`source` column). Undocumented in the sense that the docs give a different path.
- **Turn in progress**: `sessions.status = 'running'` with a live pid. Written at turn start and end, so it is exact but needs SQL, which the probe cannot run. The transcript file is written only at the end of each agent iteration.
- **Waiting on the human**: `status = 'pending'` while a tool approval is awaited. Not for `ask_question`. Desktop also posts OS notifications (`approvalNeeded`, `questionAsked`). No hook for it.
- **Hooks**: file hooks (nine active event files) and plugin code hooks; config paths in the row.
- **OpenTelemetry**: yes, but see below.

## Could not determine

- Everything about a live run: real `ps` argv of the compiled Bun binary (does Bun rewrite argv[0]? does `process.execPath` equal the path the wrapper passed?), real timing of the `running`/`idle` writes, whether `pending` really shows during an approval on a live turn. I did not download or run the binary (rule: do not install).
- Whether `caffeinate` or an assertion appears: none in source (negative grep), unobserved.
- Where JetBrains runs its agent (the plugin repo is separate; not read). VS Code is the `vscode-agents` row.
- Whether `CLINE_HOOKS_DIR` / `--hooks-dir` is read anywhere. `main.ts` sets it; no reader in `sdk/packages/{core,shared,agents}`, `apps/cli`, or the desktop sidecar. `sdk/packages/llms` and other packages were not grepped.
- Ordering of `PreToolUse` versus the approval prompt.
- Whether the hub daemon ever exits by itself: no idle shutdown found; not proven.
- The CLI 2.x store layout (2.0.0 to 2.18.0, `dist/cli.mjs`). Not matched by the row.
- Beta/Nightly/Dev desktop channels: matched only by bundle id in principle; the reference probe cannot match them because of the space in the path.
- Hub WebSocket status stream: needs the token in `~/.cline/data/locks/hub/production.json`. Not read, not recommended.
- OTLP collector behaviour of the shipped binaries: build script says values are inlined; not tested.

## Contradicts common belief, or another file

- **"Cline CLI 2.0"**: stale. The `cline` package is 3.0.65 (2026-09-24); 3.0.0 shipped 2026-05-12 as a compiled Bun binary. 2.x was a Node script (`dist/cli.mjs`).
- **The window you see is not the worker.** The TUI and the desktop app are hub clients. The turn runs in a detached singleton daemon (same binary, `--cline-hub-daemon`), and shell tool children hang off it. CPU or children of the CLI or `cline-app` say little in hub mode. `--yolo` and sandbox runs are the exception and stay in-process.
- **Docs describe "spokes"; source has none.** `hub-spoke.mdx` says a spoke worker process runs the loop; the hub daemon itself hosts `LocalRuntimeHost` (`hub-server-transport.ts`, `runtime-handlers.ts`, telemetry header comment).
- **Docs and source disagree on paths**: docs put `sessions.db` in `~/.cline/data/sessions/`, hub locks in `~/.cline/locks/hub/owners/` and the log in `~/.cline/logs/`; source uses `data/db/sessions.db`, `data/locks/hub/production.json`, `data/logs/hub-daemon.log`. The row follows source. This also stands in `vscode-agents`.
- **`vscode-agents` says Cline stays `running` during an approval. Source says it goes `pending`** (`local-runtime-host.ts` lines 841-862; `markTurnPending` has one caller). Worth correcting in that row, which I was told not to edit.
- **CLI approves everything by default**: `--auto-approve` defaults to true, so a monitor should not expect approval waits in normal CLI use.
- **Setting `OTEL_*` in your shell does not enable OTel in a shipped binary.** The build inlines those names at compile time (`build.ts`, `build-sidecar-bin.ts`). The `vscode-agents` row lists `CLINE_OTEL_*` for the extension, which is a different code path; the SDK code uses plain `OTEL_*`. Only org remote config, or embedding the SDK, gives a user-controlled collector.
- **Hooks page is a pointer**: `docs/customization/hooks.mdx` now says "See SDK Plugins". The file-hook scheme (event-named scripts) is still in code. The `PreCompact` file is accepted but maps to no event, so it never runs. Run-start hook control (cancel, context injection) is inert in the CLI (changelog 3.0.63).
- **Terminal title carries no state** (`Cline` or `> <last prompt>`), unlike Claude Code's busy glyph.
- **Probe dedupe hides the daemon.** `tools/agents_probe.py` keeps only the outermost matched process. The detached daemon stays a child of the CLI or sidecar that spawned it while that parent lives, so it is dropped until the parent exits. Desktop is covered by summing the tree under `cline-app`, but a CLI-started daemon is invisible while its TUI is open. A fix needs "detached child with `--cline-hub-daemon`" to be exempt from the dedupe.
- **Word subcommands are not excluded on purpose.** The probe splits argv on spaces, so an exclude list containing `update`, `hub`, `history` or `config` would veto prompts like `cline update the docs`. `cline auth`, `cline hub status` and similar appear as short-lived idle sessions.

## Verification

Adversarial pass, 2026-09-29. Method: `tools/validate_row.py` (ok before and after), every `sources` entry re-fetched or re-run, `cline/cline` cloned shallow into the scratchpad (commit 647d8cb, 2026-09-29) and grepped, npm registry and Homebrew formula fetched, and the real Desktop release bundle listed and inspected. Confidence stays `documented`: no Cline is installed here (`which cline` printed `cline not found`, `ls ~/.cline` and `ls /Applications | grep -i cline` empty, `ps` shows nothing), so nothing can be `verified-locally`.

Deviation to disclose: to read the shipped Desktop bundle I ran `gh release download desktop-v0.0.37 -R cline/cline -p Cline_0.0.37_universal.app.tar.gz` (131 MB, into the scratchpad), `tar tzvf`, `tar xzf` of three members only, `plutil -p`, `file` and `strings`. Nothing was installed, opened or executed. `git clone --depth 1` and `brew info cline` were also run. Those go beyond the listed read-only commands but change nothing outside the scratchpad.

### Row edits made

1. **Corrected: tui and ide surfaces matched any executable named `cline` or `.cline`.** The probe ORs `names` with `path_contains`, so the path pattern never narrowed anything. Reproduced with `/opt/other/cline` and `/usr/bin/some/cline --foo` (both matched tui); the vendor's own 1.x Go binary is also called `cline`. Both surfaces now match by path only: `/@cline/cli-darwin-` and `/node_modules/cline/bin/.cline`. The daemon surface keeps names because the `--cline-hub-daemon` argument is the discriminator there.
2. **Corrected: `--kanban` added to the tui `exclude_args`.** It makes the CLI launch the separate `kanban` app (`apps/cli/src/commands/kanban.ts`, `program.ts`), not an agent turn.
3. **Corrected: docs-versus-source path claim was too broad.** `docs/sdk/architecture/hub-spoke.mdx` does put the hub log in `~/.cline/logs/`, but `docs/cli/cli-reference.mdx` puts it at `data/logs/hub-daemon.log`, which is what the source does.
4. **Corrected: `connect` subcommand claim.** The label said word subcommands are short-lived. `cline connect <adapter> ... -i` is how detached connector processes are launched (`apps/cli/src/connectors/common.ts`), and those are long lived. They still show as an idle session; not excluded, because `connect` is an ordinary word in a prompt.
5. **Added: ACP mode defaults `--auto-approve` to false** (`docs/cli/cli-reference.mdx` line 74), so `pending` is common there. The row said only that the CLI default is true.
6. **Added sources:** real release bundle, the false-positive reproduction, connect/kanban, ACP default, Homebrew formula.

### Claims, one by one

| # | Claim in the row | Verdict | Basis |
|---|---|---|---|
| 0 | One engine across CLI, Desktop, VS Code, JetBrains, SDK | confirmed | `README.md` lines 51-107 |
| 1 | CLI 3.0.65 on 2026-09-24, compiled Bun binary in per-platform packages; 2.0.0 to 2.18.0 were `dist/cli.mjs` | confirmed | npm registry: latest 3.0.65 (time 2026-09-24T05:55:56Z), 3.0.0 on 2026-05-12, 2.0.0 on 2026-02-02 and 2.18.0 on 2026-05-01 with `bin dist/cli.mjs`, `@cline/cli-darwin-arm64` has os darwin, cpu arm64, bin `bin/cline` |
| 2 | Wrapper order CLINE_BIN_PATH, cached `bin/.cline`, platform package; `spawnSync`; hard link from postinstall | confirmed | `apps/cli/bin/cline`, `script/postinstall.mjs` (`fs.linkSync`, copy fallback) |
| 3 | Desktop: Tauri, identifier `bot.cline.app` and three variants, `cline-app`, sidecar `code-sidecar` with no args, piped stdio | confirmed, and upgraded from inferred to observed | tauri confs; `main.rs` `Command::new(binary)` with stdin null and stdout/stderr piped, no `.arg`; bundle `Contents/MacOS/{cline-app,code-sidecar}`, `CFBundleExecutable=cline-app`. Dev-only note: `macos_notification.rs` builds a dev bundle with a `cline-app` symlink, so the source alone was not proof for the release; the tarball is. |
| 4 | Hub daemon spawned detached as `<execPath> --cline-hub-daemon --cwd ...`, env `CLINE_RUN_AS_HUB_DAEMON=1`, sentinel scrubbed | confirmed | `hub/daemon/index.ts` lines 70, 401-466; `hub-daemon-env.ts` lines 44-45; the sidecar binary contains `--cline-hub-daemon` |
| 5 | `cline doctor` uses `pgrep -fal -- --cline-hub-daemon` and sidecar patterns | confirmed | `doctor.ts` lines 171, 250, 264-274 |
| 6 | Hub daemon hosts `LocalRuntimeHost`; docs describe spokes, source has none | confirmed | `hub-server-transport.ts` line 277, `runtime-handlers.ts` line 78, `hub-spoke.mdx`; a negative claim about the whole repo, not exhaustively proven |
| 7 | Runtime selection: auto uses hub if compatible else local plus prewarm; yolo and `--data-dir` force local; Desktop is `require-hub` | confirmed | `host.ts` lines 60-215, `session-runtime.ts` lines 149-160, `run-agent.ts` 168-175, `desktop-app/sidecar/context.ts` lines 1295-1306 |
| 8 | Flags `--id`, `--zen`, `--acp`, `--auto-approve` default true | confirmed, with the ACP exception added | `program.ts`, `cli-reference.mdx` |
| 9 | `sessions.db` schema, WAL, `db/sessions.db`, pid, statuses, sources | confirmed | `sqlite-db.ts` lines 188-229 and 355, `sqlite-session-store.ts`, `paths.ts`, `records.ts`, `types/common.ts` |
| 10 | Transcript `<id>/<id>.messages.json`, rewritten at `iteration_end` | confirmed | `session-artifacts.ts`; sub-agent and team files use other stems inside the root session directory, which the glob also catches (harmless) |
| 11 | Docs and source disagree on paths | corrected | see edit 3 |
| 12 | running at turn start, idle at end, pending only during approval, dead pid to failed | confirmed | `local-runtime-host.ts` lines 841-862, 1850, 1882, 2279-2325; `persistence-service.ts` lines 430-470. The reconciler runs at host creation and on reads, so a raw SQL reader can see a stale `running` row: keep the pid check |
| 13 | Shell tool is a detached direct `/bin/bash` child; no caffeinate or power assertion | confirmed | `bash.ts` line 733 `spawn(config.executable, config.args, {detached: !isWindows})`, `shell.ts` `getDefaultShell`; source grep for `caffeinate|powerSave|IOPM|keep.?awake` empty; the same strings are absent from both shipped Desktop binaries |
| 14 | File hooks: names, extensions, search paths, PreCompact maps to nothing, hooks page is a pointer | confirmed | `hook-file-config.ts`, `paths.ts` lines 487-501, `hooks.mdx` (143 bytes, "See details under SDK Plugins"), `CHANGELOG.md` 3.0.63 |
| 15 | Code hooks and stages | confirmed | `docs/sdk/plugins.mdx` |
| 16 | Desktop notifications, four events, default enabled, app id = identifier | confirmed | `desktop-notifications.ts` lines 15-43, `main.rs` line 1206 |
| 17 | OTEL_* inlined at build time, hub service `cline-hub-daemon`, remote config route | confirmed as source; the "no-op in a released binary" conclusion stays inferred | `build.ts` lines 33-53, `build-sidecar-bin.ts`, `telemetry.ts` line 43, `opentelemetry.mdx`. Not tested on a running binary. The docs call gRPC the default; `telemetry-config.ts` defaults to `http/json`. Not a row claim, noted here. |
| 18 | Nothing Cline installed or running here | confirmed | `which cline` printed `cline not found`; `ls ~/.cline` No such file; nothing in `/Applications`; `ps` empty |
| 19 | Synthetic probe check | corrected | table superseded by the one below |
| - | `--hooks-dir` / `CLINE_HOOKS_DIR` has no reader | unsupported as stated, kept as "not found" | `main.ts` line 798 sets it; a repo-wide grep now finds only `apps/vscode` code with its own `hooksDir`, still no reader in the SDK or CLI. Left as an open question in the row |
| - | `ask_question` does not flip status to pending | unsupported (inferred by absence), left marked as inferred | no reader of `markTurnPending` other than the approval wrapper |
| - | Working signal 1 is typed `transcript_write` but its meaning is a SQL predicate | noted | the probe evaluates only the messages file mtime for it, which can raise working late and never lowers it; a fresh session has no id in argv so the probe reads nothing for it. Weak, and stated in the meaning |
| - | Process name `code-sidecar` is Cline-only | unsupported beyond "no other program found" | one web search found none; the doctor command also matches by that name. Kept; a `proc_pidpath` detector should check the bundle path |

### Synthetic probe check after the repair (`tools/agents_probe.py` `matches()`, hand-written ps lines)

| ps line | Result |
|---|---|
| `.../node_modules/cline/node_modules/@cline/cli-darwin-arm64/bin/cline` | tui |
| same under `/opt/homebrew/Cellar/cline/3.0.3/libexec/...` with `--id 1790000000000_abcde` | tui |
| pnpm layout `.pnpm/@cline+cli-darwin-x64@3.0.65/node_modules/@cline/cli-darwin-x64/bin/cline --yolo fix the tests` | tui |
| same `update the readme` | tui (word subcommands still not vetoed, on purpose) |
| `.../node_modules/cline/bin/.cline` | tui |
| `.../bin/.cline --cline-hub-daemon --cwd /Users/x/proj` | daemon (hub) |
| `.../bin/cline --acp` | ide |
| `--version`, `--zen refactor`, `--kanban` | none |
| `cline connect telegram -i` | tui (long-lived connector, see edit 4) |
| `node .../cline/bin/cline --id abc` (wrapper) | none |
| `/Applications/Cline.app/Contents/MacOS/cline-app` | gui |
| `.../Contents/MacOS/code-sidecar` | daemon (sidecar) |
| `.../code-sidecar --cline-hub-daemon --cwd /a` | daemon (hub) |
| `/Applications/Cline Beta.app/Contents/MacOS/cline-app` | none (space splits argv[0]) |
| `/opt/other/cline`, `/usr/bin/some/cline --foo`, `/usr/local/bin/cline --acp` | none (was tui and ide before) |

`agents_probe.py --row registry/agents/cline.json` on this Mac: 0 sessions.

### Still open

- Real `ps` argv of the compiled Bun binary. If Bun ever rewrites argv[0] to a bare `cline`, the path-only match would miss it; the old name-only match would have caught it. Check on the first live run.
- Installs that set `CLINE_BIN_PATH` to another location are not matched.
- Live timing of `running` and `idle`, and whether `pending` appears during a real approval.
- The earlier "Contradicts common belief" bullet about the hub log path is narrower than written (edit 3); the rest of that section stands.
