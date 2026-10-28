# Menus, the main thread and startup

Issues #53 and #55. What a menu open and a card hover cost on main, whether main ever stalls, and how long the app takes from `MMMain` to its icons and summaries. Every number here comes from `tools/bench/bench` on the research Mac, a MacBookPro18,1 with 10 cores on macOS 27.0.1. Other agents built and tested in other worktrees during every run. [MEASUREMENTS.md](MEASUREMENTS.md) has the idle cost and the tick.

## What changed

**Cards on hover.** `MMMenuFromSpec` built every row's card before the menu opened, about 2 ms a card, so menu open grew with the rows. `MMMenuFromSpecOnHover` in `Sources/UI/MMSpecMenu.h` gives each row with a card its submenu arrow and an empty submenu. The submenu's delegate builds the card in `menuNeedsUpdate:`, when the pointer or the keyboard opens it. The shell builds every menu this way through `MMShellMenu` and `MMShellOneIconMenu`. A card whose finding went away after the menu opened says so in one line. The render tool and the tests call `MMLoadCards`, which builds each waiting card as a hover would, and `MMRenderMenu` and `MMMenuProblems` call it too, so the checks see the cards the person sees.

**Menus read only the snapshot.** An expert may implement `-prepareFor:` in `Sources/Core/MMExpert.h`. The graph queue calls it once per snapshot, after the build and before main sees the snapshot, and main reads the result with `-[MMSnapshot preparedFor:]`. This is the one change outside this work's paths: an optional method in `MMExpert.h`, two methods in `MMGraph.h`, and one call in `-[MMGraph buildNow]`.

| Expert | What moved off main |
|---|---|
| LocoHost | `MMPlan`, which reads the rules, the prefs and watching-since through `MMMustKeep`, the mode, the idle minutes and the day of watching. The mode's plan after a review reads the prepared plan too. Protect writes the rules file on the act queue. |
| WorkForest | `MMPlan`, the keeps, the protect list, Recently Removed from the undo log and the day of watching. The mode's plan after a review reads the prepared plan. Keep and Protect write their files on the act queue. |
| Noo-Noo | The mode and the day of watching. |
| MinMacs | The mode and the day of watching, for the header and the summary. |
| Insomnia | The first look before Insomnia's first pass. After that pass the menu reads Insomnia's own state, as before. |

**Hang detection.** `Sources/Shell/MMWatchdog.h`. Two run loop observers on main mark where each pass starts and ends. A thread of its own sleeps until a pass starts, then wakes once at start plus 50 ms. If the same pass still runs, it reads main's run state, suspends main, walks its frame pointers, resumes it, and waits for the pass to end. Each stall goes to NSLog, to `stalls.log` in the support folder as a JSON line, and to `MMWatchdogStalls()`. A stall says how long the pass took, how much CPU main used in it, whether main was waiting or running at the 50 ms mark, and main's stack at that mark. It is on in a debug build, `DEBUG=1 ./build.sh`, which defines `MM_DEBUG`, and wherever `MINMACS_WATCHDOG=1` is set. `MMMain` starts it then. When main sleeps, the watchdog thread sleeps too.

**Startup.** An expert whose icon was hidden at the last run gets no status item, no menu and no per-snapshot update until its field appears or Settings shows it. On a first launch every item is made, and an expert whose field is empty hides its icon at the first snapshot, as DESIGN.md "First launch" asks. On the next launch that expert waits. `MMStartupTimes()` gives the marks in ms since `MMStartupBegin`, which `MMMain` calls first.

## How it is measured

- `bench menus --iterations 200` builds a new fixture snapshot of a new generation for each turn, on a queue of its own, and runs the prepare step there. Then main times `MMShellMenu`, which is what `menuNeedsUpdate:` of the status item's menu runs. A hover is the card submenu's `menuNeedsUpdate:`, then the card's layout and its drawing into a bitmap.
- Every expert has a fixture now: LocoHost 12 servers, MinMacs 20 apps and 2 agents, WorkForest 16 worktrees in 2 repos, Noo-Noo 12 clutter items, Insomnia 2 agents.
- `bench hangs --rounds 10` starts Core with every built-in expert, every mode Idle, and the watchdog at 50 ms. Each menu open and each card hover runs in a pass of main of its own, 3 ms after the one before: on a new fixture snapshot, on Core's live snapshot, and the One Icon menu.
- `bench startup` runs `MMShellStartHeadless`: the launch the app runs after its instance check, without NSStatusItem and without NSApp's run loop. Each item makes its icon image and label, and nothing in the menu bar. It runs twice in one `MINMACS_HOME`, a first launch and then a later one.

## Menu open and card hover

200 builds each, wall ms on main. Both runs on the same fixtures, one after the other, at load averages of 30 to 41. "Before" is main at f04a47b, where menu open built every row's card. "Before" had no fixture for WorkForest, Noo-Noo and Insomnia, so those three had no rows.

| Expert | Rows | Menu open p95 before | Menu open median after | Menu open p95 after | Card hover median after | Card hover p95 after |
|---|---|---|---|---|---|---|
| LocoHost | 12 | 37.02 | 1.32 | 1.52 | 6.86 | 7.65 |
| MinMacs | 14 | 26.09 | 1.64 | 1.88 | 5.11 | 6.11 |
| WorkForest | 14 | 1.47, no rows | 1.35 | 1.62 | 5.95 | 7.29 |
| Noo-Noo | 11 | 1.01, no rows | 1.39 | 1.74 | 3.99 | 6.15 |
| Insomnia | 1 | 0.87, no rows | 0.91 | 1.04 | 5.65 | 6.22 |
| One Icon, every expert | | 15.61 | 2.94 | 3.28 | | |

Menu open is under 30 ms at p95 for every expert, and card hover under 16 ms. The `menus` run also shows:
- No card was built while a menu opened, and every hover built its card.
- After every card is hovered, each expert's menu holds the same items, titles and card sizes as the menu built with every card up front.
- Main ran no log query and read no keeps file while the menus opened and the cards were built.

**What the graph queue does now.** The prepare step, from the same `menus` run, at the median: LocoHost 0.73 ms, MinMacs 0.28 ms, Noo-Noo 0.28 ms, Insomnia 0.07 ms. WorkForest took 18.0 ms. That figure is the bench's alone. The fixture's findings come from a stand-in expert, so `MMMustKeep` reads each worktree again from the fixture facts. In the app, WorkForest made the findings from those same facts, and it reads them from each finding. On this Mac's real process table with an empty `MINMACS_HOME`, `bench idle --tick-runs 10` timed the prepare step at 1.48 ms of CPU a tick at the median. In the app, main did this work on every snapshot before, through `badgeFor:` and `accessibilityStateFor:`.

## Main never waits

`tools/bench/run.sh 60 10 200`, from 23:50 UTC on 2026-10-27, at load averages of 17 to 20.

- The watchdog caught the 120 ms stall made on purpose, as "waits", in `MMBenchStallOnPurpose`.
- Then 110 menu opens, 50 of them on Core's live snapshot, and 900 card hovers ran in 14180 passes of main. No pass took over 50 ms.

## Startup

Same run, headless, in ms from where `MMMain` starts.

| Launch | Core started | Items made | First snapshot | Every summary | Made at launch | Left for later |
|---|---|---|---|---|---|---|
| First | 3.99 | 15.16 | 90.55 | 116.40 | MinMacs, LocoHost, WorkForest, Noo-Noo, Insomnia | none |
| Later | 2.62 | 9.52 | 80.14 | 80.47 | MinMacs, LocoHost | WorkForest, Noo-Noo, Insomnia |

In that empty `MINMACS_HOME`, WorkForest, Noo-Noo and Insomnia had empty fields, so the later launch left them for later. The items are made within 300 ms and every summary within 5 seconds on both launches.

**Not measured here.** The bench never launches the app, so these numbers leave out what happens before `MMMain` and around it: dyld, `NSApplication`'s launch until `applicationDidFinishLaunching:`, and the status bar's own cost for each `NSStatusItem`. The headless items make the icon image and the label, which is the work the shell does for each item. The first snapshot waits on Core's first Senses pass and rebuild.

## The gate

`tools/bench/budgets.json` gains three budgets that `gate.py` reads from the startup and watchdog runs, and skips when a run has none:

| Budget | Phase 6 | Ceiling | This run |
|---|---|---|---|
| Menu open at p95, worst expert | 30 ms | 60 ms | 1.78 ms, MinMacs |
| Card hover at p95, worst expert | 16 ms | 32 ms | 7.65 ms, LocoHost |
| Icons after launch, headless | 300 ms | 300 ms | 15.16 ms, first launch |
| Every summary after launch, headless | 5000 ms | 5000 ms | 116.40 ms, first launch |
| Main-thread stalls over 50 ms | 0 | 0 | 0 |

`test/bench.sh` checks each of these, every linked expert's rows and cards, the deferred items of the later launch, and the watchdog's own catch.

## Rerun

```sh
tools/bench/run.sh 60 10 200          # one minute of idle, then menus, startup twice, the watchdog run and the gate
./test.sh bench                       # the short run and the gate
DEBUG=1 BUILD_DIR=build/debug ./build.sh   # a build whose main-thread watchdog is on
```
