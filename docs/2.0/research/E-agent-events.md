# Research E: agents as event sources

Track E of [RESEARCH.md](../RESEARCH.md), issue FRIKKern/minmacs#5. Researched on 2026-10-27 on a MacBookPro18,1, Apple M1 Pro, macOS 27.0.1 [`sysctl -n hw.model machdep.cpu.brand_string`, `sw_vers`]. Everything here was read, nothing was installed or changed.

## Summary

- **MinMacs can learn most agent state today without installing any hook.** Claude Code writes a per-process file `~/.claude/sessions/<pid>.json` with `"status":"busy"|"idle"|"shell"`. On this Mac all 20 files agreed with the `caffeinate` child signal at one moment: 3 busy with `caffeinate`, 16 idle without it, 1 `shell` without it [joined snapshot of the files and `ps -axo pid=,ppid=,comm=`, 16:12 CET]. Codex keeps turn status in `~/.codex/thread_history_1.sqlite` table `thread_turns` [`sqlite3 ... immutable=1`].
- **cmux already injects Claude Code hooks into every session on this Mac** and streams them as `agent.hook.*` events over its Unix socket. 19 of the 20 running `claude` processes carry `--settings`. Pid 31251 runs as `claude --dangerously-skip-permissions` with no `--settings` [`ps -o args= -p <pid>` for each status file, verifier rerun]. `cmux events` gives MinMacs SessionStart, UserPromptSubmit, PreToolUse, Stop, SubagentStop and SessionEnd with `session_id`, `cwd` and `_ppid`, with nothing new installed [`cmux events --after 174371 --limit 4`].
- **When a hook is needed, the cheap recipe is an async command hook that appends one line to a spool file.** Claude Code and Codex both document `async: true`, and Claude Code does not enforce a timeout on async hooks. A synchronous hook can stall the agent. The cmux Codex wrapper says a synchronous hook made "every launch hang ~35s".
- **The MinMacs 1.2 probe calls 3 idle Claude sessions working on CPU alone.** Their status files say idle. Their status has not changed for 6 to 11 days [`tools/agents_probe.py`, the status files]. (unverified: a verifier rerun of the probe later the same day reported 3 working, all with a `caffeinate` child, and no session working on CPU alone.)
- **Registry check.** 1 of 63 rows has a running instance on this Mac (`claude-code`). 6 more have an install and session data that can be checked on the next use, with no install: `codex`, `cursor`, `pi`, `omp`, `warp` and `zed`. 2 rows have only a binary or app (`grok-build`, `xcode-agents`). The other 54 have nothing local beyond generic matches on `node` or `python3`.
- **`socket_activity` needs splitting into two signals.** One counts bytes moving on the agent's own connections. `nettop`, through the private NetworkStatistics framework, already counts them per process. The other asks a local status API, such as Herdr's socket or Kilo's `GET /session/status`.

## Method

- Read [PLAN.md](../PLAN.md), [RESEARCH.md](../RESEARCH.md) track E, [DESIGN.md](../../DESIGN.md), `registry/README.md`, `registry/schema.json`, all 63 `registry/agents/*.json` and `registry/evidence/conductor.md` on branch `main` at `7c3fe60`. That commit holds the same registry as `legacy` at `8882121`, since `git ls-tree` lists 63 rows on both.
- Read `Sources/Agents.m` and `Sources/Hosts.m` of MinMacs 1.2, `locohost/Sources/{Intel,Where,Ports}.m` at `c48cc39`, and `workforest/Sources/Trees.m`.
- Fetched vendor docs: Claude Code hooks, Codex hooks, Cursor hooks and cmux `agent-hooks.md`. Read pi 0.82.0 docs from its installed package.
- Ran only read commands: `ps`, `pgrep`, `ls`, `stat`, `find`, `mdfind`, `sqlite3` opened with `mode=ro` or `immutable=1`, `nettop`, `otool -L`, `strings`-style `grep -a -c`, and the cmux CLI commands `version`, `help`, `events --help`, `events --after … --limit 4`, `capabilities` and `docs agents`. I also ran `tools/agents_probe.py`, which spawns only `ps`, `pmset -g assertions` and `lsof` [`tools/agents_probe.py:35,103,143`]. It also reads each argv in process through `sysctl` `KERN_PROCARGS2` [`tools/agents_probe.py:17-26`].
- Two helper files were written to the session scratchpad: `rows.py` and its output `rows.tsv`, under `/private/tmp/claude-501/-Users-frikk-jarl-Documents-GitHub/ed8e842b-dd11-47b1-8a32-0ea5188ceb22/scratchpad/e/`.

## 1. Claude Code

**Version on this Mac.** Running sessions use 2.1.300 to 2.1.311 [`~/.claude/sessions/*.json` field `version`]. Binaries live in `~/.local/share/claude/versions/` [`ls`].

**Hook events.** The docs list 33 events: `SessionStart`, `Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `MessageDisplay`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `Elicitation`, `ElicitationResult` and `SessionEnd` [https://code.claude.com/docs/en/hooks]. The registry row lists 8 of them [`registry/agents/claude-code.json` `hooks.events`].

**Events MinMacs needs.**
- `UserPromptSubmit` starts a turn, and `Stop` ends one. `Stop` "does not run if the stoppage occurred due to a user interrupt. API errors fire StopFailure instead" [hooks docs, Stop section]. A detector therefore cannot rely on `Stop` alone.
- `Stop` carries `background_tasks` and `session_crons`, which "let hooks distinguish 'session is done' from 'session is paused waiting for background work'" [hooks docs]. That decides whether Insomnia should keep the Mac awake after a turn.
- `Notification` with `notification_type` `permission_prompt`, `idle_prompt`, `agent_needs_input` or `elicitation_dialog` marks the waiting state [hooks docs, Notification matcher table].
- `SessionStart` has `source` of `startup`, `resume`, `clear`, `compact` or `fork` [hooks docs].
- `WorktreeRemove` carries `worktree_path` [hooks docs].
- Every event carries `session_id`, `transcript_path`, `cwd`, `permission_mode` and `hook_event_name` [hooks docs, common input fields].

**Do not hook `WorktreeCreate`.** "Configuring a WorktreeCreate hook replaces that default git behavior", and the hook "must return the path to the created worktree directory" [hooks docs, WorktreeCreate]. An observer hook would break `claude --worktree`. Watch the folder with FSEvents instead.

**Handler types and cost.**
- Handler types are `command`, `http`, `mcp_tool`, `prompt` and `agent` [hooks docs].
- "By default, hooks block Claude's execution until they complete." The `async: true` field is "only available on `type: "command"` hooks". With it, "Claude Code starts the hook process and immediately continues without waiting", and it "doesn't enforce `timeout`" [hooks docs, Run hooks in the background].
- An `http` hook POSTs the input JSON. A non-2xx status or a "Connection failure" is a "non-blocking error" [hooks docs]. The docs do not offer `async` for `http`, so an HTTP hook waits for MinMacs to answer. The default timeout is 600 seconds [hooks docs, Default timeouts].
- Spawning `/bin/sh -c "cat >/dev/null"` took about 12 ms per run in this shell: 200 runs in 2.44 s [`/usr/bin/time -p`]. An async command hook pays that off the agent's path.

**Where sessions live.**
- Transcripts are at `~/.claude/projects/<cwd with / and . as ->/<session>.jsonl` [`registry/agents/claude-code.json` `session_store`; `locohost/Sources/Intel.m:315`]. This Mac has 9 project folders and 91 transcripts at depth 2 [`ls`, `find`].
- **Live state per process is at `~/.claude/sessions/<pid>.json`.** Fields include `pid`, `sessionId`, `cwd`, `startedAt`, `version`, `kind`, `entrypoint`, `status`, `statusUpdatedAt` and `messagingSocketPath` [`head` of `59666.json`]. The file also has `procStart`, `peerProtocol`, `peerFeatures`, `pidDomain`, `name`, `nameSource`, `nameSince` and `updatedAt` [same file, verifier rerun]. There are 20 files, one per running session [`ls ~/.claude/sessions/*.json | wc -l`]. The binary holds the strings `statusUpdatedAt` and `messagingSocketPath` [`grep -a -c` on `versions/2.1.310`]. I found no vendor doc for this folder, so it is undocumented and can change.
- `messagingSocketPath` points to `/tmp/cc-socks/<pid>.sock`, mode `srw-------` [`ls -la /tmp/cc-socks`]. I did not connect to it.
- I saw a `shell` status on one session. My guess is that it means a user `!` shell command, but I have no source for that.

**Where worktrees live.** `claude --worktree` and subagents with `isolation: "worktree"` create `<repo>/.claude/worktrees/<name>`. The docs show `worktree_path` as `/Users/.../my-project/.claude/worktrees/feature-auth` [hooks docs, WorktreeRemove input]. This Mac has 23 of them, in `barkpark`, `client-app` and `side-project` [`find ~/Documents/GitHub -maxdepth 4 -path '*/.claude/worktrees/*'`].

**Hooks installed today.** `~/.claude/settings.json` has no `hooks` key [keys printed: `agentPushNotifEnabled`, `attribution`, `editorMode`, `enabledPlugins`, `inputNeededNotifEnabled`, `model`, `notifications`, `skipDangerousModePermissionPrompt`, `tui`]. The hooks come from cmux through `--settings` (section 3).

## 2. Codex

**Version on this Mac.** codex-cli 0.154.0 [`codex --version`]. `/Applications/Codex.app` is version 26.506.21252, and `/Applications/ChatGPT.app` also has bundle id `com.openai.codex` [`mdfind`, `defaults read`]. The registry row names only ChatGPT.app [`registry/agents/codex.json` sources]. `codex` on PATH is the cmux shim `/var/folders/.../cmux-cli-shims/.../codex` [`which codex`]. No Codex process ran during this research [`pgrep -fl -i codex`].

**Hook events.** There are 12: `SessionStart`, `SessionEnd`, `SubagentStart`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStop`, `Stop` and `Interrupt` [https://learn.chatgpt.com/docs/hooks, redirected from developers.openai.com/codex/hooks].
- Config lives in `~/.codex/hooks.json`, `[hooks]` in `~/.codex/config.toml`, or the same in `<repo>/.codex/` for trusted projects [same page].
- "By default, Codex waits for a command hook to finish". `async: true` runs it in the background [same page].
- "Non-managed hooks must be reviewed and trusted before they run". New or changed hooks are "skipped until trusted" in `/hooks` [same page]. A MinMacs hook therefore needs one manual trust step from the user.
- `notify` in `config.toml` runs one program with one JSON argument, and `agent-turn-complete` is its only type [web search summary of the Codex config docs; I could not fetch the config reference, which returned 404] (unverified: the verifier's search also found only third-party pages. `registry/agents/codex.json` `hooks.config` says the same). On this Mac that one slot is taken: `notify = [".../SkyComputerUseClient", "turn-ended"]` [`~/.codex/config.toml:7`]. MinMacs must not take it over.

**Cost of a synchronous hook.** The cmux wrapper says: "codex runs hooks synchronously and BLOCKS until they return, so a synchronous `cmux hooks codex <sub>` made every launch hang ~35s on "Running SessionStart hook"". Its fix "nohup-backgrounds the real cmux call with a 30s watchdog, and `echo '{}'` returns to codex instantly" [`/Applications/cmux.app/Contents/Resources/bin/cmux-codex-wrapper:248-255`].

**Where sessions live, with no hook.**
- Rollouts are at `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl`, 118 files [`find`]. Turn markers are `event_msg` payloads `task_started` and `task_complete` [type counts over the newest rollout's last 300 lines].
- `state_5.sqlite` table `threads` has `cwd`, `git_branch`, `git_sha`, `rollout_path`, `source` and `updated_at`, 118 rows [`pragma table_info(threads)`]. MinMacs can link a thread to a worktree from this table without walking 30 days of folders, as `workforest/Sources/Trees.m` does today.
- `thread_history_1.sqlite` table `thread_turns` has `status` values `completed` 591, `interrupted` 8 and `failed` 1 [`sqlite3 "file:...?immutable=1"`]. The registry says `inProgress` marks a live turn [`registry/agents/codex.json` sources, 2026-09-29]. I saw no live turn.
- `~/.codex/thread-writer-locks/` holds only `.coordination.lock` [`ls -laR`]. `~/.codex/ipc/ipc.sock` exists [`ls`].

## 3. cmux

**Version.** cmux 0.64.22 (102) [`cmux --version`].

**Hooks it injects.**
- In a cmux terminal, `claude` resolves to `cmux-claude-wrapper`, which "intercepts `claude` invocations to inject --session-id and --settings flags" [`cmux-claude-wrapper:1-7`].
- The injected JSON hooks `SessionStart`, `Stop`, `SubagentStop`, `SessionEnd`, `Notification`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse` and `PermissionRequest` [`cmux-claude-wrapper:943`].
- The catch-all `PreToolUse` hook and the `Stop` feed run with `"async":true`. A second `PreToolUse` hook, matcher `CronCreate`, runs synchronously with `"timeout":5`. `SessionStart`, `Stop`, `Notification` and `UserPromptSubmit` run synchronously with `"timeout":10`, and `SessionEnd` with `"timeout":1` [same line].
- For Codex, the wrapper adds hooks per run and "nothing is written to ~/.codex" [`cmux-codex-wrapper:2-9`].
- For other agents, `cmux hooks setup <agent>` writes files such as `~/.pi/agent/extensions/cmux-session.ts`, `~/.cursor/hooks.json` and `~/.grok/hooks/cmux-session.json` [https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/agent-hooks.md]. None of those files exist on this Mac [`ls` of each path].

**What cmux exposes.**
- **Socket.** The path is `~/.local/state/cmux/cmux-501.sock`, mode `srw-------` [`$CMUX_SOCKET_PATH`, `ls -la`]. `cmux capabilities` reports `access_mode: automation` and lists `events.v1` [`cmux capabilities`].
- **`cmux events`.** It streams NDJSON frames with `seq`, `name`, `category`, `source`, `payload`, `workspace_id`, `surface_id` and `pane_id`. `--after <seq>` replays retained events, and `--cursor-file` resumes [`cmux events --help`, 4 frames replayed]. Payloads of `agent.hook.PreToolUse` carry `session_id`, `cwd`, `_ppid`, `tool_name`, `tool_input` and `redacted_fields` [same run]. cmux sets `tool_input` to `null` and lists it in `redacted_fields`: all 8,648 `tool_input` keys in `~/.cmuxterm/events.jsonl` are `null` [`grep -o`, verifier rerun].
- **Event mix.** The last 400 lines of `~/.cmuxterm/events.jsonl` hold `agent.hook.PreToolUse` 122, `feed.item.received` 72, `agent.hook.Stop` 8, `agent.hook.SessionStart` 4, `agent.hook.UserPromptSubmit` 4 and `agent.hook.SessionEnd` 4 [tail and count]. (unverified: the file grows, and a verifier rerun of the last 400 lines gave PreToolUse 127, feed.item.received 68, feed.item.completed 68, notification.clear_requested 63, sidebar.metadata.updated 63 and SubagentStop 8.) The file rotates near 16 MB, since `events.jsonl.1` is 16,777,188 bytes [`ls -la ~/.cmuxterm`].
- **Workstream log.** `~/.cmuxterm/workstream.jsonl` is 280,111,932 bytes [`ls -la`]. MinMacs 1.2 reads its last 2 MB plus `claude-hook-sessions.json` [`Sources/Hosts.m:142-238`].
- **Process tree.** LocoHost already calls `cmux top --all --processes --format tsv` for Where [`locohost/Sources/Where.m:97-103`].

**Cheap use.** Run one `cmux events --category agent --cursor-file <MinMacs state> --reconnect` per app launch, read-only, and filter by `--name`. This replaces the 2 MB tail read in MinMacs 1.2. cmux already redacts `tool_input` to `null`, but the payload still holds other fields, so MinMacs should keep only the event name, `session_id`, `cwd`, `_ppid` and the time.

## 4. pi

**Version and store.** `@earendil-works/pi-coding-agent` 0.82.0 at `~/.pi/agent/node_modules` [`package.json`]. Sessions are at `~/.pi/agent/sessions/--<path>--/<timestamp>_<uuid>.jsonl` [`docs/session-format.md:8`]. There are 26 files, the newest dated 2026-08-25 [`find`, `stat`].

**Events.** Hooks are TypeScript extensions in `~/.pi/agent/extensions/*.ts` or `.pi/extensions/*.ts` [`docs/extensions.md:117-120`]. Events include:
- `session_start` and `session_shutdown`
- `agent_start`, `agent_end` and `agent_settled`
- `turn_start` and `turn_end`
- `tool_execution_start` and `tool_execution_end`
- `tool_call`, which "Can block"
- `user_bash`
[`docs/extensions.md:388-860`]

**The end-of-work event.** "Use `agent_settled` for status integrations that need to know Pi will not continue running automatically" [`docs/extensions.md:558-561`].

**Cheap recipe.** An extension handler that does not `await` anything. On `agent_start` and `agent_settled` it writes one line to the MinMacs Unix socket and drops errors. This is a guess at the cleanest form: I have not run it. The registry row is still `inferred` [`registry/agents/pi.json`].

**What the user must install.** One file in `~/.pi/agent/extensions/`. Without it, MinMacs only has the session file's mtime and a shell child, both weak [`registry/README.md` row `pi`].

## 5. Cursor

**Install.** `/Applications/Cursor.app` and `cursor-agent` 2026.05.24-dda726e [`ls`, `cursor-agent --version`]. Cursor was not running [`pgrep`].

**Events.** `sessionStart`, `sessionEnd`, `preToolUse`, `postToolUse`, `postToolUseFailure`, `subagentStart`, `subagentStop`, `beforeShellExecution`, `afterShellExecution`, `beforeMCPExecution`, `afterMCPExecution`, `beforeReadFile`, `afterFileEdit`, `beforeSubmitPrompt`, `preCompact`, `stop`, `afterAgentResponse`, `afterAgentThought` and `workspaceOpen` [https://cursor.com/docs/agent/hooks].
- Config lives in `~/.cursor/hooks.json`, `<project>/.cursor/hooks.json` or `/Library/Application Support/Cursor/hooks.json` [same page].
- Hooks fail open: "Other exit codes - Hook failed, action proceeds". The page describes `sessionStart` and `sessionEnd` as fire-and-forget, and `afterAgentThought` has no output fields [same page].
- The page does not say clearly whether agent hooks fire in the CLI [same page].

**Where sessions and worktrees live.**
- `~/.cursor/chats/*/*/store.db`, 2 files [`rows.tsv`].
- `~/.cursor/projects/<slug>/agent-transcripts/<id>/<id>.jsonl`, 185 files, the newest dated 2026-09-02 [`find`].
- Worktrees are at `~/.cursor/worktrees/<repo>/<5-char id>`. On this Mac `client-ui/aJk6u` and `Y5dFe` are git worktrees of `~/Documents/GitHub/client-ui` [`.git` file `gitdir:` lines]. WorkForest's scan roots should include `~/.cursor/worktrees`.

**Signal with no install.** An app-wide Electron power-save blocker held per chat turn, but the assertion name is unverified [`registry/README.md` row `cursor`]. Cursor was not running, so I could not check it.

## 6. Conductor

**Not installed on this Mac.** There is no `/Applications/Conductor.app` and no `~/Library/Application Support/com.conductor.app` [`ls`]. Everything below is from `registry/evidence/conductor.md`, which itself rests on third-party readers.
- Worktrees are at `~/conductor/workspaces/<repo>/<city>`.
- State is in `~/Library/Application Support/com.conductor.app/conductor.db`, where `sessions.status = 'working'`.
- Agent processes carry `CONDUCTOR_SESSION_ID`, `CONDUCTOR_WORKSPACE_ID` and `CONDUCTOR_WORKSPACE_PATH`.
- Conductor has no hooks of its own. Claude Code hooks pass through, but whether `Stop` and `Notification` fire in its headless mode is an open question in that file.

## 7. Deliverable table

Verification statuses:
- **Seen** means a running instance was checked on this Mac today.
- **Data** means installed, with session files read today, but no live turn seen.
- **Absent** means not installed.

| Agent | Events | Paths | Cheapest recipe | What the user installs | Status today |
|---|---|---|---|---|---|
| Claude Code | 33 hook events. MinMacs needs UserPromptSubmit, Stop, StopFailure, Notification, SessionStart, SessionEnd and WorktreeRemove | `~/.claude/sessions/<pid>.json` with status, `~/.claude/projects/*/*.jsonl`, `<repo>/.claude/worktrees/*` | Watch `~/.claude/sessions/` with FSEvents or kqueue and read `status`. Optionally add an async command hook that appends to a spool file | Nothing. The hook is optional, through a MinMacs plugin or `--settings` | Seen: 20 sessions, status agrees with `caffeinate` 20 of 20 |
| Claude Code in cmux | agent.hook.* for 9 events, plus feed and notification events | `~/.local/state/cmux/cmux-501.sock`, `~/.cmuxterm/*.jsonl` | `cmux events --category agent --cursor-file … --reconnect` | Nothing. cmux already injects its hooks | Seen: 4 frames replayed, 19 of 20 sessions run with `--settings` |
| Codex | 12 hook events | `~/.codex/sessions/Y/M/D/rollout-*.jsonl`, `state_5.sqlite` threads, `thread_history_1.sqlite` thread_turns | Read `thread_turns.status` and the rollout tail. Optionally add an async command hook | Nothing. A hook needs a one-time `/hooks` trust step. Leave `notify` alone | Data: 118 threads, 600 turns, none live |
| cmux | `cmux events` names such as agent.hook.PreToolUse, feed.item.received and workspace.prompt.submitted | socket as above | the events stream with a cursor file | Nothing | Seen |
| pi | session_start, agent_start, agent_settled, turn_*, tool_execution_* and session_shutdown | `~/.pi/agent/sessions/--<path>--/*.jsonl`, `~/.pi/agent/extensions/` | One extension that sends one line to the MinMacs socket and never awaits | One extension file | Data: 26 sessions, no cmux or MinMacs extension. 13 other entries sit in `~/.pi/agent/extensions/` |
| Cursor | 18 agent hooks plus workspaceOpen | `~/.cursor/chats/*/*/store.db`, `~/.cursor/projects/*/agent-transcripts/`, `~/.cursor/worktrees/<repo>/<id>` | Power assertion with no install. Optionally an async hook in `~/.cursor/hooks.json` | Nothing, or one hooks.json entry | Data: 2 chats, 185 transcripts, 2 worktrees, not running |
| Conductor | None of its own. Hosted Claude Code hooks pass through | `conductor.db`, `~/conductor/workspaces/` | Read `sessions.status` | Nothing | Absent |

## 8. Hook recipe that does not slow the agent

For every agent that runs shell commands as hooks, use the same ingest:

1. The hook is `minmacs hook <agent>`, which is the MinMacs binary in CLI mode, run with `async: true` in Claude Code and Codex. Cursor documents no async field, so there the hook uses only the fire-and-forget events `sessionStart` and `sessionEnd`, plus `stop`, and exits at once.
2. It reads stdin and keeps only the event name, session id, cwd, pid, ppid and time. It appends one line of at most 512 bytes with `O_APPEND` to `~/Library/Application Support/MinMacs/events/<agent>.jsonl`, then sends a one-byte datagram to the MinMacs Unix socket. Both steps ignore every error and exit 0. The size limit and file layout are my proposal, not something measured.
3. The app reads the spool on the datagram, or on its 5-second Senses pass if the datagram is lost. Nothing breaks when the app is not running.

Why not the other options:
- **A Claude `http` hook.** It cannot be async, so MinMacs's response time becomes the agent's [hooks docs].
- **A synchronous hook.** It stalls the agent, as cmux saw with a 35 s hang [`cmux-codex-wrapper:250-253`].
- **Codex `notify`.** It is one slot and already taken [`~/.codex/config.toml:7`].

Which events to hook, for Claude Code: UserPromptSubmit, Stop, StopFailure, Notification, SessionStart and SessionEnd. Skip PreToolUse and PostToolUse, because they fire on every tool call: 122 of the last 400 cmux events [`events.jsonl` tail]. Never hook WorktreeCreate.

## 9. Registry check: 63 rows

I ran `rows.py` against each row's `surfaces[].process.names`, `surfaces[].bundle_ids` and `session_store.glob`, using `shutil.which`, `mdfind kMDItemCFBundleIdentifier` and `glob`, and `tools/agents_probe.py` for running processes.

| Group | Rows | What is local |
|---|---|---|
| Running, live signal checkable today | `claude-code` | 20 sessions, probe matched all 20 |
| Installed with session data, checkable on next use with no install | `codex`, `cursor`, `pi`, `omp`, `warp`, `zed` | `codex`: 118 rollouts and both apps. `cursor`: app, CLI and 2 chats. `pi`: 0.82.0 and 26 sessions. `omp`: `~/.local/bin/omp` and 3 sessions. `warp`: app and `warp.sqlite`. `zed`: app and `threads.db` |
| Binary or app only, no sessions | `grok-build`, `xcode-agents` | `grok` exists only as cmux's bundled `/Applications/cmux.app/Contents/Resources/bin/grok`. Xcode is installed with 0 agent transcripts |
| Matched only through another product | `junie`, `rovo-dev` | `junie` matched on Zed's bundle id, which the row lists as a host. `rovo-dev` matched on Cursor's id `com.todesktop.230313mzl4w4u92`. Neither has data |
| Generic process name only, nothing else | `aider`, `auggie`, `autohand`, `codebuddy`, `continue`, `deepagents`, `deepseek-harness`, `gemini-cli`, `hermes`, `letta`, `mastracode`, `mistral-vibe`, `openclaw`, `openhands`, `qoder`, `qwen-code`, `t3-code`, `trae` | `node` or `python3` is on PATH. That says nothing about the agent |
| Nothing local | the other 34 | no binary, no bundle, no session files |

Findings from the check:
- **The registry README is stale.** It says "Only `claude-code` was checked against a running instance (1 row `verified-locally`)" [`registry/README.md:9`], but `codex.json` is also `verified-locally` after a live `codex exec` turn on 2026-10-01 [`registry/agents/codex.json` sources].
- **The 1.2 probe treats idle sessions as working.** It reported 6 Claude sessions working, 3 of them on CPU alone at 3.4 to 5.0% [`tools/agents_probe.py` table] (unverified: a verifier rerun reported 3 working, all with `caffeinate`, and 17 idle). All 3 have `status: idle` with `statusUpdatedAt` 6.1 to 11.2 days old, and no `caffeinate` child. The `tree_cpu` floor of 3% [`registry/agents/claude-code.json` `working_signals`] makes them working. The status file should rank above `tree_cpu`.
- **Process names that match many tools.** A row whose only process name is `node`, `python3` or `bun` cannot be checked by presence. The detector needs `path_contains` or argv rules for those rows, as `claude-code` has.

## 10. Where `socket_activity` could come from

**Today.** The schema allows `socket_activity` [`registry/schema.json:149`], and 9 rows declare it: `agent-deck`, `aider`, `deepseek-harness`, `deepagents`, `herdr`, `kilo`, `letta`, `prime-agent` and `vscode-agents` [`grep -l`]. Neither detector evaluates it: `Sources/Agents.m:253-279` handles only `child_process`, `tree_cpu`, `transcript_write`, `tool_children` and `power_assertion`, and the README says the probe "still cannot evaluate `socket_activity`" [`registry/README.md:14`].

**The 9 rows mean two different things.**

1. **Bytes moving on the agent's own model connection.** `aider` and `deepseek-harness` mean this: an "established TCP connection … with bytes moving" [their `working_signals`].
   - `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` gives state and addresses, which LocoHost already reads [`locohost/Sources/Ports.m:326-357`]. Its `sockbuf_info` has only `sbi_cc`, the bytes queued now, not a running total [`MacOSX.sdk/usr/include/sys/proc_info.h:517-525`]. That is not enough to tell traffic from a kept-alive idle socket.
   - `nettop` gives running byte totals per process. In 2 s the busy session 59666 moved 6,427 bytes in and 163,184 out, while session 2095, idle for 11 days, moved 0 [`nettop -P -L 2 -s 2 -x -n -p 59666 -p 2095 -J bytes_in,bytes_out`]. A verifier rerun of the same command gave 5,107 in and 22,241 out for 59666, and printed no row at all for 2095.
   - `nettop` links `/System/Library/PrivateFrameworks/NetworkStatistics.framework` [`otool -L /usr/bin/nettop`]. That is private API, so MinMacs could either run `nettop -P -L 1 -J bytes_in,bytes_out -x -n` once per pass, or link the private framework. Running `nettop` is the safe choice and costs one process spawn.
2. **Asking a local status API over a socket.** The other 7 rows mean this.
   - `herdr`: the JSON socket `~/.config/herdr/herdr.sock`.
   - `kilo` and `vscode-agents`: `GET /session/status` on a loopback port.
   - `deepagents`: LangGraph thread status.
   - `letta`: WebSocket `update_loop_status`.
   - `prime-agent`: the supervisor's JSONL Unix socket.
   - `agent-deck`: `agent-deck list --json`.
   [each row's `working_signals[].meaning`]
   Each needs its own small client, and some need a password from the server's environment [`registry/agents/vscode-agents.json`]. This is a different signal: a query, not a measurement.

The schema should split `socket_activity` into `net_bytes`, which has a `floor_bytes` over a window, and `local_status`, which has a transport, an address and a field to read. `net_bytes` can share LocoHost's socket pass and one `nettop` sample per Senses pass.

## Recommendations

1. **PLAN §3, Know › Sessions.** Make `~/.claude/sessions/<pid>.json` the first Claude Code source for working, idle and waiting. Watch the folder with FSEvents and rank `status` above `caffeinate` and far above `tree_cpu`. Map the pid to the transcript by `sessionId` and to its worktree by `cwd`, which also removes the lossy folder-name encoding in `locohost/Sources/Intel.m:330` and `workforest/Sources/Trees.m:541`. Shared pattern: one session index for every expert.
2. **PLAN §3, Know › Where.** Replace the 2 MB tail of `workstream.jsonl` with one `cmux events --category agent --cursor-file … --reconnect` reader owned by the core. Keep only the event name, `session_id`, `cwd`, `_ppid` and the time. Drop `tool_input`. Shared pattern: one event reader feeding the Graph.
3. **PLAN §3, Know › Sessions, Codex.** Read `state_5.sqlite` threads, which has `cwd` and `git_branch`, and `thread_history_1.sqlite` `thread_turns.status` with `immutable=1` or `mode=ro`. Stop walking 30 days of rollout folders. Never write `notify`.
4. **PLAN §5, Out of the box.** Ship with zero hooks. The status file, cmux events, Codex SQLite and power assertions cover Claude Code, Codex, Cursor, omp, Warp and Zed on this Mac with nothing installed (unverified for Cursor, omp, Warp and Zed: this file checked no live signal for them). Offer hooks only as an opt-in per agent in Settings, written as async command hooks that call `minmacs hook <agent>`, with the spool and datagram recipe of section 8.
5. **PLAN §3, Senses.** Add one per-process byte counter, from `nettop` once per pass, to the 5-second pass. Feed it to `net_bytes` for `aider` and `deepseek-harness`, and to LocoHost's activity model. Shared pattern: one sampler.
6. **PLAN §2, Keep: agent registry.** Split `socket_activity` into `net_bytes` and `local_status` in `registry/schema.json`. Add a `session_status_file` signal for Claude Code. Fix the README count of `verified-locally` rows from 1 to 2. Add `/Applications/Codex.app` to the `codex` row.
7. **PLAN §3, Know › Git, and WorkForest scan roots.** Add `<repo>/.claude/worktrees/*`, `~/.cursor/worktrees/*/*` and `~/conductor/workspaces/*/*` as known worktree roots. Never install a `WorktreeCreate` hook, because it replaces Claude Code's own worktree creation.
8. **PLAN §6, keep-awake for a working agent.** Insomnia should treat Claude Code's `Stop` with a non-empty `background_tasks` or `session_crons` as still working, and `StopFailure` as idle. Shared pattern: one working-or-idle verdict per session, owned by MinMacs.
9. **PLAN §9, Phase 1.** Add a fixture test where a session with `status: idle` and 4% tree CPU must come out idle. `Sources/Agents.m:262-264` counts any tree CPU at or above the floor as working and reads no status file, so 1.2 fails that case by its code. The verifier's probe rerun saw no such session at that moment.

## Open questions

1. Is `~/.claude/sessions/<pid>.json` a stable interface? It is undocumented, and its `status` values `busy`, `idle` and `shell` came from observation only. What `shell` means is a guess.
2. Does `cmux events` need the socket password when MinMacs runs outside a cmux terminal? This research ran inside cmux with `CMUX_SOCKET_PATH` set. The help says a password comes from `--password`, `CMUX_SOCKET_PASSWORD` or Settings [`cmux help`].
3. Does Codex `thread_turns.status` show `inProgress` during a live TUI turn? No Codex process ran today.
4. Do Cursor's agent hooks fire in `cursor-agent`, and what is Cursor's power-assertion name? The docs do not say, and Cursor was not running.
5. Do Claude Code hooks and the status file work under Conductor's headless mode? Conductor is not installed.
6. Is running `nettop` once every 5 seconds cheap enough? I did not measure its CPU cost. Linking NetworkStatistics is private API and may break across macOS releases.
7. Should MinMacs ship a Claude Code plugin with hooks? A plugin's `WorktreeCreate` does not run with `--worktree --tmux` [hooks docs], which does not matter if MinMacs never hooks that event. Whether users accept a plugin install is a product call, not a research result.

## Verification

Verifier pass on 2026-10-27, read-only, on the same Mac. Each claim was checked against its cited source again. Live numbers were taken again with the same commands, so small drift in moving files is expected.

**What I checked.**
- Machine: `sysctl -n hw.model machdep.cpu.brand_string` and `sw_vers` gave MacBookPro18,1, Apple M1 Pro, macOS 27.0.1.
- Claude Code status files: 20 files in `~/.claude/sessions/`, 3 `busy`, 16 `idle` and 1 `shell`. The 3 busy pids 55599, 59666 and 77597 each have a `caffeinate` child, and no other session has one [`ps -axo pid=,ppid=,comm=`]. Versions run from 2.1.300 to 2.1.311. `grep -a -c` on `versions/2.1.310` found `statusUpdatedAt` 6 times and `messagingSocketPath` 5 times. `/tmp/cc-socks/*.sock` are `srw-------`.
- `--settings`: 19 of 20 session pids carry it. Pid 31251 does not. Corrected in the summary and the table.
- Claude Code hooks docs at https://code.claude.com/docs/en/hooks, all three parts of the page: 33 events, the `Stop` quote, the `background_tasks` quote, the Notification types, the `SessionStart` sources, both `WorktreeCreate` quotes, the `worktree_path` example, the common input fields, the five handler types, the async quotes, the `http` non-blocking errors, the 600 s default and the plugin `--worktree --tmux` note all match.
- `~/.claude/settings.json` keys match and there is no `hooks` key. 9 project folders, 91 transcripts at depth 2 and 23 `.claude/worktrees` entries: 18 in `client-app`, 4 in `barkpark`, 1 in `side-project`.
- Spawn cost: 200 runs of `/bin/sh -c "cat >/dev/null"` took 2.47 s real.
- Codex: `codex-cli 0.154.0`, the cmux shim on PATH, no `codex` process in `ps`. `/Applications/Codex.app` is 26.506.21252 with id `com.openai.codex`, and so is `ChatGPT.app`. The registry row names only ChatGPT.app. 118 rollouts, 118 `threads` rows with the cited columns, `thread_turns` completed 591, interrupted 8, failed 1. The newest rollout tail has `task_started` 4 and `task_complete` 5. `config.toml:7` is the `notify` line. The registry `inProgress` source is dated 2026-09-29 and the live `codex exec` turn 2026-10-01. `workforest/Sources/Trees.m:575` walks 30 days of rollout folders.
- Codex hooks page at https://learn.chatgpt.com/docs/hooks: 12 events, the config locations, the "waits" and `async` quotes and the trust quotes match. The `notify` type claim rests on third-party pages only, so it is marked unverified.
- cmux: version 0.64.22 (102). `cmux-claude-wrapper:1-7` and line 943 match, with two hooks added to the text: a synchronous `PreToolUse` guard for `CronCreate` and `SessionEnd` with `"timeout":1`. `cmux-codex-wrapper:2-9` and `:248-255` match. The socket path, mode, `access_mode: automation` and `events.v1` match. `cmux events --help` lists `--after`, `--cursor-file`, `--name`, `--category`, `--reconnect` and `--limit`. A replay of 4 frames from seq 174371 showed the cited frame fields. `tool_input` is always `null` and listed in `redacted_fields`, so that claim was corrected. `events.jsonl.1` is 16,777,188 bytes. `workstream.jsonl` has grown to 281,267,774 bytes. `cmux help` line 13 gives the password order. The three `cmux hooks setup` paths match https://raw.githubusercontent.com/manaflow-ai/cmux/main/docs/agent-hooks.md, and none of the three files exists.
- MinMacs and LocoHost code: `Sources/Hosts.m:142-238`, `Sources/Agents.m:253-279`, `tools/agents_probe.py:35,103,143`, `registry/schema.json:149`, `registry/README.md:9` and `:14`, `locohost/Sources/Ports.m:326-357` at `c48cc39`, `Intel.m:315` and `:330`, and `workforest/Sources/Trees.m:541` match. The `cmux top` call is at `Where.m:103`, so the range became 97-103. The probe also calls `sysctl` in process, which was added.
- SDK header `MacOSX.sdk/usr/include/sys/proc_info.h:517-525` holds `struct sockbuf_info` with no running byte total. `otool -L /usr/bin/nettop` lists NetworkStatistics.framework.
- `nettop`: the command works, but the numbers move. The rerun gave 5,107 in and 22,241 out for 59666 and no row for 2095. Added next to the original numbers.
- pi: 0.82.0 at `~/.pi/agent/node_modules`, `docs/session-format.md:8`, `docs/extensions.md:117-120`, the event headings at lines 392 to 851, "Can block" at line 753, and the `agent_settled` quote at 558-561 match. 26 sessions, newest 2026-08-25. `~/.pi/agent/extensions/` is not empty: it holds 13 other entries, so the table now says no cmux or MinMacs extension.
- Cursor: the app, `cursor-agent` 2026.05.24-dda726e, no Cursor process, 2 `store.db`, 185 transcripts with the newest on 2026-09-02, and two `client-ui` worktrees with matching `gitdir:` lines. The docs page at https://cursor.com/docs/agent/hooks lists the 18 agent hooks plus `workspaceOpen`, the three config paths and the fail-open quote. The page has no "don't block" phrase. It calls `sessionStart` and `sessionEnd` fire-and-forget, so both places that quoted it were corrected.
- Conductor: no app, no Application Support folder and no `~/conductor`. The four bullets match `registry/evidence/conductor.md` lines 23 to 39.
- Registry: 63 rows on `main` at `7c3fe60` and on `legacy` at `8882121`, with no diff under `registry/`. `rows.tsv` shows the groups in section 9 exactly, and 1 + 6 + 2 + 2 + 18 + 34 = 63. The 9 `socket_activity` rows and their meanings match. `codex.json` is `verified-locally`, so the README count is stale.
- Probe: a rerun of `tools/agents_probe.py` reported 20 sessions, 3 working, all with `caffeinate`, and 17 idle. It found no session working on CPU alone. The claim of 6 working with 3 on CPU alone could not be reproduced, so it is marked unverified. Recommendation 9 now cites the `tree_cpu` code at `Sources/Agents.m:262-264` instead.

**Counts.**
- Confirmed: 86 claims.
- Corrected: 9 claims. These are the `--settings` count, the probe's `sysctl` call, the status-file field list, the cmux hook timeouts, the `tool_input` redaction, the `Where.m` line range, the Cursor "don't block" quote, the pi extensions folder, and the recommendation 9 evidence. The `nettop` rerun numbers were added next to the original numbers.
- Unsupported, marked "(unverified)": 4 claims. These are the 1.2 probe reading of 6 working sessions, the exact tail counts of `events.jsonl`, the Codex `notify` single-type claim, and the no-install coverage of Cursor, omp, Warp and Zed in recommendation 4.
