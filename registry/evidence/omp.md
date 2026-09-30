# omp (Oh My Pi) evidence

Date: 2026-09-30. Version read: 18.4.4 (npm and GitHub release, 2026-09-29). Not installed on this Mac, never seen running. Confidence `documented`: source, docs and install scripts only.

## What I checked

- Repo: the hint URL `github.com/oh-my-pi/pi-coding-agent` is a 404. The project is `github.com/can1357/oh-my-pi` (MIT, Stencil Labs, fork of `badlogic/pi-mono`). I read raw files from `main` (README, `docs/*.md`, `crates/pi-natives/src/power.rs`, `packages/utils/src/process-name.ts`, `packages/tui/src/ttyid.ts`) and the full npm tarball `pi-coding-agent-18.4.4.tgz` (`src/`, `dist/cli.js` head, `package.json`), downloaded to a scratch dir, not installed.
- Install scripts: `https://omp.sh/install` (read in full, not run), the Homebrew formula `can1357/homebrew-tap/Formula/omp.rb`, release assets of v18.4.4.
- Local: `which omp`, `ls ~/.omp`, `ls ~/.local/bin/omp /opt/homebrew/bin/omp` all empty; `bun --version` 1.0.0.
- One small experiment, in a scratch dir only: a `#!/usr/bin/env bun` script reached through a symlink named `omp`, printing `ps -o comm=,args= -p <self>` before and after `process.title = "omp"`. This ran Bun, which is a step beyond the read-only command list; no agent, no session, no multiplexer was touched. Result: ps showed `bun bun <symlink path> <args>` both times and the title never changed. Bun here is 1.0.0, so this only corroborates omp's own source comment (below); it does not prove behaviour on Bun 1.3.14+.
- Row checks: `tools/validate_row.py registry/agents/omp.json` passes. `tools/agents_probe.py --row registry/agents/omp.json` runs and finds 0 sessions (nothing running). I fed `matches()` synthetic argv for 14 shapes: native binary (bare, absolute, brew, `--print`, `--version`, a worker), Bun global (plain, `--print`, worker), bunx, pi under node, pi retitled, `node .../@oh-my-pi/...`, and `bun run dev`. Each omp shape scored on exactly one omp surface, workers and `--version` scored nothing, and no omp shape also matched `pi.json` (nor the reverse).

## Findings by question

| Question | Answer | Source |
|---|---|---|
| Runtime | Bun, not Node. `engines: {bun: >=1.3.14}`, `dist/cli.js` shebang `#!/usr/bin/env bun`, `src/cli.ts` line 46 exits if `Bun.semver` says too old. | tarball `package.json`, `dist/cli.js`, `src/cli.ts` |
| Process shapes on macOS | (a) native Bun single-file binary `omp` (curl installer to `~/.local/bin/omp`, or brew): argv[0] base name `omp`. (b) `bun install -g`: `bun /Users/<u>/.bun/bin/omp ...`, argv[0] `bun`. (c) bunx or source checkout: `bun <path containing @oh-my-pi/pi-coding-agent>`. | `omp.sh/install`, `omp.rb`, README, my symlink test |
| Retitle | omp does not retitle on macOS. `process-name.ts`: Bun's `process.title` setter only stores a JS value; the kernel name stays `bun` on the shebang path and is right only for compiled binaries. | `packages/utils/src/process-name.ts` |
| Bundle id | None. CLI only; release assets are bare Mach-O files. | GitHub release assets |
| Session map | Flags `--resume [id]`, `-r`, `--session [id]` (id prefix or path, value optional). A plain launch has no id in argv. Fallback: `~/.omp/agent/terminal-sessions/<tty>` (file named `ttys009`, holds cwd and session file path). Then cwd bucket plus newest file. | `docs/cli-reference.md`, `docs/session.md`, `ttyid.ts`, `session-paths.ts` |
| Store | `~/.omp/agent/sessions/<encoded-cwd>/<ISO ts>_<uuidv7>.jsonl`; profiles `~/.omp/profiles/<name>/agent/sessions`; `PI_CODING_AGENT_DIR` / `PI_CONFIG_DIR` move it. First line is a 256-byte `title` slot, then a `session` header (id, cwd, timestamp, version, title...), then entries with id, parentId, timestamp, type. Subagent children: `<parent>/<agentId>.jsonl`. `documented=true` (docs/session.md calls itself the source of truth). I did not open a real file: none exists here. | `docs/session.md` |
| Turn in progress | In-process IOKit assertion, type `PreventUserIdleSystemSleep`, name `omp agent session`, taken when in-flight count goes 0 to 1 and released at 0, so exactly one turn. Default on (`power.sleepPrevention: idle`). `pmset -g assertions` should show it under omp's own pid (the `bun` process for shape b). | `agent-session.ts` (`powerAssertionOptions`, `#beginInFlight`, `#endInFlight`), `session/settings.ts`, `power.rs` |
| Waiting on the human | Not visible from a process list. The assertion stays held during an approval prompt or an `ask` question. Events: `tool_approval_requested` / `tool_approval_resolved`; `tool_execution_start` with `toolName: "ask"`. The same marker is written into the session file as a `custom` entry. Opt-in: `omp collab list --json` gives `busy` and `inputRequired` per live host. | `docs/extensions.md`, `modes/warp-events.ts`, `docs/collab.md` |
| Hooks | TS/JS extension modules, not a JSON table. `~/.omp/agent/extensions/`, `<cwd>/.omp/extensions/`, `hooks/pre|post/`, `extensions:` in `config.yml`, `-e/--hook`. Events listed in the row. | `docs/extensions.md`, `extension-loading.md`, `hooks.md` |
| OpenTelemetry | Yes, built in, inert until an `OTEL_EXPORTER_OTLP*_ENDPOINT` is set; http/protobuf only; GenAI spans, metrics, logs. | `docs/environment-variables.md` section 11, `telemetry-export*.ts` |

## What contradicts common belief (and the hint)

1. "Node-hosted fork of pi" is wrong. omp needs Bun and cannot start under Node. The `prior-art` note that it runs as `node .../@oh-my-pi/pi-coding-agent/dist/cli.js` does not hold for the current package: its bin is a Bun script.
2. The name `omp` does not appear in ps for a Bun global install. It is `bun /path/to/.bun/bin/omp`. Only the curl and brew installs are a real `omp` process. A `names: ["omp"]`-only row would miss the install the README marks "recommended" (`bun install -g`).
3. omp is not pi where state is concerned. pi has no permission prompts; omp has three approval modes (default `yolo`, so prompts are off until the user changes it). pi has no per-turn OS signal; omp holds a named sleep assertion per turn.
4. The bash tool does not create shell children. It runs in an embedded in-process shell with in-process coreutils, so `tool_children` (direct shell children) is blind. It is left out of the row.
5. omp re-executes its own binary for 16 workers and broker daemons (`__omp_worker_*`). Those would otherwise show as extra idle sessions, and the daemons can outlive the session. The row vetoes each by exact argument.
6. The `pi` row is already narrowed to `@earendil-works/pi-coding-agent/dist/cli.js` under `node`. The collision `prior-art` predicted (and README case 12 still lists) no longer exists in the file I checked. README case 12 and `prior-art` item 5 are stale on this point.
7. On this Mac the installer's default path (Bun present and native) would call `bun install -g` and then stop on "Bun 1.3.14 or newer is required", because Bun is 1.0.0. Inferred from the script, not run.

## Could not determine

- Real `ps` output of a running omp on macOS, for any shape. Argv for the native binary is inferred from how compiled Bun executables are exec'd; shape (b) is corroborated only by my Bun 1.0.0 symlink test.
- Whether `pmset -g assertions` prints the name `omp agent session` verbatim. It is the string passed to `IOPMAssertionCreateWithName`, so it should.
- A CPU floor for `tree_cpu`. 3% is a guess.
- Whether the assertion is held while a turn waits on an approval or `ask`. I found nothing that lowers the in-flight count there, so it should be; not seen live.
- The exact wait record in the session file for approvals (only `ask` and the generic `tool_execution_start` marker were read). I did not trace where that marker is written relative to the approval gate.
- `mise` and Nix install paths: process shape not read.
- Custom `BUN_INSTALL` locations are not matched by the shim surface. `--mode=rpc` (equals form) cannot be vetoed; `-p` cannot be matched, so `omp -p` runs read as interactive sessions. ACP and rpc processes are not vetoed on purpose (they run real turns).
- Whether `omp collab list` works without a reachable relay. I did not run it.
- Warp OSC events (`warp://cli-agent`) work only inside Warp.
- I did not read the code of the other tools that name omp (Herdr, cmux, Emdash, Agent Deck, CASS) beyond what `prior-art` records.

## Verification

Adversarial re-check, 2026-09-30. Sources re-fetched: npm tarball `@oh-my-pi/pi-coding-agent-18.4.4.tgz`, raw files on `can1357/oh-my-pi` `main`, `https://omp.sh/install`, the Homebrew formula, the GitHub release API. `tools/validate_row.py registry/agents/omp.json` passes before and after. Confidence stays `documented`: omp is not installed here (`which omp`, `ls ~/.omp`, `ls ~/.local/bin/omp /opt/homebrew/bin/omp` all empty again; `bun --version` 1.0.0; no omp process, no `omp agent session` assertion in `pmset -g assertions`).

I ran `agents_probe.matches()` over all `registry/agents/*.json` for 28 synthetic argv shapes (native, brew, release asset, `--print`, `-p`, `--version`, workers, Bun shim, Bun global package path, package-manager runs, subcommands, `oh-my-posh`, `pi`).

### Confirmed

- Repo, hint URL 404, version: `github.com/oh-my-pi/pi-coding-agent` returns 404; `can1357/oh-my-pi` returns 200; npm latest is 18.4.4; release v18.4.4 published 2026-09-29 with assets `omp-darwin-arm64` and `omp-darwin-x64` (no .app or .dmg).
- Bun, not Node: `engines {bun: >=1.3.14}`, bin `omp: dist/cli.js`, `dist/cli.js` starts `#!/usr/bin/env bun`, `src/cli.ts` exits below the minimum Bun.
- Homebrew: formula installs `omp-darwin-<arch>` as `bin/omp`, so argv[0] base name is `omp`.
- Binary is a Bun single-file executable (`docs/macos-signing-notarization.md`); bare Mach-O, cannot be stapled, no bundle id.
- `process.title = APP_NAME` at `src/cli.ts` line 54; `process-name.ts` header says macOS has no clean equivalent on the shebang path.
- 16 `__omp_worker_*` selectors (8 in `worker-selectors.ts`, 8 in `cli.ts`); a grep of the whole tarball finds no others. All 16 are in `exclude_args`. Non-compiled workers re-exec as `[executable, hostEntry, workerArg]`.
- Power assertion: `powerAssertionOptions()` gives reason `omp agent session`, `idle: true`; `#beginInFlight` acquires at count 0 to 1, `#endInFlight` releases at 0; `power.sleepPrevention` default `idle`; `power.rs` maps idle to `PreventUserIdleSystemSleep` via `IOPMAssertionCreateWithName` with the reason as the assertion name. The probe's name match (`omp agent session`, case-insensitive substring) is right.
- Session store: path, `<timestamp>_<uuidv7>.jsonl` (`mintSessionId` = `Bun.randomUUIDv7`, `fileSafeTimestamp` replaces `:` and `.` with `-`), header version 3, 256-byte title slot, append-only with no fsync, memory-only until the first assistant message, `tool_execution_start` and `session_exit` custom entries, breadcrumb `~/.omp/agent/terminal-sessions/<terminal-id>` (macOS `ttys009` from `ttyname(0)` minus `/dev/`). `documented: true` holds: `docs/session.md` calls itself the source of truth.
- Session flags `--resume [id]`, `-r`, `--session [id]`, `--continue/-c`, `--fork`, `--session-dir`, `--no-session`, `-p/--print`, `--mode text|json|rpc|acp|rpc-ui`, `--profile`/`OMP_PROFILE`; `--help/-h`, `--version/-v` are real flags in `src/cli/args.ts`. `session_id_args` and the `*_{session_id}*.jsonl` pattern are consistent with an id-prefix value.
- Approval: default `yolo`, `always-ask` and `write` prompt, prompt text `Allow tool: <name>` (`docs/approval-mode.md`).
- Hooks: all 29 listed event names appear in the docs and source; extension and hook locations, `--extension/-e/--hook`, `extensions:` in `config.yml`, profile dir `~/.omp/profiles/<name>/agent/`.
- Warp OSC mapping (`permission_request`, `question_asked`, `stop`) in `src/modes/warp-events.ts`.
- OpenTelemetry: off until an endpoint is set, http/protobuf only, `telemetry.otlpExportEnabled` default true, `OTEL_SDK_DISABLED` opt out.
- `omp collab list --json`: `busy` and registry under `~/.omp/run/collab-hosts`; `collab.autoStart` default `off`.
- Third-party claim (Herdr hook-only, Agent Deck `Allow tool:` on v17.3.8): matches `registry/evidence/prior-art.md` lines 93 and 212. That file is itself a secondary record.
- Local observation that omp is not installed: re-run, same result.
- Process patterns: `omp` names do not match `oh-my-posh`, `pi`, or any other row's surfaces; no other row matches an omp shape; workers, `--version` and Bun-shim workers score nothing.

### Corrected

- Vendor: the row said "Can Boluk / Stencil Labs". `package.json` author is "Stencil Labs, Inc." with contributor Mario Zechner; no source names a person as vendor. Now "Stencil Labs, Inc. (repo can1357/oh-my-pi; fork of pi by Mario Zechner)".
- Curl installer label: it does not always put a binary at `~/.local/bin/omp`. With a host-architecture Bun >= 1.3.14 on PATH the default path is `bun install -g` (`install.sh` main, lines 322-333). The row's own source claim already said so; the surface label did not. Label fixed.
- Subcommand vetoes were unsourced and incomplete. `src/cli-commands.ts` registers about 50 commands plus aliases; the row vetoed 21. Added utility subcommands and aliases: `__complete agents clip dry-balance grep grievances images img install login play plugins predict q read say search share skill skills ssh stream token toks ttsr web-search worktree wt`. Each is a non-session process that the old row listed as an idle session (synthetic `omp grep foo`, `omp login`, `omp worktree add x` all matched). `omp worktree add` is also spawned by omp's own bash tool (`src/tools/bash.ts` line 996). Deliberately not vetoed because they run model turns or are session clients: `launch`, `acp`, `commit`, `cleanse`, `compress`, `find`, `join`.
- Package-manager false positive: `bun install -g @oh-my-pi/pi-coding-agent`, `bun add -g ...` and `bun run --filter @oh-my-pi/pi-coding-agent test` matched the bun + package surface and would read as idle omp sessions. Added exact-argument vetoes on that surface: `add i upgrade remove rm pm link unlink --filter` (`install` and `update` were or are now in the shared list).
- Subagent child sessions `<parent>/<agentId>.jsonl`: the row cited `docs/session.md`, which does not say this. The real source is `src/task/executor.ts` line 3521 and `artifactsDirectoryFor()` in `session-manager.ts`. Claim kept, citation fixed. The row's glob `sessions/*/*.jsonl` correctly excludes these files.
- `inputRequired` in `omp collab list`: `docs/collab.md` defines it as a host-side question waiting for a writable guest, not "a question waits" for the local user. Wording fixed in the waiting signal and the source claim; whether a local approval prompt sets it is not documented.
- `.claude/hooks/pre|post` read: `docs/hooks.md` says the native layout only "mirrors" it. The actual read is in `src/discovery/claude.ts` (lines 383-389, 621). Hook config text and the source entry now cite that.
- The earlier evidence claim that `omp -p` "reads as an interactive session" is wrong. `-p` is in surface 1's veto list and the print surface needs the substring `--print`, so `omp -p hi` matches nothing (invisible, not misfiled). Recorded as a source entry; `--print` still matches surface 2.

### Unsupported or inferred (kept, now labelled)

- The turn assertion stays held while a turn waits on an approval or an `ask` question. No code path lowers the in-flight count during a tool wait, but it was never seen live. The signal's `meaning` now says "inferred, not seen live".
- External programs started by the embedded bash tool are direct children of omp under their own names. The docs confirm in-process builtins (`no fork/exec`) and PTY default shell `sh`; direct-child behaviour for external programs is inferred, not documented. Claim reworded. The decision to omit `tool_children` does not depend on it.
- `tool_execution_start` with `toolName: ask` blocking until answered and no later `toolResult` meaning still waiting: read from the writer and the Warp mapping, not seen live (already flagged in the row).
- Local Bun 1.0.0 symlink test (`bun <symlink> args` in ps, `process.title` not changing): not re-run by this verifier (it executes Bun, outside the read-only command list). It stays as corroboration only. It does not change the row: if a newer Bun did retitle to `omp`, surface 1 would still match by name, but flags and worker vetoes would be lost on that path. Noted in the row.
- `tree_cpu` floor 3% is uncalibrated (no process to measure); the signal says so.
- Real `ps` output of a running omp, for any shape, and the literal `pmset -g assertions` text: never observed. This is why confidence cannot exceed `documented`.

### Left open

- Substring `/.bun/bin/omp` also matches `/.bun/bin/omp-<anything>`. Unlikely; schema has no way to anchor it.
- `bun run <script> ... @oh-my-pi/pi-coding-agent` in the oh-my-pi monorepo (dev checkout) can still match the package surface.
- Exact-argument vetoes hide a session only when one of the veto words is a separate argument; a single-quoted multi-word prompt is safe.
- Custom `BUN_INSTALL` locations are not matched by the shim surface; `--mode=rpc` cannot be vetoed; mise and Nix process shapes were not read.
