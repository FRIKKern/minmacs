# Sources

build.sh compiles every `.m` under this folder into one binary. Core symbols use the prefix `MM`. [docs/2.0/PLAN.md](../docs/2.0/PLAN.md) section 3 describes each part, and [SYNTHESIS.md](../docs/2.0/research/SYNTHESIS.md) section 1 lists the patterns P1 to P66 that each Core folder holds.

| Folder | What it holds |
|---|---|
| `main.m` | The entry point. It registers the experts linked in, then hands over to the shell. |
| `Shell` | The app delegate: MMCoreStart, core.sock, one status item per expert, One Icon, Settings with a pane for each expert that offers `prefSpecs`, the login item and URLs. The main-thread watchdog of `MMWatchdog.h`, and the startup marks the bench reads. |
| `Core/Runtime` | Labeled serial queues, dispatch timers, jobs with deadlines, the out-of-process worker and crash breadcrumbs. |
| `Core/Senses` | The one 5-second pass over processes, sockets, power, thermal, memory and lid, plus kqueue exits and FSEvents. |
| `Core/Know` | The agent registry, sessions, Where, git, the Sizer and the clutter catalog. |
| `Core/Graph` | The immutable snapshot of every finding and its owner, and the one builder that makes it. |
| `Core/Store` | The support folder, the prefs domain and the SQLite log for undo, history and trends. |
| `Core/Review` | The review broker: rules, the fingerprint cache, batches, the judge and the summary. |
| `Core/Act` | Modes, MustKeep, plans, actions, undo and the one notifier. |
| `Experts/MinMacs` | Performance: apps, agents, RAM, CPU, energy and heat. |
| `Experts/LocoHost` | Localhost servers: what runs, where, who uses it and what it costs. |
| `Experts/WorkForest` | Git worktrees: merged, stale, in use and what each holds. |
| `Experts/NooNoo` | Developer clutter: caches, build output and leftovers from agents and tools. |
| `Experts/Insomnia` | Keeping the Mac awake while an agent works. |
| `UI` | The menu kit to [DESIGN.md](../docs/DESIGN.md): status items, header, summary, rows, hover cards and the render tool. |
| `CLI` | The verb registry, Core's verbs, the old names `locohost` and MinMacs 1.x, and the URL router. |

An empty folder holds a `.gitkeep` until its first file lands.
