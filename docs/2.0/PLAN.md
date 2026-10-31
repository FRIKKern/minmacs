# MinMacs 2.0 plan

**The best developer experience on a Mac: five experts, one core, nothing to set up.**

Version 2, 2026-10-27. Updated from the [research synthesis](research/SYNTHESIS.md) and the owner's decisions in issue #10. A tag such as (A1) or (D5) names the research recommendation behind a line.

MinMacs 2.0 is one app with five experts in the menu bar. Each keeps its own icon and its own field:

| Expert | Field |
|---|---|
| **MinMacs** | Performance: apps, agents, RAM, CPU, energy and heat |
| **LocoHost** | Localhost servers: what runs, where, who uses it, what it costs |
| **WorkForest** | Git worktrees: merged, stale, in use, what each holds |
| **Noo-Noo** | Developer clutter: caches, build output, leftovers from agents and tools |
| **Insomnia** | Keeping the Mac awake while work runs, and letting it sleep when nothing does |

They share one core, which makes all five together cost about what one costs today and lets each expert know what the others know.

## 1. Principles

1. **Less is more.** Each expert shows less than its standalone app does today, and knows more. Every menu follows [DESIGN.md](../DESIGN.md).
2. **Works out of the box.** Install, and each expert finds its own scope. There is no setup screen and no permission prompt at launch. A permission is asked for the first time a function needs it (G3).
3. **One core, many experts.** An expert is a lens on shared facts. It never samples, scans or asks the model on its own.
4. **Experts help each other.** A worktree knows its servers, a server knows its worktree, a cache knows its project, and keep-awake knows which agent works.
5. **Nothing is lost.**
   - Every action is checked fresh right before it runs.
   - An action either goes to the Trash, goes to a recovery folder, or uses the owning tool's own command.
   - What cannot be verified is kept. MinMacs never empties the Trash (C1).
6. **Each expert is optional.** Hiding its icon keeps its expertise feeding the others. The app cannot know whether an icon is visible, so opening MinMacs again opens the Settings window on its overview pane (G2).

## 2. What each app brings

| Expert | From | Keep | Leave behind |
|---|---|---|---|
| MinMacs | MinMacs 1.2 | Agent registry, app quit and restore, browser tab trim | The `setVerdict:` removal bug, main-thread sampling, NSTimer ticks, the 2 MB tail of `workstream.jsonl` (E2, H8) |
| LocoHost | LocoHost 0.1 | Socket and activity model, investigation, Where, restart and keep | Its own agent name list, now registry lookups (A2). Main-thread sampling, fixed temp file names, and the unset `merged` key (A6, H8) |
| WorkForest | WorkForest 0.1 | Discovery, merge detection, reversible removal, batching, the render harness, the day of watching | Scans on global queues with no autorelease pool, the lock shared with main, the `locohost list --json` spawn (H8) |
| Noo-Noo | Noo-Noo 0.7 (Go) | Its knowledge, ported: extent-union sizing, leak signatures, cache targets, safety rules, audit before delete, git recovery bundles, trend math | The daemon, Wails app, socket RPC, six permanent `os.RemoveAll` sites, broken auto-clean and Settings save (A9) |
| Insomnia | Insomnia | Both power assertion types, lid mode through the sudoers rule, battery, network and thermal guards, "manual wins" | `pmset -g` reads (80 ms each; lid state now comes from IOKit), the debug prefs, the self-updater (A14, B5) |

The registry splits `socket_activity` into `net_bytes` and `local_status`, adds a `session_status_file` signal, and adds `/Applications/Codex.app` to the codex row (E6).

## 3. The shared core

One process, `MinMacs.app`, with up to five status items. The same binary is the CLI. It is Objective-C, built with clang alone, for **macOS 14 and later**. Core symbols use the prefix **MM**.

```
Core/
  Runtime  labeled serial queues, dispatch timers, jobs with deadlines, the out-of-process worker, crash breadcrumbs
  Senses   one 5-second pass: processes, sockets, power, thermal, memory pressure, lid; exits by kqueue; folders by FSEvents
  Know     Registry (agents), Sessions, Where, Git, Sizer, Clutter catalog
  Graph    one immutable snapshot of every finding and its owner, rebuilt by one builder
  Store    one support folder, one prefs domain, SQLite for history, undo and trends
  Review   one broker: rules first, fingerprint cache, batches, judge, summary
  Act      modes, MustKeep, plans, actions, undo, one notifier
Experts/   MinMacs, LocoHost, WorkForest, NooNoo, Insomnia: lenses on the graph, each with its menu and CLI verbs
UI/        the menu kit to DESIGN.md: status items, header, summary, rows, hover cards, render tool
CLI/       one verb registry and one URL router
```

The catalog of 66 shared patterns in [SYNTHESIS.md](research/SYNTHESIS.md) section 1 is the Core API. Phase 0 writes it as headers.

**Threads (H1, H2).**
- AppKit runs on the main thread only.
- Each knower has one labeled serial queue, `no.guerrilla.minmacs.<expert>.<job>`, with dispatch timers and an autorelease pool per work item.
- One builder makes an immutable graph snapshot with a generation number. Main is the only writer of the current snapshot, so menus read without locks.

**Senses (A1, B1, B2, B3, B12).**
- **One pass every 5 seconds,** at about 6.3 ms of CPU on this Mac. One `KERN_PROC_ALL` sysctl covers every pid, and LocoHost's socket scan covers our own pids.
- **Never in a tick:** `lsof`, `nettop`, `ps` or `pmset`.
- **Pushed, not polled:** process exits come from kqueue `NOTE_EXIT`, and app launch, quit, sleep and wake from `NSWorkspace`.
- **Folders come from FSEvents with a saved event id.** `node_modules` and `.git/objects` are filtered in the callback. A `MustScanSubDirs` event rescans only that folder.
- **Energy is shown as a rank,** from `ri_energy_nj` deltas, never as joules or watts.

**Know.**
- **Agents (A2, E1, E2, E3, B6).** The registry is the only agent recognizer. Claude Code's status comes, in order of trust, from:
  1. `~/.claude/sessions/<pid>.json`
  2. a `caffeinate` child
  3. tree CPU

  cmux comes from one `cmux events` reader. Codex threads and turns come from its SQLite files, opened read-only.
- **Worktrees (E7, C4, C5, A12).** The scan roots are the user's folders plus:
  - `<repo>/.claude/worktrees/*`
  - `~/.cursor/worktrees/*/*`
  - `~/conductor/workspaces/*/*`

  Merge checks add git's `merge-tree` simulated merge. A `git worktree lock` or Claude Code's ownership marker counts as in use. Remote containment is its own git fact.
- **Sizes (A3, B4, D2).** The Sizer has three tiers:
  1. Every periodic walk uses `getattrlistbulk` with allocated and private size.
  2. Right before an action, Noo-Noo's extent union.
  3. A statfs delta is written into the undo record.

  A size shown is what deleting frees.
- **Clutter (D1, D5, D6, D8).** The catalog ships as data in `registry/clutter/*.json`, beside `registry/agents/`.
  - A cache path is never found by running the tool. MinMacs reads env vars and config files instead.
  - The root-owned simulator dyld cache is report-only.
  - `dist` and `build` are skipped when git tracks them.
  - Back-links in tool files count as owner facts, such as DerivedData's `WorkspacePath` and Playwright's `.links`.

**Store (A4, C2, F8).**
- One support folder and one prefs domain.
- Rules come from WorkForest, with MinMacs's wildcards and without the `setVerdict:` removal.
- **SQLite,** which macOS ships, holds one append-only log for undo, restore, review history and trends. The app and the CLI write to it safely at the same time.

**Act (A9, A10, C3, D3, B7, H3, B11).**
- **Undo** writes its record before acting.
- **A git bundle is taken** whenever commits exist on no remote.
- **The Trash** replaces every permanent delete.
- **Tool-owned caches** are cleaned with the tool's own command. It runs first in dry-run form, and its output is kept in the undo record.
- **Keeps.** Work keeps and review keeps are separate, and timed keeps use a stable key.
- **Stopping.** SIGTERM first, and SIGKILL only on a second request. Pid and start time are checked before both.
- **Heavy walks** run out of process behind one `MMWorker` protocol. It is an XPC service if phase 0's test passes on macOS 14, and a `minmacs _walk` child if not. The test passed on macOS 14.8.9 on 2026-10-31, docs/2.0/TESTS.md question 3. 2.0 runs the child today, and a move to XPC is a change of its own.
- **One notifier,** for actions the person did not ask for. It sends one notification per review, with an Undo action.

## 4. The review: cover more, pay less

**Today, measured (track F).**
- One LocoHost review of 5 hosts used 14,175 tokens. One WorkForest review of 91 worktrees used 243,061.
- On the default schedules that is about **3.26M tokens a day**, before event reviews.
- Thinking is 76 to 85 percent of output.
- `claude -p` already caches a repeated system prompt for one hour.

**2.0.** One broker, starting from WorkForest's Review.m (A6), on your own login: Haiku first, Luna through codex when Claude is out of usage, no API keys and no tools.

1. **Fingerprint cache first** (A5, F1). A finding goes to the model only when its facts changed. Under track F's model this cuts about 1,092 tree reviews a day to about 80, before any rules.
2. **Rules as data** (F2), with a count of how many findings each rule decides.
3. **Smaller calls.**
   - Compact JSON with empty fields dropped and stable facts first (F5).
   - A routine schema of verdict, confidence, about, reason and keep_evidence only. Prose is built from facts or asked for when a card opens (F6).
   - `--effort low`, measured against the fixture before the target relies on it (F3).
   - A five-minute cache TTL when one expert's calls run more than an hour apart (F4).
4. **One wake queue,** with a ten-minute gap between event reviews (A7).
5. **Investigate**, only on request. It uses a custom system prompt and only Read, Grep and Glob, scoped to one workstream (F9).

**Measured as two numbers (decision 10):**
- uncached tokens, the closest proxy for what counts against a subscription
- list cost

Every call records its full usage split (F7). **Target:** a fifth of today's 3.26M or less on a normal day. A bad day at a quarter is acceptable. Track F's model gives about 150k a normal day and about 680k a bad one, so the fingerprint cache must work from day one.

## 5. Out of the box

- **Every expert starts in Proactive** with a day of watching before it acts on its own (A8).
- **Insomnia** keeps the Mac awake only while an agent works (decision 4).
- **No hooks are installed** (decision 11). Claude Code's status files, cmux events, Codex's SQLite and power assertions cover Claude Code and Codex with nothing installed. Opt-in async hooks may come later, if a measurement shows a gap.
- **No onboarding window.** On the first day each expert's summary says what it watches and when it first acts (G3).
- **Icons:** an expert whose field is empty on this Mac starts with its icon hidden, and shows it when the field appears.
- **Login:** MinMacs registers as a login item on first launch, says so in one line, and has a switch in Settings (decision 18).
- **The model** is found on its own: whichever claude or codex login is signed in.
- **Old apps:** their settings, rules, keeps and undo records carry over.

## 6. Sophistication, where it helps

- **Wrap Up a workstream.** It covers its servers, its worktree with that worktree's `.next` and `node_modules`, its caches and its headless browsers, in one undoable step. Clutter is ranked by owner state first, merged worktrees first, then by size freed (D7).
- **Is this port mine?** `minmacs work --here --json` answers for an agent.
- **Go to** the cmux tab, tmux pane, terminal tab or agent app that runs something.
- **Finished or paused.** A Claude Code `Stop` with background tasks or session crons counts as still working, and `StopFailure` counts as idle (E8).
- **Insomnia, battery-aware** (C8). It ends on low battery, offers to turn off on battery, and ties each assertion to the working agent's pid.
- **Trends** of disk and memory growth over weeks. The example in the menu will be a measured one, from phase 3.

## 7. Menus and CLI

**Menus** follow DESIGN.md:
- **Five icons by default** (decision 3). Each is a square template symbol, with `autosaveName` set to `minmacs.<expert>` and removal allowed (G1).
- **"One Icon" in Settings** gives one flat menu with a section per expert, never nested submenus (C10, G4).
- **Footer:** Hide Icon, Settings… and Quit MinMacs (G5).
- **One Settings window** replaces the nested settings submenus.
- **Unavailable actions** are dimmed in place with the reason in gray. Actions that never apply are hidden (decision 12).
- **Rare power actions** are Option alternates, and nothing is reachable only through Option (G11).
- **One width, one label column, one set of formatters** for every expert (A11, A16).
- **User data stays with its owner.** Data rows such as Cursor's `state.vscdb` and Claude Code transcripts belong to their owner, and the card names the owner's setting (D10).
- **Cross-links.** A fact from another expert links to its card. Phase 0 tests whether one status item can open another's menu at a given row.
- **Verdict words.** Each expert keeps its own words (idle, stale, remove) in menus, prompts and `--json`. Core stores keep, go and unsure underneath (decision 9).

**CLI** (A13, C11, H6, B10):
- **One verb registry and one URL router.** Every verb has `--json` and `--dry-run`, and `minmacs hosts 3000` explains one port.
- **Talking to the app.** The CLI talks to the running app over `core.sock` in the support folder, with a lock and a same-user check. It runs the core cold when no app answers. Verbs that change things go through the app.
- **Old names keep working.** `locohost`, `workforest`, `noo-noo` and `insomnia` stay as names for the same binary, and their URL schemes stay too.
- **Shortcuts** use "Run Shell Script" with the CLI. There are no App Intents, which are Swift only.

## 8. Migration

On first launch MinMacs 2.0 reads the old apps' state and offers, once, to quit and remove them:
- **Prefs** from `no.guerrilla.locohost`, `no.guerrilla.workforest`, `no.guerrilla.minmacs` and Insomnia's bundle domain.
- **Noo-Noo's files:** `~/.config/noo-noo/config.toml` and `store.db`.
- **State:** rules, activity, `closed.json`, `removed.json` and `kept.json`. Every restore record keeps working.
- **Hidden icons stay hidden:** each old app's hidden or visible icon state carries over to `minmacs.<expert>` (G8).
- **Insomnia's sudoers rule** stays, and a lid override that is still on is turned off.
- **Noo-Noo's LaunchAgent** is checked with `+[SMAppService statusForLegacyURL:]` and removed with consent (B9).
- **The standalone apps** get bug fixes only from now on, and their READMEs point here (decision 15). They are archived after 2.0 ships.

## 9. Phases

Each phase ships something usable. Phase 6 starts once phase 4 is done and runs alongside phase 5, so release builds on its numbers. CI runs build.sh, test.sh on fixtures, and the render tool, and keeps the PNGs (A15). Phases 2 and 3 run as parallel agents in separate worktrees once the core interfaces are fixed.

| Phase | Deliverable | Done when |
|---|---|---|
| 0. Decide | Decisions recorded. Core headers for the 66 patterns. The menu kit and render tool from WorkForest. The 2.0 skeleton and CI. The settling tests | The headers compile, the kit renders LocoHost's and WorkForest's cards as today, CI runs on every push, and each settling test has a written result |
| 1. Core with MinMacs and LocoHost | Runtime, Senses, Know, Graph, Store, Review, Act, the menu kit, the CLI, two status items | It replaces MinMacs 1.2 and LocoHost on this Mac, and all their checks pass in CI. Idle footprint is 50 MB or less, idle CPU 0.5 percent or less over 10 minutes, and peak footprint 100 MB or less (H4). The render check covers Increase Contrast and Control-F8 (G7). A session with status idle and 4 percent CPU comes out idle (E9). docs/REVIEW.md lists every fact sent |
| 2. WorkForest | The expert, FSEvents scanning, cross-links, Wrap Up | Every check in WorkForest's test.sh passes. A warm scan of about 100 worktrees takes under a second. A full scan peaks at 300 MB or less in the worker, and the app returns to idle (H5). Wrap Up is undoable end to end |
| 3. Noo-Noo and Insomnia | The clutter catalog on Undo, tool commands and the Trash. Disk trends. Insomnia from the graph, with its guards | Disk tests pass on fixtures, and nothing outside listed clutter rows can be touched. The guard matrix passes |
| 4. One review | The broker with the fingerprint cache, rules as data, smaller calls and Investigate. Measured with a budget of about 2M Haiku tokens (decision 16) | Uncached tokens and list cost a day, against today's 3.26M, with the same verdicts on a recorded fixture |
| 5. Release | Migration, docs, Homebrew, a notarized release, old repos archived | A clean install and an upgrade from each of the five apps work on a fresh user account. The README publishes the measured idle cost (C13) |
| 6. Bench and polish | A bench suite with a regression gate in CI, then tuning of the tick, menus, scans, review and startup, a 24-hour soak, and two weeks of daily use with every bug fixed under a test | Every budget in docs/2.0/BENCH.md holds on this Mac: with five experts on, idle CPU 0.3 percent or less, idle footprint 45 MB or less, under 1 wakeup a second; menu open under 30 ms and card hover under 16 ms at p95; a warm scan of 300 worktrees under 2 seconds; icons within 300 ms of launch. A 24-hour soak has no leak, hang or crash |

**Settling tests for phases 0 and 1.** Each needs a written result before code depends on it:
- Does an ad-hoc signed app get notification permission on macOS 27?
- Does `SMAppService` register from an ad-hoc bundle?
- Does an embedded XPC service launch on macOS 14?
- Does the System Settings menu bar toggle hide all five icons at once?
- Can one status item open another's menu at a given row?
- Do `.ips` crash reports name the dispatch queue?
- Does an autorelease pool explain WorkForest's memory spike?
- Does `cmux events` need a password outside a cmux terminal?
- Is `~/.claude/sessions/<pid>.json` stable across releases, and what does `shell` mean?
- Does Codex `thread_turns.status` show a live turn?
- Are clone refcounts exact?
- Do FSEvents for `~/Documents` reach an ad-hoc app without a prompt?
- What does `tmp_cleaner` remove?
- How much does removing one pnpm worktree's `node_modules` really free?

## 10. Risks

- **Scope.** Five products in one. Each phase ships before the next starts.
- **More destructive actions.** One Undo engine, the Trash or the tool's own command, checking fresh before acting, git bundles, and the fixture-only rule for tests. Asking a package manager for a path can install things, so AGENTS.md bans it in tests (D).
- **One process for all.** Long walks run in the out-of-process worker, because code inside the process cannot be stopped from outside. A crash breadcrumb names the expert and job that ran last (H3).
- **Privacy** (C12).
  - No Screen Recording or Accessibility rights are asked for.
  - Every host the app contacts is listed, and no telemetry is sent.
  - docs/REVIEW.md lists each expert's facts, which are redacted and can be turned off per expert.
- **Lid mode.** It keeps the sudoers rule until a notarized build ships a LaunchDaemon (B8). A lid override that is still on is cleared at launch.

## 11. Decisions

Decided by the owner on 2026-10-27, issue #10. The numbers match SYNTHESIS.md section 5.

| # | Decision |
|---|---|
| 1 | **Removing clutter:** tool-owned caches go through the tool's own command (`xcrun simctl`, `brew cleanup`, `pnpm store prune`, `docker system prune`). Build output and leftover temp folders go to the Trash |
| 2 | **macOS 14** is the oldest supported version |
| 3 | **Five icons** by default, with "One Icon" in Settings |
| 4 | **Insomnia** keeps the Mac awake only while an agent works, from the first launch on |
| 5 | **SQLite** for undo, history and trends |
| 6 | **Worktrees other tools made:** act on Claude Code's agent worktrees once their session has ended. Only show Cursor's and Conductor's for now |
| 7 | **Commits on no remote:** a worktree whose HEAD is on no remote but is squash-merged may be removed in Eager only, after a git bundle is saved. Proactive keeps it |
| 8 | **A server keep** sticks to project folder and script, falling back to folder and port |
| 9 | **Words:** each expert keeps its own verdict words. Core stores keep, go and unsure |
| 10 | **Review cost** is measured as uncached tokens and list cost. A fifth of today is the target, and a quarter on a bad day is acceptable |
| 11 | **Hooks:** none ship in 2.0 |
| 12 | **Unavailable actions** are dimmed in place with the reason. Actions that never apply are hidden |
| 13 | **An Apple Developer account,** before release, for notarization, notifications and the lid-mode LaunchDaemon. Not needed for phases 0 to 4 |
| 14 | **Noo-Noo's offload** comes after 2.0 |
| 15 | **The standalone apps** are frozen: bug fixes only |
| 16 | **About 2M Haiku tokens** are approved for the phase 4 measurements |
| 17 | **MM** is the Core prefix |
| 18 | **Login item** at first launch, said in one line, with a Settings switch |
| 19 | **Every settling test** in section 9 is approved |
