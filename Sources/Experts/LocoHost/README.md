# LocoHost

Localhost servers on the shared core, issue #22. LocoHost lists every server, says where it runs and who uses it, and stops what nobody needs. It reads processes, sockets, args and cwd from the Senses sample in `MMFacts`, agents from the registry, sessions from Know and places from Know's Where. Reviews go through the Core broker, and stops through `MMRunAction` and `MMUndo`. It never samples, scans or asks the model on its own.

| File | What it holds | Ported from LocoHost 0.1 |
|---|---|---|
| `MMLHHost.h/.m` | The host model, its words, and the menu, card, badge and accessibility state as specs. Pure, so `tools/render.m` draws it from fixture hosts | `LHHost` in `Ports.h`, the menu and card code in `main.m` |
| `MMLHScan.h/.m` | Hosts from the facts: listeners, the process tree, launchers, clients, connections, activity, rules, git's own files and the allowlisted project files | `-[LHScanner sample]` in `Ports.m`, `Rules.m`, `Project` in `Intel.m` |
| `MMLocoHost.h/.m` | The `MMExpert`: findings, the mode and manual keep checks, the stop action, rules, the review request, the menu view, and what wakes a review in the app | `Candidates`, `MustKeep`, `Plan`, `AutoStop` and `watchEvents` in `main.m` |
| `MMLHCLI.m` | The verbs | `RunCLI` in `main.m` |

## Findings

One finding per listening process, kind `server`, id `locohost:server:<stableKey>`. Decision 8 sets the stable key: the project folder and the package.json script, such as `~/code/app#dev`, else the folder and the port. A second server with the same key adds its port. The instance key is `pid:start`. The fingerprint holds the instance, the state, whether a client has it open, duplicates, the protect list, whether its agent session is fresh, and how long it has been quiet, in the graph's age buckets. The finding's facts are the whole host as JSON, for `--json` and the menu. The proposal is Stop Server, reversible by restart.

## The idle tick, issue #52

- `inputDigestFrom:` digests what the hosts are built from: the listeners and the connections to or from a listening port, each listener's tree with each process's start, a CPU band and its memory in 16 MB steps, the parents above it, each agent and its state, and the session, worktree and git objects. When it matches, the graph hands back the last findings. A server tree at 10 % CPU or more always builds, since two busy samples in a row mark a server busy, and so does a server that still waits for its first place.
- Know's Where works out a new place in the background on every call. A rebuild asks it once a minute per server, and once more 10 seconds after the first ask, and reuses the last answer in between.
- The stopped records come from the undo log only after `MMLogStamp()` moved. `MMLHQuote` makes its character set once, and the env lookups use `getenv`.

## Keeps

- **Every mode.** Not a dev server, protected, used within the quiet threshold, younger than 30 minutes, or its agent session active in the last hour. A server that restarted since the plan cannot be verified, so it stays.
- **The review.** Used after the review. Core adds no review, a failed review, an old review, a changed fingerprint, a timed keep and the `protect` list.
- **Proactive.** A live agent above it, or quiet for less than six hours.
- **Judged evidence.** A judged keep with evidence stays in every mode, and the plan says what the evidence is.
- **Manual.** An action the person asks for only checks that it is still the same server.

SIGTERM goes first. `MMStopKill` reaches only what got SIGTERM on an earlier request, which Core records in `core/term-sent.json`. The stop record holds the command, the folder, the port and the framework, so `restore` and `restart` start it again through `MMUndo`.

## What the review gets

The routine schema in LocoHost's words: `in_use`, `idle` and `unsure`. Per server: ports, bind, kind, framework, the command line redacted and cut at 400 characters, the project, branch and worktree, the launcher, the agent, whether its parent exited, uptime, CPU now, memory, process count, connections and new connections, clients, busy, minutes since activity, minutes watched, minutes since the repo was touched, protected, duplicates, the quiet threshold, waste as CPU minutes, an energy rank and memory held, and for dev servers the project files and the agent session.

The project files are the package.json name, description and script, the README's first heading and paragraph, the mix.exs app, and the names of config files. The session is the agent, the title, when it started and was last active, and how it matched. The first prompt, the transcript path, `.env` files, other file contents and the environment are never read or sent. Core's `MMCompactFacts` redacts and clips every string again. docs/REVIEW.md does not exist yet, so this list stands in for LocoHost's part of it.

Two rules decide before the model: `locohost.not-a-dev-server` keeps services and high-port listeners, and `locohost.in-use-now` keeps a server with a new request or real CPU work right now.

## Verbs

Registered through `MMExpert` as `MMVerbSpec`. The 2.0 verbs are `hosts [port]`, `where <port>`, `review` and `restore [record id|port]`. The 1.x verbs keep their names and options, so `locohost list` and the rest work when the binary runs as `locohost`: `list`, `who`, `explain`, `ready`, `free`, `waste`, `summary`, `auto`, `mode`, `idle`, `close-idle`, `close`, `open`, `stopped`, `restart`, `keep` and `rules`. A verb whose usage starts with `locohost ` is one of those. Every verb takes `--json` and `--dry-run`.

The verb block reads its words from `-[MMArgs all]` and prints through `MMArgs`, so a verb handed to the app over core.sock prints in the person's terminal. `test/locohost/lhcli.m` runs the verbs through the real registry, as the app does. `legacyName` is `locohost`, and `openURL:` handles `locohost://review` and `locohost://close-idle`.

A verb reads `MMArgs.snapshot`, or `MMArgs.settledSnapshot` when it reports CPU or new connections. In the app that is the current snapshot. In the CLI, Sources/CLI builds it from its cold fact source, `MMColdFacts`, which takes a sample a second after a first one that every expert saw, as 0.1 did. LocoHost has no fact source and never samples. Actions run on `no.guerrilla.minmacs.locohost.act`, never on main.

`minmacs help` lists only the 2.0 verbs that `minmacs` runs. `locohost help` lists the 1.x verbs too.

## In the app

`main.m` registers `MMLocoHost.shared` through `MMRegisterBuiltInExperts`. `MMRegisterExpert` ignores a second call with the same id. After the graph builds its first findings, LocoHost observes snapshots on main. A review wakes on the `locohost.reviewMinutes` schedule, 60 by default, for a dev server new for two minutes, at one, three and seven days of uptime, and on memory pressure. After a new review the mode's plan runs through `MMRunAction` and one `MMNotify` says what it did. The newest review is read from the log at most once a minute and handed to the graph with `saveReview:`.

## Left open

- `docs/REVIEW.md` does not exist. The list above is LocoHost's part.
- Git facts come from `MMFacts.worktrees` when Know has them, else from git's own files through Core's fact cache, with no git spawn. Both sit in one function, `MMLHGitOf` in `MMLHScan.m`, declared in `MMLHScan.h`. The git work replaces its body with `MMGitFacts`. Commit, dirty and upstream facts wait for that.
- The project files are read by LocoHost through Core's fact cache, from an allowlist. They belong in Know.
- The HTTP title probe of 0.1 is gone, so page titles are not shown or sent. A probe would belong in Senses.
- Energy is a rank, as DESIGN.md asks. `idleEnergyWh` is gone from `--json`, and `energyRank` is there in its place.
- `viewFor:` on main reads no file and no log. Each finding carries its timed keep in its facts, and Recently Stopped is read from the undo log in `findingsFrom:` on the graph queue. Go To runs `MMGoTo` on `no.guerrilla.minmacs.locohost.go`. A verdict shows only for the server instance it judged, through `MMLHVerdictFor`.
- The shell builds the shim for the `locohost` name. LocoHost only registers verbs, so `minmacs list` and other generic 1.x names are the registry's to scope.

## Legacy fixes 43 to 48

| Issue | What 1.2.1 fixed | Here |
|---|---|---|
| 43 | A choice for one app removed shared patterns | Protect toggles only this port's own entry, through `-[MMRules set:value:inList:key:]` |
| 44 | ignoreServing did not match wildcards | Every protect and ignore list matches through `MMRules`: exact, a trailing `*`, or `*text*`. `ignore.devApps` uses `Docker*` and the like |
| 45 | New defaults reached only old files | `MMRules` merges new defaults on every load and keeps a removed default out |
| 46 | CI did not run the tests on fixtures | `test/locohost.sh` runs in `./test.sh`, with fake claude, codex, tmux and cmux, and skips no check |
| 47 | The README did not match the code | This file lists the verbs and facts from the code |
| 48 | Registry rows declared `socket_activity`, which no detector reads | The same change on main: the rows and the schema drop it. LocoHost decides socket activity from Senses' sockets |

## Investigate, issue #35

The card of a dev server with a folder offers "Investigate…" after its main actions, so it often sits under More. The view carries each finding's last run from `MMInvestigations`, read from memory, and the card's note shows its answer. The action goes to `-[MMInvestigations ask:snapshot:confirm:failed:]`, which shows the cost and the model before anything runs. `Sources/Core/README.md` says how the run is scoped.
