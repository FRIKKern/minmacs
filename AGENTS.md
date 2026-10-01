# For AI agents working in this repo

**Build and verify**

```sh
./build.sh                       # universal build, installs ~/Applications/MinMacs.app and ~/.local/bin/minmacs
minmacs plan                     # non-destructive: shows the current plan
./test.sh                        # fixtures only: TextEdit and build/Stubborn.app; nothing else is touched
./test.sh --browser              # adds a live Chrome test that opens its own two tabs
```

**Layout**: `Sources/Scanner.m` samples processes and attributes them to apps. `Sources/Rules.m` holds the keep/close lists and the JSON rules file. `Sources/Browser.m` reads and closes tabs through ScriptingBridge aimed at one pid. `Sources/main.m` is the menu bar UI, the CLI (`RunCLI`), the plan, quitting, force quitting and restoring. `Sources/Hosts.m` holds host readers that feed `MMAgents.overrides`; today only `MMCmuxReader`. `tools/stubborn.m` is the test app that refuses to quit. `tools/mkicon.m` renders the icon.

**Invariants that must hold after any change**

1. Graceful first. `QuitApps` always runs before `ForceQuitApps`, and force happens only when the user's setting or an explicit `--force` allows it. Every force path says that unsaved changes are lost.
2. Only apps whose verdict is `MMClose`, and that are neither spared nor a trimmable browser, are ever quit. `MMKeep` and `MMUnsorted` reach the quit functions only through the per-app items the user picked.
2a. Browser tabs: only `noise` tabs are closed. Work wins over noise. Private windows are never read. Tabs are addressed by process id, never by bundle id, because a second instance of the same browser may belong to an agent.
2b. A spared app is never touched by `run`, with or without `--force`.
3. Everything that gets quit is first added to the closed list, so Restore can bring it back. The CLI and the app share that list through the explicit `no.guerrilla.minmacs` preferences domain.
4. The plan shown in the menu and by `minmacs plan` is the exact set `run` acts on. No hidden extras.
5. macOS system processes are informational only. Nothing in the background list is ever acted on.
6. Builds with clang alone. No Swift, no packages, no Xcode project.

7. The cmux reader reads only the key names it is named for: `pid, sessionId, surfaceId, workspaceId, updatedAt` from `~/.cmuxterm/claude-hook-sessions.json` and `kind, createdAt, workstreamId` from the last 2 MB of `~/.cmuxterm/workstream.jsonl`. It never reads, stores, logs or prints a payload, prompt, title or context, and never opens either file for writing. It is off unless `minmacs.readCmux` is on or `--cmux` is passed. Only `blocked` (any age) and `working` (under 60 s) are ever written to overrides. Tests point it at fixtures with `minmacs.debug.cmuxDir`; never at a real `~/.cmuxterm`.

**Using MinMacs from an agent**: `minmacs agents [--cmux]` lists agent sessions as working, idle or blocked (blocked = waiting on the human, cmux only). `minmacs plan --json` to explain what will go, `minmacs run --yes --force` to do it, `minmacs restore` afterwards. Tell the user first when the plan force quits anything or closes tabs: unsaved changes and form contents do not come back.
