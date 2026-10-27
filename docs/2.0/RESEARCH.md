# MinMacs 2.0 research brief

**Goal:** find every pattern the five experts can share, and the best known way to do each. The research feeds the plan in [PLAN.md](PLAN.md). Every finding names its source: a file and line in our code, a URL, an Apple header, or a command run on this Mac.

**Rules for every track**
- Only claim what a source shows. Mark guesses as guesses.
- Read-only on this Mac: no installs, no deletes, no settings changes. Running commands that only read is fine.
- Name the concrete thing: the API, function, file or number.
- End with recommendations, each tied to a plan section and to one shared pattern.

**Our code to read**
- `~/Documents/GitHub/locohost`
- `~/Documents/GitHub/workforest`
- `~/Documents/GitHub/minmacs`, branch `legacy` for MinMacs 1.2
- [FRIKKern/insomnia](https://github.com/FRIKKern/insomnia) and [FRIKKern/noo-noo](https://github.com/FRIKKern/noo-noo)

## Tracks

### A. Shared patterns in our five codebases
Inventory every concept implemented more than once:
- process sampling and the process tree, socket reading, responsible-app lookup
- prefs, rules files, state files, the support folder
- the review call, judge, summary, batching, redaction
- modes, MustKeep, plan and act, undo and restore, keep and protect
- the menu builder, hover cards, text items, the render harness
- the CLI parser, the URL scheme, install, uninstall and build scripts, test fixtures and fakes, CI

For each concept, name:
- every implementation, by file and function
- the best one, and why
- the shape of the one shared API in Core

**Deliverable:** a catalog of shared patterns, about 30 entries, each one "concept · implementations · canonical choice · Core API".

### B. macOS platform: the fastest and cheapest way to know things
For each fact the experts need, find the most efficient API on macOS 13 to 27, and measure where we can:
- **Process exits:** kqueue `EVFILT_PROC` with `NOTE_EXIT`, against polling.
- **App launch and quit:** `NSWorkspace` notifications.
- **Sockets:** `proc_pidfdinfo` and `PROC_PIDFDSOCKETINFO` cost per sample, and whether `nettop` or NetworkStatistics is usable without entitlements.
- **Folders:** FSEvents with per-folder latency, and `getattrlistbulk` for fast sizing that knows about APFS clones.
- **Energy and heat:** `ri_energy_nj` and `proc_pid_rusage` energy, thermal state, memory pressure through `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`.
- **Power and lid:** IOPM assertions, lid state.
- **Running in the background:** SMAppService login items and agents, and XPC services for isolating heavy scanners.
- **Other surfaces:** App Intents or Shortcuts from Objective-C, and notification actions with UNNotificationAction.

For each, give:
- the cost
- the permissions or entitlements it needs
- whether it works unsigned or ad-hoc signed
- an Objective-C call sketch

**Deliverable:** a table of fact · best API · cost · permission · notes.

### C. Prior art: what the best Mac tools get right
Study these:
- **System monitors:** Stats, iStat Menus, Activity Monitor
- **Cleaners:** CleanMyMac, DaisyDisk, DevCleaner for Xcode, npkill, kondo, Mole, OnyX
- **Keep-awake:** Amphetamine, Lungo, KeepingYouAwake
- **Ports:** port managers and lsof front-ends
- **Worktrees:** git worktree managers, plus the worktree handling in Conductor, cmux, Cursor and Claude Code
- **Menu bar UI:** Bartender and Ice for menu bar management, Raycast for UI patterns

For each tool, cover what it detects, how it decides, how it undoes, how it presents, and what it charges. Then:
- the five patterns worth taking
- the five mistakes to avoid
- the gaps where nothing does what we plan

**Deliverable:** a comparison table, then the take-and-avoid lists.

### D. Developer clutter: the Noo-Noo knowledge base
Build a catalog of what piles up on a developer Mac. Cover:
- **Apple:** Xcode DerivedData, archives, device support, simulators and runtimes
- **Android and JVM:** Android SDK and Gradle, CocoaPods, Maven
- **JavaScript:** npm, pnpm store, yarn, bun, Playwright and Puppeteer browsers, `node_modules`, `.next`, `.turbo`, `dist`, `build`
- **Python:** pip, uv, poetry, conda
- **Others:** cargo `target`, Go build and module caches, Homebrew
- **Containers:** Docker, Colima and OrbStack disks, images and volumes
- **Editors:** JetBrains caches, VS Code and Cursor caches
- **Model files:** Ollama models, Hugging Face hub
- **Agents:** Claude Code, Codex and cmux logs, temp folders and transcripts
- **System:** `/private/tmp` and `$TMPDIR` families, old logs, the Trash

For each entry, give:
- its path patterns
- how to size it, especially where APFS clones change the real size
- whether it is safe to remove, and what regenerates it at what cost
- how to tie it to an owning project or tool
- the official cleanup command, where one exists, such as `xcrun simctl delete unavailable`, `brew cleanup` or `docker system prune`
- read-only measurements of the sizes on this Mac

**Deliverable:** the catalog as JSON-ready rows, in the same spirit as MinMacs's agent registry, plus totals for this Mac.

### E. Agents as event sources
How do the agents on this Mac create work, and how can they tell us about it, instead of us polling? Cover:
- Claude Code hooks: SessionStart, Stop, PreToolUse and others, and where its sessions and worktrees live
- Codex hooks and session files
- cmux hooks and `cmux events`
- pi
- Cursor and Conductor worktrees

For each agent, answer:
- which events exist
- how a hook could notify MinMacs cheaply, through a URL, a file or a Unix socket, without slowing the agent
- what the user must install, ideally nothing

Also check MinMacs's 63-row agent registry: which rows can be verified on this Mac today, and where the `socket_activity` signal could come from.

**Deliverable:** a table of agent · events · paths · hook recipe · verification status.

### F. Model review economics
- **Token use today:** measure LocoHost's and WorkForest's actual tokens per review from their `review.json` files.
- **Prompt caching:** does `claude -p` cache a repeated system prompt, and does `codex exec`? Find the evidence.
- **Cutting tokens:** fact compression, such as dropping null fields, short keys, and one block per workstream; fingerprint caching; rules-first triage.
- **Model choice:** Haiku against Luna against a local model, on quality and cost.
- **The Investigate agent:** what a read-only, tool-scoped deep run costs.

**Deliverable:** a cost model with measured inputs, and a target design with expected tokens a day.

### G. Menu bar UX at the highest standard
- **Apple's guidance:** the Human Interface Guidelines for menu bar extras, menus, progressive disclosure and notifications.
- **Showing many icons:** how several experts show icons without crowding the menu bar, including the notch, Bartender and Ice behavior, and an all-in-one "MinMacs" icon option.
- **Setup:** onboarding with zero setup, and how the best apps explain what they do on first launch without a wizard.

Check these against docs/DESIGN.md and propose changes.

**Deliverable:** about 10 rules to add or change, each with its source.

### H. One-process architecture
Sketch one app with five NSStatusItems sharing one core, and work out:
- the threading model and time budgets per expert
- crash isolation: in-process, with an XPC service per heavy scanner, or a helper
- the memory budget
- how the experts share the graph without locks on the main thread
- how the CLI talks to a running app, or works alone, as today

Measure today's idle CPU and memory of the LocoHost and WorkForest apps on this Mac, as the baseline.

**Deliverable:** an architecture note with diagrams in text, plus measured baselines.

## How the run is organized

Each track has a researcher and a verifier:
- **The researcher** does the work and writes the deliverable.
- **The verifier** tries to break the researcher's claims against the sources, and marks each claim confirmed, corrected or unsupported.

A final synthesis merges the tracks into:
1. the shared-pattern catalog, the Core API surface
2. changes to PLAN.md, section by section
3. an updated DESIGN.md proposal
4. open questions that research could not settle

The output goes to `docs/2.0/research/`, one file per track, plus `SYNTHESIS.md`. Each track has an issue in the Research milestone.
