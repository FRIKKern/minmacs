# Bench

Issues #23, #51, #52, #53 and #55. docs/2.0/MEASUREMENTS.md has the method and the numbers of #23 and #51, and docs/2.0/BENCH.md those of the idle tick, the menus, startup and the watchdog.

| File | What it does |
|---|---|
| `bench.m` | `idle`, `menus`, `hangs`, `startup` and `apps`. Each prints one JSON object. |
| `build.sh` | Builds `bench` from every `.m` under `Sources` except `main.m`, at -O2, eight files at a time. |
| `run.sh` | A full run: idle with the old apps over the same window, menus, startup twice, the watchdog run, the gate and `report.md`. |
| `gate.py` | Checks a run against `budgets.json`: ok, over, FAIL or skip per budget. |
| `budgets.json` | The phase 6 budgets of PLAN.md section 9, and today's ceilings. |
| `report.py` | The Markdown tables of one run. |

The bench refuses to run unless `MINMACS_HOME`, `MINMACS_CLAUDE`, `MINMACS_CODEX`, `MINMACS_CMUX` and `MINMACS_TMUX` are set. `run.sh` and `test/bench.sh` set them to a fresh folder and `/usr/bin/false`. It sets every mode to Idle, reads the old apps with `proc_pid_rusage` and `ps`, and never signals a process.

- `menus` opens each expert's menu through `MMShellMenu`, the app's own path, from a fixture snapshot that the graph queue's prepare step already ran on. Then it hovers each card through its submenu's delegate and draws it.
- `hangs` starts Core and the main-thread watchdog, then opens every expert's menu and hovers every card, each in a pass of main of its own, on fixture snapshots and on Core's live one. It first makes a 120 ms stall on purpose and checks the watchdog names `MMBenchStallOnPurpose` in its stack.
- `startup` runs the app's launch with `MMShellStartHeadless`: no NSStatusItem and no NSApp run loop. Run it twice in one `MINMACS_HOME` for a first and a later launch.

Every expert has a menu fixture in `FixtureSource`. A new expert with none gets the shared fixture facts in `FixtureFacts`. Add a fixture there when that gives it no rows, since `test/bench.sh` wants rows and cards from every linked expert.

Issue #52 added to `bench idle`: the whole process's CPU from one sample to the next (`inWindow.tickCPUms`), what each pass read and carried and its CPU by part (`senses`), each build's CPU by part and by expert, the skipped builds and the reused findings (`graph`), and the pushed signals by kind (`signals`). `run.sh` and `test/bench.sh` set `MINMACS_NO_BACKOFF=1`, so the pass keeps 5 seconds on battery and while the person is away. `MM_BENCH_BACKOFF=1` lets `run.sh` back off as the app does.
