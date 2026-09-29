# For AI agents working in this repo

**Build and verify**

```sh
./build.sh                       # universal build, installs ~/Applications/MinMacs.app and ~/.local/bin/minmacs
minmacs plan                     # non-destructive: shows the current plan
./test.sh                        # closes and restores TextEdit under a temporary rule; nothing else is touched
```

**Layout**: `Sources/Scanner.m` samples processes and attributes them to apps. `Sources/Rules.m` holds the keep/close lists and the JSON rules file. `Sources/main.m` is the menu bar UI, the CLI (`RunCLI`), the plan, quitting and restoring. `tools/mkicon.m` renders the icon.

**Invariants that must hold after any change**

1. Never force-quit. `QuitApps` uses `-[NSRunningApplication terminate]` only. Anything still running after the grace period is reported, not killed.
2. Only apps whose verdict is `MMClose` are ever quit. `MMKeep` and `MMUnsorted` are never passed to `QuitApps` except through the per-app "Quit Now" the user chose.
3. Everything that gets quit is first added to the closed list, so Restore can bring it back. The CLI and the app share that list through the explicit `no.guerrilla.minmacs` preferences domain.
4. The plan shown in the menu and by `minmacs plan` is the exact set `run` acts on. No hidden extras.
5. macOS system processes are informational only. Nothing in the background list is ever acted on.
6. Builds with clang alone. No Swift, no packages, no Xcode project.

**Using MinMacs from an agent**: `minmacs plan --json` to explain what will go, `minmacs run --yes` to do it, `minmacs restore` afterwards. Warn the user before `run` if the plan includes a browser, since tabs come back but form contents don't.
