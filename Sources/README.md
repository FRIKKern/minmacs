# Sources

build.sh compiles every `.m` under this folder into one binary. Core symbols use the prefix `MM`. [docs/2.0/PLAN.md](../docs/2.0/PLAN.md) section 3 describes each part, and [SYNTHESIS.md](../docs/2.0/research/SYNTHESIS.md) section 1 lists the patterns P1 to P66 that each Core folder holds.

| Folder | What it holds |
|---|---|
| `main.m` | The entry point. It registers the experts linked in, then hands over to the shell. |
| `Shell` | The app delegate: MMCoreStart, core.sock, the one icon that opens the menu window, the login item and URLs. With the pref `core.window` off: one status item per expert, One Icon, and Settings with a pane for each expert that offers `prefSpecs`. The main-thread watchdog of `MMWatchdog.h`, and the startup marks the bench reads. The menu window's wiring, issue #62: `MMWindowFeed` makes the window's model from a snapshot and its `MMPerformance`, `MMFixRunner` runs Fix Everything through `MMRunAction` and `MMRunWrapUp`, `MMWindowController` answers the window while it is open and applies the welcome's two answers at Start, the login item and the removal choice, and `MMWindowCLI` is the `window` verb, which the shell adds with `MMAddVerb`. |
| `Core/Runtime` | Labeled serial queues, dispatch timers, jobs with deadlines, the out-of-process worker and crash breadcrumbs. |
| `Core/Senses` | The one 5-second pass over processes, sockets, power, thermal, memory, lid, the whole Mac's network and the home volume's size, plus kqueue exits and FSEvents. |
| `Core/Know` | The agent registry, sessions, Where, git, the Sizer and the clutter catalog. |
| `Core/Graph` | The immutable snapshot of every finding and its owner, and the one builder that makes it. |
| `Core/Store` | The support folder, the prefs domain and the SQLite log for undo, history and trends. |
| `Core/Review` | The review broker: rules, the fingerprint cache, batches, the judge and the summary. Investigate and its scoped tool server. |
| `Core/Act` | Modes, MustKeep, plans, actions, undo and the one notifier. |
| `Experts/MinMacs` | Performance: apps, agents, RAM, CPU, energy and heat. |
| `Experts/LocoHost` | Localhost servers: what runs, where, who uses it and what it costs. |
| `Experts/WorkForest` | Git worktrees: merged, stale, in use and what each holds. |
| `Experts/NooNoo` | Developer clutter: caches, build output and leftovers from agents and tools. |
| `Experts/Insomnia` | Keeping the Mac awake while an agent works. |
| `UI` | `Window`: the menu window to [DESIGN.md](../docs/DESIGN.md), its view model, its views, Settings in place and the welcome. The menu kit of the menus of before: status items, header, summary, rows, hover cards. The render tool's drawing. |
| `CLI` | The verb registry, Core's verbs, the old names `locohost` and MinMacs 1.x, and the URL router. |

An empty folder holds a `.gitkeep` until its first file lands.
