# fx (vercel-labs/fx), research notes

Date 2026-09-30. Confidence `documented`. fx is not installed on this Mac, so nothing was seen running. Sources: https://fx.sh/llms-full.txt (all docs in one file), the public repo at main (commit 1b1f9af, release v0.0.12 per https://releases.fx.sh/latest.txt), https://fx.sh/setup.sh, and a tarball of main read with grep. Nothing was installed, started or run.

## What I checked

- Local: `which fx` (not found), `ls ~/.fx` (absent), `ls ~/.local/bin` (no fx), `ps` for an fx process (none). No store, so no key names printed from a real record.
- Surfaces: one native Zig binary, `~/.local/bin/fx` (setup.sh). No app bundle, no bundle id, no daemon of its own, no cloud surface. Modes: interactive TUI, `fx ask` one-shot, `fx acp` stdio server, plus libfx (Node and WebAssembly embeds) that run inside a host app and create no fx process.
- Session store: `~/.fx/sessions/<id>/`. Docs promise only the directory. Source shows `session.json` (manifest), `events.jsonl` (append-only, frames `{schema_version, seq, timestamp_ms, event:{<variant>:{...}}}`), `authority.json`, `permissions.json`, `recovery.json`, `checkpoint.json`, `session.lock`, `owner.live`. Event variants: user, assistant, tool_call, tool_result, steering, turn_completed, interrupted, context_checkpoint. Key names come from source and a test fixture, not from a real file. Marked `documented: false`: the supported reader is `fx session <id> --json`, and the format has migrations (schema v3, legacy `session.json`).
- Process to session: new session ids are generated (12-char base64url) and never appear in argv. Only `fx resume <id>`, `--resume <id>` and `--resume-<id>` carry one. The reliable map is `~/.fx/sessions/<id>/owner.live` (`{"pid":N,"opened_at_ms":T}`) or lsof on the exclusive `session.lock`.
- Turn in progress: the source has an explicit open-turn state machine (`nextConversationTurnOpen`): `user` opens, `turn_completed` or `interrupted` closes. That is the most precise signal, but the probe cannot read frame types.
- Waiting on the human: internal hook `AttentionRequired` (kinds permission, question, route_recovery); Herdr socket report `blocked` with custom status; an afplay chime and a BEL.
- Hooks: four internal lifecycle events (PreToolUse, Stop, PostTurnEnd, AttentionRequired). No settings key, no docs page, no external command hook. Only built-in providers (Herdr, notification sounds) register handlers.
- OpenTelemetry: none. Docs say no product telemetry. Local only: FX_TRACE, FX_RECORD, `~/.fx/usage.jsonl`.
- Sleep inhibitor: none. No caffeinate, IOPMAssertion or pmset in the source.
- Ran `tools/validate_row.py registry/agents/fx.json` (ok) and evaluated `matches()` from `tools/agents_probe.py` on 12 synthetic command lines: `fx`, `fx -c`, `fx resume <id>` (session id read), `fx ask ...` and `fx acp` (own surfaces), the internal helpers, `doctor`, `upgrade` and `--version` (all rejected).

## Contradicts common belief

- "fx" is usually the JSON viewer (antonmedv/fx, brew formula `fx`). Same binary name. The row matches by name only, because argv[0] is `fx` when typed, so path_contains never fires for the common case. Expect the JSON viewer to be reported as an idle fx session unless a pid hit in `owner.live` is required. The probe cannot do that.
- A shell is NOT a direct child of a working fx on macOS. Foreground tool commands run through fx re-executing itself by absolute path: `fx __fx_foreground_session__ <deadline|none> <argv...>`, which calls setsid and spawns the command. The shell is a grandchild, and the direct child has the same executable name as its parent. `tool_children` would stay false, so it is left out. This is not seen live. It follows from `command_runner.zig`.
- fx spawns more copies of itself: `fx --fx-internal-terminal-host` (shared, direct child of the first fx that needed it, own process group, 30 s idle grace after its last session, may outlive that fx), plus launcher, control and tmux variants. A "child named fx" signal would read working while a background dev server runs. So `child_process fx` is left out. These helpers are vetoed by exact argument, otherwise each would show as an idle fx session.
- Unlike Claude Code, Codex and grok-build there is no sleep assertion, so there is no level signal to poll. "Idle" cannot be told from "waiting for the model" by process state alone.
- fx does have lifecycle hooks in the source, but users cannot configure them. Do not tell users to add an fx hook.
- Sound is the odd one: on macOS, `afplay` children appear at turn end and on attention by default. Any detector counting unknown short children as tools would misread them. The row lists afplay as a waiting/done signal only.

## Could not determine

- Real-run behaviour: no live process, so no CPU numbers (floor 3% is a guess), no transcript write gaps, no confirmation that shell tool calls show up as the helper child.
- Whether `session.lock` is held for the whole life of an interactive session. Inferred: `park()` is called only from subagent code and tests.
- Whether the `user` frame is written when the prompt is sent, and how often assistant text is flushed to events.jsonl during a long call. The 30 s window is copied from the generic default.
- Whether the AttentionRequired wait leaves any trace in the store. A pending `tool_call` without `tool_result` looks the same as a slow tool.
- Whether Herdr's `custom:fx` reports are visible to anything but Herdr.
- Whether `fx pr` and `fx issue` should count: they run a model turn and exit. They are excluded from the TUI surface and not tracked.
- The substring hazard: `args_contain` is substring, so `fx --add-dir ~/tasks` matches the `ask` surface (oneshot, reads always working) and scores above the TUI surface; `acp` in an argument does the same for the ACP surface. Accepted, since interactive launches rarely carry path arguments; a session id containing `ask` would also trigger it (about 1 in 26 000 ids, by my arithmetic, not measured).
- The relaunch after an auto-upgrade (ctrl+g) runs `resume <id> --upgrade-relaunch [<rev>]`. It has an id in argv, but I did not confirm whether the old process is replaced in place or a new one is spawned.
- Model-related note, not a detection issue: `fx login grok` connects a Grok (xAI) subscription. That is a model provider inside fx, not a separate "Grok Bot" surface; the existing `grok-build` row covers xAI's own CLI.

## Verification

Adversarial pass, 2026-09-30. Re-fetched https://releases.fx.sh/latest.txt (v0.0.12), https://fx.sh/setup.sh, https://fx.sh/llms-full.txt and the main tarball; downloaded the macOS arm64 release archive into a scratch directory and read it with `file`, `otool -L` and `strings` only (never installed or executed). `tools/validate_row.py registry/agents/fx.json` printed `ok` before and after the edits. fx is not installed here, so confidence stays `documented` at most.

Confirmed
- fx is a Zig agent CLI, Apache-2.0, experimental, latest release v0.0.12, main at 1b1f9af (README banner, GitHub API, latest.txt).
- Install: one binary to `~/.local/bin/fx`, `FX_INSTALL_DIR` overrides, archive `fx-<os>-<arch>.tar.gz` with os macos or linux and arch x86_64 or aarch64 (setup.sh detect_platform, mv lines). The archive holds fx, LICENSE, THIRD_PARTY_NOTICES.md; no bundle.
- Session store `~/.fx/sessions/`; file names events.jsonl, session.json, authority.json, permissions.json, recovery.json, checkpoint.json, session.lock, owner.live (session_log.zig 31-47; strings in the binary). `documented: false` is right: docs promise only the directory.
- owner.live body is `{"pid":N,"opened_at_ms":T}`, written by trackOwnerLiveness at create and open (session_log.zig 4113, 4252; session_store.zig 2904, 3039) and deleted by clearOwnerLiveness.
- Session ids: 9 random bytes, base64url, 12 chars; allowed set letters, digits, . _ -, up to 255 (session_layout.zig).
- Frame variants and the open-turn rule (session_event.zig ConversationEvent; nextConversationTurnOpen: user opens, turn_completed or interrupted closes, context_checkpoint leaves the state alone).
- `session.lock` is released only by park(), whose non-test callers are src/core/subagent/managed_owner.zig 560 and tool_host.zig 675, so an interactive session holds it for its life. This upgrades the earlier "inferred" wording to source-confirmed; still not seen live.
- Foreground helper: `<self exe> __fx_foreground_session__ <deadline|none> <argv...>` spawned as a direct child, setsid in the bootstrap; enabled wherever libc, spawn and replace exist and the OS is not Windows or WASI, so it holds on macOS (command_runner.zig 72-77, 1187-1230). The self path is executablePathAlloc on macOS (self_exe.zig).
- Terminal helpers: the five `--fx-internal-terminal-*` tokens are exact argv[1] values (host.zig, native_session.zig, tmux_session.zig) and appear in the release binary.
- Hooks: four kinds, four scopes; built-ins register only PostTurnEnd and AttentionRequired handlers (Herdr, notifications). No user config, no hooks page in llms-full.txt (the only "hook" hit there is an xterm.js key handler).
- Herdr: state idle, working, blocked, source `custom:fx`, env HERDR_SOCKET_PATH and HERDR_PANE_ID, FX_HERDR=0 (herdr.zig, docs Herdr integration).
- Telemetry: docs say none; no otel, otlp or opentelemetry string in src, docs, sdk, README, or the release binary (only an @opentelemetry/api line in sdk/tests/next/pnpm-lock.yaml).
- No sleep inhibitor: no caffeinate, IOPMAssertion or pmset in src or in the binary, and the binary links only libSystem (no IOKit).
- Top-level commands and aliases in exclude_args are complete against TopLevelKind and builtins/commands.zig (`balance` is an alias of `credits`; `--help`, `-h`, `--version`, `-v` handled). `resume` and its aliases are correctly not excluded.
- `fx acp`: stdio JSON-RPC, one session and one prompt at a time per connection, one process per project, editor gives an absolute path (acp docs).
- `fx ask`: `--resume`, `--json`, `--no-save` (fx-ask docs); `--no-save` cannot combine with `--resume`.
- antonmedv/fx is a different tool (README: f(x), MIT, docs at fx.wtf), so the name collision is real.
- Nothing installed here: `which fx` printed `fx not found`, `ls ~/.fx` failed, no fx process in `ps`.

Corrected
- Sound cues. The row and the notes said afplay plays only when a turn finishes or attention is required. Source shows more: bloom at startup, press on cancel, click after a /model or /fast change, all gated by the sound switch (on by default on macOS); release and toggle only at level max (`notifications.max`, default false). Only success and error at turn end, and success at attention, mean done or waiting. The `afplay` waiting_signal meaning was rewritten; the "Sound is the odd one" bullet above is superseded by this.
- Session id extraction. The label listed `--resume-<id>` as an id carrier, but `session_id_args` cannot read it: `agents_probe.session_id()` handles `flag value` and `flag=value` only. Recorded in the label. `resume last` also returns the word `last`, which has no store file (harmless).
- Upgrade relaunch, previously "could not determine": app_entry_runtime.zig calls std.process.replace with `<exe> resume <id> --upgrade-relaunch [<rev>]`, so it is an in-place replace, same pid, no duplicate process. The id is in argv afterwards. Inferred from source and its tests, not seen live.
- `fx session resume <id>` is an interactive resume but `session` is in exclude_args, so it is a false negative. Kept (removing `session` would let the read-only `fx session <id> --json` show as an idle session); now written down.

Unsupported or unverified (left as stated, confidence limits)
- Every CPU floor and window: nothing was seen running. The 3% floor and 30 s window are guesses.
- How often events.jsonl is written during a long model call or tool call.
- Whether the `user` frame is written when the prompt is sent (inferred from the state machine).
- Whether the AttentionRequired wait leaves a trace in the store.
- Whether Herdr `custom:fx` reports are visible to anything but Herdr.
- The upgrade relaunch executable path is presumed to be the installed `fx` (basename `fx`), so the name match survives; source reads the current executable path but was not run.
- The 1 in 26 000 figure for a session id containing `ask` is arithmetic, not measured.

Process-pattern check (agents_probe.matches on 34 synthetic lines)
- Correct: `fx`, `-c`, `-r`, `resume <id>`, `--resume <id>`, `--model x` on the TUI surface; `ask` forms (also after global flags) on the ask surface; `acp` on the ACP surface; `pr`, `issue`, `doctor`, `upgrade`, `--version`, `sessions`, the foreground helper and the terminal host match nothing.
- False positives, all known: antonmedv/fx (`fx .foo`, `fx data.json`) and `fx wat` or `fx version` match the TUI surface. A real vercel fx never accepts a bare non-command word, so these are the JSON viewer or a command that exits at once. The schema has no way to require "no positional argument", so this cannot be fixed in the row; a pid hit in `~/.fx/sessions/*/owner.live` is the only discriminator.
- Misfiles: `fx --add-dir /Users/x/tasks` and `fx --model ask-x` score 2 on the ask surface and beat the TUI surface (score 1). `args_contain` is a substring test; no exact-match option exists.
- False negatives: `fx --add-dir workspace` (a flag value equal to an excluded word) and `fx session resume <id>`.
- The helpers cannot be mistaken for sessions: they are vetoed by exact argument, and the probe's parent-dedupe would also keep only the outermost fx.

Grok Bot: fx's `fx login grok` is a Grok subscription used as a model provider inside fx. It does not make fx a Grok Bot surface, and grok-bot.json was not touched here (out of scope for this task).
