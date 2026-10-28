# Noo-Noo

Developer clutter on the shared core, issues #28, #29 and #30. Noo-Noo lists caches, build output and leftovers from agents and tools, says who owns each and what deleting it frees, and cleans finished projects first. It reads `MMFacts.clutter`, the worktrees, their git facts and the sessions. It never samples, scans or asks the model on its own.

| File | What it holds | Ported from Noo-Noo 0.7 |
|---|---|---|
| `MMNNMenu.h/.m` | The menu, the cards and the growth line as specs, from a plain view. Pure, so `tools/render.m` draws it from fixture rows | `menubar/menu.go`, `heuristics/cache_velocity.go` |
| `MMNooNoo.h`, `MMNooNooExpert.m` | The `MMExpert`: findings, owner state, the policy, the rule, actions, the review request, the menu view, the mode after a review, and the verbs | `modules/dev`, `modules/caches`, `leaks/module.go`, `cli/*_cmd.go` |

## What Core holds for it

- **The catalog.** `registry/clutter/*.json`, one row per kind: the 52 rows of `docs/2.0/research/D-clutter.md`, plus `agent-trial`, `tmp-gocache`, `cocoapods-pods`, `python-pycache` and `minmacs-recovery`. `registry/clutter-schema.json` describes a row, and `test/noonoo/validate_clutter.py` checks each one. build.sh ships them in `Resources/registry/clutter`.
- **Know, `Core/Know/MMClutter.{h,m}`.** It loads the rows, expands `~`, `${cache:<tool>}`, `${claude}`, `${codex}` and `${support}` from env vars and the documented defaults, never by running a tool, and finds the items:
  - Build rows look inside the repo index's checkouts for their folder names, pruned at the first match, with a manifest beside them.
  - Leak rows carry NN's signatures: `agent-scratch` (session alive by `--session-id`, its transcript in the last 30 minutes, or Know's session index), `aged`, `open`, and `family` (5 or more mktemp siblings, 12 hours quiet, never `com.apple.`).
  - Nothing held open: `MMOpenUnder` reads each process's cwd, executable and open files through libproc, the in-process form of NN's `lsof +D`.
  - Whether git tracks a `dist` or `build` folder comes from `git ls-files` through `MMGit`, so the git is `MMGitPath`'s and the child runs through `MMRun`. It runs on `no.guerrilla.minmacs.core.clutter.git`, and only actions and verbs ask.
  - Owners come from back-links: DerivedData `WorkspacePath`, Playwright `.links`, simulator `lastBootedAt`, the session id, or the checkout that holds a build folder.
  - Sizes come from `MMSizer quick`, through the worker in the app.
  - Scans run on `no.guerrilla.minmacs.core.clutter`, a row at most as often as its `every` says, checked every 5 minutes, never on the 5-second tick. The last items persist in `core/clutter.json`, and `MMCore.m`'s fact source only reads them.
- **The walls, `-[MMClutterCatalog whyNot:kind:]`.** Only a path a listed row names may be acted on. Always refused: `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private/etc`, `/Applications`, `/opt`, `/dev`, `/Volumes`, ignoring case; the home folder, its parents, its first level and the shared folders under `~/Library`; the support folder and the test home; a symlink; another user's path; anything a row's `never` protects or a folder that holds one; a report or data row; a `dist` or `build` folder git tracks.
- **Act, `Core/Act/MMClutterAct.{h,m}`.** `MMClutterAction` runs through `MMRunAction`. Recheck reads the item again from disk and puts every path through the walls.
  - Cache, build and leak rows go to the Trash through `MMUndo`. Undo moves them back.
  - Tool rows first take an APFS clone of the row's folder into `<noonoo>/recovery/<rid>`, then run the tool's dry run and command through `MMToolCommand`. What the tool removed is listed as the record's recovery files, so undo copies it back. The `minmacs-recovery` row sends the copy to the Trash after 7 days.
  - Every record holds an audit of the paths before and after, and the statfs delta.
- **Trends.** Each scan adds one point a day per row to the log, `noonoo.disk.<row>`. `MMClutterTrendOf` is NN's day bucket and least-squares fit, plus the 7-day ratio of `cache_velocity.go`.

## Findings and order

One finding per item, `noonoo:clutter:<row>:<path>`. Finished projects come first: build output whose worktree is merged, squash-merged, lost its remote branch, is gone, or whose Claude Code session ended. Then leftovers, then caches and build output of active projects, then what stays. Within a section the order is what deleting frees.

The rule `noonoo.owner-state` decides every finding, so the model is never asked about clutter. Proactive cleans finished projects and leftovers. Eager adds caches. After a new review the app's watch on main takes the mode from the view `prepareFor:` made on the graph queue, so main reads no pref. A tool's own cleanup runs only when the person asks. An agent working in the project keeps its build output in every mode.

## Menu

The header is what deleting frees, then finished projects, what the Trash holds and the mode. The summary starts with the growth line when a row grows fast: at least `noonoo.growthMinBytes`, 1 GB by default, over the window, and doubling in a week or growing that much a week. Actions: Clean Finished Projects and Clean Leftovers. More holds Undo Last Clean and Scan Now. A card says why the item stays or how it goes and comes back, with the owner as a link row that opens WorkForest's worktree card. The link names the worktree by the repo index's path.

## Verbs

- `clutter [list | show <id|path> | trends | check <path> | scan] [--json] [--dry-run]` reads.
- `clean <id|path|row> ... | --finished | --leftovers | --undo [rid] [--json] [--dry-run]` changes things, so it runs in the app. A member of a temp family names the family.

`legacyName` is `noo-noo`.

## Checks

`./test.sh noonoo` builds `test/noonoo/tool.m` with Core, the kit, MMArgs and the expert. Its fixtures sit in `$MINMACS_HOME/nn<pid>`: a stand-in for `/` with a home, `/private/tmp` and `$TMPDIR`, a repo with a squash-merged worktree, caches, a simulator Devices folder, agent scratch, temp families, a code-sign clone and transcripts. `test/noonoo/fake-xcrun.sh` stands in for `xcrun simctl delete unavailable`. The tool refuses to run without a clutter root inside `MINMACS_HOME`. The section renders the menu and cards to `build/render/noonoo`.

## Left open

- The test still hands squash-merged facts over by hand. In the app they come from Core's repo index through `MMFacts`.
- The Chrome clone signature checks open files and executables, not NN's launch causality for hard-linked launchers. A clone a live Chrome holds through a hard link stays.
- pnpm's `.modules.yaml` `storeDir` is not read yet, so an unused store layout is not marked.
- Docker, Colima, OrbStack and Homebrew rows only report, since their commands change data in place that a recovery copy cannot bring back.
- The Trash frees nothing until the person empties it. The header says what it holds.
- docs/REVIEW.md does not exist. The review gets the row, class, section, state, owner state, members, freed MB, idle days and the reason.
