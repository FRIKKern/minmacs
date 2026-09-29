# Claude Squad

Confidence: documented (public source, no live instance). Not installed here, not running.

## What was checked

- Shallow clone of https://github.com/smtg-ai/claude-squad at ce1ffb4 (2026-08-20, v1.0.20, also the latest release and the Homebrew stable). Read `main.go`, `app/app.go`, `config/`, `daemon/`, `session/`, `session/tmux/tmux.go`, `install.sh`, `.goreleaser.yaml`, README.
- Local: `which -a cs claude-squad` (not found), `ls ~/.claude-squad` (absent), `/tmp/claudesquad.log` and `$TMPDIR/claudesquad.log` (absent; the source uses `os.TempDir`, which on macOS is `$TMPDIR`), `tmux ls` (no server). Nothing was started or attached.
- `strings -a` on Claude Code 2.1.284 still contains the permission-prompt text Claude Squad greps for (3 hits).

## Shape

```
cs (TUI, Go)  --pty child-->  tmux attach-session -t claudesquad_<title>   (one per instance, long-lived)
   |          --every 500ms->  tmux capture-pane ..., git diff              (short-lived)
   |          --new-session->  tmux SERVER  -->  agent (claude/codex/aider/gemini/amp)   cwd ~/.claude-squad/worktrees/<branch>_<hex>
   '-- on exit, if auto_yes:  cs --daemon (setsid, pid in ~/.claude-squad/daemon.pid)
```

- No .app, no bundle id. Binary is `claude-squad`; `cs` by install.sh default or a `ln -s` from Homebrew; `--name` can pick anything.
- The agent is not a child of `cs`. `tmux new-session -d` daemonises the server; the pane program hangs off it. (Ancestry inferred from tmux behaviour, not observed.)
- Session id in argv: none for `cs`. The tmux session name `claudesquad_<title>` (whitespace removed, `.` to `_`) appears in the argv of its tmux children. No row in `registry/agents/` matches a process named `tmux`, so the probe never reports those children.
- Store: `~/.claude-squad/state.json` (`instances` array, keys in the row's sources), `config.json` (documented), `daemon.pid`, `worktrees/`. Log in `$TMPDIR/claudesquad.log`. No conversation is stored; the transcript is the agent's own.
- Waiting: no hook, no status field. Only auto-yes looks at pane text, per program.
- Hooks: none. OpenTelemetry: none (nothing in go.mod or source).

## Could not determine

- Idle and busy CPU of `cs`. The 5% floor is a guess. Its 500 ms loop spawns tmux and git for every instance, so an idle manager may sit above it.
- Whether the pane process is `claude` itself or `$SHELL -c claude` (tmux runs the command through the default shell; shells often exec a simple command).
- Whether `state.json` `status` is ever fresher than the last create, quit or cursor move (source says no).
- The `~/.claude/projects` folder name for a worktree cwd.
- How many `cs` names in the wild are Coursier. `cs` alone is not proof; require `~/.claude-squad/`.
- Windows and Linux behaviour (not needed).

## Contradicts common belief

- "Claude Squad shows which agents are working." It shows whether the pane text changed in the last 500 ms tick. A long silent tool call, a network wait or a stalled prompt reads as Ready (the "●" icon), except that where the prompt string is recognised (program `claude` exactly, `aider*`, `gemini*`) an unchanged pane keeps its previous status instead of becoming Ready; a blinking cursor or clock can read as Running. The source comment calls Ready "waiting for user input"; it is not.
- "Auto-yes handles Claude Code permission prompts." The check is `t.program == "claude"` exactly. `DefaultConfig()` writes the absolute path from `which claude` into `default_program`, so on a default install the prompt test is off. (`aider` and `gemini` use prefix tests and are fine; the trust-prompt handler uses a suffix test and is fine.) Inferred from source, not run.
- "Claude Squad's tree contains the agents." It does not. CPU or children of `cs` say nothing about turns. Detect the agent by its own row and attribute it to a squad by cwd or tmux session name.
- "`cs` in ps means Claude Squad." Coursier also installs `cs`.
- `state.json` is not a live view: it is written on create, kill, quit, list-cursor moves, first view of a help screen and `cs reset` only, never per status tick.

## Verification

Second pass, 2026-09-29, by a reviewer who did not write the row. Source read: fresh clone of smtg-ai/claude-squad at ce1ffb4 (= tag v1.0.20). Nothing was installed, started or attached. Ceiling: `documented` (harness not installed here).

`tools/validate_row.py registry/agents/claude-squad.json` printed `ok` before and after the repairs. `tools/agents_probe.py --row` printed 0 sessions (nothing running).

| # | Claim | Result |
|---|---|---|
| 1 | Binary built as `claude-squad`; install.sh renames to `cs` by default, `--name` overrides; README says Homebrew and manual both give `cs`, Homebrew via `ln -s` | confirmed (`.goreleaser.yaml`, `install.sh` lines 270-276, README lines 22-39; Homebrew formula file installs only `claude-squad`) |
| 2 | Homebrew stable 1.0.20 | confirmed (formulae.brew.sh API and homebrew-core formula) |
| 3 | Latest release v1.0.20, 2026-08-20, darwin amd64/arm64 tar.gz, no .app | confirmed from the release page and its asset list. The REST API was rate limited on re-check, so the `05:11:12Z` second-level timestamp is unre-verified (page shows 20 Aug 05:11) |
| 4 | Tmux session name `claudesquad_<title>`, `new-session -d -s -c <program>`, attach on a pty, `capture-pane -p -e -J -t` | confirmed (`session/tmux/tmux.go`) |
| 5 | Agent is a child of the tmux server, not of `cs` | confirmed as design, still inferred as observed fact. `man tmux` `-D` text supports "server is a daemon by default". Not seen live |
| 6 | `cs` children: long-lived attach plus `capture-pane` and `git diff` every 500 ms | corrected: per active instance every 500 ms (`git diff --numstat`, full `git diff` for the selected one), plus `capture-pane` every 100 ms for the selected instance (preview tick). Label updated |
| 7 | Status Running/Ready is a 500 ms pane-hash diff, no turn signal | confirmed |
| 8 | "An unchanged pane is Ready even while a permission prompt is showing" | corrected: true only when no prompt string is recognised. If it is recognised (claude exact, aider*, gemini*), the status is left unchanged, not set to Ready, and Enter is tapped only with auto-yes. Claim and evidence rewritten |
| 9 | Prompt strings and the exact-equality claude test, HasSuffix in the trust handler | confirmed |
| 10 | Default install writes an absolute path as the program, so the claude prompt test is off | confirmed from source (`GetClaudeCommand` returns `which claude` output or `LookPath`); narrowed: on if the user sets bare `claude` or runs `cs -p claude`. Runtime effect is inferred, not run |
| 11 | Prompt string exists in installed Claude Code | confirmed: `strings -a ~/.local/share/claude/versions/2.1.284 \| grep -c 'No, and tell Claude what to do differently'` printed 3 |
| 12 | state.json layout, config path, daemon.pid, worktree naming, `instances.json` unused | confirmed |
| 13 | state.json written only on create (two sites), quit, cursor up/down | corrected: also kill (`DeleteInstance`), first view of a help screen, `cs reset`, and the daemon on SIGINT/SIGTERM. Still never per status tick. Claim rewritten |
| 14 | InstanceData key names and Status ints 0 Running, 1 Ready, 2 Loading, 3 Paused | confirmed (`session/storage.go`, `session/instance.go`) |
| 15 | Claude Squad stores no conversation | confirmed: grep for jsonl, transcript, conversation over the Go source printed nothing. The `~/.claude/projects` folder name for a worktree cwd is still unchecked |
| 16 | Auto-yes daemon: `cs --daemon`, hidden flag, Setsid, PID file, 1000 ms poll, killed on next TUI start | confirmed (`main.go`, `daemon/daemon.go`, `daemon_unix.go`, `config.go`). Kill is `proc.Kill()` (SIGKILL) |
| 17 | No hooks, no OpenTelemetry | confirmed: grep for otel, telemetry, hook over `*.go`, `go.mod`, README printed nothing; go.mod deps match the claim |
| 18 | Log at `$TMPDIR/claudesquad.log` | confirmed (`log/log.go` uses `os.TempDir`) |
| 19 | Not installed, not running; `/tmp/claudesquad.log` absent | corrected: `/tmp` is not `$TMPDIR` on macOS. Rechecked `$TMPDIR/claudesquad.log`, also absent. `which`, `ls ~/.claude-squad`, `ps` re-run: nothing |
| 20 | `cs` is also the Coursier launcher | was unsupported (no source). Now confirmed at https://get-coursier.io/docs/cli-installation and added to sources. The second check (`~/.claude-squad/` exists) cannot be expressed in the schema, so the probe will report a Coursier `cs` as Claude Squad |
| 21 | Notes: per-instance tmux children are hidden by the outermost-process rule | corrected: wrong reason. No row matches `tmux`, so they are never reported. Notes and body fixed |
| 22 | `tree_cpu` floor 5% | unsupported and unmeasured (already flagged weak). Added: the TUI redraws a spinner and polls the selected pane every 100 ms, so an idle `cs` may exceed 5% and read as always working |

Process patterns, checked against `matches()` in `tools/agents_probe.py`:
- `names: ["cs","claude-squad"]` compares the base name of argv[0]. It matches `cs`, `~/.local/bin/cs` and the `cs --daemon` process (argv[0] is `os.Executable()`).
- The TUI surface vetoes `--daemon` by exact token, so the daemon falls to the second surface. Correct.
- False positive: Coursier `cs`. Not fixable in the row. Left as a documented limit.
- False negative, rare: exclude tokens are matched after splitting on spaces, so a program string such as `cs -p "aider --help"` or `-p "codex debug"` is dropped.
- No match against tmux, git, the agents in the panes, or Claude Code's own row.

Confidence stays `documented`. Not verified: pane process shape (`claude` or `$SHELL -c claude`), idle and busy CPU of `cs`, Coursier's process shape in `ps`, Linux and Windows.
