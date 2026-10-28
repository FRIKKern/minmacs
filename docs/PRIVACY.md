# What MinMacs sends to the model

MinMacs asks a model only through the review broker and Investigate, both in `Sources/Core/Review`. It runs the `claude` CLI or the `codex` CLI on the person's own login, so the data goes where that CLI sends it, under that account. [REVIEW.md](REVIEW.md) says when a call happens and how the broker keeps calls few.

This page lists every field a review sends, per expert, from the code that builds it. `./test.sh docs` runs `test/docs/privacy.py`, which reads that code. It fails when an expert sends a key that is not in a table here, or when a table here names a key the code no longer sends. It also fails when a facts function writes a key it cannot name, such as one from a variable or a merged dictionary.

## What is redacted

Every value goes through the same steps in `MMCompactFacts` in `Sources/Core/Review/MMModel.m` before it leaves:

- **The home folder** becomes `~` wherever it appears, in every string and in every finding id.
- **Secrets.** `MMRedact` replaces with `<redacted>`:
  - the value of a `key=value` or `key: value` pair whose key holds token, secret, password, passwd, pwd, api key, auth, credential, private key, session, cookie or bearer
  - the value after a flag such as `--token` or `--api-key`
  - a password in a URL, such as `https://user:<redacted>@host`
  - any run of 40 or more letters, digits, `+`, `_` or `-`, which is how most keys and tokens look
- **Length.** A string longer than 400 characters is cut there. Several fields are cut shorter by the expert, as the tables say.
- **Empty values.** Null, false, zero and empty values are dropped.

The finding `id` is the one string that is not redacted, so the answer can be matched back to it. It does have the home folder as `~`.

**What is never sent.** No file contents beyond the few project fields of LocoHost below, no `.env` file, no environment variables, no transcript or log, no page body and no first prompt. LocoHost's and WorkForest's code say so in a comment above their facts functions. The tables below are everything those functions write.

## Every review call

The broker wraps each expert's facts in the same frame, from `BatchInput`, the judge and the summary in `Sources/Core/Review/MMReview.m`. The system prompt is the expert's own, fixed text, and the schema is the shape of the answer.

| Key | What it holds |
|---|---|
| `blocks` | One block per top owner of the findings in the call |
| `w` | The block's top owner: its folder, with the home folder as `~`, else its name or key |
| `f` | The findings of the block, each with its expert's facts below |
| `id` | The finding's id, such as `locohost:server:~/code/app#dev` or `workforest:worktree:~/code/app-search` |
| `ws` | The expert's shared keys that every finding of the block has in common, sent once |
| `all` | The values every finding of the call has in common, sent once |
| `now` | The time of the call, in ISO 8601 with the local time zone |
| `first` | Judge calls only: the first review's verdict for the finding |
| `verdict` | In `first`: the first review's verdict word. In a summary line: the verdict word |
| `confidence` | In `first`: the first review's confidence, from 0 to 1 |
| `reason` | In `first`: the first review's reason, one sentence |
| `keep_evidence` | In `first`: the fact the first review named for keeping it, if any |
| `lines` | Summary calls only: one line per finding of the review |
| `title` | In a summary line: the finding's title, such as a server or worktree name |
| `about` | In a summary line: what the verdict is about, in a few words |

A summary call runs only when a review needed more than one batch. A judge call runs only in Eager mode.

## MinMacs

`-[MMMinMacsExpert reviewFactsFor:]` in `Sources/Experts/MinMacs/MMMinMacsExpert.m`. MinMacs asks only about findings with a proposed action, and its rule `minmacs.lists` decides every one of those. So in the current code no MinMacs finding reaches the model. If one ever passes the rule, these are its fields:

| Key | What it holds |
|---|---|
| `group` | Where the app sits in the menu: quit, trim, spared, kept or unsorted |
| `verdict` | Which list in the person's rules names it: keep, close or unsorted |
| `processes` | How many processes roll up into the app |
| `browser` | Whether it is a browser |
| `state` | An agent's state word, when the finding has one |
| `pressure` | The Mac's memory pressure level |
| `memoryMB` | The app's memory footprint in MB |
| `cpu` | The app's CPU percent, rounded |
| `reason` | Why it is spared or kept, cut at 120 characters |

## LocoHost

`ReviewFacts` in `Sources/Experts/LocoHost/MMLocoHost.m`, one entry per listening server.

| Key | What it holds |
|---|---|
| `ports` | The ports it listens on |
| `bind` | The address of its main port: `127.0.0.1`, `::1` or `*` |
| `kind` | dev, service or other |
| `framework` | The framework or server it looks like, such as Vite or Postgres |
| `command` | Its command line, and the package manager command that started it, cut at 400 characters |
| `project` | The repo or worktree and subfolder, else the folder name, cut at 120 characters |
| `branch` | The git branch of its folder |
| `worktree` | The worktree name of its folder |
| `launcher` | What started it, such as `pnpm dev · Claude Code · cmux`, cut at 200 characters |
| `agent` | The name of a live coding agent above it in the process tree |
| `parent_exited` | Whether the shell, terminal or agent that started it is gone |
| `uptime_minutes` | Minutes since it started |
| `cpu_percent_now` | Its process tree's CPU percent now |
| `memory_mb` | Its process tree's memory in MB |
| `processes` | How many processes its tree holds |
| `connections_now` | Open connections now |
| `new_connections_now` | Connections that are new in this sample |
| `clients_now` | The names of the apps connected to it now |
| `cpu_busy_now` | Whether it was busy in the last two samples |
| `minutes_since_activity` | Minutes since its last activity |
| `watched_minutes` | Minutes since LocoHost first saw it |
| `repo_touched_minutes_ago` | Minutes since the last commit of its checkout |
| `protected` | Whether the person's protect list names it |
| `duplicates` | Ports of other dev servers on the same folder and branch |
| `quiet_after_minutes` | The person's quiet threshold in minutes |
| `waste` | What it held while quiet, the four keys below |
| `since`, in `waste` | "last activity", or "LocoHost first saw it" when no activity was seen |
| `cpu_minutes_since`, in `waste` | CPU minutes since then |
| `energy_rank_now`, in `waste` | Its energy rank in this sample |
| `memory_mb_held`, in `waste` | Memory in MB it holds |
| `project_files` | Dev servers only: the project fields below, read from a fixed list of files |
| `name`, in `project_files` | The name in `package.json` or `pyproject.toml`, cut at 80 characters |
| `description`, in `project_files` | The description in `package.json`, `mix.exs` or `pyproject.toml`, cut at 300 characters |
| `script`, in `project_files` | The `package.json` script it runs and its command, such as `dev: vite`, cut at 200 characters |
| `readme`, in `project_files` | The first paragraph of its README, cut at 300 characters |
| `app`, in `project_files` | The app name in `mix.exs` |
| `configs`, in `project_files` | The names, never the contents, of up to 12 known config files in its folder, such as `vite.config.ts` |
| `agent_session` | Dev servers only: the newest agent session in its folder, the five keys below |
| `agent`, in `agent_session` | The agent's name, such as Claude Code |
| `title`, in `agent_session` | The session's title, cut at 200 characters |
| `started_minutes_ago`, in `agent_session` | Minutes since the session started |
| `last_active_minutes_ago`, in `agent_session` | Minutes since the session was last active |
| `match`, in `agent_session` | How the session was matched to the server |

The `.env` file and every other file content are never read for this. For an Erlang `beam.smp` server, the arguments before `-extra` are replaced by `…`.

## WorkForest

`ReviewFacts` in `Sources/Experts/WorkForest/MMWorkForest.m`, one entry per linked worktree. The main checkout of a repo is never sent.

| Key | What it holds |
|---|---|
| `repo` | The repo's name |
| `folder` | The worktree's folder name |
| `branch` | Its branch, absent when detached |
| `locked` | Whether git has it locked |
| `detached` | Whether HEAD is detached |
| `protected` | Whether the branch is a protected one, such as main |
| `made_by` | The tool that made it, such as claude-code, cursor or conductor. Absent when the person made it |
| `default_branch` | The repo's default branch |
| `dirty_files` | How many tracked files have changes |
| `untracked_files` | How many files are untracked |
| `stashes` | How many stashes are on the branch |
| `unpushed_commits` | Commits on no remote and not in the default branch |
| `commits_not_in_default` | Commits not in the default branch |
| `merged` | How the branch reached the default branch: ancestor, tree, patch, squash, pr or merge-tree |
| `upstream` | The remote branch, `gone` when it was deleted, `none` when it was never pushed |
| `on_remote` | Whether HEAD is on some remote |
| `last_commit_days_ago` | Days since the last commit |
| `git_facts` | "not read yet", when git facts are not known yet |
| `created_days_ago` | Days since the worktree was made |
| `newest_file_days_ago` | Days since the newest file change outside `.git` and caches |
| `quiet_days` | Days since the last commit, file change or agent activity |
| `disk_mb` | Its size on disk in MB |
| `freed_mb` | What removing it frees in MB |
| `cache_mb` | How much of that is caches |
| `files` | How many files it holds |
| `processes` | The names of processes whose folder is inside it |
| `servers` | LocoHost's servers inside it, such as `:3000 Vite, in use` |
| `agent_session` | The newest agent session that ran in it, the five keys below |
| `agent`, in `agent_session` | The agent's name |
| `title`, in `agent_session` | The session's title, cut at 200 characters |
| `working_now`, in `agent_session` | Whether the session works now |
| `last_active_minutes_ago`, in `agent_session` | Minutes since the session was last active |
| `started_minutes_ago`, in `agent_session` | Minutes since the session started |

No file contents, no `.env`, no first prompt, no transcript path and no environment.

## Noo-Noo

`-[MMNooNooExpert reviewFactsFor:]` in `Sources/Experts/NooNoo/MMNooNooExpert.m`. Noo-Noo asks only about items with a proposed action, and its rule `noonoo.owner-state` decides every one of those. So in the current code no Noo-Noo item reaches the model. If one ever passes the rule, these are its fields:

| Key | What it holds |
|---|---|
| `kindID` | The id of its row in the clutter catalog, such as `pnpm-store` |
| `class` | The row's class: cache, tool, build, data or leak |
| `section` | Its menu section: finished, leftovers, caches or kept |
| `state` | free, live or kept |
| `ownerState` | Its owner's state, such as squash-merged |
| `members` | How many paths the item holds |
| `freedMB` | What deleting it frees in MB |
| `idleDays` | Days since it was last used |
| `why` | Why it is a leftover, cut at 120 characters |

The item's path is part of its `id`, with the home folder as `~`.

## Insomnia

Insomnia sends nothing. Its `reviewRequest` returns nil, so the broker never asks the model about it.

## Investigate

Investigate runs only when the person asks and confirms the cost. It sends:

- a fixed system prompt of 426 characters
- the schemas of MinMacs's own three tools, Read, Grep and Glob
- one message with three lines: `Subject:`, the finding's title cut at 200 characters, `Folders:`, the folders it may read with the home folder as `~`, and `Question:`, the person's question cut at 1,000 characters

Then the model asks for tool calls, and their results are sent too:

- **Read** sends the lines of one file inside the folders, each line redacted as above, at most 512 KB of the file.
- **Grep** sends the matching lines with their file, with the home folder as `~`, and line number. Each line is cut at 300 characters and redacted.
- **Glob** sends the paths that match.
- One call's output stops at 100 KB, and a run stops after 12 turns.
- Files named like `.env`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.keychain`, `id_rsa` and its kin, `.netrc`, `.npmrc`, `.pypirc`, `credentials`, `credentials.json` and `.git-credentials` are never read. `.env.example`, `.env.sample` and `.env.template` may be. A path outside the folders, through `..` or a symlink, is refused.

So unlike a review, Investigate sends the contents of files in the folders it may read. Each tool call writes one line to an audit file in the support folder. When the run ends, MinMacs keeps the count of calls and refusals and the bytes handed to the model, and deletes that file.

## Where it goes

A search of `Sources` for `http://` and `https://` strings finds only localhost URLs, which LocoHost uses to open or check a local server. `NSURLSession` appears only in LocoHost's port check. The code holds no telemetry. The model calls go out through the `claude` or `codex` CLI.

There is no switch yet that turns the review off for one expert. [PLAN.md](2.0/PLAN.md) section 10 asks for one.
