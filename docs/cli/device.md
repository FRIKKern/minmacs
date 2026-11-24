`device` is the one read a remote orchestrator, such as BarkBot, makes to choose a Mac for a task now. It reads what Core already holds, the last Senses pass and the graph in the app, or one sample when no app runs. On the verb itself it reads the hardware by sysctl, the displays from CoreGraphics, the display-sleep setting from IOKit, memory by `host_statistics`, swap by `vm.swapusage` and MinMacs's own accounting by one `proc_pid_rusage`. It runs no process and adds nothing to any tick. It writes nothing.

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
              "memory": {"footprintBytes": 41943040, "peakBytes": 62914560}, "budgets": {"cpuPercent": 0.3, "idleWakeupsPerSecond": 1}, "over": []}
}
```
