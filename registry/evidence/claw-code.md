# claw-code (ultraworkers/claw-code)

Research date 2026-09-30. Not installed on this Mac and nothing was run, so confidence is `documented`. Everything comes from the public source (main at 08106b0, 2026-08-16, downloaded as a tarball into the scratchpad and read) and its own docs. `tools/validate_row.py registry/agents/claw-code.json` passes.

## Shape

```
claw            (crate rusty-claude-cli, bin `claw`, workspace 0.1.3)
  bare `claw` + TTY          -> line-editor REPL, prompt "> "        (session)
  claw "x" | prompt | -p | pipe -> one shot, alive = working
  claw doctor|status|mcp serve|--resume ... -> short command, not a session
claw-analog     (crate claw-analog)  one task per run, opt-in JSON snapshot via --session
claw-rag-service (Qdrant RAG daemon) -> a service, not an agent; no row surface

turn:   user text -> [model stream] -> assistant msg -> per tool: sh -lc child -> tool_result -> ... -> assistant msg without tool_use
store:  <cwd>/.claw/sessions/<fnv1a64(canonical cwd), 16 hex>/session-<ms>-<n>.jsonl   (appended, one line per message)
```

## What I checked

- Identity: README says it is the public Rust implementation of the `claw` CLI; `rust/crates/rusty-claude-cli/Cargo.toml` names the binary `claw`. No tags and no GitHub releases exist, so there is no installable artifact; only a build from source (`cargo build`, `install.sh`) produces one. The release workflow would name the macOS asset `claw-macos-arm64`.
- Process shape: argv parsing in `main.rs` (REPL vs one-shot vs subcommands), and that `--resume` restores, runs slash commands and exits. Matching rules tested with `agents_probe.matches()` on 12 synthetic argv lines: bare `claw`, dev-build paths, `claw doctor`, `claw --resume latest`, `claw -p`, `claw-macos-arm64`, `claw-analog` (its own surface wins by path length), `openclaw-tui` and `clawd` (no match), `--version` (vetoed).
- Sessions: `session_control.rs`, `session.rs`, `docs/g010-clone-disambiguation-metadata.md`, USAGE.md line 552. Key names only, from source. No record exists locally to read.
- Working signals: `conversation.rs` run_turn write order; `bash.rs` (`sh -lc`, stdin null); grep for `caffeinate`, `IOPMAssertion`, sleep inhibitors (none).
- Waiting: `CliPermissionPrompter` (plain stdout, blocking stdin), `worker_boot.rs` and where `WorkerRegistry` is used.
- Hooks: USAGE.md "Hook configuration", `hooks.rs`, `config.rs` discovery order.
- OTel: grep for `opentelemetry`, `otlp`, `OTEL_` in the whole tree; where `SessionTracer` is built.
- Local: `which claw claw-analog`, `ls ~/.claw ~/.claw.json`, `ps` for claw processes, `ls /Applications`. All empty.

## Could not determine

- No live instance: real `ps` argv, whether a REPL holds any file open, and how the direct-child signal behaves on macOS are all unobserved. `sh -lc "<one command>"` may exec in place on macOS, leaving the command, not `sh`, as the direct child (inferred, README case 9).
- Where a user would put the binary. The dev-build paths, the name `claw`, and `claw-macos-arm64` are the only shapes seen in source. A copy renamed by the user still matches by name if it is called `claw`.
- Whether a bare name `claw` collides with an unrelated program. Nothing on this Mac is called that; not checked elsewhere.
- CPU floor of 3% is a guess, as in most rows.
- The `.claw/sessions` glob is relative to a project directory, so it cannot be expanded from `~`; the row records it as a relative glob and the mapping is by process cwd.
- Whether the quiet gap during a long model stream is short. The assistant message is written only after the stream ends, so a slow reply can leave the transcript silent well past 30 s with no child and low CPU. No exact turn state exists to fix that.
- MCP stdio servers configured through `mcpServers` are direct children of `claw`; only a server launched through a shell name would be misread as a tool child. Not tested.

## Contradicts common belief

- It is not a Claude Code fork or wrapper, and `cargo install claw-code` installs a deprecated stub that only prints a rename notice (README warns of this). It does read `CLAUDE.md`, `.claude/CLAUDE.md` and `AGENTS.md` as instruction files, and sends `claude-code` as its default user-agent app name (`telemetry/src/lib.rs`). Neither means Claude Code's `~/.claude` store or hooks apply: config and sessions live under `.claw`.
- Its hook config accepts Claude Code's JSON shape, but only three events run: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`. `Stop`, `Notification`, `UserPromptSubmit`, `SessionStart` are accepted as config, flagged `unknown_hook_event`, and never fire. So the usual "waiting" hook (`Notification`) does not exist here.
- Sessions are per project, not global. `~/.claw/sessions` is only a read fallback for `--resume latest`; nothing writes there.
- `claw state` help says `.claw/worker-state.json` is written by the REPL or a one-shot prompt. In the source only the Worker* model tools create a `WorkerRegistry`, so a plain REPL does not write it. If it exists, its `tool_permission_required` status describes a worker, not the REPL.
- `crates/telemetry` looks like telemetry, but the CLI never builds a tracer or sink outside tests, so it exports nothing, and there is no OpenTelemetry at all.
- The README calls the repo "not the serious production project" and "an agent-managed exhibit", and points users to LazyCodex and Gajae-Code. Those are separate projects and are not surfaces of this row. 195k stars is star count, not proof of use.
- "Grok Bot": not found in this repo. xAI's Grok appears here only as a model provider (`grok`, `grok-3`, `grok-mini`, `XAI_API_KEY`), not as a separate surface. The xAI harness is the `grok-build` row.

## Verification

Independent check, 2026-09-30. I downloaded the tarball for main@08106b0 (`codeload.github.com/ultraworkers/claw-code/tar.gz/08106b0c...`) into the scratchpad, re-read the cited files, and re-ran the local commands. `tools/validate_row.py registry/agents/claw-code.json` passed before and after the repair. No harness is installed here, so confidence stays at most `documented`, and I kept it there: every behavioural claim rests on source I read, none on a live process.

Corrected (2 claims, both repaired in the row):

- **Process match by dev-build path: corrected.** The claw surface listed `path_contains` `/rust/target/{release,debug}/claw`. `path_contains` is a substring test on argv[0], and that string is a prefix of `.../claw-rag-service` (crate `claw-rag-service`, an axum RAG server, binary named after the package). Reproduced with `agents_probe.matches()`: `/x/rust/target/release/claw-rag-service --port 1` scored 26 for the claw surface. Also `claw-analog complete zsh` scored 26 for claw, because claw-analog's own veto (`complete`) removed only its own surface and claw's list has no `complete`. Fix: removed `path_contains` from the claw surface, so only the base name (`claw`, `claw-macos-arm64`) matches. Re-tested on 12 argv lines: the RAG server, `claw-analog complete`, `openclaw-tui`, `clawd` and `mock-anthropic-service` all score 0 for claw; `claw-analog -w . task` matches only the claw-analog surface. The earlier line "claw-analog (its own surface wins by path length)" is no longer how it works: they are now disjoint by name. Cost of the fix: no path specificity, so a bare `claw` argv[0] is the only discriminator.
- **Hook shell: corrected.** The row said hooks run as `sh -c`. `runtime/src/hooks.rs` `shell_command` (~745-753) runs `Command::new("sh").arg("-lc")` on non-Windows, the same as the bash tool. Row `working_signals[0].meaning` and source 10 now say `sh -lc`. Hook stdin is piped; the bash tool's stdin is `Stdio::null()`.

Confirmed:

- Identity and repo: README line 96 "Claw Code is the public Rust implementation of the `claw` CLI agent harness"; `rusty-claude-cli/Cargo.toml` `[[bin]] name = "claw"`; `rust/Cargo.toml` version 0.1.3; the same README warns `cargo install claw-code` is a deprecated stub.
- No release artefact: GitHub API `/releases` returned `[]`, `/tags` returned `[]`, `git ls-remote --tags` printed 0 lines, `--heads` printed 191. main HEAD 08106b0, committed 2026-08-16T06:18:33Z. Stars 195286.
- Release workflow: matrix `macos-arm64`, bin `claw`, artifact `claw-macos-arm64`; upload step gated on `refs/tags/`.
- Not installed: `which claw claw-analog` printed "claw not found" and "claw-analog not found"; `ls -d ~/.claw ~/.claw.json` both "No such file or directory"; `ps` showed only my own grep; `ls /Applications | grep -i claw` empty.
- REPL vs one-shot: `parse_args` sends `-p`, `prompt`, a bare prompt and piped stdin to `CliAction::Prompt`; empty `rest` with a TTY goes to `Repl`; the REPL uses `input::LineEditor::new("> ", ...)` (rustyline 15 in Cargo.toml). Also `-p` takes one token and rejects a following flag.
- `--resume` / `resume` route to `parse_resume_args` (restore, run slash commands, exit); no session id in a live REPL argv, so leaving `session_id_args` out is right.
- Veto list: every name in `exclude_args` is a real non-session arm in `parse_args`, `is_known_top_level_subcommand` or `parse_local_help_action` (`setup` is in the local-help arms, not in the known-subcommand list; still an exit). `acp` and `--acp`/`-acp` all rewrite to the ACP server path.
- Session store: `SessionStore::from_cwd` gives `<canonical cwd>/.claw/sessions/<fnv1a64 hex16>/`, extension `jsonl`; `current_session_store()` uses `env::current_dir()`; id format `session-{millis}-{counter}`; USAGE.md line 552 says the same. Rotation at 256 KiB to `<stem>.rot-<ms>.jsonl`. Writes are `OpenOptions::append` one line per message after the first bootstrap write.
- `global_sessions_root()` has exactly one caller, `scan_global_sessions` (session_control.rs:328), a read scan. Nothing writes there.
- Record shape: `session_meta` keys (`type`, `version`, `session_id`, `created_at_ms`, `updated_at_ms`, `workspace_root`, `model`, `fork`), `message` with `role`/`blocks`/`usage`, `prompt_history` (`timestamp_ms`, `text`), `compaction`. Key names read from source; no real record was read.
- Turn order in `run_turn`: `push_user_text`, then `api_client.stream`, then `push_message(assistant)`, break if no tool uses, else `push_message(result)` per tool.
- Bash tool: `sh -lc <command>`, stdin null, direct child; the Linux sandbox launcher is behind `cfg!(target_os = "linux")`, so on macOS it is plain `sh`.
- No sleep inhibitor: grep for `caffeinate`, `IOPMAssertion`, `IOKit` over `rust/crates` found nothing.
- Hooks: only `PreToolUse`, `PostToolUse`, `PostToolUseFailure` in `enum HookEvent`; config.rs records other names as `unknown_hook_event`; USAGE.md "Hook configuration" and ROADMAP.md line 4312 ("claw-code supports 3 event types"). Config discovery order matches `ConfigLoader::discover`.
- Permission prompt: `CliPermissionPrompter::decide` prints "Permission approval required" and blocks on `io::stdin().read_line`; ROADMAP.md line 6161 files the gap.
- `worker-state.json`: `emit_state_file` writes it; `WorkerRegistry` is built only in `tools/src/lib.rs` (plus tests); the CLI only reads the file, and its help text claiming the REPL writes it is inaccurate.
- Telemetry: `grep -rli 'opentelemetry\|otlp\|OTEL_'` over the tree found no file. `SessionTracer::new` and `JsonlTelemetrySink::new` appear only in tests; `ConversationRuntime.session_tracer` defaults to `None` and `with_session_tracer` has no non-test caller.
- Provider and user agent: `DEFAULT_APP_NAME = "claude-code"`; `grok`, `grok-3`, `grok-mini`, `grok-3-mini`, `grok-2` are `ProviderKind::Xai` with `XAI_API_KEY`.
- Non-collision with the openclaw row: only `openclaw-tui|agent|acp|node` in other rows, compared exactly.
- claw-analog surface: binary name from Cargo.toml `[[bin]]`; its subcommands are `doctor`, `config`, `complete`, `agents`, so the three vetoes are its own. Not vetoed: `agents`, which runs sub-agents and is real work.

Unsupported or left inferred (kept, labelled as such in the row):

- `sh -lc "<one command>"` exec-in-place on macOS: still inferred. I did not run it (read-only rule).
- CPU floor 3%: an unmeasured guess, as the row says.
- "Bare `claw` collides with no other program": unsupported either way. A web search for a `claw` CLI found only OpenClaw material (a different name, `openclaw`), nothing conclusive. Treat a bare `claw` match as unverified against other software on a user's machine.
- Quiet gap during a long model stream, and MCP servers launched through a shell counting as tool children: unobserved, as the row says.

Not vetoed, left as is: `permissions`, `cost`, `clear`, `memory`, `ultraplan`, `usage`, `stats`, `fork`, `login`, `logout` return an error and exit at once (single-sample blip at most). Vetoing them would also hide a real one-shot such as `claw -p usage`, which the exact-argument rule cannot tell apart.

"Grok Bot" (asked for by the user): confirmed not part of this repo; xAI Grok appears only as a model provider here (see the provider check above). The xAI harness is the `grok-build` row.
