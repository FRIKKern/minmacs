# Store

The support folder, the prefs domain, rules files, state files, the SQLite log and the migration from MinMacs 1.2 and LocoHost. Issue #19. The headers are `MMStore.h` and `MMLog.h`.

| File | What it holds | Ported from |
|---|---|---|
| `MMStore.m` | `MMSupportDir`, `MMExpertDir`, prefs on `no.guerrilla.minmacs`, `MMStateFile`, `MMRules` | LocoHost `LHSupportDir` and `SaveActivity`, WorkForest `WFRules`, MinMacs 1.2 `Match` |
| `MMLog.m` | The append-only log in `minmacs.sqlite`, and trend points | Noo-Noo `audit.go`, in SQLite per decision 5 |
| `MMMigrate.m` | `MMLegacyPlan` and `MMImportLegacy` | The file and pref shapes of LocoHost and MinMacs 1.2 |

## Where things live

- The support folder is `~/Library/Application Support/MinMacs`, or `$MINMACS_HOME`. Each expert has a folder in it, such as `locohost/`.
- Prefs go to `no.guerrilla.minmacs` through CFPreferences. With `MINMACS_HOME` set they go to `$MINMACS_HOME/Preferences/no.guerrilla.minmacs.plist`, so a test never writes the person's prefs.
- Keys carry the expert, such as `locohost.mode`. `review.model` and `core.oneIcon` belong to the Settings window. An icon's shown state is AppKit's own key, `NSStatusItem Visible minmacs.<expert>`.
- `rules.json` keeps each named list at the top level. `_defaults` lists every default it ever added, so a default the person removed is not added again.
- The log is one table of rows. Triggers refuse `UPDATE` and `DELETE`. A new state of a record is a new row with the same `rid`. Trend points sit in their own table, one per bucket.

## The migration

`MMImportLegacy` reads, and never writes, what the old apps leave:

| Old | New |
|---|---|
| `locohost.*` prefs | the same keys, and `locohost.model` becomes `review.model` |
| `minmacs.*` prefs of 1.2 | the same keys. 1.2 used the same domain, so on the person's own Mac they are already in place |
| `NSStatusItem Visible Item-0` of each app | `NSStatusItem Visible minmacs.<expert>`, so a hidden icon stays hidden |
| LocoHost `rules.json` | `locohost/rules.json`, with `protect.names` and the other nested lists as flat names |
| LocoHost `activity.json` and `keep.json` | `locohost/activity.json` and `locohost/kept.json` |
| LocoHost `closed.json` | one `undo` row per stopped server in state `done`, with its restart command |
| LocoHost `review.json` | one `review` row |
| MinMacs 1.2 `rules.json` | `minmacs/rules.json`, wildcards kept |
| `minmacs.closedBundleIDs` and `minmacs.closedTabs` | one `undo` row per app to relaunch, with its tabs |

Each source is imported once, and the `core.migrated` pref records when. A 2.0 file that already exists is left as it is. `test/store.sh` runs it on copies of the fixtures in `test/store/legacy`.
