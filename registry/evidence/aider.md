# Aider: evidence notes (2026-09-29)

Row: `registry/agents/aider.json`. Validator: ok. Confidence `documented`. Aider is not installed on this Mac and nothing was running (`which aider` -> not found, `ps | grep -i aider` empty, `ls ~/.aider*` no match), so no surface was classified live. Version researched: PyPI `aider-chat` 0.86.2, repo `Aider-AI/aider` main = 0.86.3.dev, last commit 2026-05-22 (depth-1 clone at 5dc9490, unpacked to the scratchpad, never installed or run).

## What I checked

- Source: `pyproject.toml`, `aider/args.py`, `io.py`, `analytics.py`, `waiting.py`, `run_cmd.py`, `linter.py`, `coders/base_coder.py`, `main.py`, `models.py`, `repomap.py`.
- Docs: aider.chat/docs/install, usage/notifications, config/options, usage/browser, usage/watch (all return 200; notifications page read from the repo copy).
- `aider-install` 0.2.0 sdist from PyPI (read only), Homebrew formula `aider.rb` and formulae.brew.sh API, PyPI JSON, GitHub API (releases, tags, commits, issues search).
- Grep of the whole tree for `otel|opentelemetry` and for `hook`.
- Matcher test: the row's surfaces run through `agents_probe.matches` against made-up ps lines (uv venv, Homebrew, pip'd python, `--gui`, `--version`, `pip install aider-chat`, unrelated script). Behaved as intended; `--row` probe run finds 0 agents, as expected.

## Answers per field

| Field | Answer | Basis |
|---|---|---|
| Surfaces | Terminal REPL (the product). `--gui`/`--browser` Streamlit UI in the same process. `--watch-files` and `-m/--message` are modes of the same process. No desktop app, no bundle id, no daemon, no official IDE extension. | args.py, main.py, docs |
| Process | Python console script `aider = aider.main:main`. ps shows the venv's python, with the script path as argv[1]. Nothing is named `aider`. Official installer -> `~/.local/share/uv/tools/aider-chat/bin/python` (shim `~/.local/bin/aider`); pipx -> `.../pipx/venvs/aider-chat/`; Homebrew -> `/Cellar/aider/<v>/libexec/bin/python`; pip -> any python with `/bin/aider` in args | pyproject, aider-install, formula. Paths inferred, not observed |
| Process to session | No session id, no `--session` flag. One markdown log per project, so map by cwd -> git root -> `.aider.chat.history.md` (unless `--chat-history-file` is in argv). Two aiders in one repo share the file | args.py, io.py |
| Store | `<git root>/.aider.chat.history.md`, append-only markdown, headers `# aider chat started at ...`, user text as `#### ` lines and `> ` tool output. Not JSON/JSONL/SQLite. Also `.aider.input.history` (prompt_toolkit), optional `.aider.llm.history`, `.aider.tags.cache.v4/` (repo map sqlite cache). Per-user `~/.aider/` holds only analytics id, install stamps, caches, oauth keys | args.py, io.py, repomap.py |
| Turn in progress | No exact external signal. Turn runs in-process (litellm), no child for the model call. Best available: socket traffic to the LLM host, CPU, tool children (git, /run, lint, test), chat-log write within seconds (start and end only). Exact only if launched with `--analytics-log FILE`: `message_send_starting` then `message_send` / `message_send_exception` | base_coder.py, analytics.py |
| Waiting on human | Only with `--notifications` (or `--notifications-command`): aider runs a shell command when it returns to the prompt or asks a y/n / text question after an LLM call started. macOS default: terminal-notifier, else osascript `display notification`. Otherwise idle-at-prompt and blocked-on-confirmation are indistinguishable | io.py, notifications doc |
| Hooks | None. Not Claude Code style. Closest: `--notifications-command`, `--lint-cmd`/`--test-cmd`, `--analytics-log`. Config in `.aider.conf.yml` (cwd, git root, home), `AIDER_*` env vars, `.env` | args.py, docs |
| OpenTelemetry | No. Opt-in PostHog analytics only; issue #4360 requesting OTel is open | grep, GitHub |

## Could not determine

- Real `ps` argv for any install path. Especially: whether a Homebrew or python.org framework Python shows `.../Python.app/Contents/MacOS/Python` instead of the venv path (the third surface, matched on `/bin/aider` in args, covers that case only if the script path is still argv[1]).
- Whether a uv-tool install shows the venv python or the uv-managed interpreter as argv[0].
- CPU while streaming vs. at the prompt, and the spinner thread's cost. The 3 percent floor is a guess.
- Whether litellm keeps the API connection alive after a turn, which decides how usable `socket_activity` is.
- Behaviour on Ctrl-C mid-stream for `--analytics-log` (neither end event is obviously emitted).
- Whether an unofficial VS Code/Neovim wrapper changes process shape. I did not look at third-party integrations.

## Contradicts common belief, the hint, or the docs

- "Terminal pair programmer" hint is right, but there is no `aider` process name to match. Matching on names alone finds nothing; the row matches on install paths and the `/bin/aider` script argument.
- Aider has no session concept. Sessions are not files or ids; the transcript is per project directory, so it can hold many sessions and is shared by concurrent ones.
- The transcript is a poor liveness signal: assistant text is written only after the reply completes, unlike Claude Code's incremental JSONL.
- Aider has no hooks despite `--notifications` looking like one, and issue #5300 ("Hooks (Claude Code-style lifecycle hooks)") looks like a feature but was filed on the wrong repo by mistake and closed as such (its author says it was for a personal fork).
- `--analytics-log` writes events even with analytics disabled (the early return checks logfile), so it is a usable, privacy-neutral local turn marker.
- Project activity: latest GitHub *release* object is v0.86.0 (2025-08-09), while tags and PyPI go to 0.86.2 and main has had no commit since 2026-05-22. Homebrew still pins python@3.12 (issue #3037 py3.13 support).
- Notifications fire on confirmations too (add file, run command), not only when the reply is done, so "notified" does not mean "turn finished".

## Verification

Independent adversarial pass, 2026-09-29. Validator: `ok` before and after the edits. Sources re-checked against a fresh depth-1 clone of Aider-AI/aider (5dc9490, 2026-05-22), the aider-install 0.2.0 sdist, the Homebrew formula, PyPI JSON, GitHub pages and docs.streamlit.io. Nothing was installed or run. Confidence stays `documented` (harness not installed, so nothing can be `verified-locally`).

Legend: confirmed, corrected, unsupported (kept but flagged as inference in the row).

### Sources and factual claims

- Console script `aider = "aider.main:main"`: confirmed (pyproject.toml line 27).
- Official installer command and `uv tool update-shell`: confirmed (aider_install/main.py lines 10 and 12; console script `aider-install`).
- uv tool venv at `~/.local/share/uv/tools/aider-chat`: corrected from inferred to corroborated. `uv tool dir` prints `/Users/frikkjarl/.local/share/uv/tools` here, and a running uv tool (`claude-swap`) shows the shape `<venv>/bin/python ~/.local/bin/<shim> args`. Analogy only, no aider process seen.
- Homebrew formula `aider` 0.86.2, `python@3.12`, Language::Python::Virtualenv: confirmed. The Cellar path in ps: unsupported (see process patterns below).
- No aider on this Mac: confirmed (`which aider` -> not found, no aider in ps, `ls -d ~/.aider*` -> no match).
- One chat log per project, default `<git root>/.aider.chat.history.md`, `# aider chat started at` header: confirmed (args.py 274-287, io.py 336). `documented: true` holds, `--chat-history-file` is on the options page (200).
- Other files (`.aider.input.history`, `--llm-history-file`, `.aider.tags.cache.v4`, `~/.aider/{analytics.json,oauth-keys.env,caches}`): confirmed. `installs.json` was not re-checked separately.
- Turn is in-process, `llm_started()` then WaitingSpinner: confirmed (base_coder.py 1419-1440). Children only from git, run_cmd, linter (`sys.executable -m flake8`), scrape (playwright), pip helpers, notification command: confirmed.
- Chat log written at prompt submit and at reply end, not while streaming: confirmed (io.py `user_input`, `ai_output`; `ai_output` is called in `send`'s finally, base_coder.py 1829).
- Notification behaviour: confirmed, with a correction. `ring_bell` runs only when `self.notifications` is true (io.py 1090). `--notifications-command` alone does nothing. The row said "--notifications / --notifications-command"; now reads "--notifications (optionally with --notifications-command)". Fires from `get_input`, `confirm_ask` and `prompt_ask`: confirmed. macOS default terminal-notifier, else osascript, message "Aider is waiting for your input": confirmed.
- Analytics log records `message_send_starting` / `message_send` / `message_send_exception` and works without analytics: confirmed (analytics.py 214 early return checks logfile; base_coder.py 1420, 1511, 2114).
- No hooks, no OpenTelemetry: confirmed (grep for otel/opentelemetry finds no file; hook grep finds only `--no-verify` and excepthook). Issue #4360 open: confirmed. Issue #5300: confirmed as opened on the wrong repo and closed by its author (page text read; closed as "completed", not "not planned"). Added as its own source entry.
- Release state: confirmed. PyPI 0.86.2, requires-python `<3.13,>=3.10`; main is `0.86.3.dev` with `<3.15`; last commit 2026-05-22T14:02:20Z; GitHub "Latest" release is v0.86.0 (Aug 9, 2025). Added as its own source entry.
- `--gui` runs Streamlit in the same process: confirmed (`cli.main(st_args)`, no subprocess). Corrected: "default port 8501" is a Streamlit default (docs.streamlit.io prints `Default: 8501`), not an aider setting; grep for 8501 in the aider tree finds nothing, and the browser docs page does not mention it. Label and source reworded.
- `--browser` is an alias of `--gui`: confirmed (args.py 657-658).
- Not investigated further: a third-party VS Code/Neovim wrapper, and whether the analytics log survives Ctrl-C. Still open, as listed above.

### Working signals

- socket_activity: unsupported (inferred, not observed) and not implemented in `tools/agents_probe.py`. Flagged in notes.
- tool_children: confirmed as a signal. Checked the risk that an idle aider keeps a persistent `git cat-file --batch` child (GitPython does that for its default object DB): aider opens the repo with `odbt=git.GitDB` (repo.py 125), so no such child is expected. Inferred from source, not observed. Added as a source entry.
- tree_cpu 3 percent floor: unsupported (a guess, as the row already says).
- transcript_write: confirmed as weak. Corrected in notes: the probe cannot evaluate it for this row, because aider has no session id and `per_session` has no `{session_id}`, so the age is always None.
- Probe side effect: an osascript/terminal-notifier child appears when aider returns to the prompt with `--notifications` on, so `tool_children` briefly reads "working" at exactly the moment the turn ends.

### Process patterns (tested with `agents_probe.matches` on synthetic argv)

- uv, pipx, Homebrew venv python running the script, with and without `--gui`: match as intended. `--no-gui`: tui, not gui (good). `--version`, `-h`, `--check-update`: excluded (good). `python -m pip install aider-chat`: not matched (good).
- Corrected: framework Python. On this Mac a python.org Python shows as `.../Python.app/Contents/MacOS/Python <script>` (observed, pid of an unrelated script), so a Homebrew or pipx venv on a framework Python most likely does not show the venv path either. The `/Cellar/aider/` and `/pipx/venvs/` entries may then never fire, and those installs are caught by the name-based pip surface through `/bin/aider` in argv. Not observed for aider itself. Recorded in notes.
- Repaired: with that shape, `aider --gui` on a framework Python fell through to tui. Added a second gui surface (python names, `args_contain` `/bin/aider` and `--gui`), placed before the tui surfaces. Tested: `--gui` -> gui, `--no-gui` -> tui, `--gui --version` -> excluded.
- Repaired: `python3.14` added to the python names (repo main allows `<3.15`; released 0.86.2 only up to 3.12). Previously a pyenv or Homebrew 3.14 aider was invisible.
- Not repairable in data, documented instead: `args_contain` is a substring test, so `/bin/aider` also matches `python ~/.local/bin/aider-install` (the official installer, a real Aider-AI product, verified as console script `aider-install`), and any `/bin/aider*` script such as an unrelated `aider-notify.py`. Both are short-lived or rare. They cannot be excluded without an anchor the engine does not have. Dropping the pip surface would instead hide every framework-Python install, which is the worse error.
- Helper children (`python -m flake8`, pip, playwright) match the tui surfaces but are dropped by the probe's "outermost process" rule because their parent also matches.
- Matched by nothing, correctly: `python -m aider`, an unrelated `python3 -m pip install aider-chat`.
