# Bench

Issues #23 and #51. docs/2.0/MEASUREMENTS.md has the method and the numbers.

| File | What it does |
|---|---|
| `bench.m` | `idle`, `menus` and `apps`. Each prints one JSON object. |
| `build.sh` | Builds `bench` from every `.m` under `Sources` except `main.m`, at -O2, eight files at a time. |
| `run.sh` | A full run: idle with the old apps over the same window, menus, the gate and `report.md`. |
| `gate.py` | Checks a run against `budgets.json`: ok, over, FAIL or skip per budget. |
| `budgets.json` | The phase 6 budgets of PLAN.md section 9, and today's ceilings. |
| `report.py` | The Markdown tables of one run. |

The bench refuses to run unless `MINMACS_HOME`, `MINMACS_CLAUDE`, `MINMACS_CODEX`, `MINMACS_CMUX` and `MINMACS_TMUX` are set. `run.sh` and `test/bench.sh` set them to a fresh folder and `/usr/bin/false`. It sets every mode to Idle, reads the old apps with `proc_pid_rusage` and `ps`, and never signals a process.

A new expert needs no change here. `bench menus` gives an expert with no fixture of its own the shared fixture facts in `FixtureFacts`. Add a fixture in `FixtureSource` when that gives it no rows.
