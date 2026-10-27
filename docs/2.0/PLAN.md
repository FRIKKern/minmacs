# MinMacs 2.0 plan

**The best developer experience on a Mac: five experts, one core, nothing to set up.**

MinMacs 2.0 is one app with five experts in the menu bar. Each expert keeps its own icon and its own field:

| Expert | Field |
|---|---|
| **MinMacs** | Performance: apps, agents, RAM, CPU, energy and heat |
| **LocoHost** | Localhost servers: what runs, where, who uses it, what it costs |
| **WorkForest** | Git worktrees: merged, stale, in use, what each holds |
| **Noo-Noo** | Developer clutter: caches, build output, leftovers from agents and tools, what piles up on a dev Mac |
| **Insomnia** | Keeping the Mac awake while work runs, and letting it sleep when nothing does |

They share one core. That makes all five together cost about what one costs today, and lets each expert know what the others know.

## 1. Principles

1. **Less is more.** Each expert shows less than its standalone app does today, and knows more. Every menu follows docs/DESIGN.md.
2. **Works out of the box.**
   - Install, and each expert finds its own scope: scan roots, agents, terminals, the claude or codex login.
   - Defaults are safe and useful, with no setup screen.
   - Settings exist, and nobody has to open them.
3. **One core, many experts.** An expert is a lens on shared facts. It never samples, scans or asks the model on its own.
4. **Experts help each other.** A worktree knows its servers, a server knows its worktree, a cache knows its project, and keep-awake knows which agent is working.
5. **Nothing is lost.** Every action can be undone, is checked fresh right before it runs, and goes to the Trash or a recovery folder, never a permanent delete.
6. **Each expert is optional.** Hide its icon and its expertise still feeds the others. With every icon hidden, MinMacs still runs the core for agents on the CLI.

## 2. What each app brings

| Expert | From | Keep | Leave behind |
|---|---|---|---|
| MinMacs | MinMacs 1.2 | Agent registry (63 harnesses, working, blocked and idle signals), app quit and restore, browser tab trim, cmux reader | The rule-removal bug in `setVerdict:`, the monolithic menu, CI that never runs tests |
| LocoHost | LocoHost 0.1 | Socket and activity model, investigation, Where, restart and keep, the review and judge, modes | Its private copy of shared code |
| WorkForest | WorkForest 0.1 | Discovery, merge detection by ancestry and squash, reversible removal with saved `.env` files, batching, the render harness | Its private copy of shared code |
| Noo-Noo | Noo-Noo 0.7 (Go) | Its knowledge: APFS-aware sizing, leak signatures, cache targets, safety rules, audit before delete, recovery bundles, disk trends. Ported to Objective-C | The Go daemon, Wails app, socket RPC, permanent deletes, broken auto-clean and Settings save |
| Insomnia | Insomnia | Power assertions, lid mode through the sudoers rule, battery, network and thermal guards, "manual wins" | The self-updater, `pmset` on the main thread, debug hooks in release builds |

## 3. The shared core

One process, `MinMacs.app`, with up to five status items. The same binary is the CLI. Built with clang alone, in Objective-C, like four of the five today.

```
Core/
  Senses     one 5-second pass: processes, sockets, power, thermal, memory pressure
             FSEvents for folders that change, instead of rescanning them
  Know       Registry (agents), Sessions (Claude Code, Codex, pi), Where (cmux, tmux, Terminal, iTerm2, apps),
             Git (repos, worktrees, merges), Sizer (APFS-aware, cached), Clutter (Noo-Noo's knowledge as data)
  Graph      links facts: session → worktree → servers, processes, caches, keep-awake need
  Review     one broker for every expert: rules first, fingerprint cache, batches, judge, summary
  Act        Modes (MustKeep, Plan), Undo (records, Trash, recovery, restore), Notify
  Store      one support folder; state files per expert, written by the core
Experts/     MinMacs, LocoHost, WorkForest, NooNoo, Insomnia: each a lens on Graph, with its own menu and CLI verbs
UI/          the DESIGN.md menu kit: header, summary, rows, hover cards, render harness
```

**One sampler.** Today MinMacs, LocoHost and WorkForest each walk the process table on their own timers. In 2.0 one pass feeds all five.

**Event-driven, not polling.** FSEvents tells WorkForest and Noo-Noo which folders changed, so a warm scan reads only what changed. Today WorkForest's warm scan takes 5 seconds. The goal is under one second, measured in phase 1.

**One graph, five lenses.** Every finding has an owner. The graph lets each expert answer questions it cannot answer alone:

| Expert | Gains from the others |
|---|---|
| LocoHost | The worktree a server runs in and whether it is merged, from WorkForest. Whether its agent is working, from MinMacs |
| WorkForest | The servers running inside a worktree, from LocoHost. Its node_modules and build output, sized by Noo-Noo. Its agent, from MinMacs |
| Noo-Noo | Which project a cache belongs to and whether that project is finished, from WorkForest. Leftover temp folders of agents that ended, from MinMacs |
| MinMacs | Which apps and helpers belong to a finished workstream: headless Chrome, a dev server, an idle agent |
| Insomnia | Whether any agent is working, from MinMacs. Whether a long build or test runs, from LocoHost and MinMacs. No polling of another binary |

## 4. The review: cover more, pay less

**Today**, measured on this Mac:
- LocoHost: about 18k tokens an hour.
- WorkForest: about 190k tokens a review, every 2 hours.
- Together that is roughly 2.7M tokens a day.
- Both describe the same sessions and worktrees separately.

**2.0** has one review broker for all experts. The cost figures in this list are estimates to be measured in phase 4.

1. **Rules decide first.** "Uncommitted changes", "used 3 minutes ago", "a service" and "a known cache kind" need no model.
2. **Fingerprint cache.** A finding goes to the model only when its facts changed since its last verdict. Fingerprints are things like the git HEAD, activity buckets and size buckets.
3. **One block per workstream.** The facts that LocoHost and WorkForest both send today are sent once.
4. **Agents where they pay.**
   - Batches run in parallel, with a small schema per expert.
   - The judge runs only on borderline findings in Eager.
   - **Investigate** sends one deeper agent run at a single workstream, only when you ask. It gets read-only tools scoped to that workstream's folders.

The review runs on your own login: Haiku first, Luna through codex when Claude is out of usage, no API keys and no tools in the routine review. It wakes on events from every expert, spaced at least ten minutes apart:
- a new server or worktree
- memory pressure or low disk
- uptime marks
- an agent going idle

**Target:** a fifth of today's tokens or less, with the same verdicts on a recorded fixture.

## 5. Out of the box

On first launch, with no questions asked:
- **Scan roots** come from where git repos and agent sessions actually are on this Mac.
- **Agents** are recognized from the registry, and terminals from Where.
- **The model** is found: claude or codex login, whichever is signed in.
- **Each expert starts in its safest useful mode:**
  - MinMacs, LocoHost and WorkForest in Proactive. They act only on obvious waste, after a day of watching.
  - Noo-Noo in Proactive for known cache kinds, which go to the Trash.
  - Insomnia keeps the Mac awake while agents work.
- **Old apps:** if any of the five standalone apps is installed, their settings, rules and undo records are carried over, and you are asked once to remove the old copies.

## 6. Sophistication, where it helps

These are the capabilities that set 2.0 apart, each owned by one expert:

- **Wrap Up a workstream.** WorkForest, LocoHost and Noo-Noo together: an agent finished yesterday, its branch is merged, so its servers, worktree, caches and headless browsers go in one undoable step.
- **Is this port mine?** `minmacs work --here --json` tells an agent which port, worktree and processes belong to its own session.
- **Go to.** Jump from any server or worktree to the cmux tab, tmux pane, terminal tab or agent app it lives in.
- **Clutter that knows its owner.** Noo-Noo sizes `node_modules`, `.next`, DerivedData, simulators, the pnpm store, Docker disks and agent temp folders. It ties each to its project, and finished projects go first.
- **Heat and battery aware.** MinMacs and Insomnia together keep the Mac awake for a working agent. They let it sleep when the lid closes in a bag, and stop leftovers sooner when the Mac runs hot.
- **Trends.** Disk and memory growth over weeks, from Noo-Noo's trend math. "The pnpm store grew 9 GB this month."

## 7. Menus and CLI

**Menus.** Each expert has its own icon and menu, all built with one menu kit to docs/DESIGN.md:
- a header of two lines and a summary of at most three
- at most two actions
- sections of at most six rows
- a hover card that says in plain words why something stays or when it goes

A row that belongs to another expert links there. A server's card shows "worktree speed-3-base, merged" and opens WorkForest's card.

**Settings.** One window for all experts: show or hide each icon, the mode per expert, the model.

**CLI.**
- One binary: `minmacs status`, `minmacs work`, `minmacs hosts …`, `minmacs trees …`, `minmacs apps …`, `minmacs clutter …`, `minmacs awake …`, `minmacs review`, `minmacs tidy --dry-run`, `minmacs where`, `minmacs restore`.
- `locohost`, `workforest`, `noo-noo` and `insomnia` stay as names for the same binary, so scripts and agents keep working. So do their URL schemes.

## 8. Migration

On first launch MinMacs 2.0 reads the old apps' state and offers, once, to quit and remove them:
- **Prefs domains:** `no.guerrilla.minmacs`, `locohost`, `workforest` and `insomnia`.
- **State files:** rules, activity, `closed.json`, `removed.json` and `kept.json`.
- **Restore records:** a worktree removed by WorkForest stays restorable.
- **Insomnia:** the sudoers rule stays, with its exact two commands, and a lid override that is still on is turned off.
- **Noo-Noo:** its LaunchAgent `io.noo-noo.d` is removed, with consent.
- **The old repos** are archived with a pointer to MinMacs after 2.0 ships.

## 9. Phases

Each phase ships something usable, with tests in CI and rendered menus. Phases 2 and 3 run as parallel agents in separate worktrees once the core interfaces are fixed.

| Phase | Deliverable | Done when |
|---|---|---|
| 0. Decide | This plan agreed. Core interfaces written as headers: Finding, Expert, Graph, Review broker, Undo. The menu kit extracted from LocoHost and WorkForest | You sign off on scope and the open questions |
| 1. Core with MinMacs and LocoHost | Senses, Know, Graph, Review, Act, Store, the menu kit, the CLI, and two status items | Replaces MinMacs 1.2 and LocoHost on this Mac. All their checks pass in one `test.sh`, which CI runs. Idle CPU and memory are measured and stay below MinMacs 1.2's |
| 2. WorkForest | The expert, FSEvents scanning, cross-links with LocoHost, Wrap Up | WorkForest's 62 checks pass, a warm scan of this Mac's 99 worktrees takes under a second, and Wrap Up is undoable end to end |
| 3. Noo-Noo and Insomnia | Noo-Noo's knowledge ported onto Undo and the Trash. Insomnia with its guards, driven by the graph | The disk tests pass on fixtures, and nothing outside listed clutter kinds can be touched. The guard matrix passes |
| 4. One review | Rules-first triage, the fingerprint cache, workstream facts, Investigate | Tokens a day against today's 2.7M, aiming for a fifth or less, with matching verdicts on a recorded fixture |
| 5. Release | Migration, docs in the Pensum style, Homebrew, signed release, old repos archived | A clean install and an upgrade from all five apps work on a fresh user account |

## 10. Risks

- **Scope.** Five products in one. Phase 1 alone replaces two apps, and each phase ships before the next starts.
- **More destructive actions.** One Undo engine, the Trash by default, checking fresh before acting, and the fixture-only rule for tests in AGENTS.md.
- **One process for all.** Heavy work runs on background queues with time budgets, and a slow expert can never block a menu. Crash reports are kept per expert.
- **Privacy.** Each expert's facts are listed in docs/REVIEW.md, redacted, and can be turned off per expert.
- **Lid mode.** `disablesleep` survives a crash, so the app clears it on launch, as Insomnia does. A privileged helper waits for a signed, notarized build.

## 11. Open questions

1. **Noo-Noo's offload** (moving big folders to an external drive): in phase 3, or later?
2. **An Apple Developer account** for a signed, notarized app and a cleaner lid mode, or stay source-built?
3. **Noo-Noo's default for known caches:** Trash on its own in Proactive, as proposed, or always ask?
4. **The standalone apps:** freeze now, or keep fixing them until 2.0 ships?
