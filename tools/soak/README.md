# Soak

Issue #56. docs/2.0/BENCH.md section Soak has the method, what passes, the numbers of the one-hour run, and how to start the 24-hour run and the week of real use.

| File | What it does |
|---|---|
| `soak.m` | `soak run`: Core headless with every built-in expert, every mode Idle, the watchdog on, and every menu and card opened on the live snapshot once a minute. `soak _walk` is Core's walker child. |
| `build.sh` | Builds `soak` from every `.m` under `Sources` except `main.m`, at -O2 with -g, then `procstat` and `agent`. |
| `run.sh` | The soak: fixture churn beside `soak`, a sample every hour by default, then the stop, the crash report search and `report.md`. |
| `procstat.c` | One read of one pid: footprint, CPU, threads and open fds, from `proc_pid_rusage` and `proc_pidinfo`. |
| `agent.c` | The fake agent. It calls `setsid` and ends by itself. |
| `report.py` | The report and the verdict of one run folder. |

`test/soak.sh` runs a 24-second soak and checks the report rules on a run made by hand.
