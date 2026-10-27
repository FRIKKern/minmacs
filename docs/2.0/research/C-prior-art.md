# Research C: prior art, what the best Mac tools get right

Track C of the MinMacs 2.0 research brief, GitHub issue FRIKKern/minmacs#3. Sources were read on 2026-10-27.

## Summary

I studied 26 tools in six groups: system monitors, cleaners, keep-awake apps, port managers, worktree tools and menu bar tools. The best of them share three habits. They check fresh right before they act. They mark what they own and touch only that. They show a plain reason next to each thing they offer to remove.

Most cleaners still delete permanently. DaisyDisk, kondo, Mole's `clean` and `purge`, and Noo-Noo today all do. Undo is rare. WorkForest's restore and Claude Code's "keep or remove" exit prompt come closest.

No tool links the five fields. No port manager knows whether the server's worktree is merged. No keep-awake app knows whether an agent is working. No cleaner knows whether a cache's project is finished. MinMacs 2.0's graph is new ground, and that is where it should spend its effort.

Price is not a moat. Free and open-source tools lead in every group. These include Stats, KeepingYouAwake, Amphetamine, Ice, npkill, kondo, Mole, LeftOpen and worktrunk.

## Method

- Web pages were read with WebFetch and WebSearch. Each claim links the page it came from.
- Our own code was read with `grep` on `~/Documents/GitHub/locohost`, `~/Documents/GitHub/workforest` and the clones of insomnia and noo-noo in the session scratchpad.
- `ls /Applications` on this Mac shows `cmux.app` and `Cursor.app` installed. None of the other studied apps are installed, so every app claim below comes from vendor or project pages, not from running the app.
- I could not read Conductor's archive behavior, CleanMyMac's store page (HTTP 403), or a full KeepingYouAwake settings reference. These gaps are listed under open questions.

## Comparison table

| Tool | Detects | Decides | Undoes | Presents | Charges |
|---|---|---|---|---|---|
| Stats | CPU, GPU, RAM, disk, network, battery, sensors, Bluetooth | Shows only, no actions | Nothing to undo | One menu bar item per module, popups, widgets | Free, MIT |
| iStat Menus 7 | CPU, GPU, RAM, disks, network, sensors, battery, weather and more | User rules, such as CPU over 60% for 10 seconds | Nothing to undo | One item per monitor, or a combined item | $11.99 single, $14.99 family, 14-day trial |
| Activity Monitor | CPU, memory pressure, energy, disk, network per process | Memory pressure colors; user picks what to quit | None | Window with tabs and columns | Built in |
| CleanMyMac | System junk, malware, large and old files, app leftovers | Vendor Safety Database of rules and exceptions | Not documented | App plus menu bar Menu with alerts | From $3.33 a month |
| DaisyDisk | Folder sizes, hidden space, snapshots | User only; system folders refused | 5 seconds to cancel, then permanent | Sunburst rings and a Collector | $9.99 once, five Macs |
| DevCleaner for Xcode | DerivedData, archives, device support, simulator logs, docs | Preselects old device support, keeps newest per OS | Not documented | Window with categories | GPL-3.0, tip jar; free (unverified) |
| npkill | `node_modules` and other targets | User picks; warns on app-owned folders | Not documented; guess: permanent | TUI with size and last change | Free, MIT |
| kondo | Build artifacts for 20+ project kinds | User picks; `--older 3M` filter | None: "rm -rf with a prompt" | CLI and GUI | Free, MIT |
| Mole | Caches, logs, app leftovers, project artifacts, installers | Protected paths, whitelist, skip when unsure | Trash for `uninstall`, `analyze`, `slim`; permanent for `clean`, `purge`, `installer`; an operation log | CLI, JSON, Raycast and Alfred launchers | Free, GPL-3.0; a paid Mac app |
| OnyX | System caches, databases, settings | User picks tasks | Not documented | Window | Free, donations |
| Amphetamine | Apps, displays, devices, power, Wi-Fi, VPN, CPU, idle, drives | User triggers | Ends sessions; ends on low battery | Menu bar item | Free, no in-app purchases |
| Lungo | Nothing; user starts it | Duration or until off | Turns off on battery if set | Menu bar item, URL scheme, Shortcuts | $4 once |
| KeepingYouAwake | Nothing; user starts it | Duration or until off | Deactivates below a battery level | Menu bar item, URL scheme | Free, MIT |
| LeftOpen | Listening ports, owning project, app, service, exposure | Grouped by origin; checks PID and start time | None; SIGKILL only as a second step | `MenuBarExtra`, CLI with `--json` | Free, MIT |
| LocalhostBar | Loopback TCP listeners, HTTP or not | Locks system services and other users' PIDs | None | Popover list | Free, MIT |
| worktrunk | Worktrees, ahead and behind, unpushed, CI | Six integration checks before deleting a branch | None; `-D` to force | `wt list` table | Free, MIT or Apache-2.0 |
| gwm, gwtree, wtm | Worktrees | Clean merged worktrees | Not documented | CLI or TUI | Free |
| Claude Code | Its own worktrees, changes, submodules, locks | Keeps any worktree with work; marker in git metadata | Prompt to keep; resume command printed | Exit prompt and CLI | Part of Claude Code |
| Cursor | Agent worktrees | Keeps the newest 25 per Mac | Not documented | Agents Window, `/apply-worktree` | Part of Cursor |
| Conductor | One worktree per workspace | User archives | Not documented | App with diff and PR review | Not found |
| cmux | Git branch, PR, listening ports, notifications per workspace | Shows only | Nothing to undo | Sidebar tabs, blue ring, CLI and socket | Free, GPL-3.0-or-later; server parts BSL 1.1 |
| Bartender | Menu bar items | User triggers, such as battery unplugged | Profiles | Bartender Bar, Command Bar search | One-time or yearly Pro |
| Ice | Menu bar items | User sections: shown, hidden, always hidden | Profiles (unverified) | Ice Bar under the notch | Free, GPL-3.0 |
| Raycast | Not applicable | Not applicable | Destructive alert before irreversible actions | Action panel on ⌘K, Enter runs the first action | Free; Pro $10 a month |

Sources for each row are in the sections below.

## System monitors

### Stats

- **Detects.** CPU, GPU, memory, disk, network with public IP, battery, sensors for temperature, voltage and power, Bluetooth and a clock ([github.com/exelban/stats](https://github.com/exelban/stats)).
- **Decides.** It shows numbers and takes no actions ([same README](https://github.com/exelban/stats)).
- **Presents.** One menu bar item per module, popups, and desktop widgets behind a setting. The README says macOS sets the icon order. It also says that on macOS 26 a hidden icon is turned back on in System Settings, Menu Bar ([FAQ](https://github.com/exelban/stats)).
- **Cost of itself.** The author writes that Sensors and Bluetooth are the heaviest modules. Turning them off can cut Stats's CPU and power use "by up to 50% in some cases" ([README](https://github.com/exelban/stats)). This is the clearest public statement I found that sampling has a cost the user pays.
- **Charges.** Free, MIT license. It sends requests only to api.mac-stats.com and api.github.com and says it has no telemetry ([README](https://github.com/exelban/stats)).

### iStat Menus 7

- **Detects.** "CPU, GPU, memory, disks, network, sensors, battery, weather and more" ([bjango.com/mac/istatmenus](https://bjango.com/mac/istatmenus/)).
- **Decides.** User rules raise notifications, for example "CPU usage above 60% for more than 10 seconds" or a public IP change ([bjango.com](https://bjango.com/mac/istatmenus/)).
- **Presents.** One item per monitor. A combined mode merges several into one menu bar item, and you choose what goes in the bar and what goes in the menu ([bjango.com](https://bjango.com/mac/istatmenus/)).
- **Charges.** $11.99 single and $14.99 family at the 2024 launch ([TidBITS](https://tidbits.com/?p=67835)). The bjango.com page shows "$?" placeholders, not prices. A 14-day trial ([MacRumors](https://macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/)). Also in Setapp at $9.99 a month ([bjango.com](https://bjango.com/mac/istatmenus/)).

### Activity Monitor

- **Detects.** CPU, memory, energy, disk and network per process ([support.apple.com](https://support.apple.com/guide/activity-monitor/welcome/mac)).
- **Decides.** It leaves the decision to the user, with one summary signal. Memory pressure is green when "your computer is using all of its RAM efficiently". It is yellow when it "might eventually need more RAM" and red when it "needs more RAM" ([support.apple.com](https://support.apple.com/guide/activity-monitor/check-if-your-mac-needs-more-ram-actmntr34865/mac)). The pressure is computed from free memory, swap rate, wired memory and file cache ([support.apple.com](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac)).
- **Energy.** The Energy tab has Energy Impact, "12 hr Power", App Nap and "Preventing Sleep" columns ([support.apple.com](https://support.apple.com/guide/activity-monitor/view-energy-consumption-actmntr43697/mac)). "Preventing Sleep" is the fact Insomnia needs about other apps.
- **Undoes.** Quit and Force Quit, with no undo ([support.apple.com](https://support.apple.com/guide/activity-monitor/quit-a-process-actmntr1002/mac)).

## Cleaners

### CleanMyMac

- **Detects.** System junk, malware, duplicates, large and forgotten files ([macpaw.com/cleanmymac](https://macpaw.com/cleanmymac)).
- **Decides.** MacPaw says a Safety Database of "cleaning rules, exceptions, and app-specific instructions" is checked on every scan. It says `/Library` and `/System/Library` are on an internal ignore list. It also says the database lists apps that must quit before their caches are cleared and asks the user before quitting them ([macpaw.com safety database](https://macpaw.com/support/cleanmymac/knowledgebase/safety-database), [macpaw.com safety](https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety)). It protects cache folders that hold licenses or offline data, and its example is Spotify's offline music ([same](https://macpaw.com/support/cleanmymac/knowledgebase/safety-database)). By default it offers only generated data, never personal files ([same](https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-safety)). The rule format is not public.
- **User ignore list.** Control-click an item and choose Add to Ignore List. It is undone in Preferences (unverified: the cited page describes only the internal ignore list, and a related MacPaw page says only that users can "add files, folders, and apps to ignore lists").
- **Presents.** A menu bar Menu that stays after the main app closes. It shows health, disk, memory, battery and CPU. A Health Monitor process raises alerts for low disk, high memory and unresponsive apps. The current pages give no default for the Trash alert. They say to set "Notify if Trash size exceeds" in Settings. The 2 GB default is documented only for the discontinued CleanMyMac 3 ([macpaw.com menu](https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu), [macpaw.com processes](https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-processes)).
- **Undoes.** None of the pages I read mention undo or the Trash.
- **Charges.** "Starting at $3.33/month" ([macpaw.com/cleanmymac](https://macpaw.com/cleanmymac)). The store page returned HTTP 403, so I could not confirm the plans.

### DaisyDisk

- **Detects.** Folder sizes, hidden space with an admin scan, and APFS snapshots ([daisydiskapp.com](https://daisydiskapp.com/)).
- **Decides.** "Only you decide what to delete" is a DaisyDisk feature line shown on download listings such as [TechSpot](https://www.techspot.com/downloads/7474-daisydisk-for-mac.html), not on the guide. The Collector refuses `/System`, `/Library` and the home folder ([daisydiskapp.com/guide/deleting-files](https://daisydiskapp.com/guide/deleting-files)).
- **Undoes.** Items wait in the Collector until you press Delete. Then you have 5 seconds to cancel, and deletion is permanent and skips the Trash ([guide](https://daisydiskapp.com/guide/deleting-files)).
- **Presents.** Sunburst rings you drill into ([daisydiskapp.com](https://daisydiskapp.com/)).
- **Charges.** $9.99 once, for up to five Macs ([daisydiskapp.com](https://daisydiskapp.com/)).

### DevCleaner for Xcode

- **Detects.** Device Support, Archives, Derived Data, Documentation Cache, old simulator and device logs ([github.com/vashpan/xcode-dev-cleaner](https://github.com/vashpan/xcode-dev-cleaner)).
- **Decides.** It preselects Device Support except the newest version of each OS. It can remind you to scan again ([README](https://github.com/vashpan/xcode-dev-cleaner)). The README warns that it relies on undocumented Xcode folder layouts.
- **Charges.** On the Mac App Store, GPL-3.0, with a tip jar. Free (unverified: the README does not state a price) ([README](https://github.com/vashpan/xcode-dev-cleaner)).

### npkill

- **Detects.** `node_modules` from the current folder, or custom targets with `-t` and profiles with `-p` ([github.com/voidcosmos/npkill](https://github.com/voidcosmos/npkill)).
- **Decides.** The user picks. It marks folders that installed apps may depend on with a warning sign, and `-x` excludes them ([README](https://github.com/voidcosmos/npkill)).
- **Presents.** A TUI with size and a `last_mod` column, sorting by size, path or age, and `--json` output ([README](https://github.com/voidcosmos/npkill)).
- **Undoes.** `--dry-run` simulates. The README does not say whether delete is permanent. My guess is that it is.
- **Charges.** Free, MIT.

### kondo

- **Detects.** Artifacts for more than 20 project kinds, among them Cargo, Node, Gradle, Swift, Unity, Unreal and Zig ([github.com/tbillington/kondo](https://github.com/tbillington/kondo)).
- **Decides.** The user picks. `--older 3M` limits to projects not changed for three months ([README](https://github.com/tbillington/kondo)).
- **Undoes.** None. The README calls it "essentially `rm -rf` with a prompt" ([README](https://github.com/tbillington/kondo)).
- **Charges.** Free, MIT.

### Mole

- **Detects.** Caches, logs, temp files, app leftovers, project artifacts such as `node_modules`, `target` and `dist`, and installers ([github.com/tw93/Mole](https://github.com/tw93/Mole)).
- **Decides.** It validates paths and protects shared and system locations. "When it can't prove an item is safe, it skips or refuses it". Purge protects nested git repos and key files. If the whitelist cannot be read, `clean`, `purge` and `optimize` stop ([README](https://github.com/tw93/Mole)).
- **Undoes.** `uninstall`, `analyze` and `slim` use the Trash. `clean`, `purge` and `installer` delete permanently. `clean` also empties `~/.Trash` by default. Every action goes to `~/Library/Logs/mole/operations.log`, which `mo history` shows ([README](https://github.com/tw93/Mole)).
- **Presents.** A CLI with `--dry-run` on every destructive verb, and JSON for `status`, `analyze` and `history` ([README](https://github.com/tw93/Mole)).
- **Charges.** Free, GPL-3.0. A separate paid app is sold at mole.fit ([README](https://github.com/tw93/Mole)).

### OnyX

- **Detects.** System file structure, caches, databases and indexes, and hidden settings ([titanium-software.fr](https://www.titanium-software.fr/en/onyx.html)).
- **Decides.** The user picks tasks. Each version supports one macOS version. Version 5.1.1 needs macOS 27 ([same page](https://www.titanium-software.fr/en/onyx.html)).
- **Charges.** Free, donations.

## Keep-awake

### Amphetamine

- **Detects.** Triggers for a running or frontmost app, an external display, a USB or Bluetooth device, power adapter and battery level, Wi-Fi, IP, VPN and DNS, audio output, a mounted drive, CPU above a threshold, and idle time ([App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)).
- **Lid.** Closed-display mode on Apple silicon needs an installed script and admin approval. Skipping it can fail when the power source changes ([App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)). This is the same problem Insomnia solves with a sudoers rule for exactly two `pmset` commands (`insomnia/Sources/main.m:698-701`).
- **Undoes.** It can "Auto-end session if your Mac's battery is low" ([App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)).
- **Charges.** Free. "Nothing to unlock/no 'pro' version", no ads and no tracking ([App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)).

### Lungo

- **Decides.** A duration or until off. It can deactivate when the Mac switches to battery and can let the display sleep while the Mac stays awake ([sindresorhus.com/lungo](https://sindresorhus.com/lungo)).
- **Presents.** A menu bar item, a URL scheme with `activate`, `deactivate`, `toggle`, `hours` and `minutes`, Shortcuts, a CLI and Raycast commands ([same](https://sindresorhus.com/lungo)).
- **Charges.** $4 once ([same](https://sindresorhus.com/lungo)).

### KeepingYouAwake

- **Mechanism.** "A small wrapper around Apple's `caffeinate`". It only prevents sleep with the lid open ([github.com/newmarcel/KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake)). `man caffeinate` on this Mac shows `-w pid`, which drops the assertion when a given process exits. That is the simplest way to tie keep-awake to one agent process.
- **Undoes.** A third-party guide says it deactivates below a set battery level ([addictivetips](https://www.addictivetips.com/mac-os/disable-lock-screen-sleep-on-macos)). A changelog shows a `keepingyouawake:///activate` URL and battery preferences with Low Power Mode (unverified: the [softpedia changelog](https://mac.softpedia.com/progChangelog/KeepingYouAwake-Changelog-140246.html) returned HTTP 403 on re-fetch, and the project README mentions neither). I did not confirm these in the project's own source.
- **Charges.** Free, MIT.

## Port managers

### LeftOpen

- **Detects.** For each port, it walks up from the process's working folder to a marker such as `.git`, `package.json`, `pyproject.toml`, `Cargo.toml` or `go.mod`. It names the owning `.app`, global npm packages, `python -m` modules and services such as Redis and Postgres. It tells `127.0.0.1` from `0.0.0.0` and LAN addresses ([github.com/SonghaiFan/leftopen](https://github.com/SonghaiFan/leftopen)).
- **Decides.** It checks the PID and start time again before acting. It groups by origin and says how each group stops: SIGTERM for dev servers, `brew services stop` for launchd services, and quit for apps ([README](https://github.com/SonghaiFan/leftopen)).
- **Undoes.** None, but force is a deliberate second step. If the port still listens 5 seconds after SIGTERM, a second close within two minutes sends SIGKILL ([README](https://github.com/SonghaiFan/leftopen)). LocoHost does the same with a 6-second grace and a Force setting (`locohost/Sources/main.m:25`, `:336-337`).
- **Presents.** A SwiftUI `MenuBarExtra` grouped into Dev Servers, Background Services, Apps and System. A CLI with `leftopen 3000` to explain one port and `--json` ([README](https://github.com/SonghaiFan/leftopen)).
- **Charges.** Free, MIT.

### LocalhostBar and others

- LocalhostBar names a server from the page's HTML `<title>`, project markers and known services. It never signals system services or other users' PIDs ([github.com/robzilla1738/localhostbar](https://github.com/robzilla1738/localhostbar)). Free, MIT.
- A search also found Manfath, Berth, Noodles, Seeports and devglow as menu bar port tools. Only Seeports is confirmed, as a "Menu bar port inspector". The other four come from search results only (unverified) ([search results: hunted.space, alternativeto.net, gingerbeardman.com](https://www.gingerbeardman.com/apps/seeports/)). I did not read their READMEs, so I make no claims about them.

## Worktrees

### Claude Code

- **Detects.** Its own worktrees under `.claude/worktrees/<name>/` on a branch `worktree-<name>` ([code.claude.com/docs/en/worktrees](https://code.claude.com/docs/en/worktrees.md)).
- **Decides.** On exit it checks for changed or untracked files, dirty submodules and new commits. A clean unnamed worktree is removed. A worktree with work prompts "keep or remove". When it cannot verify the state, it asks instead of removing ([same](https://code.claude.com/docs/en/worktrees.md)).
- **Ownership.** "Claude Code writes a marker into the git metadata of every worktree it creates with git, and the sweep keeps any worktree without one." It holds a `git worktree lock` while an agent runs and releases locks of sessions whose process has exited ([same](https://code.claude.com/docs/en/worktrees.md)).
- **Sweep.** Subagent and background worktrees older than `cleanupPeriodDays` are removed unless they hold work, unpushed commits or dirty submodules ([same](https://code.claude.com/docs/en/worktrees.md)).
- **Reuse.** A reused name resets to the default branch only when the old worktree is clean, is still on its own branch, and either has no commits of its own or was merged. Merged means the remote branch is gone and every commit is already on the default branch. If the state cannot be verified, it reopens at the old tip ([same](https://code.claude.com/docs/en/worktrees.md)).
- **Undoes.** "Keep" preserves the folder and branch, and it prints a `claude --worktree <name> --resume` command. "Remove" deletes the work ([same](https://code.claude.com/docs/en/worktrees.md)).
- **Carries ignored files.** `.worktreeinclude` copies gitignored files such as `.env` into new worktrees ([same](https://code.claude.com/docs/en/worktrees.md)).

### Cursor

- **Decides.** Cleanup "keeps the newest worktrees up to the configured machine-wide maximum count". `cursor.worktreeMaxCount` defaults to 25. Cleanup also finds worktrees made with plain `git worktree add`, which makes them "eligible for deletion" ([cursor.com/docs/configuration/worktrees](https://cursor.com/docs/configuration/worktrees)). The page does not say that cleanup checks for uncommitted work.
- **Setup.** `.cursor/worktrees.json` with `setup-worktree` commands ([same](https://cursor.com/docs/configuration/worktrees)).
- **Presents.** `/apply-worktree` brings changes back, and `/delete-worktree` removes the checkout ([same](https://cursor.com/docs/configuration/worktrees)).

### Conductor

- Each workspace is a git worktree on its own branch with a `.context` folder for notes. App processes get `CONDUCTOR_PORT`. The flow ends with "review the diff, open a pull request, merge, and archive the workspace" ([conductor.build/docs](https://www.conductor.build/docs/), [workspaces and branches](https://www.conductor.build/docs/concepts/workspaces-and-branches)). The pages I read do not say what archive does to the folder or branch.

### cmux

- The sidebar entry of each workspace shows the git branch, PR status and number, working folder, listening ports and the latest notification. An agent that needs input gets a blue ring. Notifications come from OSC 9, 99 and 777 escape sequences or `cmux notify` ([github.com/manaflow-ai/cmux](https://github.com/manaflow-ai/cmux)).
- Everything is scriptable through a CLI and a Unix socket ([same](https://github.com/manaflow-ai/cmux)). Free, GPL-3.0-or-later. The server parts use the Business Source License 1.1 ([same](https://github.com/manaflow-ai/cmux)).

### worktrunk and other CLIs

- `wt remove` deletes a branch only when it passes one of six checks: same commit, ancestor, empty three-dot diff, equal trees, a simulated merge that adds nothing, or a patch-id that matches one squash commit ([worktrunk.dev/remove](https://worktrunk.dev/remove/)). The history walk is capped, so an old squash merge "needs -D to remove" ([same](https://worktrunk.dev/remove/)).
- `--force` is for a dirty worktree and `-D` for an unmerged branch. These are two separate flags for two separate risks ([same](https://worktrunk.dev/remove/)).
- Removal runs in the background and logs to `.git/wt/logs/{branch}/internal/remove.log` ([same](https://worktrunk.dev/remove/)).
- `wt list` dims branches that are safe to delete (unverified: the README does not say this). CI status shows only with `wt list --full`. worktrunk has a `hash_port` template filter for a stable port per worktree ([worktrunk README](https://github.com/max-sixty/worktrunk)).
- WorkForest already records `ancestor | tree | patch | squash | pr` (`workforest/Sources/Trees.h:23`). It keeps patch-ids of the newest 400 commits on disk (`workforest/Sources/Trees.m:103-104`). `grep merge-tree` in `workforest/Sources` finds nothing, so worktrunk's simulated-merge check is the one WorkForest lacks.
- gwm, gwtree and wtm each have a "clean merged worktrees" command ([search results](https://docs.rs/crate/gwm/latest), [gwtree](https://www.mintlify.com/ahmadawais/gwtree/commands/overview), [wtm](https://github.com/jarredkenny/worktree-manager)). I did not read how they detect merges.

## Menu bar and UI patterns

### Bartender

- **Presents.** Hidden items open in Bartender Bar on hover, click or hotkey. Triggers show an item when a condition holds, such as battery when power is unplugged or the mic during meetings. The Command Bar searches and runs any menu bar item from the keyboard. Items hidden behind the notch can move to Bartender Bar ([macbartender.com](https://www.macbartender.com/)).
- **Permissions.** Screen Recording is optional. Without it Bartender shows app icons instead of images of the items ([macbartender.com](https://www.macbartender.com/)).
- **Trust.** In 2024 the app was sold to Applause without notice. An update arrived with a new signing certificate and the Amplitude analytics framework, in an app that holds Accessibility and Screen Recording rights. Version 5.0.53 later removed Amplitude ([mjtsai.com](https://mjtsai.com/blog/2024/06/05/bartender-acquired-by-applause-group/), [TidBITS](https://tidbits.com/?p=66951)).
- **Charges.** Bartender 7 once, or Pro yearly with a 14-day trial ([macbartender.com](https://www.macbartender.com/)).

### Ice

- Sections for shown, hidden and always hidden. The Ice Bar shows hidden items below the menu bar for Macs with a notch. Search ([github.com/jordanbaird/Ice](https://github.com/jordanbaird/Ice)). Profiles and groups are listed under "Features/Roadmap", and the page says "Some features have not yet been implemented", so whether they ship is unverified. macOS 14 or later. Free, GPL-3.0.

### Raycast

- **Action panel.** ⌘K opens all actions for the selected item. Enter runs the first action directly. Typing filters the actions, and each action shows its shortcut so you learn it ([manual.raycast.com/action-panel](https://manual.raycast.com/action-panel)).
- **Destructive actions.** `confirmAlert` with `Alert.ActionStyle.Destructive` is meant for "irreversibly deleting something" ([developers.raycast.com](https://developers.raycast.com/api-reference/feedback/alert)).
- **Menu bar commands.** These refresh in the background on an `interval` such as `"5m"`. A title-only item renders disabled and serves as a section title. An `alternate` item appears when ⌥ is held. Raycast advises against long titles ([developers.raycast.com](https://developers.raycast.com/api-reference/menu-bar-commands)).
- **Charges.** Free core. Pro is $10 a month or $96 a year ([raycast.com/pricing](https://www.raycast.com/pricing)).

## Five patterns to take

1. **Check fresh, then act.** LeftOpen checks the PID and start time again before it acts ([README](https://github.com/SonghaiFan/leftopen)). Claude Code asks instead of removing when it cannot verify a worktree ([docs](https://code.claude.com/docs/en/worktrees.md)). Mole skips anything it cannot prove safe ([README](https://github.com/tw93/Mole)). PLAN.md section 1, principle 5 already asks for this. These tools show that "cannot verify" must mean "keep", never "go ahead".
2. **Mark what you own.** Claude Code's sweep removes only worktrees with its marker in git metadata. It locks a worktree while an agent runs ([docs](https://code.claude.com/docs/en/worktrees.md)). MinMacs 2.0 should touch only what it can tie to an owner, and treat a lock as "in use".
3. **Say how each thing will stop or go.** LeftOpen labels each group with its stop method: SIGTERM, `brew services stop` or quit ([README](https://github.com/SonghaiFan/leftopen)). Activity Monitor gives one color for memory pressure ([support.apple.com](https://support.apple.com/guide/activity-monitor/check-if-your-mac-needs-more-ram-actmntr34865/mac)). This fits the hover card rule in DESIGN.md that the status says "what happens next".
4. **Separate the risks, and make force a second step.** worktrunk has `--force` for a dirty tree and `-D` for an unmerged branch ([worktrunk.dev](https://worktrunk.dev/remove/)). LeftOpen sends SIGKILL only on a second close within two minutes ([README](https://github.com/SonghaiFan/leftopen)).
5. **Keep a log you can read back.** Mole writes every action to `operations.log` and shows it with `mo history` ([README](https://github.com/tw93/Mole)). WorkForest's `removed.json` and `workforest restore` go further, because they can undo (`workforest/Sources/Forest.m:222`, `workforest/Sources/main.m:95-96`). One Undo log in Core should be both the history and the restore list.

Runner-up patterns:

- **A combined icon.** iStat Menus merges several monitors into one item ([bjango.com](https://bjango.com/mac/istatmenus/)).
- **Triggers that show an item only when it matters.** Bartender does this ([macbartender.com](https://www.macbartender.com/)).
- **An action panel where Enter does the obvious thing.** Raycast does this ([manual.raycast.com](https://manual.raycast.com/action-panel)).
- **JSON output on every verb.** Mole, npkill and LeftOpen all have it.

## Five mistakes to avoid

1. **Permanent delete as the default.** DaisyDisk deletes permanently after a 5-second cancel window ([guide](https://daisydiskapp.com/guide/deleting-files)). kondo is "`rm -rf` with a prompt" ([README](https://github.com/tbillington/kondo)). Mole's `clean` and `purge` delete permanently, and `clean` also empties the Trash by default ([README](https://github.com/tw93/Mole)). Noo-Noo today calls `os.RemoveAll` (`noo-noo/internal/autoclean/apply.go:57-59`). MinMacs 2.0 should never empty the Trash on its own, because the Trash is its undo.
2. **Cleanup by count or age alone.** Cursor keeps the newest 25 worktrees per Mac. Cleanup also claims worktrees the user made with `git worktree add`, and the page does not say it checks for uncommitted work ([cursor.com](https://cursor.com/docs/configuration/worktrees)). Age is a hint, not a verdict. Claude Code's sweep shows the safer rule: age, and no work, and our marker ([docs](https://code.claude.com/docs/en/worktrees.md)).
3. **A safety list nobody can read.** CleanMyMac's Safety Database decides what is safe, and its format is not public ([macpaw.com](https://macpaw.com/support/cleanmymac/knowledgebase/safety-database)). Noo-Noo's knowledge should ship as readable data, as PLAN.md section 3 proposes with "Clutter (Noo-Noo's knowledge as data)", so users and the verifier can audit each rule.
4. **The tool costs more than it saves.** Stats's author says turning off two modules, Sensors and Bluetooth, can cut its CPU and power use "by up to 50% in some cases" ([README](https://github.com/exelban/stats)). Five experts that each sample on their own repeat this mistake. PLAN.md section 3, "One sampler", is the fix, and phase 1 should publish the measured idle cost.
5. **Broken trust through broad rights and quiet changes.** Bartender's sale came with a new signing certificate and an analytics framework, later removed, in an app with Screen Recording rights ([mjtsai.com](https://mjtsai.com/blog/2024/06/05/bartender-acquired-by-applause-group/)). Stats and LeftOpen state exactly which hosts they contact ([Stats](https://github.com/exelban/stats), [LeftOpen](https://github.com/SonghaiFan/leftopen)). MinMacs 2.0 should ask for no Screen Recording or Accessibility rights. It should list every network call in docs/REVIEW.md and send no telemetry.

## Gaps nobody fills

Each gap is "no tool I read does this". This is not proof that no tool anywhere does it.

1. **A port that knows its worktree and branch state.** LeftOpen and LocalhostBar find the project folder ([LeftOpen](https://github.com/SonghaiFan/leftopen), [LocalhostBar](https://github.com/robzilla1738/localhostbar)). cmux shows a branch and ports per workspace but does not judge them ([cmux](https://github.com/manaflow-ai/cmux)). None says "this server runs in a squash-merged worktree, stop it". This is PLAN.md section 3, the LocoHost row.
2. **A cache that knows its project is finished.** npkill and kondo use last-change time ([npkill](https://github.com/voidcosmos/npkill), [kondo](https://github.com/tbillington/kondo)). None asks git whether the branch is merged. This is PLAN.md section 6, "Clutter that knows its owner".
3. **Keep-awake that follows agent work.** Amphetamine's triggers cover apps, CPU and idle time, but not "an agent is working" ([App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)). `caffeinate -w pid` can follow one process (`man caffeinate`), but nothing picks the process for you.
4. **One undoable Wrap Up.** Cursor, Conductor and worktrunk remove a worktree. None also stops its servers, trashes its caches and closes its headless browsers as one restorable step ([Cursor](https://cursor.com/docs/configuration/worktrees), [Conductor](https://www.conductor.build/docs/), [worktrunk](https://worktrunk.dev/remove/)). This is PLAN.md section 6, "Wrap Up a workstream".
5. **Restore after removal.** Only WorkForest recreates a removed worktree and puts back its ignored files (`workforest/Sources/main.m:95`). Claude Code offers "keep" before removal but has no restore after it ([docs](https://code.claude.com/docs/en/worktrees.md)).
6. **Cross-tool worktree hygiene.** Claude Code, Cursor and Conductor each manage their own worktrees, in different places with different rules ([Claude Code](https://code.claude.com/docs/en/worktrees.md), [Cursor](https://cursor.com/docs/configuration/worktrees), [Conductor](https://www.conductor.build/docs/concepts/workspaces-and-branches)). Cursor's cleanup can even claim worktrees other tools made. Nothing gives one view of all of them with one rule.
7. **An agent asking "is this port mine?"** LeftOpen has `--json` per port ([README](https://github.com/SonghaiFan/leftopen)), but none answers per session. This is PLAN.md section 6, "Is this port mine?".

## Recommendations

1. **PLAN.md section 1, principle 5, "Nothing is lost".** Add the rule "cannot verify means keep", from Claude Code and Mole. Add "MinMacs never empties the Trash", against Mole's `clean`.
2. **PLAN.md section 3, Act and Undo.** Make one append-only Undo log the source for the history view, the restore list and the CLI `minmacs restore`. Model it on Mole's `operations.log` plus WorkForest's `removed.json`.
3. **PLAN.md section 3, Act.** Use LeftOpen's two-step force: SIGTERM, then SIGKILL only on a second request within a short window. Check the PID and start time again before both. LocoHost's 6-second grace stays (`locohost/Sources/main.m:25`).
4. **PLAN.md section 3, Know, Git.** Add worktrunk's simulated-merge check with `git merge-tree` to WorkForest's ancestor, tree, patch, squash and pr checks. Keep the capped patch-id cache, and say "needs a look" when the cap is hit.
5. **PLAN.md section 3, Know, Git.** Honor `git worktree lock` and Claude Code's ownership marker as "in use, never touch". Treat worktrees under `.claude/worktrees/`, Cursor's and Conductor's as owned by those tools. Show them, but act only through the owner's own rules or with consent. This needs track E for paths.
6. **PLAN.md section 3, Know, Clutter.** Ship Noo-Noo's rules as a readable JSON file in the repo, with protected paths like DaisyDisk's `/System`, `/Library` and home refusal. Add a CleanMyMac-style list of apps to quit before a cache is cleared. Avoid CleanMyMac's closed database.
7. **PLAN.md section 5, Out of the box.** Default Noo-Noo to the Trash for known kinds, with one log and no permanent delete in any mode. This answers open question 3 in favor of the Trash, with undo.
8. **PLAN.md section 6, Heat and battery aware.** Insomnia should copy two guards from Amphetamine and Lungo: end on low battery, and an option to turn off on battery. Tie each assertion to the working agent's PID, as `caffeinate -w` does.
9. **PLAN.md section 7, Menus.** Copy Raycast's rule that the first action runs on a plain click and the rest sit under More. Use a title-only item as a section label. Offer an ⌥ alternate for force. DESIGN.md's limit of four card actions matches this.
10. **PLAN.md section 7, Menus.** Offer one combined "MinMacs" icon, like iStat Menus' combined mode, as an option for crowded bars and notched Macs. Track G owns the details.
11. **PLAN.md section 7, CLI.** Give every verb `--json` and `--dry-run`, as Mole, npkill and LeftOpen do. Add `minmacs hosts 3000` to explain one port, as `leftopen 3000` does.
12. **PLAN.md section 10, Privacy.** Ask for no Screen Recording or Accessibility rights. List every host the app contacts, as Stats does. Send no telemetry.
13. **PLAN.md section 9, phase 1.** Publish the measured idle CPU and memory of the core in the README, as a promise Stats's numbers show users care about.

## Open questions

1. What does Conductor's "archive" do to the worktree folder and branch? Its docs pages I read do not say.
2. Does Cursor's worktree cleanup check for uncommitted work before it deletes past the 25 cap? The docs page does not say. If it does not, should WorkForest warn when Cursor's count nears 25?
3. Should MinMacs act on worktrees that Claude Code, Cursor or Conductor own, or only show them and link to the owner?
4. Does npkill delete permanently or use the Trash? Its README does not say.
5. KeepingYouAwake's battery threshold and URL scheme come from third-party pages. Confirm in its source if Insomnia's URL scheme should match it.
6. Is a combined single icon the default, or only an option? This is shared with track G.
7. CleanMyMac's current plans and prices could not be read, because the store page returned HTTP 403.

## Verification

The verifier re-checked this file on 2026-10-27. Each web claim was re-fetched with WebFetch at its cited URL. Each code claim was re-read at its file and line. `man caffeinate` and `ls /Applications` were re-run.

**Counts.** 86 claims confirmed, 9 corrected, 6 marked unverified.

**Code and commands checked.**

- `insomnia/Sources/main.m:698-701` holds the sudoers rule for exactly two `pmset -a disablesleep` commands. Confirmed.
- `locohost/Sources/main.m:25` sets `kGrace = 6`. Lines 336-337 say SIGKILL happens only when the setting is Force Stop It or force is set. Confirmed.
- `workforest/Sources/Trees.h:23` lists `ancestor | tree | patch | squash | pr`. `Trees.m:103-104` keeps patch-ids of the newest 400 commits. `grep -rn merge-tree workforest/Sources` finds nothing. `Forest.m:222` defines `removed.json`. `main.m:95-96` lists `restore` and `removed`. All confirmed.
- `noo-noo/internal/autoclean/apply.go:50-56` holds only comments. The `DefaultDeleter` function and its `os.RemoveAll` call are at lines 57-59. Corrected.
- `man caffeinate` shows `-w pid`, which releases the assertion when the process exits. Confirmed.
- `ls /Applications` shows `cmux.app` and `Cursor.app` and none of the other studied apps. Confirmed.

**Corrected.**

1. iStat Menus detects: the page says "weather and more". It does not list power or time.
2. iStat Menus price: MacRumors does not list prices. Only TidBITS gives $11.99 and $14.99. bjango.com shows "$?" placeholders.
3. CleanMyMac Trash alert: the 2 GB default is documented only for CleanMyMac 3. Current pages give no default.
4. DaisyDisk "Only you decide what to delete": the quote is not on the cited guide. It appears on download listings such as TechSpot.
5. Claude Code name reuse: the reset also needs a clean worktree on its own branch, and it also happens when the worktree has no commits of its own.
6. cmux license: GPL-3.0-or-later, with server parts under BSL 1.1.
7. Bartender: version 5.0.53 removed Amplitude. Added to the trust line and to mistake 5.
8. Noo-Noo `os.RemoveAll` line numbers: 57-59, not 50-56.
9. Stats cost: the README says turning off Sensors and Bluetooth cuts CPU and power use "by up to 50%". The earlier "can double" wording was an inference and now quotes the README.

**Marked unverified.**

1. CleanMyMac Control-click "Add to Ignore List" and undo in Preferences. The cited page does not describe it.
2. DevCleaner is free. The README does not state a price.
3. KeepingYouAwake URL scheme and Low Power Mode. The softpedia page returned HTTP 403, and the project README mentions neither.
4. Manfath, Berth, Noodles and devglow as menu bar port tools. Only Seeports was confirmed.
5. `wt list` dims branches that are safe to delete. The worktrunk README does not say this. CI status shows only with `wt list --full`.
6. Ice profiles and groups. They are listed under "Features/Roadmap" with a note that some features are not yet implemented.

**Checked but weak.** Activity Monitor's welcome page does not itself list per-process metrics. The sub-pages for memory and energy do support the claims made. The Amphetamine App Store listing covers network and VPN triggers in general terms. The words Wi-Fi, IP and DNS were not quoted back exactly. Opinions and recommendations were not counted as claims.
