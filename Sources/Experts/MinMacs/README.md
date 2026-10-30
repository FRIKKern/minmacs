# MinMacs expert

Performance: apps, agents, RAM, CPU, energy and heat. Issue #21. Ported from MinMacs 1.2 on branch `legacy`.

| File | What it holds | Ported from |
|---|---|---|
| `MMMinMacs.h` | The expert, the rules, the tab bridge and the input types | |
| `MMMinMacsExpert.m` | Findings, the policy, quit and trim actions, the menu, cards, review rule and verbs | `main.m`, `Scanner.m`, `Agents.m` |
| `MMMinMacsRules.m` | `minmacs/rules.json` with the fixes for #43, #44 and #45 | `Rules.m` |
| `MMMinMacsBrowser.m` | Tabs through Apple events to one pid, loaded at runtime | `Browser.m` |
| `MMMinMacsSpecs.m` | Makers for the specs of `Core/MMExpert.h` | |
| `MMMinMacsWrapUp.m` | Wrap Up's helpers part and its localhost tabs part | |

## What it reads

- Apps come from Core's `MMRunningApps()`, which reads `NSWorkspace.runningApplications` once per app launch or quit, with helpers rolled up from `facts.sample` by responsible pid, then by parent, at most 12 hops. Issue #52: the app each process rolls up into is kept while its start and parent hold and the app list is the same, and the undo records are read again only when `MMLogStamp()` moved.
- Loopback listeners come from the sample's socket table. Remote debugging comes from the sample's arguments.
- A working agent spares every app in its process tree. Agents come from `facts.agents`, hosted agents included, and from `facts.sessions` whose `stillWorking` is set. Waiting on the person counts as working.

## What it does

- Quit and Force Quit run through `MMRunAction` and `MMQuitApps`. Force Quit is refused until this app instance was asked to quit once. The undo record holds `relaunch` with the bundle path, bundle id, pid and step, so `MMUndo restore` opens the app again.
- Trim reads tabs at action time, records only the tabs that closed, and keeps a tab whose URL moved on. Restore reopens those tabs through the bridge, then restores the record.
- The card's Always Keep, Quit on MinMacs, Leave Unsorted, Close Even When Serving and Spare When Serving write `minmacs/rules.json` on `no.guerrilla.minmacs.minmacs.act`, then ask for a rebuild, so main never waits on the file.
- Proactive never quits an app. Eager quits a close-list app only while memory pressure is warn or worse, or heat is serious or worse. No mode trims tabs.
- Verbs: `apps`, and its parts of `status` and `restore`. Each takes `--json` and `--dry-run`.
- Wrap Up has two MinMacs parts. Helpers stops the processes a finished workstream left behind. Tabs comes after it: for each running browser whose tabs MinMacs reads, Chromium browsers and Safari, it closes the tabs on localhost, 127.0.0.1 or ::1 at a port one of the plan's server parts stops. Its title names the count and the browser, such as "Close 3 localhost tabs in Google Chrome". It never quits a browser. A tab whose URL changed since the read stays open.
- The tabs part reads tabs through the tab bridge only. Off main and off the graph queue it reads at once. On main and on the graph queue it uses the last read, at most a minute old, and queues a read on `no.guerrilla.minmacs.minmacs.tabs` only when `mayReadWithoutAsking:` says no prompt would show. A read that changed the open tabs asks the graph for a rebuild.
- MustKeep for the tabs part: a browser on the keep list or on no list in the rules is never touched, nor one a working agent started. A private window is never read: the Apple events bridge skips Chromium's incognito windows, and the expert drops any tab marked `privateWindow`. Safari's scripting does not say which windows are private.
- The record holds the closed tabs and `reopen`, with the bundle id, the app path, the URLs and the ports, and sets `restoreLast`. The Wrap Up's restore brings back every other part first, waits up to 15 seconds for the ports to listen, then opens the URLs in the same browser through the bridge.
- With `MINMACS_HOME` set, the Apple events bridge refuses to read, close or open, so a test never reaches a real browser.

## Open for the wiring

- `main.m` registers `MMMinMacsExpert.shared` through `MMRegisterBuiltInExperts`.
- The spec classes of `Core/MMExpert.h` have no implementation on this branch. `MMMinMacsSpecs.m` uses them when they link and value objects with the same properties when they do not.
- `MMArgs` has no interface yet. `MMMinMacsWords` reads its words through `words`, `arguments` or `argv`, and else from the process arguments after the verb.
- `status` and `restore` are shared verbs. This expert registers its own `MMVerbSpec` for each, and `statusJSON:`, `statusLine:` and `restore:dryRun:` are there for a registry that merges the parts.

## Checks

`./test.sh minmacs` builds `test/minmacs/tool.m` with Core, the kit and the expert. It runs fixture apps from `test/minmacs/stubborn.m`, a fixture agent from `test/minmacs/agent.c`, and a fake tab bridge on a JSON file, all inside `$MINMACS_HOME`. It renders the menu and cards to `build/render/minmacs`. `./test.sh wrapup` runs the tabs part end to end with a fixture browser process, a bundle id unique to the run and a fake bridge on a JSON file.
