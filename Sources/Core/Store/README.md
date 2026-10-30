# Store

The support folder, the prefs domain, rules files, state files, the SQLite log and the migration from the five old apps. Issues #19 and #37. The headers are `MMStore.h`, `MMLog.h`, `MMGains.h` and `MMMigrate.h`.

| File | What it holds | Ported from |
|---|---|---|
| `MMStore.m` | `MMSupportDir`, `MMExpertDir`, prefs on `no.guerrilla.minmacs`, `MMStateFile`, `MMRules` | LocoHost `LHSupportDir` and `SaveActivity`, WorkForest `WFRules`, MinMacs 1.2 `Match` |
| `MMLog.m` | The append-only log in `minmacs.sqlite`, and trend points | Noo-Noo `audit.go`, in SQLite per decision 5 |
| `MMGains.m` | The kept log of what came back, table `gains` in `minmacs.sqlite`, for designs 100 to 103 | New code |
| `MMMigrate.m` | `MMLegacyPlan`, `MMImportLegacy` and `MMMigrateFollowUp` | The file and pref shapes of LocoHost, WorkForest, Insomnia, Noo-Noo and MinMacs 1.2 |

## Where things live

- The support folder is `~/Library/Application Support/MinMacs`, or `$MINMACS_HOME`. Each expert has a folder in it, such as `locohost/`.
- Prefs go to `no.guerrilla.minmacs` through CFPreferences. With `MINMACS_HOME` set they go to `$MINMACS_HOME/Preferences/no.guerrilla.minmacs.plist`, read and written as a file under an flock and never through CFPreferences, so a test never writes the person's prefs.
- Keys carry the expert, such as `locohost.mode`. `review.model` and `core.oneIcon` belong to the Settings window. An icon's shown state is AppKit's own key, `NSStatusItem Visible minmacs.<expert>`.
- `rules.json` keeps each named list at the top level. `_defaults` lists every default it ever added, so a default the person removed is not added again.
- The log is one table of rows. Triggers refuse `UPDATE` and `DELETE`. A new state of a record is a new row with the same `rid`. Trend points sit in their own table, one per bucket.
- Opening the log may wait up to 15 seconds for another process's lock: the 5-second busy timeout, then 10 seconds of retries. So `MMCoreStart` calls `MMLogOpenOffMain` first. From then on `+[MMLog shared]` on main never opens the log: it returns the log once the `core.log.open` queue has opened it, and nil before. `MMLogMainThreadOpens` counts opens on main, and `test/fixes.sh` holds the app to zero. A CLI run never calls `MMLogOpenOffMain`, so its main thread opens the log as before. The legacy import hands its rows to that queue through `MMLogWhenOpen` and marks a source done after its rows are in.
- `MMRemoveStaleFiles` removes what an older build wrote and nothing reads. Today that is `repos.eventid`, the one event id of the first repo watch. Each root's stream keeps `repos.<hash>.eventid` now. `MMCoreStart` runs it once, on `core.store`, and it removes only a plain file of that name.

## What came back

`MMGains` keeps one row per finished action in the table `gains` of `minmacs.sqlite`, for 30 days. Act writes it in `MMRunAction` through `MMGainsRecordAction` in `Act/MMGainsAct.m`, and `-[MMUndo restore:]` marks it undone. `minmacs gains [--days N] [--json]` reads it.

- Memory back is the footprint of the process trees a stop or a quit ended, read from the fresh sample right before it ran, with a pid counted once. Other actions end no process and give no memory back.
- Disk back is what MMSizer said deleting frees. A move to the Trash waits as "in the Trash" and counts only once every item it moved is gone from the Trash. An item at its old path again with the inode it had in the Trash was put back by hand and never counts. Each read settles the waiting rows.
- Memory and disk are two numbers and are never summed.
- The kind is server, app, tab, helper, cache or worktree. A Wrap Up's parts are kind workstream, each with its own kind in `part`, and count as one action. Who did it is you for a menu or the CLI, auto for a mode or an expert's own rule, and run for a part of a Wrap Up.
- A failed action, the lid override, a keep-awake hold, a setting and the migration's own moves write nothing.
- The table is not append-only, unlike the log's rows. Rows older than 30 days are deleted on each write and read. Opening an older `minmacs.sqlite` adds the table and `gains_schema` with version 1, and leaves the log's tables as they are.

## The migration

`MMImportLegacy` reads, and never writes, what the old apps leave. Every read goes through the home folder it is given, so a test points it at a copy. For the person's own home a prefs domain is read through CFPreferences, and for any other home from its plist file. Noo-Noo's `store.db` is opened read-only and immutable, so SQLite writes no journal next to it.

| Old | New |
|---|---|
| `locohost.*` prefs | the same keys, and `locohost.model` becomes `review.model` |
| `workforest.*` prefs | the same keys, and `workforest.model` becomes `review.model`. `fetch`, `checkPRs` and the CLI paths are gone |
| `insomnia.*` prefs of `no.guerrilla.insomnia` | the same keys. The debug prefs, the guard clocks and the update check stay out |
| `minmacs.*` prefs of 1.2 | the same keys. 1.2 used the same domain, so on the person's own Mac they are already in place |
| `NSStatusItem Visible Item-0` of each app, Noo-Noo's in `io.noo-noo.app` | `NSStatusItem Visible minmacs.<expert>`, so a hidden icon stays hidden |
| LocoHost `rules.json` | `locohost/rules.json`, with `protect.names` and the other nested lists as flat names |
| LocoHost `activity.json` and `keep.json` | `locohost/activity.json` and `locohost/kept.json` |
| LocoHost `closed.json` | one `undo` row per stopped server in state `done`, with its restart command |
| LocoHost and WorkForest `review.json` | one `review` row each |
| WorkForest `rules.json` | `workforest/rules.json`. `protect.paths` becomes `protect`, `ignore.paths` becomes `ignore`, and the roots join `core/rules.json` |
| WorkForest `removed.json` | one `undo` row per removal, which restore takes back at its commit with the files 0.1 saved, left where 0.1 put them. `workforest/legacy-removed.json` maps 0.1's id to the rid, the map the expert's own import keeps, so each record comes in once |
| Noo-Noo `config.toml` | `noonoo/legacy-config.json`, the whole file. `auto_clean.enabled` off makes `noonoo.mode` idle, on with the risk acknowledged makes it proactive. The scan and worktree roots join `core/rules.json` |
| Noo-Noo `store.db` | the last 500 `actions` and `auto_clean_events` as `legacy` rows. Noo-Noo deleted for good, so they are history and never undo rows. The import reads it in its `MMLogWhenOpen` work, off main in the app |
| MinMacs 1.2 `rules.json` | `minmacs/rules.json`, wildcards kept |
| `minmacs.closedBundleIDs` and `minmacs.closedTabs` | one `undo` row per app to relaunch, with its tabs |

An imported `undo` row's body has the shape `MMUndoRecord` in Act reads: `rid`, `state`, `kind`, `by`, `at` and `payload`. A stop keeps its command in `payload.restart.command`, an app keeps its bundle id and tabs in `payload.relaunch`, and a removed worktree keeps `payload.worktree` and `payload.recovery`. The old record stays in `payload.legacy`.

Each source is imported once, and the `core.migrated` pref records when. A source marked before is not read again. A 2.0 file that already exists is left as it is.

## The follow-up

`MMMigrateFollowUp` runs once after the import, off main. The shell starts it 20 seconds after launch on `no.guerrilla.minmacs.core.migrate`, only when `MMMigrateWanted` says so: never under `MINMACS_HOME` or `MM_TESTS`, and never headless. Each part is recorded in `core.migrated` when it is done, so a second launch asks nothing and runs nothing.

- **The lid.** When the old Insomnia had `insomnia.lid` on and the override is still live, it goes off once, through `MMRunAction` and `MMLidOverride`, with an undo record of kind `lid` by `guard`. An override another tool set stays. While Insomnia.app runs it owns the override, and a refused write tries again at the next launch. While the 2.0 pref `insomnia.lid` is on, which the import carries over, the Insomnia expert owns the override: it may want it on with the lid shut and an agent at work, and it clears it itself when nothing does. Then the part is done with no write. Insomnia's sudoers rule is never touched.
- **Noo-Noo's LaunchAgent.** `~/Library/LaunchAgents/io.noo-noo.d.plist`, with its state from `+[SMAppService statusForLegacyURL:]`. One confirm. On yes `launchctl bootout` stops it, as Noo-Noo's own uninstall does, and the plist goes to the Trash with an undo record that puts it back.
- **The old apps.** LocoHost, WorkForest, Insomnia and Noo-Noo in `~/Applications` and `/Applications`, each checked by its bundle id. One confirm names them. On yes each is quit when it runs and goes to the Trash, each with its own undo record. `minmacs restore <rid>` puts one back. What failed goes in one alert.

With `MINMACS_HOME` set, launchctl runs only through `MINMACS_LAUNCHCTL_CMD` and the lid commands only through `MINMACS_INSOMNIA_CMD`. Under `MM_TESTS`, `MMUseNooNooAgentStatus` and `MMUseLegacyRunningApps` stand in for ServiceManagement and the running apps.

`test/store.sh` runs the import on the fixtures in `test/store/legacy`. `test/migrate.sh` runs the import, every restore and the follow-up on copies in `test/migrate/legacy` and fixtures it makes, inside a sandbox that refuses to read or write the real old apps' files.
