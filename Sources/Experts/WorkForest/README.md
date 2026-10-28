# WorkForest

Git worktrees on the shared core, issue #24. WorkForest lists every worktree, says whether it is merged and what removing it frees, and removes what nobody needs, in a way that can be undone. It reads worktrees from Core's repo index in `MMFacts.worktrees`, git facts from `-[MMFacts gitFor:]`, disk facts from Know's `MMTreeDisk`, processes and their folders from the Senses sample, and sessions from Know. Reviews go through the Core broker, and removals through `MMRunAction` and `MMUndo`. It never samples, scans, runs git or asks the model on its own.

| File | What it holds | Ported from WorkForest 0.1 |
|---|---|---|
| `MMWFTree.h/.m` | The tree model, its words, the work keeps, and the menu, card, badge and accessibility state as specs. Pure, so `tools/render.m` draws it from fixture trees | `WFTree` in `Trees.h`, `WFWorkKeeps`, `WFCategory` and the words in `Forest.m`, the menu and card in `main.m` |
| `MMWorkForest.h/.m` | The `MMExpert`: trees and findings from the facts, the mode keeps, the remove action, the rules, the review request, WorkForest 0.1's records, the menu view and the app's watchers | `WFMustKeep`, `WFPlan`, `WFCandidates` and `WFRemove` in `Forest.m`, the prompts and facts in `Review.m`, `watchEvents` and `decide` in `main.m` |
| `MMWFCLI.m` | The verbs | `RunCLI` in `main.m` |

## Findings

One finding per checkout, kind `worktree`, id `workforest:worktree:<path>`. The stable key is the path, as the kernel names it. The instance key is HEAD. A main checkout is a finding with no proposal, so a server in it can link to it. Every linked worktree proposes Remove Worktree. Its reversibility is `MMReversibleBundle` when HEAD is on no remote, so decision 7 holds: Proactive keeps it, and Eager removes it only after a git bundle. Otherwise it is `MMReversibleRestart`, since the undo record recreates it at its commit. `MMReversibility` has no value of its own for that.

The fingerprint holds HEAD, the merge state, the upstream, the dirty, untracked and unpushed counts, whether HEAD is on a remote, whether anything runs inside, the session's age bucket, the quiet bucket, protected and locked. The finding's facts are the whole tree as JSON, for `--json`, the menu and the review.

## Keeps

- **Every mode, on fresh facts.** The main checkout, a missing folder, a worktree Cursor or Conductor made (decision 6), a protected branch, a lock, git facts not known yet, uncommitted or untracked files, commits on no remote that are not merged, a detached HEAD with commits no branch holds, a process inside, an agent session that works in it now or was active in the last day, a file change in the last day, files not walked yet, and a worktree made in the last day. HEAD that moved since the plan cannot be verified, so it stays.
- **Core's keeps.** No review, a failed or old review, a changed fingerprint, a timed keep and the `protect` list in `workforest/rules.json`.
- **The review.** Worked on after the review.
- **Proactive.** Not merged with the remote branch still there, or quiet for less than a week. A judged keep with evidence stays in every mode.
- **Manual.** Remove from the CLI or the menu runs the work keeps and Core's keeps, with no review needed.

`WORKFOREST_RECENT_HOURS` and `WORKFOREST_PROACTIVE_HOURS` change the day and the week, for tests.

## Removing and restoring

`MMRunAction` checks the action again, reads fresh facts, writes the undo record, then the action:

1. When HEAD is on no remote, `-[MMUndo bundle:]` takes a git bundle of the commits on no remote. No bundle, no removal.
2. The ignored files that are not caches, from `MMWorktreeIgnoredFiles`, are copied to the recovery folder with `-[MMUndo recover:]`. A `.env` is saved, and `node_modules` is not.
3. `MMWorktreeRemove` runs `git worktree remove` with no `--force`, so git refuses a worktree with changes, then `git branch -d` for a merged branch only.

`-[MMUndo restore:]` recreates the worktree at its commit, from the bundle when the repo lost it, then copies the saved files back without writing over anything. WorkForest 0.1's `removed.json` is imported into the undo log once per record, with its saved files left where 0.1 put them, so `restore <0.1 id>` still works. The 0.1 files are never changed.

## What the review gets

The routine schema in WorkForest's words: `active`, `stale` and `unsure`. Per worktree: repo, folder, branch, locked, detached, protected, who made it, the default branch, dirty, untracked, stashes, unpushed, commits not in the default branch, merged, upstream, whether HEAD is on a remote, the last commit's age, created, newest file and quiet days, disk, freed and cache sizes, the file count, process names, LocoHost's servers inside, and the agent session's agent, title, ages and whether it works now. No file contents, no `.env`, no first prompt, no transcript path and no environment. Core's `MMCompactFacts` redacts and clips every string again.

Two rules decide before the model: `workforest.holds-work` keeps a worktree with uncommitted work, commits on no remote, a process inside or a working session, and `workforest.locked-or-protected` keeps a locked one or a protected branch. Eager's judge gets WorkForest's own judge prompt.

## Verbs

`trees` and its other name `worktrees`, registered through `MMExpert`: `list [--all]`, `explain <path>`, `review [--model] [--mode] [--fresh] [--path]`, `plan`, `auto [--mode] [--path] [--review]`, `clean-up [--yes]`, `remove <path> --yes`, `restore <id|path>`, `removed`, `keep <path> [--days n] [--off]`, `protect <path> [--off]`, `prune <path>` and `rules`. Every command takes `--json` and `--dry-run`. A command that changes things needs the app, unless it is given `--dry-run`. That holds for `keep` and `protect` too, since a keep and the protect list change what the modes may remove. The verb is registered with `mutates:NO` because `list`, `explain` and the other reads run anywhere, so each changing command calls `needsApp` itself. `--fresh` sends every worktree to the model past the fingerprint cache.

WorkForest 0.1's syntax works under the `workforest` name through the shim in `Sources/CLI/MMCLI.m`: `list`, `explain`, `review`, `summary`, `auto`, `clean-up`, `remove`, `restore`, `removed`, `keep`, `prune`, `rules` and `fetch` become `trees` commands, and `mode` becomes Core's `mode workforest`. `openURL:` handles `workforest://review`, `clean-up` and `rescan`.

## In the app

`main.m` registers `MMWorkForestExpert.shared` through `MMBuiltInExpertClasses`. After the first findings, WorkForest observes snapshots on main. A review wakes every two hours by default, `workforest.reviewMinutes`, and for a new worktree, a worktree whose quiet time passes a week, a month or three months, and low disk, at most every 30 minutes. After a new review the mode's plan runs through `MMRunAction` on `no.guerrilla.minmacs.workforest.act`, and one `MMNotify` says what went. A finished background disk walk asks the graph for a rebuild.

## Left open

- Git facts come from `MMRepoIndex factsFor:wait:`, which another branch fills. Until it lands, `test/workforest.sh` feeds fixture git facts from `test/workforest/gitfacts.py` through `test/workforest/wfcli.m`.
- `MMGitFacts` has no last commit subject, so the subject is neither shown nor sent. WorkForest 0.1's check that a secret in the subject is redacted is run on the session title instead.
- The disk walk of `MMTreeDisk` runs in process on `no.guerrilla.minmacs.core.disk`, with an autorelease pool per walk. It belongs in the worker of P4, next to `sizeTrees:`.
- Process folders come from `-[MMSample cwdOf:]` for every process of the person's uid on each rebuild. A rebuild with a thousand processes reads a thousand folders.
- `viewFor:` reads the undo log, the keeps and the rules on main when the snapshot changes, as LocoHost's does.
- Sessions that only named a worktree in a parent folder's log, WorkForest 0.1's "a session named this folder", are not matched. Know's session index matches by working folder only.
- `fetch` is gone: MinMacs never fetches. The merged pull request check through `gh` is gone too.
- docs/REVIEW.md does not exist yet, so the list above stands in for WorkForest's part of it.
