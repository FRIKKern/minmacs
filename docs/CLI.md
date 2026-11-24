# CLI

This page is generated from `minmacs help --json` by `test/docs/clidoc.py`. `./test.sh docs` fails when it does not match the built binary. To write it again after a verb changes:

```sh
python3 -I test/docs/clidoc.py build/MinMacs.app/Contents/MacOS/MinMacs > docs/CLI.md
```

The app binary is also the command line tool. `install.sh` and `build.sh --install` link it as `~/.local/bin/minmacs`. When the app runs, the CLI hands each verb to it over `core.sock` in the support folder. When no app answers, it builds a snapshot itself and answers from that.

## Nobody at the terminal

No verb ever waits for a person, decision D3. When stdin is not a TTY, or `MINMACS_UNATTENDED=1` is set, or `minmacs unattended on` was run, the CLI reads nothing from stdin. A change that keeps a way back, such as a worktree removal or a plain stop that Undo starts again, goes ahead as `--yes` would. One that does not is not done without `--yes`: `locohost close --force`, a SIGKILL, is refused with a message that names what to add and exit 2, and `investigate` only shows what a run would cost. `MINMACS_UNATTENDED=0` says a person is here: then nothing is read without a TTY either, and a verb that would ask refuses instead.

## Exit codes

- **0.** OK.
- **1.** The verb ran and something did not work, or nothing matched.
- **2.** An unknown verb, a missing argument or a bad value.
- **3.** The verb changes things, and no MinMacs app answers on core.sock.

## minmacs

### MinMacs

#### `apps`

```
apps [list | quit <bundle-id|pid> [--force] | trim [<bundle-id>] | keep|close|unsorted <bundle-id> | serving on|off <bundle-id> | classify <url>] [--json] [--dry-run]
```

Flags: `--force`, `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `status`

What each expert sees, as its menu header says it.

```
status [--json]
```

Flags: `--json`.

#### `net`

The whole Mac's network: the route out, bytes and rates, and the home volume's size.

```
net [--json]
```

Flags: `--json`.

#### `work`

Each workstream, or Wrap Up of a finished one.

```
work [path] [--here] [--json] | work wrap-up <id> [--dry-run] [--json]
```

Flags: `--here`, `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `review`

The last review, a new one with --now, or with --model the model reviews ask: auto, opus, sol, sonnet or haiku.

```
review [expert] [--now] [--model <model>] [--json]
```

Flags: `--now`, `--model`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `investigate`

Look deeper into one, after you confirm its cost.

```
investigate <finding|workstream|path> [question] [--yes] [--json]
```

Flags: `--yes`, `--json`.

#### `tidy`

What each mode would act on, and act on it.

```
tidy [expert] [--dry-run] [--mode <mode>] [--json]
```

Flags: `--dry-run`, `--mode`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `where`

The terminal tab, pane or app it runs in.

```
where <pid> | where --port <port> [--go] [--json]
```

Flags: `--port`, `--go`, `--json`.

#### `restore`

Undo the last run, or one record; a thing deleted at once cannot be brought back.

```
restore [rid] [--list] [--expert <expert>] [--limit <n>] [--dry-run] [--json]
```

Flags: `--list`, `--expert`, `--limit`, `--dry-run`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `history`

The last hour in memory: Mac, disk, agent and server rings, one value a minute.

```
history [--json]
```

Flags: `--json`.

#### `gains`

What came back: memory and disk by day, by kind and by who did it.

```
gains [--days <n>] [--json]
```

Flags: `--days`, `--json`.

#### `performance`

The Performance tab: memory and disk by holder, the fixes ranked, and what came back.

```
performance [--json]
```

Flags: `--json`.

#### `mode`

Show or set an expert's mode.

```
mode <expert> [idle|proactive|eager] [--json]
```

Flags: `--json`.

#### `removal`

Show what happens to a thing MinMacs removes, which always keeps a way back; with --waiting, what MinMacs could not delete or put back, and delete one or put it back; --close ends a Wrap Up whose state cannot be read, once nothing of it waits.

```
removal [--json] | removal --waiting [--delete <id> | --put-back <id> [--to <path>] | --close <wrap-up>] [--dry-run] [--json]
```

Flags: `--json`, `--waiting`, `--delete`, `--put-back`, `--to`, `--close`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `self`

What the running MinMacs app costs this Mac: its CPU now and since launch, the tools it ran, memory, disk writes and wakeups, against its budgets.

```
self [--window <seconds>] [--json]
```

Flags: `--window`, `--json`.

#### `device`

What this Mac can take on now, for a remote orchestrator: identity, power, lid and display, what keeps it awake, load, agents, quiet holds and MinMacs's own cost.

```
device [--json]
```

Flags: `--json`.

`device` is the one read a remote orchestrator, such as BarkBot, makes to choose a Mac for a task now. It reads what Core already holds, the last Senses pass and the graph in the app, or one sample when no app runs. On the verb itself it reads the hardware by sysctl, the displays from CoreGraphics, the display-sleep setting from IOKit, memory by `host_statistics`, swap by `vm.swapusage` and MinMacs's own accounting by one `proc_pid_rusage`. It runs one process, `sudo -n -l` through `MMLidOverride`, which never prompts, for `provision.lidRuleInstalled`, and adds nothing to any tick. It writes nothing.

`device --json` prints one object. `schema` is 1, and a field is added, never changed in meaning, while it stays 1.

| Field | What it holds |
|---|---|
| `schema`, `at`, `inApp` | The shape's version, the time in seconds since 1970, and whether the running app answered |
| `identity.computerName`, `identity.localHostName` | The Mac's name in Sharing, and its Bonjour name |
| `identity.model`, `identity.chip` | `hw.model`, such as `Mac17,4`, and the chip, such as `Apple M5` |
| `identity.cores` | `physical`, `logical`, `performance` and `efficiency` cores, null where the kernel has no such level |
| `identity.memoryBytes` | The memory size |
| `identity.macOS` | `version`, such as `26.6.0`, and `build`, such as `25G72` |
| `identity.minmacs` | MinMacs's `version` and `build`, the bundle's `CFBundleVersion` |
| `power.onAC`, `power.batteryPercent` | On the charger, and the battery's percent, null without a battery |
| `power.lowPowerMode`, `power.thermal` | Low Power Mode, and the thermal state: `nominal`, `fair`, `serious` or `critical` |
| `power.online` | A default route exists |
| `lid.closed` | The lid is shut, from IOKit's `AppleClamshellState` |
| `lid.insomniaLidMode`, `lid.insomniaLidLive` | Insomnia's lid mode is on, and its override is set now, from IOKit's `SleepDisabled` |
| `lid.screenOff`, `lid.keepsScreenLit` | The pref `insomnia.lid.screenOff`, and lid mode on with it off, so the panel stays lit with the lid shut |
| `display.active` | `external` when a display that is not built in is awake, else `builtin` when the built-in panel is lit, else `asleep` when a display is there but asleep, else `none`; `unknown` when CoreGraphics could not be asked |
| `display.canCaptureScreen` | True only when some display is active and awake, so screenshots and recordings show something. The built-in panel counts while the lid is open, or while Insomnia's lid override is live with `insomnia.lid.screenOff` off. Display sleep still turns it off |
| `display.known`, `display.builtinLit`, `display.externalAwake` | The parts `canCaptureScreen` is made of |
| `display.displays` | Each online display: `id`, `builtin`, `asleep`, `active`, `main`, `mirrored`, `vendor`, `model`, `width` and `height` in pixels. A virtual display or a dummy plug shows as one that is not built in |
| `awake.held` | Something of MinMacs holds the Mac awake now: Keep Mac Awake, an agent, a hold or a quiet hold |
| `awake.manual`, `awake.manualHeld` | The pref Keep Mac Awake, and whether the app holds it now |
| `awake.agentsMode` | The pref Awake While Agents Work |
| `awake.agents`, `awake.holds` | `{pid, reason}` of each agent and each `insomnia hold` the app holds the Mac awake for. Empty with no app |
| `awake.quiet` | `{pid, reason, awake}` of each quiet hold |
| `awake.others` | `{pid, process, type, name}` of every other process's sleep assertion, at most 20, from the last Senses pass |
| `awake.displaySleepMinutes` | The display-sleep setting of the power source in use, 0 for never |
| `load.memoryPressure` | `normal`, `warn` or `critical`, the kernel's level |
| `load.memoryUsedBytes`, `load.memoryTotalBytes`, `load.swapUsedBytes` | Memory used as Activity Monitor counts it, the memory size and the swap in use |
| `load.cpuPercent` | The whole Mac's CPU this minute, 100 for every core busy, from the app's last hour. Null with no app |
| `load.loadAverage` | The 1, 5 and 15 minute load averages |
| `load.diskFreeBytes`, `load.diskTotalBytes` | The home volume |
| `agents.working`, `agents.total`, `agents.workingNames` | How many agents work, how many run, and the names of those that work |
| `agents.list` | Each agent: `pid`, `name`, `harness`, `state` (`working`, `waiting`, `idle` or `unknown`), `working`, and the TCP `ports` its process tree listens on |
| `quiet.active`, `quiet.holders` | Whether a quiet hold is active, and each one as `quiet --json` gives it |
| `minmacs` | What the app costs, since its launch: `pid`, `runningSeconds`, `sinceLaunch.cpuPercent` and `sinceLaunch.idleWakeupsPerSecond`, `memory.footprintBytes` and `memory.peakBytes`, the `budgets` and the budgets it is `over`. In the app it reads itself; from the CLI it reads the pid the app gives on core.sock. Null with no app |
| `provision` | D3: what this Mac still needs a person for once, read without asking anything. `unattended`; `lidRuleInstalled`, whether the sudoers rule lid mode needs is in place; `notificationsAuthorized`, null outside the app, which alone can read it; `loginItem`, `enabled`, `requiresApproval`, `notRegistered` or `notFound`, and `loginItemApproved`, null where it cannot be read; `needsPerson`, the names of what is missing: `lidRule`, `notifications`, `loginItem` |

An example of the shape, for a Mac with the lid shut, Insomnia's lid mode live, the screen left on and a quiet hold for a screen recording. `test/device.sh` checks these cases on fixture power facts and displays:

```json
{
  "schema": 1, "at": 1795506021, "inApp": true,
  "identity": {"computerName": "Studio Mac", "localHostName": "Studio-Mac", "model": "Mac17,4", "chip": "Apple M5",
               "cores": {"physical": 10, "logical": 10, "performance": 4, "efficiency": 6}, "memoryBytes": 17179869184,
               "macOS": {"version": "26.6.0", "build": "25G72"}, "minmacs": {"version": "2.0.0", "build": "20000"}},
  "power": {"onAC": true, "batteryPercent": 80, "lowPowerMode": false, "thermal": "nominal", "online": true},
  "lid": {"closed": true, "insomniaLidMode": true, "insomniaLidLive": true, "screenOff": false, "keepsScreenLit": true},
  "display": {"active": "builtin", "canCaptureScreen": true, "known": true, "builtinLit": true, "externalAwake": false,
              "displays": [{"id": 1, "builtin": true, "asleep": false, "active": true, "main": true, "mirrored": false,
                            "vendor": 1552, "model": 41060, "width": 1710, "height": 1107}]},
  "awake": {"held": true, "manual": false, "manualHeld": false, "agentsMode": true, "agents": [{"pid": 2767, "reason": "Claude Code works"}],
            "holds": [], "quiet": [{"pid": 4989, "reason": "screen recording", "awake": true}], "others": [], "displaySleepMinutes": 10},
  "load": {"memoryPressure": "normal", "memoryUsedBytes": 8712962048, "memoryTotalBytes": 17179869184, "swapUsedBytes": 0,
           "cpuPercent": 7.5, "loadAverage": [2.71, 2.32, 2.22], "diskFreeBytes": 926834085888, "diskTotalBytes": 994610155520},
  "agents": {"working": 1, "total": 1, "workingNames": ["Claude Code"],
             "list": [{"pid": 2767, "name": "Claude Code", "harness": "claude-code", "state": "working", "working": true, "ports": [49210]}]},
  "quiet": {"active": true, "holders": [{"pid": 4989, "reason": "screen recording", "since": 1795506000, "by": "cli", "rid": "25537f7a3643", "awake": true}]},
  "minmacs": {"pid": 812, "runningSeconds": 86400, "sinceLaunch": {"cpuPercent": 0.21, "idleWakeupsPerSecond": 0.6},
              "memory": {"footprintBytes": 41943040, "peakBytes": 62914560}, "budgets": {"cpuPercent": 0.3, "idleWakeupsPerSecond": 1}, "over": []},
  "provision": {"unattended": true, "lidRuleInstalled": true, "notificationsAuthorized": true, "loginItem": "enabled", "loginItemApproved": true, "needsPerson": []}
}
```

#### `quiet`

Peace for a task such as a screen recording: while that process runs no expert acts on its own, and the Mac and display stay awake.

```
quiet [--json] | quiet hold <pid> [--reason <text>] | quiet release <pid> [--dry-run]
```

Flags: `--json`, `--reason`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

A quiet hold gives one task peace while its process runs, such as a screen recording or a run of screenshots. While a held process lives, no expert acts on its own: no mode quits an app, trims tabs, stops a server, removes a worktree or cleans up. The check sits in `MMPlan` and `MMRunAction`, so every expert obeys it, in the app and in a cold CLI alike. What the person presses, Fix Everything included, still runs, and Fix Everything's end note says a quiet hold is active. The Mac and its display stay awake: the app takes `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep` for it, and Insomnia's screen-off sleeps no display. Nothing is ever signaled.

- `quiet hold <pid> [--reason <text>]` checks the pid by its start time, writes an undo record of kind `quiet` through `MMRunAction` and holds until that process exits. It runs in the app, which keeps the assertions. A second hold of the same process keeps the first. Pid 1 and MinMacs itself are never held.
- `quiet release <pid>` ends every quiet hold of that pid. It may run with no app, since the holds live in `quiet/holds.json` in the support folder, which every MinMacs process reads.
- The hold also ends when the process exits, seen by kqueue. A hold whose process ends while no MinMacs runs is ended at the app's next start, and one whose process still runs is held awake again then.
- Every hold and its end is in `minmacs log`: "Quiet for screen recording, pid 4123, 12:03 to 12:41.", and while it lasts "Quiet for screen recording, pid 4123, since 12:03. It lasts while that process runs."

`quiet --json` prints `{active, holders, kept}`. Each holder is `{pid, reason, since, by, rid, awake}`: `since` in seconds since 1970, `by` who asked, `rid` its undo record, and `awake` whether the MinMacs process that took it still runs and holds the Mac and display awake. `kept` is what this process holds assertions for, in the app, or null. `device --json` gives the same holders as `quiet`.

#### `unattended`

Show or set whether this Mac runs with nobody at it: then nothing waits for a person, no confirm is shown and the welcome is skipped; MINMACS_UNATTENDED=1 or 0 decides over it for one process.

```
unattended [on|off] [--json]
```

Flags: `--json`.

`on` is for a Mac that runs with nobody at it, driven by an agent such as BarkBot. Then no confirm is shown, even for a press in the window or a menu, a failure is a notice in the log with at most one notification, and the welcome is skipped, at once when the app runs and else at its next launch: Open at login is turned on and the log says the welcome was skipped. The pref is `core.unattended`, and each change is a row of the log by `cli`.

`MINMACS_UNATTENDED=1` in a process's environment makes that process unattended whatever the pref holds, and `MINMACS_UNATTENDED=0` makes it attended. `--json` prints `{"unattended", "pref", "env"}`: what holds now, the pref, and the environment's word or null.

The one prompt MinMacs cannot take away is macOS's own: the administrator password for the lid rule, the first time lid mode is turned on, and only on that explicit turn with a person here, such as `insomnia lid on`. Unattended, lid on without the rule is refused at once with a notice. A fleet Mac takes it once at setup, and `device --json` names what is still missing in `provision.needsPerson`. A link that acts, such as `workforest://clean-up`, asks a person who is here first, and runs unasked only while unattended.

#### `version`

The version.

```
version [--json]
```

Flags: `--json`.

#### `help`

Every verb.

```
help [--json]
```

Flags: `--json`.

#### `window`

What the menu window shows: asks, the two sides, the ring, the fixes and Settings.

```
window [--json]
```

Flags: `--json`.

#### `log`

What MinMacs did and decided, and each setting that changed, newest first, 50 entries unless --limit says.

```
log [--limit <n>] [--json]
```

Flags: `--limit`, `--json`.

### LocoHost

#### `hosts`

Every localhost, or what one port is, how it runs and why.

```
hosts [port] [--json]
```

Flags: `--json`.

### WorkForest

#### `trees`

Every git worktree, whether it is merged, and what removing it frees.

```
trees [list|explain <path>|review|plan|auto|clean-up|remove <path>|restore <id|path>|removed|keep <path>|protect <path>|prune <path>|rules|prs on|off] [--all] [--mode <mode>] [--model <model>] [--path <path>] [--days <n>] [--off] [--fresh] [--review] [--merged] [--yes] [--dry-run] [--json]
```

Flags: `--all`, `--mode`, `--model`, `--path`, `--days`, `--off`, `--fresh`, `--review`, `--merged`, `--yes`, `--dry-run`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `worktrees`

Every git worktree, whether it is merged, and what removing it frees.

```
worktrees [list|explain <path>|review|plan|auto|clean-up|remove <path>|restore <id|path>|removed|keep <path>|protect <path>|prune <path>|rules|prs on|off] [--all] [--mode <mode>] [--model <model>] [--path <path>] [--days <n>] [--off] [--fresh] [--review] [--merged] [--yes] [--dry-run] [--json]
```

Flags: `--all`, `--mode`, `--model`, `--path`, `--days`, `--off`, `--fresh`, `--review`, `--merged`, `--yes`, `--dry-run`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

### Noo-Noo

#### `clutter`

```
clutter [list | show <id|path> | trends | check <path> | scan] [--json] [--dry-run]
```

Flags: `--json`, `--dry-run`.

#### `clean`

Removes clutter to the Trash with undo, or with --command runs the row's own cleanup, which cannot be undone.

```
clean <id|path|row> ... [--command] | --finished | --leftovers | --undo [rid] [--json] [--dry-run]
```

Flags: `--command`, `--finished`, `--leftovers`, `--undo`, `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

### Insomnia

#### `awake`

```
awake [--json]
```

Flags: `--json`.

## The old names

The binary looks at the name it was started under. A link named `locohost`, `workforest`, `noo-noo` or `insomnia` answers that expert's verbs first, then the verbs of `minmacs`. Below is what differs from `minmacs` under each name.

### locohost

#### `where`

The cmux tab, tmux pane, terminal tab or app a server runs in.

```
where <port> [--go] [--json]
```

Flags: `--go`, `--json`.

#### `review`

Ask the model which localhosts are in use.

```
review [--mode name] [--model name] [--port p] [--json]
```

Flags: `--mode`, `--model`, `--port`, `--json`.

#### `restore`

List the servers LocoHost stopped, or start one again.

```
restore [record id|port] [--json]
```

Flags: `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `list`

Every localhost, its cost, state and who started it.

```
locohost list [--all] [--json]
```

Flags: `--all`, `--json`.

#### `who`

The process on a port, its folder, branch, command and clients.

```
locohost who <port> [--json]
```

Flags: `--json`.

#### `explain`

What it is, how it runs, why it is there and what it wastes.

```
locohost explain <port> [--json]
```

Flags: `--json`.

#### `ready`

Wait until the port answers; exit 0 ready, 1 timed out.

```
locohost ready <port> [--http] [--timeout s]
```

Flags: `--http`, `--timeout`.

#### `free`

The first free port at or above port, 3000 by default.

```
locohost free [port]
```

#### `waste`

What each dev server burned since it was last used.

```
locohost waste [--json]
```

Flags: `--json`.

#### `summary`

The review's words and what the mode would do.

```
locohost summary [--mode name] [--json]
```

Flags: `--mode`, `--json`.

#### `auto`

One round of the mode.

```
locohost auto [--mode name] [--port p] [--dry-run] [--review] [--force] [--json]
```

Flags: `--mode`, `--port`, `--dry-run`, `--review`, `--force`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `mode`

Show or set the mode.

```
locohost mode [idle|proactive|eager]
```

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `idle`

What Close Idle would stop right now.

```
locohost idle [--port p] [--json]
```

Flags: `--port`, `--json`.

#### `close-idle`

Stop every confirmed idle server.

```
locohost close-idle [--yes] [--force] [--port p] [--review]
```

Flags: `--yes`, `--force`, `--port`, `--review`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `close`

Stop one server, SIGTERM, then SIGKILL on a second request.

```
locohost close <port|pid> [--yes] [--force]
```

Flags: `--yes`, `--force`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `open`

Open it in the browser.

```
locohost open <port>
```

#### `stopped`

What LocoHost stopped, with the command to start each again.

```
locohost stopped [--json]
```

Flags: `--json`.

#### `restart`

Start the server LocoHost last stopped on that port again.

```
locohost restart <port>
```

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `keep`

No mode stops it for this many hours, 4 by default, 0 clears.

```
locohost keep <port> [hours]
```

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `rules`

Print the rules file path.

```
locohost rules
```

### workforest

Every verb is the same as under `minmacs`.

### noo-noo

Every verb is the same as under `minmacs`.

### insomnia

#### `insomnia`

```
insomnia on|off|toggle | agents on|off | lid on|off | screen on|off | heat on|off | set battery|unplugged|offline|quiet <minutes or percent|never> | hold <pid> [reason] [--json] [--dry-run]
```

Flags: `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

### Commands of the 1.x apps

An old command that is no verb under that name is rewritten to 2.0 words before it runs. Under an old name, the expert's own verb wins over the rewrite. Under `minmacs`, any 2.0 verb wins. `<arg>` is the old command's first argument. The rewrites are read from `MMLegacyWords` in `Sources/CLI/MMCLI.m`, and only the ones that apply are listed.

Under `minmacs`:

- `minmacs plan` becomes `minmacs tidy minmacs --dry-run`.
- `minmacs run` becomes `minmacs tidy minmacs`.
- `minmacs agents` becomes `minmacs work`.

Under `locohost`:

None apply. Every old command is a verb of its own under this name.

Under `workforest`:

- `workforest list` becomes `workforest trees list`.
- `workforest explain` becomes `workforest trees explain <arg>`.
- `workforest review` becomes `workforest trees review`.
- `workforest summary` becomes `workforest trees plan`.
- `workforest auto` becomes `workforest trees auto`.
- `workforest clean-up` becomes `workforest trees clean-up`.
- `workforest remove` becomes `workforest trees remove <arg>`.
- `workforest restore` becomes `workforest trees restore <arg>`.
- `workforest removed` becomes `workforest trees removed`.
- `workforest keep` becomes `workforest trees keep <arg>`.
- `workforest prune` becomes `workforest trees prune <arg>`.
- `workforest fetch` becomes `workforest trees fetch`.
- `workforest rules` becomes `workforest trees rules`.
- `workforest mode` becomes `workforest mode workforest <arg>`.
