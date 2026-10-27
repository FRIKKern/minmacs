# Insomnia

Keeping the Mac awake while an agent works, and letting it sleep when nothing does. Issue #31. Ported from Insomnia's one `main.m`. The expert reads agents and sessions from the snapshot and power, lid, heat and network from `MMPower`. It holds the Mac awake through Core's `MMAwake` and writes the lid override through Core's `MMLidOverride` inside `MMRunAction`. It never samples, scans or runs a process itself.

| File | What it holds | Ported from |
|---|---|---|
| `MMInsomnia.h` | The prefs, guard clocks, input, state, view and the expert | |
| `MMINGuards.m` | Prefs, the guard clocks, the pause reason, the input from facts and `MMINDecide`. Pure | the pref getters, `-syncLid`, `-pauseReason`, `-evaluateAgents` |
| `MMINMenu.m` | The data classes, the menu, the cards and the accessibility state as specs. Pure, so `tools/render.m` links it | `-showMenu`, `-agentsLine`, `-refreshIcon` |
| `MMInsomniaExpert.m` | Findings, the pass on `no.guerrilla.minmacs.insomnia.power`, the lid and setting actions, the menu glue and `openURL:` | `-apply:`, `-reconcile`, `-syncLid`, `-enableLid:`, the URL commands |
| `MMINCLI.m` | The verbs `awake` and `insomnia` | the URL scheme |

## What it decides

- **Decision 4.** Awake While Agents Work starts on and Keep Mac Awake starts off. The Mac stays awake only while an agent works, from the first launch.
- **One pair per pid.** Each working agent gets its own `PreventUserIdleSystemSleep` and `PreventSystemSleep` pair, through `+[MMAwake holdFor:reason:]`. The pair ends on that pid's exit, by kqueue, before the next pass.
- **The quiet period.** An agent that stops keeps its pair for `insomnia.agents.quietMinutes`, 10 by default, unless it exits first. Waiting on the person and Claude Code's `shell` status count as stopped. Turning the mode off forgets when each agent last worked.
- **Manual wins.** With Keep Mac Awake on, one pair for MinMacs itself holds the Mac awake, and no agent needs its own.
- **Low battery.** On battery at or below the battery guard, 20% by default, agent holds end. Keep Mac Awake stays, since the person asked for it.
- **Holds a script asks for.** `minmacs insomnia hold <pid>` and `-[MMGraph holdAwake:pid:]` hold the Mac awake until that process exits.
- **The lid override.** Live while something holds the Mac awake, lid mode is on, the Mac has a battery and no guard pauses it. The guards are Insomnia's, unchanged, and pause only the override, only on battery: the battery at or below 20%, unplugged past 2 hours, offline past 15 minutes, and hot with the lid closed. The heat pause holds until the lid opens or the charger returns. The unplugged and offline clocks and the heat hold live in the prefs, so they survive a relaunch.
- **Ownership.** The expert clears only an override it set or one its lid mode owns, never one another tool set. While the standalone Insomnia.app runs, it writes nothing and the lid card says so. A stale override MinMacs set is cleared on the first pass after launch, and at quit the clear is started without waiting.
- **Screen off.** When the lid closes with the override live, the display sleeps once, through `pmset displaysleepnow`. Opening the lid wakes it.
- **Failures.** A refused write leaves the state as IOKit says, shows the reason on the lid row and waits five minutes before the same write again.

## The lid commands

`MMLidOverride` in `Core/Act/MMLid.m` runs Insomnia's commands word for word: `sudo -n /usr/bin/pmset -a disablesleep 1` and `0`, `sudo -n -l` to see if the rule is in place, and `pmset displaysleepnow`. The rule is Insomnia's `/etc/sudoers.d/insomnia`, so a Mac that has it keeps it. The first time lid mode is turned on without the rule, one administrator prompt writes it, through `osascript` with Insomnia's script, and `visudo -cf` checks it. Every command runs off main with a time limit. The override itself is read from IOKit, `IOPMrootDomain` `SleepDisabled`, never from `pmset -g`.

With `MINMACS_HOME` set, the commands run only through `MINMACS_INSOMNIA_CMD`, a fake that gets the whole command line, and refuse without it. A real run ignores that variable. There are no debug prefs: tests use the fake power source of `MMPowerSource`, which exists only under `MM_TESTS`, and the expert's `inputFrom` and `clock` blocks.

## Every change has a record

Each lid write and each change of a setting runs through `MMRunAction`, so it is checked fresh and leaves an undo record of kind `lid` or `setting`. A lid write is checked on fresh power facts: one that would turn the override on while a guard pauses it is kept. Automatic writes have `by` set to `guard`. Neither kind is restored by Undo, since a lid write follows the state and a setting is changed back by setting it again.

## Prefs

| Key | Default | Menu or verb |
|---|---|---|
| `insomnia.awake` | off | Keep Mac Awake, `insomnia on` |
| `insomnia.agents` | on | More, `insomnia agents on` |
| `insomnia.agents.quietMinutes` | 10 | `insomnia set quiet 20` |
| `insomnia.lid` | off | Keep Awake With Lid Closed…, `insomnia lid on` |
| `insomnia.lid.screenOff` | on | the lid card, `insomnia screen off` |
| `insomnia.lid.thermalGuard` | on | the lid card, `insomnia heat off` |
| `insomnia.lid.minBattery` | 20 | `insomnia set battery 30` |
| `insomnia.lid.graceMinutes` | 120 | `insomnia set unplugged never` |
| `insomnia.lid.offlineMinutes` | 15 | `insomnia set offline 30` |

## Verbs

- `awake [--json]` reads the app's last pass, or decides on a cold snapshot when no app runs.
- `insomnia on|off|toggle`, `insomnia agents|lid|screen|heat on|off`, `insomnia set battery|unplugged|offline|quiet <n|never>` and `insomnia hold <pid> [reason]` change things, so they run in the app. `--dry-run` says what they would do.
- `minmacs://insomnia/on`, `off`, `toggle`, `agents-on`, `agents-off`, `lid-on` and `lid-off` reach `openURL:`. The binary run as `insomnia` runs these verbs.

## Checks

`./test.sh insomnia` builds `test/insomnia/tool.m` with Core, the kit, the CLI and the expert under `-DMM_TESTS` and runs `test/insomnia/matrix.txt`. That is Insomnia's guard matrix from its `test.sh`, line by line, plus the 2.0 checks above. Power facts come from a fake power source, the clock from the tool, the lid commands from `test/insomnia/fakecmd.sh`, and the workers from `test/insomnia/sleeper.c` under a name unique to the run. The assertions are real, held by the tool for its own fixture pids for seconds, as `caffeinate` holds them. The section also checks the verbs in the built app, that the release binary has no debug prefs and no fake power source, and the render of the menu and cards from `tools/render.m`.

## Left open

- The guard numbers have no menu: the CLI sets them. They belong in a per-expert pane of the Settings window, which the shell owns.
- `insomnia://` is not in Info.plist yet. While the standalone Insomnia.app is installed it owns that scheme. `minmacs://insomnia/<command>` works now. Phase 5 adds the scheme with the migration.
- The migration of Insomnia's `no.guerrilla.insomnia` prefs, its hidden icon and a still-live override is phase 5's, PLAN.md section 8.
- C8's offer to turn keep-awake off on battery is not in the menu.
- No notification says that agent holds ended on low battery.
- The administrator prompt comes from `osascript`, so macOS names osascript in it. Insomnia ran the same script in its own process. A lid-mode LaunchDaemon waits for a notarized build, B8.
