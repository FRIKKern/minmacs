# Prior art: how other tools tell which coding agents run and what state they are in

Date of research: 2026-09-29. Machine: macOS 24.3.0 (Darwin), cmux 0.64.3 (83), Claude Code 2.1.284.
Scope: Herdr, cmux, Agent Sessions, CASS, Claude Squad, Conductor, Emdash, vibe-kanban, plus the ones found on the way: Agent Deck, Superset, Orca, CliDeck, Calyx, Tempest, CCGram, agentsview.

Evidence tags used on every finding:

- **[R]** read in a primary source: the tool's own public source or docs. The path or URL is given.
- **[O]** observed today on this Mac, or by fetching a public registry (npm, GitHub API). The exact command is given.
- **[T]** third party: a README, a blog, a catalog. Not checked against source.
- **[I]** inferred by me. Says so.

Source snapshots read (shallow clones, all fetched 2026-09-29): Herdr `master` at `fc86d86` (2026-09-29; latest release v0.9.1 of 2026-09-16), cmux `main` at `6093e59f`, Agent Sessions `a93b22b` (2026-09-26), CASS `9dabb0d` and its detection crate `franken_agent_detection` `f3c00b7`, Claude Squad `ce1ffb4` (2026-08-20), Emdash `873a3e2`, vibe-kanban `d5cbb53` (README says "sunsetting"), Agent Deck `035fd60`, CliDeck `20f9c26`, Calyx `b7099a8`, Tempest `3332b2a`. Conductor is closed source: docs only.

No session store was opened. Only file names, sizes and modification times were listed. No hook was installed, no terminal host was touched.

---

## 1. Answer in one screen

```
                         what the registry reads today          what the others add
                         -----------------------------          -------------------
 ps args  ---------------> names, path, args_contain    +  foreground process group + tty stdio   Herdr, cmux, Agent Sessions   no consent
 children / CPU / mtime -> caffeinate, tree_cpu, write  +  terminal TITLE glyphs (OSC 0/2, 9;4)    Herdr, Orca, Agent Deck       no consent, host must list titles
                                                        +  screen tail text                         Herdr, Agent Deck, Claude Squad, Agent Sessions   reads private text
                                                        +  hooks / plugins in the agent's config    cmux, Emdash, Superset, Calyx, Tempest, Herdr (6 agents)   install step
                                                        +  agent-owned structured stream            vibe-kanban, Conductor        only if you spawn the agent
```

Six findings:

1. **Nobody outside a terminal host gets "blocked" without an install or a screen read, with one exception: the terminal title.** The registry says hooks only (README section 2). Herdr's shipped manifests read "blocked" for Codex, Grok, Qwen Code, Hermes, Amp and Letta from the **terminal title or OSC 9;4 progress alone** (fixed keywords and glyphs, no screen text, no install). Orca's docs say it too, without naming per-agent rules. Table in section 4. Some titles are user-configurable (a Herdr Grok comment says so), so an absent title proves nothing.
2. **Herdr, cmux and Agent Sessions all gate on the terminal.** Herdr reads the foreground process group of the pty; cmux requires stdin and stdout to be TTYs before it treats an `ollama` process as an agent; Agent Sessions keeps only `ps` rows that have a tty. The registry has no such gate. I confirmed the inputs are readable by any same-user process (section 7, item 1).
3. **Herdr and cmux keep an explicit `unknown` state.** Herdr labels Codex `unknown` rather than `idle` when nothing decides it. The registry only has working and idle.
4. **The list of harnesses the registry lacks is long and mostly agreed.** 21 harnesses are named by at least one studied tool (table A), 11 of them by two or more state-detecting tools, and none has a row in `registry/agents/` or an id in `registry/harnesses.json`. Section 5 is that list.
5. **One existing row will misfire on a missing harness.** The `pi` row matches any `node` command line containing `pi-coding-agent/dist/cli.js`. That also matches Oh My Pi (`@oh-my-pi/pi-coding-agent/dist/cli.js`). Evaluated with `tools/agents_probe.py` `matches()` on a synthetic argv: both `@earendil-works/...` and `@oh-my-pi/...` return True [O].
6. **Two tools deliberately refuse fallbacks.** cmux deleted its title and newest-file-by-mtime layer; Emdash "does not infer agent status from terminal output". Both say a wrong state is worse than no state. The registry keeps `transcript_write` and `tree_cpu` as raise-only signals, which is compatible, but worth stating in the row schema.

---

## 2. The tools side by side

| Tool | Who starts the agent | How it knows an agent is there | How it decides working / idle / blocked | States | Kinds of harness |
|---|---|---|---|---|---|
| **Herdr** [R] | Herdr owns the pty (terminal multiplexer, Rust, Apache-2.0) | Foreground process group of the pane pty; name, `argv[0]`, wrapped script arg, known package path | Per agent: **hooks** are authoritative for 6 (pi, omp, mastracode, opencode, kilo, kimi); for the rest **screen-tail manifests** plus **OSC title/progress**; a hook can be session-identity only | idle, working, blocked, done (idle and not yet seen), unknown | 24 kinds, 22 with screen manifests |
| **cmux** [R][O] | cmux owns the terminal and injects env | env token `CMUX_SURFACE_ID`, tty and process-tree mapping, plus a 20-definition process scanner | **Hooks** (lifecycle running / idle / needsInput / unknown). Spec forbids title and mtime fallbacks | running, idle, needsInput, unknown | 20 scanner definitions; 16 hook installers on `main`; 9 installers in the installed 0.64.3 |
| **Agent Sessions** [R] | not a host; reads what is running | `ps axww -o pid,tty,command` needle match, then `lsof` for the open session log; `ps eww` for `ITERM_SESSION_ID` | **iTerm2 AppleScript** `is processing` plus the last lines of the session (`contents`); Codex rollout tail (`task_started` / `task_complete`) | activeWorking, openIdle | 16 session formats; live presence for 4 (Codex, Claude, OpenCode, Antigravity) |
| **CASS** [R] | none | Filesystem probes (one crate, `franken_agent_detection`) | none: history search only, no state | none | 32 connectors |
| **Claude Squad** [R] | Claude Squad owns a tmux session | its own tmux session | `tmux capture-pane`, hash compared every 500 ms: changed = Running; else a known prompt string = press Enter; else Ready | Running, Ready, Loading, Paused | claude, aider, gemini (prompt strings); anything else via `-p` |
| **Conductor** [T] | Conductor runs the agents; ships managed Claude Code, Codex, OpenCode executables | it launched them | closed source; docs say sessions run through the harness runtime. Mechanism not visible [I: structured stream, not screen] | not documented | 4: Claude Code, Codex, Cursor (via API), OpenCode |
| **Emdash** [R] | Emdash (Electron) | it launched them | **Hooks or plugins only**; `agents/integrations/providers.md`: "Emdash does not infer agent status from terminal output" | idle, working, awaiting-input, error, completed | 37 providers, 23 with ACP |
| **vibe-kanban** [R] | vibe-kanban spawns them | it launched them | Parses each agent's structured stdout it asked for (`stream-json`, `app-server`, `--acp`) | not a status feed | 9 executors + claude-code-router; **project is sunsetting** |
| **Agent Deck** [R] | tmux sessions it creates | tmux `list-panes`, `pane_title`, `pane_current_command` | Title glyph, then `capture-pane` busy/prompt patterns per tool; hooks for Claude, Gemini; Codex `notify` hook; pi extension | running, waiting, idle, error | ~13 with presets or hooks |
| **Superset** [R docs][T] | Superset terminals | it launched them | **Hooks and command wrappers** in `~/.superset/bin`; docs: status only works for agents launched through Superset | working / needs input / finished | 21 named + any CLI |
| **Orca** [R docs][T] | Orca terminals | recognised agent CLI started from its combobox | **OSC title + hooks**; idle = ~30 min quiet with no completion report | working, waiting (Needs You), done, red (blocked / interrupted / failed), idle | 34 named + any CLI |
| **CliDeck, Calyx, Tempest, CCGram** [R/T] | own terminals or tmux | launched by them | hooks and per-agent classifiers (CliDeck ships `*-hook.js` and `*-screen.js` per provider; file names only, contents not read). Calyx and CCGram also read Herdr | working, blocked, idle, done | 6 to 16 each |
| **agentsview** [T] | none | Session directories | none: cost and history | none | ~60 stores |

### Harness lists as printed by each tool (for the DIFF in section 5)

- **Herdr** (24, `src/detect/mod.rs` `Agent::ALL` [R]): pi, claude, codex, gemini, cursor (`cursor-agent`), devin, antigravity (`agy`), cline, omp, mastracode, opencode, copilot, kimi, kiro (`kiro-cli`), droid, amp, grok, hermes, kilo, qodercli, qwen, letta, maki, muse.
- **cmux process scanner** (20, `Sources/CmuxTaskManagerCodingAgentDefinition+BuiltIns.swift` [R]): claude, codex, grok, opencode, omp, campfire, pi, amp, cursor, gemini, kiro, antigravity, rovodev, hermes-agent, copilot, codebuddy, factory (droid), qoder, kimi, ollama.
- **cmux hook installers** (`docs/agent-hooks.md` on `main` [R]): codex, grok, opencode, pi, omp, campfire, amp, cursor, gemini, kimi, kiro, rovodev, copilot, codebuddy, factory, qoder; Claude through the wrapper; antigravity through `~/.gemini/config/hooks.json`. The **installed** 0.64.3 lists only `codebuddy, codex, copilot, cursor, factory, gemini, opencode, qoder, rovodev` [O: `strings -a /Applications/cmux.app/Contents/Resources/bin/cmux | grep "cmux hooks "`].
- **Agent Sessions** (`README.md` "Supported sources" [R]): Codex, Claude Code, Cursor, GitHub Copilot CLI, OpenCode, Antigravity, Pi, Kimi Code, Grok CLI, Hermes, OpenClaw, Qwen Code, Devin CLI, fx, Cline (CLI and Desktop), DeepSeek Harness; Droid legacy.
- **CASS** (32, `franken_agent_detection/src/connectors/mod.rs` `get_connector_factories` [R]): codex, cline, gemini, claude, clawdbot, vibe, amp, antigravity, aider, pi_agent, prime_agent, omp, factory, kimi, kiro, muse, openclaw, openhands, copilot (VS Code chat), copilot_cli, qwen, grok, devin, grok_bot, codebuff, opencode, chatgpt, cursor, goose, crush, hermes, shelley.
- **Claude Squad** (`README.md` [R]): Claude Code, Codex, Gemini, "and other local agents including Aider".
- **Conductor** (`conductor.build/docs/reference/harnesses` [R]): Claude Code, Codex, Cursor, OpenCode.
- **Emdash** (37, `packages/plugins/src/agents/registry.ts` [R]): codex, claude, grok, devin, qwen, droid, antigravity, cursor, copilot, amp, commandcode, opencode, hermes, charm, auggie, goose, kimi, kilocode, kiro, rovo, cline, codebuddy, continue, codebuff, freebuff, mistral, jules, junie, oh-my-pi, pi, prime-agent, qoder, letta, autohand, mimocode, muse, zero.
- **vibe-kanban** (`crates/executors/src/executors/mod.rs` `CodingAgent` [R]): claude-code, amp, gemini, codex, opencode, cursor-agent, qwen-code, copilot, droid; plus claude-code-router (`claude.rs:63`).
- **Agent Deck** (`README.md` and `internal/tmux/patterns.go` [R]): claude, gemini, opencode, codex, copilot, crush, muse, cursor, hermes, pi, deepseek harness (`dsh`), omp, codewhale, openclaw, commandcode (test file), plus custom `[tools.*]`.
- **Tempest** (`config/agents.json` [R]): agy, claude, cline, codex, `gh copilot`, cursor, gemini, goose, opencode, hermes, pi, amp, fx, qwen, droid, grok.
- **Superset** (`README.md` [T]): Amp, Antigravity CLI, Claude Code, Codex, Cursor Agent, Droid, fx, Gemini CLI, GitHub Copilot, Grok, Hermes, Muse Code, Devin, Kimi Code, Kiro, Mastra Code, Mistral Vibe, Oh My Pi, OpenCode, Pi, Polygraph.
- **Orca** (`README.md` [T]): Claude Code, Codex, Grok, Cursor, GitHub Copilot, Muse, DeepSeek Harness, ZCode, OpenCode, MiMo Code, Amp, OpenClaude, Antigravity, Pi, oh-my-pi, Hermes Agent, Devin, Goose, Auggie, Autohand Code, Charm, Cline, CodeBuddy, Codebuff, Freebuff, Command Code, Continue, Droid, Kilocode, Kimi, Kiro, Mistral Vibe, Qwen Code, Rovo Dev.
- **CliDeck** (`src/*-provider.js` [R]): claude, codex, gemini, opencode, antigravity, pi, shell. **Calyx** (`README.md` [R]): Claude Code, Codex, OpenCode, Hermes, Grok, pi (recognises herdr as a host). **CCGram** (`README.md` [R]): Claude Code, Codex, Gemini, Pi, Shell, with a Herdr backend.

---

## 3. Mechanisms, and what each gets right that the registry does not

### 3.1 Herdr (read closely)

**Identity.** Herdr owns the pty, so it asks the kernel which process group is in the foreground of that terminal. On macOS: `proc_pidinfo(PROC_PIDTBSDINFO).e_tpgid` and `tcgetpgrp` (`src/platform/macos.rs` `foreground_process_group_id` [R]); argv from `sysctl(KERN_PROCARGS2)` (same file [R]). Then it names the agent from, in order (`src/detect/mod.rs` `identify_agent_in_job`, `normalized_process_name` [R]):

1. the process-group leader's name or `argv[0]`, through an alias table (`claude`, `claude-code`; `cursor`, `cursor-agent`; `agy`, `antigravity`, `antigravity-cli`; `kiro`, `kiro-cli`; `qodercli`, `qoderclicn`, `qoder`, `qodercn`; `opencode`, `opencode2`, `open-code`; `copilot`, `github-copilot`, `ghcs`; `devin`, `devin-cli`; `muse`, `muse-code`, `muse-cli`, and the launcher name `muse-bin-<digit...>`);
2. when the process is a runtime (`node`, `bun`, python, `sh`, `bash`, `zsh`, `fish`, `cmd`, `pwsh`), the first script argument, skipping known option flags;
3. exact package-path suffixes: `node_modules/@earendil-works/pi-coding-agent/dist/cli.js` (pi), `node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js` (omp), `node_modules/@moonshot-ai/kimi-code/dist/main.mjs` (kimi), `@qwen-code/qwen-code/dist/index`, `mastracode/dist/cli`, `@letta-ai/letta-code/letta`, and cursor's `cursor-agent/versions/<v>/node.exe index.js`.

Other identity rules: an env hint `HERDR_AGENT=<agent>` names the agent when a sandbox wrapper hides it (`fence`, `nono`), documented in `docs/next/website/src/content/docs/agents.mdx` [R]; Letta headless runs (`-p`, `--json`, `--stream-json`, `--output-format` and more) are rejected as non-interactive (`is_interactive_letta_process` [R]); a shell auto-attaching tmux inside a pane hides the agent, and the docs say so.

**State.** One authority per pane (`agents.mdx` "Status authority" [R]):

- Agents with full lifecycle hooks (pi, omp, mastracode, opencode, kilo, kimi): hook reports, no screen fallback. Two of them (omp, mastracode) have **no** screen manifest at all: from outside Herdr they have no signal.
- Everyone else: TOML manifests evaluated on the live bottom of the buffer (not the scrolled viewport), each rule with a region, a priority, AND/OR gates and `not` gates; plus the OSC title and OSC 9;4 progress string.
- Blocked is strict: only visible approval or question UI. No matching rule for a known agent falls back to `idle` (`default_known_agent_idle_fallback`), except **Codex, which falls back to `unknown`**: "its title and composer can look the same during an active turn and after a response" (`agents.mdx` [R]).
- Working to idle needs confirmation: a plain-idle read after working is held until 3 consecutive reads or 700 ms (`src/pane/agent_detection.rs` `AGENT_PENDING_IDLE_CONFIRMATIONS = 3`, `AGENT_PENDING_IDLE_CAP = 700 ms` [R]). Poll ticks are 300 ms for an identified pane and 500 ms for an unidentified one (`src/pane.rs` [R]); process recheck 5 s.
- Manifests are versioned data (`version = "2026.09.11.1"`, `min_engine_version`), updated from herdr.dev without a release, with local overrides in `~/.config/herdr/agent-detection/<agent>.toml` and a `herdr agent explain` command that prints which rule matched. Adding a new agent still needs a binary update.

**Outside surface.** Named socket `~/.config/herdr/herdr.sock` (or `HERDR_SOCKET_PATH`); `herdr agent list` and the `agent.list` API return `agent_status` in `idle | working | blocked | done | unknown` (`socket-api.mdx` [R]). CCGram [R README] and Calyx [R README] already read it. Whether that socket needs opt-in is the job of `hosts-2`; not tested here (Herdr is not installed).

**What it gets right that the registry does not.**

| # | Herdr does | Registry today |
|---|---|---|
| 1 | Gates on the foreground process group of the terminal | No terminal gate; background helpers and one-shots pass |
| 2 | Per-agent title and progress rules, as versioned data (section 4) | No `title_signal` field; `hosts.md` proposed one but no row has it |
| 3 | Exact package-path suffixes for node-hosted agents | `pi` row uses a substring, which also matches Oh My Pi [O] |
| 4 | `unknown` as a first-class state | Only working / idle |
| 5 | Rejects headless runs of an interactive agent by flag list (Letta) | `exclude_args` exists, only a few rows use flag lists |
| 6 | Launcher-name pattern (`muse-bin-<digit...>`) | `names` is exact-match only |
| 7 | Wrapper hint by env | Nothing; a wrapped agent is invisible |
| 8 | Two agents have no outside signal and Herdr says so | Registry rows do not carry "no outside signal" as a value |

**Caveat that matters for MinMacs.** Herdr's screen tail contains the conversation. The registry rule is "never print message content". Use the title data; do not adopt screen reading. [I]

### 3.2 cmux

- **Binding is by construction, not by guess.** `docs/agent-session-tracking-spec.md` [R]: cmux injects `CMUX_SURFACE_ID` / `CMUX_WORKSPACE_ID` at spawn; a fired hook resolves its surface by flags, then env, then controlling tty, then process tree. Principle 3: "No unreliable fallback": the title/mtime layer was deleted.
- **A process scanner in the same shape as the registry.** `CmuxTaskManagerCodingAgentDefinition` has `launchKinds`, `directBasenames` and `argumentNeedles` per agent, and a primary-plus-alternate rule set for interpreter-hosted agents (`VaultAgentProcessScannerDetectRules.swift` [R]). It also lists wrappers as launch kinds: `omc` (oh-my-claude), `omx` (oh-my-codex), `omo` (oh-my-openagent).
- **Interactive means TTY on both ends.** For `ollama run`, cmux requires the process to be the terminal's foreground process group and both stdin and stdout to be TTY vnodes, because `cat prompt | ollama run model` is a one-shot (`VaultAgentProcessScanner+Ollama.swift` [R]). It identifies by the kernel-reported executable path, never argv, because argv is user-controlled.
- **Turn state for a REPL with no hooks:** `promptTurnDetection` with the prompt string `>>> ` and the waiting suffix `Send a message (/? for help)` (Ollama definition [R]).
- **Kimi retitles itself.** A source comment says Kimi's Python entrypoint overwrites its own process title and argv with "Kimi Code" (`...BuiltIns.swift` [R]), so `directBasenames` includes `"kimi code"` with a space.
- **Env as a discriminator.** Campfire is restorable only if `CAMPFIRE_SESSION_ROLE=host` (`VaultAgentProcessScannerDetectRules.swift` [R]).
- **Local proof of the lifecycle model.** `~/.cmuxterm/claude-hook-sessions.json` and `workstream.jsonl` exist here (9.9 KB and 74 MB, modified today) [O: `ls -la ~/.cmuxterm`]. The wrapper `/Applications/cmux.app/Contents/Resources/bin/claude` injects `--session-id` and `--settings` when `CMUX_SURFACE_ID` is set [R: file header]; a live Claude here carries `--settings {"preferredNotifChannel":"notifications_disabled","hooks"...` [O: `ps -axo pid=,ppid=,pgid=,tpgid=,tty=,stat=,command=`]. The title-versus-`caffeinate` agreement (7 of 7) is in `hosts.md`, not repeated.
- **Hibernation as a test of "idle".** It kills only agents whose lifecycle is `idle`, background, quiet for `idleSeconds` and unchanged for `confirmationSeconds` (~60 s), after sampling the terminal tail and a process fingerprint (`docs/agent-hooks.md` [R]).

**Gets right that the registry lacks:** `launchKinds` for wrappers; the TTY-both-ends rule; kernel path over argv for identity; env discriminators; a spec that says which signals are never allowed.

### 3.3 Agent Sessions (jazzyalex)

- **Process to transcript through open files.** `lsof -w -a -c codex -u <user> -nP -F pftn` finds the session log a process holds open; for Claude it filters `ps axww -o pid=,tty=,command=` to rows with a tty and needle `claude` or `claude-code`, then runs `lsof -p` on those pids (`AgentSessions/Services/PresenceEngine.swift` ~lines 1240-1300 and `CodexActiveSessionsModel.swift` `discoverPresencesFromRunningCommands` [R]). Headless `claude -p` runs have no tty and are matched separately and told apart from Claude Desktop by bundle location.
- **Host tab from env.** `ps eww -p <pids>` is parsed for `TERM_PROGRAM` and `ITERM_SESSION_ID` to bind a process to an iTerm2 session (`CodexActiveSessionsModel.swift` `parsePSEnvironmentOutput` [R]).
- **State from iTerm2.** AppleScript `is processing of s` is "the most reliable signal" for a generic agent; `contents of s` gives the tail, classified by marker lists: `esc to interrupt`, `re-connecting`, Codex `• working`, then prompt glyphs `› > $ # % ❯ λ`, then weak words in the last two lines (`classifyITermTail`, `classifyGenericITermTail`, `classifyClaudeITermTail` [R]). A short grace window prevents active-to-idle flicker on an inconclusive read.
- **Codex desktop:** the newest lifecycle record in a 1 MiB tail of the rollout: `task_started` = working, `task_complete` / `turn_aborted` = idle; `item_completed` with a `turn_id` = working (`CodexDesktopTurnStateReader` [R]). Same idea as the `codex` row.
- **Name-collision guard for a short name.** For `fx` it demands `~/.fx` next to the binary, because "a bare `fx` on PATH is weak evidence by itself" (`AgentSessions/Fx/FxSourceDescriptor.swift` [R]).
- **Weakness:** substring needles (`commandContainsNeedle`). The registry's exact-name rule is stricter and correct.

**Gets right that the registry lacks:** the tty filter, the headless split, `lsof` process-to-transcript, env-based host binding, and an "AND a data directory" gate for short names.

### 3.4 CASS (coding_agent_session_search)

Not a state detector. Its value is the harness catalog and the store layouts. `franken_agent_detection` decides "installed" by filesystem probes only and admits a store by schema signature, never by file name alone (Shelley connector header [R]).

**Gets right that the registry lacks:**

- **Several roots and env overrides per harness.** Kimi `$KIMI_CODE_HOME/sessions/*/*/agents/*/wire.jsonl` plus legacy `~/.kimi/sessions`; Grok `GROK_HOME`; Pi `PI_CODING_AGENT_DIR`; OMP `~/.omp/agent/sessions`, `~/.omp/profiles/<name>/agent/sessions`, XDG stores and `OMP_PROFILE`; Devin `CASS_DEVIN_DATA_ROOT`; DSH `DSH_HOME` (README "Universal Connectors" [R]). The registry `session_store.glob` is one string.
- **Claude Desktop sidecars** under `~/Library/Application Support/Claude/claude-code-sessions` and `.../local-agent-mode-sessions` (README [R]; agentsview says the same for "Claude Cowork" [T]). Not in `claude-code.json` [O: `grep -r "claude-code-sessions\|local-agent-mode" registry` returned nothing]. Not present on this Mac [O: `ls ~/Library/Application\ Support/Claude/` gave "No such file or directory"], so unverified locally.
- **One store, two products.** Codebuff and Freebuff write the same `~/.config/manicode/...` store and no record says which binary wrote it (README [R]). The registry has no field for "shares a store with".
- **A per-conversation working flag in one harness.** Shelley's SQLite `conversations` table lists an `agent_working` column in the connector header (`franken_agent_detection/src/connectors/shelley.rs` line 12 [R]). I did not see a real Shelley database. [I: this would be the only stored working flag found in any prior art.]
- **Layout drift to check in our rows [I]:** CASS reads Qwen Code at `~/.qwen/tmp/*/chats/session-*.json`; `qwen-code.json` says `~/.qwen/projects/*/chats/*.jsonl`. agentsview says `~/.qwen/projects/` [T]. One of CASS's paths is probably an older layout. Not resolved.

### 3.5 Claude Squad

`session/tmux/tmux.go` `HasUpdated` [R]: capture the pane, SHA-hash it, compare with the last tick. Changed since last tick = `Running`. Unchanged and a known prompt string is present = press Enter (`app/app.go` lines 244-249 [R]). Otherwise `Ready`. Prompt strings: Claude `No, and tell Claude what to do differently`; Aider `(Y)es/(N)o/(D)on't ask again`; Gemini `Yes, allow once`; gated on the program name (`session/tmux/tmux.go` lines 254-260). The tick is 500 ms.

**Gets right:** nothing the registry lacks. It shows the limits of "screen changed": a clock or spinner makes an idle agent look busy, and it has no blocked state (it answers the prompt itself). It does confirm the three prompt strings.

### 3.6 Conductor

Closed source. Docs list four harnesses and say Claude Code, Codex and OpenCode "come bundled": Conductor ships its own executable of each (`conductor.build/docs/reference/harnesses` [R]). A third-party post says it uses the official SDKs [T]. Consequence for the registry [I]: a bundled Claude Code inside `Conductor.app` will not match `path_contains: /claude/versions/`, and the SDK may run it without a tty. Conductor is not installed here, so untested.

### 3.7 Emdash

`agents/integrations/providers.md` [R]: "Agent activity, completion, and attention states come from explicit hooks or plugins... Emdash does not infer agent status from terminal output. If a provider has no hook/plugin integration for an event, the renderer should not show or notify an inferred status." Hook installs are marker-tagged, versioned, done under a per-root write lock, and are no-ops outside Emdash sessions (an env var check). Muse installs hooks through `managed_hooks_path` in `settings.json`. Event types: `notification | stop | error | start` with notification kinds `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog` (`apps/emdash-desktop/src/core/primitives/agents/api/agent-events.ts` [R]).

**Gets right that the registry lacks:** a per-provider table of **hook roots and their env overrides** (Claude/Codex/Copilot/Qwen/Kimi/Kiro/Vibe: home env then home; OpenCode/MiMo/Devin: XDG or APPDATA; Pi `$PI_CODING_AGENT_DIR`; Antigravity `~/.gemini/config`; Muse `$XDG_CONFIG_HOME/muse`) and the list of 37 provider ids. The registry's `hooks.config` is one string.

### 3.8 vibe-kanban

Spawns each agent in a structured mode and parses its stdout: Claude `--output-format=stream-json --input-format=stream-json`, Droid `droid exec --output-format stream-json`, Amp `--execute --stream-json`, Cursor `-p --output-format=stream-json`, Codex `app-server`, Qwen and Copilot `--acp` (`crates/executors/src/executors/*.rs` [R]). It cannot observe an agent it did not start. The README says the project is sunsetting. Nothing for the registry except the reminder that the agent's own structured mode is the only exact turn state, and only for a parent that owns the agent.

### 3.9 Others found

- **Agent Deck** [R]: reads the tmux `pane_title` first (Claude: braille U+2800-28FF = working; done markers ✳ ✻ ✽ ✶ ✢), then `capture-pane`. Busy patterns are checked before prompt patterns so a visible composer cannot mask a working session. Each preset says whether it was **captured live or inferred** in a comment (`omp` captured on v17.3.8, `muse` on 1.0.2, `dsh` busy patterns "INFERRED, not captured"). Adds a fourth state, **error**: a Codex banner led by `■` with "hit your usage limit" (`internal/tmux/patterns.go`, `codexUsageLimitBannerPatterns` [R]). This is the provenance habit the registry already follows in `sources` and `confidence`.
- **Orca** [R docs `onorca.dev/docs/model/agents-sessions`]: "State is detected from the terminal's OSC title sequence and agent hooks." Only agents started from its picker are recognised, "not a recognized agent CLI" = no indicator.
- **Superset** [R docs `docs.superset.sh/agent-status`]: hooks and wrappers only; "status only works for agents launched through Superset". "Support varies by agent... Some agents don't emit a waiting-for-input signal yet."
- **Tempest** [R `src-tauri/src/agent_hooks.rs`]: a loopback receiver on an ephemeral port with a per-run token, published in `~/.tempest/hooks/endpoint.{env,cmd}`; the hook script re-reads it, so hooks survive an app restart.
- **Calyx** [R README]: state rows plus child rows for subagents that the CLI reports (Claude Code, Codex, OpenCode, Grok).

---

## 4. Data to copy: what Herdr matches on the terminal title

From `src/detect/manifests/*.toml` [R], quoted as regex/keyword. A title read is a first glyph or a fixed phrase, never the remainder of the title.

| Harness | working | blocked | idle | Progress (OSC 9;4) |
|---|---|---|---|---|
| Claude Code | `^[U+2800-28FF U+25D0-25D3] ` (braille up to 2.1.227; half-circle spinner from 2.1.228, per the manifest comment) | none on title | `^U+2733 ` (✳) | `^4;0` = idle |
| Codex | braille spinner as a token | `Action Required` | none; falls back to **unknown** | none |
| Grok | `(^\|\s)[U+2801-28FF](\s\|$)`; progress `^4;1;-1$` | `Action Required` | title ends with `grok`, and no braille | `^4;0;0$` = idle |
| Qwen Code | `^U+25D0 ` (◐) | **`^U+2733 ` (✳)** | composer text | `^4;3` = working |
| Hermes | `^⏳` | `^⚠` | `^✓` | none |
| Amp | `^[U+2800-28FF] ` | `Plugin confirmation needed` | contains ` - amp - ` | none |
| Kiro | `^[◐◓◑◒/\|\\-]\s+kiro:` | none | none | `^4;3;?$` = working |
| Letta | braille spinner | `^\[ [!.] \] Action Required` | none | `^4;3` = **blocked** |
| Maki | none: "does not set OSC title or OSC 9;4 progress" | none | none | none |

Grok's manifest carries the comment "Title items are configurable; omitting "grok" does not imply activity. Require a spinner, with OSC progress covering titles that omit it." Two more things to notice. **The same glyph means opposite things:** ✳ is idle for Claude Code and blocked for Qwen Code. And OSC 9;4 state 3 means working for Kiro and blocked for Letta. A generic glyph rule would be wrong; the table must be per harness. Herdr's Claude working glyphs match what `hosts.md` saw here (◐ and ◑ with a `caffeinate` child, 7 of 7).

---

## 5. THE DIFF

Rule used: a harness is listed when a studied tool names it and it has **no file in `registry/agents/`** and **is not in `registry/harnesses.json`** (base list, `wave2.harnesses`). Directory listing taken at the end of the task: 30 rows (the 22 originals plus `auggie`, `cline`, `herdr`, `kilo`, `kimi`, `kiro`, `mistral-vibe`, `xcode-agents`, which appeared while I worked; other tasks write them). None of the 21 harnesses in table A has appeared as a file. Ids below follow the schema pattern `^[a-z0-9-]+$` and are proposals.

Columns: **Named by** lists the tools and, in brackets, the source. "SD" = state-detecting tools (Herdr, cmux, Emdash, Agent Deck, Superset, Orca, Tempest, Agent Sessions live presence). **First-party check** is what I fetched today: npm `registry.npmjs.org/<pkg>/latest` and GitHub `api.github.com/repos/<owner>/<repo>` [O].

### 5.1 Table A: named by at least one tool that runs, watches or hooks agents, or by a CASS connector (21)

| # | Proposed id | Named by | Identity facts | First-party check [O] | What is known about state |
|---|---|---|---|---|---|
| 1 | `omp` (Oh My Pi) | Herdr [R `Agent::Omp`], cmux [R scanner + hooks], Emdash [R `impl/oh-my-pi`], Agent Deck [R preset], Superset [T], Orca [T], CASS [R `omp.rs`], agentsview [T] (8; 6 SD) | bin `omp`; runs as `.../node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js`; store `~/.omp/agent/sessions/<safe-path>/<ts>_<uuid>.jsonl`, profiles `~/.omp/profiles/<name>/agent/sessions` | npm `@oh-my-pi/pi-coding-agent` 18.4.3 bin `omp`; GitHub `can1357/oh-my-pi` 33.7k stars, pushed 2026-09-29 | Herdr: hook-only, no screen manifest. Agent Deck (captured live, v17.3.8): busy = literal `⟨esc⟩` (U+27E8/27E9) with braille spinner; approval = `Allow tool:` line. **Collides with the `pi` row today** (section 1, item 5) |
| 2 | `muse` (Muse Code, Meta) | Herdr [R], Emdash [R `impl/muse`], Agent Deck [R], CASS [R `muse.rs`], Superset [T], Orca [T] (6; 5 SD) | bin `muse` at `~/.local/bin/muse` from `curl -fsSL https://dev.meta.ai/install.sh \| bash`; launcher execs `muse-bin-<version>` (e.g. `muse-bin-0.1.0-R708.1`); store `~/.local/share/muse/sessions/YYYY/MM/DD/<id>/session.jsonl` plus `.session.lock` | Not fetched: vendor page `dev.meta.ai/docs/muse-code` (Emdash `websiteUrl`). CASS header calls it "Meta's terminal coding agent, new as of August 2026" and its layout comes from a field report, "not vendor documentation" | Emdash hooks `SessionStart`, `UserPromptSubmit`, `Stop` via `managed_hooks_path`. Agent Deck (captured, 1.0.2): busy `◈ Thinking (2s · esc to interrupt)`, idle placeholder `Type @ to search and insert workspace file paths`. A `.session.lock` file is a liveness candidate [I] |
| 3 | `devin` (Devin CLI) | Herdr [R], Agent Sessions [R], CASS [R], Emdash [R], Superset [T], Orca [T], agentsview [T] (7; 4 SD: Herdr, Emdash, Superset, Orca) | bin `devin`, alias `devin-cli`; resume `devin --resume <id>`; CASS store `~/.local/share/devin/cli/sessions.db` | Covered today only as one **surface** (`tui`, names `devin`) inside `windsurf.json` [O: `python3` read of `registry/agents/windsurf.json`]. No own id, so the strict diff lists it | Herdr: screen manifest; hooks report session identity only, "Devin hooks do not emit a reliable state transition after every permission cancellation or user interrupt" (`integrations.mdx` [R]). agentsview gives the macOS store as `~/Library/Application Support/devin/`, CASS as `~/.local/share/devin/`: conflict [T] |
| 4 | `letta` (Letta Code) | Herdr [R], Emdash [R], catalog [T] | bin `letta`; package `@letta-ai/letta-code`; Herdr identifies by `node_modules/@letta-ai/letta-code/letta` and rejects headless flags | npm `@letta-ai/letta-code` 0.33.6 bin `letta`; GitHub `letta-ai/letta-code` 3.5k stars | Herdr screen manifest plus title `[ ! ] Action Required` = blocked, braille = working, OSC 9;4 `4;3` = blocked |
| 5 | `mastracode` (Mastra Code) | Herdr [R], Superset [T] | bin `mastracode`; Herdr path `node_modules/mastracode/dist/cli` | npm `mastracode` 0.42.2 bin `mastracode`; repo `mastra-ai/mastra` | Herdr: hook-only, "no screen manifest fallback" (`integrations.mdx` [R]). No outside signal known |
| 6 | `prime-agent` (Prime Agent) | Emdash [R], CASS [R `prime_agent.rs`], agentsview [T], catalog [T]; Herdr's "add support" page uses it as the worked example [R] | bin `prime-agent`; `prime-agent --mode acp`; store `~/.prime/agent/sessions/<id>.jsonl`; env `PRIME_AGENT_CODING_AGENT_DIR` | GitHub `PrimeIntellect-ai/prime-agent` 21.4k stars, pushed 2026-09-29 | Emdash: extension reports session file path, turn start and turn end. Pi-family JSONL but "NOT a Pi alias" (CASS header) |
| 7 | `deepseek-harness` (`dsh`) | Agent Sessions [R], Agent Deck [R], Orca [T], agentsview [T] | bin `dsh`; store `$DSH_HOME/sessions` or `~/.dsh/sessions` | npm `@deepseek-ai/dsh` 0.1.7-rc.2 bin `dsh`; GitHub `deepseek-ai/deepseek-harness` (239k stars as returned) | Agent Deck: `dsh web` prints `dsh web: http://127.0.0.1:<port>` then goes quiet; headless prints nothing until the final answer, so process liveness is the signal; busy patterns "INFERRED" |
| 8 | `fx` | Agent Sessions [R], Tempest [R `config/agents.json`], Superset [T] | bin `fx`; store `~/.fx/sessions/<id>/`; resume `fx --resume [last\|<id>]` | GitHub `vercel-labs/fx` "Unix like coding agent", Zig, 3.2k stars, homepage `fx.sh` | Short generic name: Agent Sessions requires the `~/.fx` directory as well as the binary. [I] `fx` is also a well-known JSON viewer name |
| 9 | `codewhale` (CodeWhale, formerly `deepseek-tui`) | Agent Deck [R], agentsview [T], catalog [T] | stores `~/.codewhale/sessions/`, `~/.deepseek/sessions/`; binary name not verified | GitHub `Hmbown/Codewhale` 41.0k stars, Rust, pushed 2026-09-29 | Agent Deck (captured live): busy footer `waiting for deepseek <model>, 2s/300s idle timeout` or `working (2s)`; idle = no busy marker |
| 10 | `command-code` (Command Code) | Emdash [R `impl/commandcode`], Orca [T], Agent Deck [R: `commandcode_patterns_test.go` exists], catalog [T] | bins `command-code`, `commandcode`, `cmdc` (Emdash plugin) | GitHub `CommandCodeAI/command-code` 4.1k stars, last push 2026-08-15 | Emdash hooks, root `~/.commandcode` |
| 11 | `autohand` (Autohand Code) | Emdash [R], Orca [T] | npm `autohand-cli` bins include **`ah`, `agent`, `autohand`** (the printed `bin` map was cut off; there may be more) | npm `autohand-cli` 0.9.8; repo `autohandai/code-cli` | `agent` is also a Cursor binary name (Agent Sessions Cursor `binaryNames` = `agent`, `cursor`, `cursor-agent` [R]): a name match on `agent` is not proof of either |
| 12 | `mimocode` (MiMo Code, Xiaomi) | Emdash [R], Orca [T], agentsview [T], catalog [T] | Emdash uninstall command `mimo uninstall` implies bin `mimo`; store `~/.local/share/mimocode/` [T] | GitHub `XiaomiMiMo/MiMo-Code` 13.5k stars, pushed 2026-09-29; install `curl -fsSL https://mimo.xiaomi.com/install \| bash` (Emdash source) | Emdash hooks under XDG config |
| 13 | `zero` (Zero, Gitlawb) | Emdash [R] | npm `@gitlawb/zero` bin `zero` | npm `@gitlawb/zero` 0.9.0 | Emdash prompt delivery `pty-only`, no hook. Very generic binary name |
| 14 | `freebuff` | Emdash [R], Orca [T], CASS [R] | npm `freebuff` bin `freebuff`; shares the Manicode store with `codebuff` | npm `freebuff` 0.1.6. Sibling `codebuff` is already in `harnesses.json` wave2 | Variant of a listed harness, but a separate binary; list it inside the `codebuff` row when that is written |
| 15 | `campfire` | cmux [R only] | bin `campfire`; argv needles `packages/session/bin/campfire.ts`, `packages/session/dist/campfire`; embeds Pi; config `~/.campfire/agent`; env `CAMPFIRE_CODING_AGENT_DIR` | **Not found publicly.** npm `campfire` is an unrelated chat client (`node-campfire`) | cmux hook installer `~/.campfire/agent/extensions/cmux-campfire-session.ts`; restorable only when `CAMPFIRE_SESSION_ROLE=host` |
| 16 | `maki` | Herdr [R only] | bin `maki` | GitHub `tontinton/maki` Rust, 1.1k stars, pushed 2026-09-28 | Status bar starts `[BUILD]`, `[PLAN]` or `[BASH]` when idle and gains a leading braille spinner while streaming; permission prompt replaces the input box; sets no OSC title or progress (manifest comment [R]) |
| 17 | `shelley` | CASS [R only] | Go server; DB `~/.config/shelley/shelley.db` (default `shelley.db` in the server's cwd; `shelley -db <path>`) | GitHub `boldsoftware/shelley` Go, 669 stars, pushed 2026-09-29 | `conversations.agent_working` column in the schema comment (see 3.4). The DB also holds API keys: CASS forbids raw mirroring |
| 18 | `zcode` (ZCode) | Orca [T], agentsview [T] | store `~/.zcode/cli/db/`, `~/.zcode/cli/` | Not checked: identity unverified | Nothing known |
| 19 | `openclaude` (OpenClaude) | Orca [T], agentsview [T] | store `~/.openclaude/projects/` (same shape as Claude Code's) | Not checked: identity unverified. [I] a Claude Code derivative | Nothing known |
| 20 | `ollama` (chat REPL, not a coding harness) | cmux [R only] | `ollama run <model>`, interactive only when stdin and stdout are TTYs | `ollama` is not installed here [O: `ollama --version` gave "command not found"] | cmux turn state by prompt line `>>> `. Decide whether MinMacs covers local chat REPLs |
| 21 | `grok-bot` (Grok Bot desktop) | CASS [R only] | desktop app's rolling chat replica under `CASS_GROK_BOT_DATA_ROOT` | Not checked | Chat-only, lossy, no coding role. Low value |

**Named by two or more state-detecting tools (11):** omp (6), muse (5), devin (4), letta (2), mastracode (2), deepseek-harness (2: Agent Deck, Orca), fx (2: Tempest, Superset), command-code (2: Emdash, Orca; Agent Deck has a test file for it), autohand (2), mimocode (2), freebuff (2). `prime-agent` has one state-detecting tool (Emdash) but is named by four tools in all (Emdash, CASS, agentsview, and Herdr's worked example), so it goes with them.

### 5.2 Table B: named only by session-history tools (no state detector)

Source is agentsview `README.md` "Supported Agents" [T] unless stated. These have a session store and nothing more.

| Name | Store (as printed) |
|---|---|
| Augure Code, Augure Desktop | `~/.augure/sessions/`, `~/.augure-desktop/` |
| Evener | `~/.local/state/evener/projects/` |
| Cortex Code (Snowflake) | `~/.snowflake/cortex/conversations/` |
| iFlow | `~/.iflow/projects/` |
| Forge (ForgeCode) | `~/.forge/` |
| gptme | `~/.local/share/gptme/logs/` |
| Tau | `~/.tau/sessions/` |
| Reasonix | `~/.reasonix/` |
| Omnigent | `~/.omnigent/chat.db` |
| Open Code Review | `~/.opencodereview/sessions/` |
| Piebald | `~/.local/share/piebald/` |
| Poolside | `~/Library/Application Support/poolside/trajectories/` |
| Posit Assistant, Positron Assistant | `~/.posit/assistant/workspaces/`, `~/Library/Application Support/Positron/User/` |
| QClaw, QwenPaw | `~/.qclaw/agents/`, `~/.copaw/workspaces/`, `~/.qwenpaw/workspaces/` |
| WorkBuddy | `~/.workbuddy/projects/` |
| Zencoder | `~/.zencoder/sessions/` |
| Kimi Work (desktop) | `~/Library/Application Support/kimi-desktop/daimon-share/daimon/runtime/kimi-code/home/sessions/` |
| Claude Cowork | `~/Library/Application Support/Claude/local-agent-mode-sessions/` |
| Visual Studio Copilot (Windows) | `~/Library/Caches/VSGitHubCopilotLogs/traces/` |
| ChatGPT desktop chat (CASS `chatgpt`) | `~/Library/Application Support/com.openai.chat`; a chat app, not a coding harness [I] |

### 5.3 Table C: catalog only, no detector supports them [T]

From `github.com/bradAGI/awesome-cli-coding-agents`, "Terminal-native coding agents" (136 entries; star counts as printed there, not verified): Claw Code (`ultraworkers/claw-code`, 195k), Oh My OpenAgent (`code-yeongyu/oh-my-openagent`, 69.6k; cmux lists its `omo` launcher), Open Interpreter (68.5k), Deep Agents Code (`langchain-ai/deepagents`, 29.8k), Roo Code CLI (24.3k; the `vscode-agents` row covers the extension), SWE-agent (20.4k), jcode (20.2k), Plandex (15.7k), Kode CLI (5.2k), gptme (4.4k), Tau (`huggingface/tau`, 2.9k), plus an OpenClaw family (nanobot, ZeroClaw, NanoClaw, PicoClaw, IronClaw, NullClaw, Moltis). Low priority: no observed tool reads their state.

### 5.4 Table D: gaps inside rows that already exist, or aliases of listed harnesses

| Item | Named by | Gap in the registry [O = checked by grep of `registry/` today] |
|---|---|---|
| `clawdbot`, old OpenClaw name | CASS `clawdbot` connector `~/.clawdbot/sessions`; Agent Sessions `binaryNames` `openclaw`, `clawdbot` | `clawdbot` appears nowhere in `registry/` [O] |
| Cursor binary `agent` | Agent Sessions `binaryNames` `agent`, `cursor`, `cursor-agent` | `cursor` row matches only `/.local/share/cursor-agent/versions/` [O]; fine by path, wrong by name |
| `gh copilot` launch | Tempest `command: "gh copilot"`; Herdr alias `ghcs` | `copilot-cli` row names only `copilot` [O]. [I] whether `gh copilot` still runs the same agent is not checked |
| `omc`, `omx`, `omo` launchers | cmux launch kinds (oh-my-claude, oh-my-codex, oh-my-openagent) | Not in any row [O]. [I] they start the real agent as a child; the child already matches |
| claude-code-router (`ccr`) | vibe-kanban `claude.rs:63` runs `npx -y @musistudio/claude-code-router@1.0.66 code` | Not in `claude-code.json` [O] |
| Kimi has two products | Herdr path `@moonshot-ai/kimi-code/dist/main.mjs` (TypeScript, "Kimi Code"); cmux `kimi-cli`, `kimi code`; catalog lists Kimi Code as "a separate project from" Kimi CLI | **Already handled.** `registry/agents/kimi.json` (appeared during this task) has the TypeScript CLI, the desktop app and a legacy Python CLI row matched on `Kimi` plus `Code`. cmux's comment and Herdr's path are independent confirmation |
| Qoder CLI names | Herdr aliases `qodercli`, `qoderclicn`, `qoder`, `qodercn` | For the `qoder` wave2 row |
| Claude Desktop sidecars | CASS README | Not in `claude-code.json` [O] (see 3.4) |
| Devin CLI as its own id | table A row 3 | Currently one surface inside `windsurf.json` |
| Bundled executables | Conductor docs | See 3.6 |

### 5.5 Checked and already covered (so the reader can see the exclusions)

Not in the DIFF because a row exists or the id is in `harnesses.json`: Claude Code, Codex, Cursor, Pi, OpenClaw, Gemini CLI, Antigravity, OpenCode (including `opencode2`), Hermes, T3 Code, Copilot CLI, Amp, aider, goose, Crush (Emdash calls it `charm`), Droid (cmux calls it `factory`), Windsurf, Zed, Warp, Qwen Code, VS Code agents (Cline, Roo Code, Kilo Code, Copilot agent mode), Rovo Dev (cmux `rovodev`, binary `acli`), Herdr, Xcode agents, Cline, Kilo, Kiro, Junie, Auggie, Kimi, Mistral Vibe (CASS `vibe`), Grok Build, OpenHands, Continue, Codebuff, Every Code, Conductor, Emdash, Claude Squad, Qoder, CodeBuddy, Trae, Jules. Existing rows were not re-audited beyond the checks named in 5.4.

---

## 6. Inferences (kept apart)

Everything in this section is my reasoning, not a read or an observation.

1. Adding an `omp` row without narrowing the `pi` row double-counts Oh My Pi (evidence for the collision is observed; the consequence for a real machine is not).
2. A same-user process can read what Herdr reads for the gate (`tpgid`, tty stdio). I showed the inputs exist on this Mac (section 7, item 1). Whether every harness runs in the foreground group of its terminal (it does not for IDE extensions and GUI hosts) means the gate applies to `tui` surfaces only.
3. The title table works only where a host lists titles (tmux `pane_title`, cmux `tree`, iTerm2 `name`, kitty `title`, WezTerm `cli list`, Ghostty AppleScript), per `hosts.md`. Without such a host the title is unreadable.
4. Muse's `.session.lock` and Shelley's `agent_working` are candidate signals; neither was seen on disk.
5. Conductor's bundled executables probably fall outside the current path rules.
6. The three-way (or five-way) state model is more than the registry needs to display, but the schema costs nothing to widen and both Herdr and Orca show that users tell "blocked" and "unknown" apart from "idle".

---

## 7. Local observations behind the claims above

1. Foreground and tty inputs exist for any same-user process [O]. `ps -axo pid=,ppid=,pgid=,tpgid=,tty=,stat=,command=` printed, for the Claude in a terminal here, `3891 1383 3891 3891 ttys002 S+ .../claude --settings ...` (pgid equals tpgid, stat has `+`). The same command printed `tpgid 0`, tty `??` and no `+` for the background helpers `claude bg-pty-host ...` and `claude bg-spare ...`. `lsof -a -p 3891 -d 0,1,2 -F ftn` printed `tCHR` and `n/dev/ttys002` for fds 0, 1 and 2.
2. `claude --version` printed `2.1.284 (Claude Code)`; `cmux --version` printed `cmux 0.64.3 (83) [aea6cfcde]`.
3. `ls /Applications` shows cmux, Cursor, ChatGPT and Noo-Noo; no Conductor, Superset, Orca, Emdash, Herdr, Ghostty, iTerm2 or Warp. `ls ~/Applications` shows `MinMacs.app`.
4. `python3` with `tools/agents_probe.py` `matches()` against `registry/agents/pi.json` and a synthetic argv: `node .../@oh-my-pi/pi-coding-agent/dist/cli.js` gave True; `node .../@earendil-works/pi-coding-agent/dist/cli.js` gave True; `bun .../@oh-my-pi/...` gave False.
5. Public registries, fetched 2026-09-29: npm `latest` for `@oh-my-pi/pi-coding-agent` 18.4.3, `@letta-ai/letta-code` 0.33.6, `mastracode` 0.42.2, `@deepseek-ai/dsh` 0.1.7-rc.2, `autohand-cli` 0.9.8, `@gitlawb/zero` 0.9.0, `freebuff` 0.1.6, `codebuff` 1.0.688; GitHub API for `can1357/oh-my-pi`, `letta-ai/letta-code`, `PrimeIntellect-ai/prime-agent`, `XiaomiMiMo/MiMo-Code`, `vercel-labs/fx`, `boldsoftware/shelley`, `Hmbown/Codewhale`, `tontinton/maki`, `deepseek-ai/deepseek-harness`, `CommandCodeAI/command-code`.

---

## 8. Ranked recommendation: what MinMacs should adopt first

Ranked by value over cost, given the ground rules (command line matching, direct children, no consent, no install).

| Rank | Adopt | Why, from the prior art | Cost and risk |
|---|---|---|---|
| **1** | **Write rows for the 11 harnesses that two or more state-detecting tools name, plus `prime-agent`** (table A, order: `omp`, `muse`, `devin` as its own id, `letta`, `mastracode`, `prime-agent`, `deepseek-harness`, `fx`, `command-code`, `autohand`, `mimocode`, `freebuff`), and **narrow the `pi` row first** by using the exact suffix `@earendil-works/pi-coding-agent/dist/cli.js` (Herdr's form) or an `exclude_args` for `@oh-my-pi/` | It is the assignment's main list and it is data, not code. `omp` is named by 6 detectors and today misfires as Pi [O]. Most have a verified bin name and package (section 7, item 5) | Data only. `muse` and `campfire` layouts come from a field report and a single tool; mark `confidence: inferred` until a live turn is seen. `fx`, `zero` and `autohand` (`agent`) need a second discriminator, as `copilot-cli` does |
| **2** | **A terminal gate for `tui` surfaces:** foreground process group (`tpgid` equals `pgid`, or `stat` contains `+`) and tty stdin and stdout, read from `ps` and `lsof` | Herdr (`e_tpgid`), cmux (TTY vnodes on stdin and stdout, kernel path) and Agent Sessions (tty column) all do it. Removes background helpers (`claude bg-pty-host`: `tpgid 0`, tty `??` [O]) and piped or redirected one-shots (`cat x \| ollama run`), and stale daemons that only look like sessions. Partly addresses README cases 9 and 13 | A one-shot run at a plain terminal (`droid exec`, `codex exec` typed by hand) still has a tty and still passes; those keep needing `oneshot` or a subcommand deny-list. One extra `ps` column and one `lsof` per candidate, both read-only and observed working [O]. Does not apply to IDE or GUI hosts |
| **3** | **A `title_signal` block per row, from the Herdr table in section 4,** read only through hosts that list titles | Gives a "blocked" for Codex, Grok, Qwen Code, Hermes, Amp and Letta with no hook install, and a corroborating "working" for Claude Code (Herdr, Agent Deck and `hosts.md` agree). It is the one place the registry says "hooks only" and the prior art shows otherwise | Needs a host (`hosts.md` rank 2 and 3). Keep only the first glyph and fixed keywords; drop the rest of the title. Glyph tables change with releases (Claude changed at 2.1.228), so version-date each entry as Herdr does. Same glyph, opposite meaning across harnesses (✳) |
| **4** | **Widen the state value set to `idle / working / blocked / unknown`,** and let a row say `no_outside_signal: true` | Herdr keeps `unknown` for Codex; cmux, Orca, Emdash and Agent Deck all carry a state beyond working and idle; Herdr says omp and mastracode have no outside signal. Stops the detector inventing "idle" | Schema and UI change. Keep "blocked" sourced only from a title, a hook or a host event, per `hosts.md` finding 5 |
| **5** | **Env keys as a process-to-host binding,** read with `ps eww` for a fixed key list only (`CMUX_SURFACE_ID`, `HERDR_PANE_ID`, `TMUX_PANE`, `ITERM_SESSION_ID`, `TERM_PROGRAM`) | cmux binds "by construction" through env; Agent Sessions does it with `ps eww -p` for iTerm2. Replaces tty and cwd guessing (`hosts.md` shows cmux tty collisions) | The environment holds secrets: read the named keys and discard the rest. Not tested here |
| **6** | **Multi-root and env-override in `session_store`** (`CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `GROK_HOME`, `KIMI_CODE_HOME`, `PI_CODING_AGENT_DIR`, `DSH_HOME`, `OMP_PROFILE`), a `shares_store_with` field, and the Claude Desktop sidecar directories | CASS and Emdash show every serious tool needs this. The Claude Desktop sidecars are missing today | Schema change; sidecar directories unverified on this Mac |
| **7** | **`launchers` and `wrapper_env` hints:** `omc`, `omx`, `omo`, `ccr`, `gh copilot`, `clawdbot`, `HERDR_AGENT` | Cheap aliases from cmux, vibe-kanban, Tempest, CASS and Herdr | Most are aliases of a child that already matches; low value until a wrapper is seen hiding an agent |
| skip | Screen-tail reading, `capture-pane` hashing, iTerm2 `contents` | Herdr, Agent Deck, Claude Squad and Agent Sessions use it; it is the only source of "blocked" for agents with no title and no hook | It reads private conversation text. Claude Squad's "screen changed" also mislabels an idle agent with a spinner or clock as busy |

---

## 9. Not verified

- **Herdr was read, not run.** Nothing here shows Herdr's detection agrees with a live agent on this Mac. The manifests' glyph rules are what Herdr ships on `master`, not what MinMacs observed, except Claude's ◐ and ◑, which `hosts.md` saw. I did not trace how PTY activity feeds the `working` decision (`AgentDetection` says PTY activity is "the normal working authority"; the code path was not followed). Whether `herdr.sock` needs opt-in is left to `hosts-2`.
- **CliDeck, Calyx, Tempest and CCGram**: read READMEs and file names only; the classifier source was not read. Tempest's adapter list (antigravity, claude, codex, copilot, cursor, gemini, hermes, opencode) is from file names.
- **Superset, Orca and Conductor**: docs and READMEs only, no source. Superset and Orca lists are [T]. Conductor's mechanism is an inference. "Polygraph" (Superset) was not identified.
- **Agent Island** was named by a catalog search result; the repository URL I tried does not exist, so it is not studied.
- **cmux on `main` versus 0.64.3.** Hook installers for grok, pi, omp, campfire, amp, kimi, kiro and antigravity are documented on `main`; the installed binary does not list them [O]. Behaviour of newer builds was not run.
- **Harness identity for rows 9, 12 to 15, 18 to 21 in table A** rests on one or two tools plus a registry fetch; I did not read vendor docs for Muse (`dev.meta.ai`), MiMo, Zero, ZCode, OpenClaude, CodeWhale's binary name, or Campfire. `campfire` has no public identity that I could find.
- **Store paths from CASS, Emdash and agentsview** were not opened; none of these harnesses is installed here. The Devin macOS store path conflicts between CASS and agentsview, and Qwen Code's layout differs between CASS and our row.
- **Star counts** in table A are from the GitHub API today and can be inflated or odd (DeepSeek Harness returned 239k); in table C they are as the catalog prints them. They say "named a lot", not "used a lot".
- **Whether `tpgid` and `stat +` hold for every `tui` harness** was checked on one process (Claude Code under cmux). Other harnesses, tmux panes and `screen` sessions were not checked.
- **Cloud surfaces** (Claude Squad's remote, Conductor cloud workspaces, Superset remote, Orca remote servers) are outside what a Mac process can see; not studied.
- **No session store content was read**, so no claim here depends on message content, and I cannot say which stores are populated on this Mac.
