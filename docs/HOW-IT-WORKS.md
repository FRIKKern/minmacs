# How MinMacs works

This page describes MinMacs 2.0 for a reader who does not read the code. [Sources/README.md](../Sources/README.md) and [Sources/Core/README.md](../Sources/Core/README.md) say the same for a reader who does, with the file for each part.

MinMacs is one app with two halves. Core finds out what is on the Mac. Five experts decide what that means for one kind of thing each, and show it in a menu. An expert never looks at the Mac itself. It only reads what Core found. So five experts cost one sampler, one set of file watchers and one place that asks the model.

## What happens every 5 seconds

1. **Senses** takes one sample of the Mac: every process with its CPU time, memory, arguments and folder, the open sockets, power, battery, heat, memory pressure and the lid. One sample cost 3.4 ms of CPU at the median when timed alone, and 6.2 ms on average inside the 30 minute bench of [BENCH.md](2.0/BENCH.md), on a Mac with about 865 processes.
2. **The graph** gathers that sample with what Know holds, and asks each expert for its findings. A finding is one thing an expert has an opinion about, such as one dev server or one worktree. Each finding names its owner: the worktree, the agent session or the app it belongs to. The graph then publishes one snapshot that holds every finding. The snapshot does not change after that, so the menus can read it at any time.
3. **The menus** draw from the last snapshot. They never wait for the disk, a process or the log.

A process that exits, an app that starts and a charger that comes or goes push a new build at once, without waiting for the 5 seconds. The sample backs off to 10 seconds on battery, 15 seconds when nobody has touched the keyboard or pointer for 5 minutes, and 30 seconds for both.

Much of a sample is carried over from the one before. A process with the same pid, start time, parent and name keeps its arguments and app. One that used no CPU time keeps its sockets for up to a minute. When nothing changed in what the experts read, the graph skips the build and keeps the last snapshot, for at most 30 seconds.

## The parts of Core

| Part | What it does |
|---|---|
| Runtime | The queues and timers everything runs on, jobs with time limits, a helper process for long disk walks, and a note of what ran last in case of a crash |
| Senses | The 5 second sample, the push signals for exits and power, and the folder watcher on FSEvents |
| Know | The things a sample cannot see: which processes are coding agents, their sessions and what each is doing, which terminal tab or pane runs a process, git facts for every worktree, disk sizes, and the clutter catalog |
| Graph | The snapshot of every finding and its owner, and the one builder that makes it |
| Store | The support folder, the prefs, the rules files and one SQLite log for undo records, review history and trends |
| Review | The review broker, the one place that asks a model, and Investigate. [REVIEW.md](REVIEW.md) describes both |
| Act | The modes, the keep checks, plans, actions, undo and the one notifier |

### Know

- **Agents.** A registry of known coding agents, kept as data in `registry/`, says how to spot each one from a process and how to tell if it is working. Sessions come from the files the agents write themselves, such as Claude Code's project folders and Codex's home. MinMacs installs no hooks into them.
- **Git.** A repo index walks the folders it is told to watch in the helper process, at start and every 10 minutes, and follows changes in between with FSEvents. A change inside one worktree marks only that worktree. Git facts come from git's own files where they can, such as `HEAD` and `packed-refs`, and from `git` runs off the main thread where they cannot. A warm scan of 100 worktrees took 0.2 seconds on the fixture of [MEASUREMENTS.md](2.0/MEASUREMENTS.md), section Git.
- **Merges.** WorkForest needs to know whether a branch is merged, also when it was squash-merged or rebased. Core keeps a patch id for each commit forever, so a new commit on the default branch costs one new patch id, not hundreds.
- **Sizes.** The Sizer says what deleting a folder would free. It counts APFS clones and hard links once, only when every holder is inside what would be deleted.
- **Clutter.** The clutter catalog is a list of rows in `registry/clutter/`, one per kind of cache or leftover. Only a path a row names can ever be acted on, and a fixed list of system and home folders is always refused.

## The experts

An expert is one class that reads the snapshot. It gives Core four things: its findings, its rules, how to ask the model about a finding, and its menu, cards and CLI verbs as plain data. A shared kit in `Sources/UI` draws every menu and card, so all five look and behave the same way.

- **MinMacs** groups processes into the apps that own them, and lists apps by the close list and keep list in its rules. It spares an app an agent uses, such as a browser a test drives. It quits apps and closes noise tabs, and Restore brings both back.
- **LocoHost** lists every listening server on the Mac, with the folder, branch, framework and agent that started it, and who is connected. It stops a dev server nobody has used for a while. The undo record holds the command, so it can start the server again.
- **WorkForest** lists every git worktree and whether its branch is merged, by ancestry, the same tree, patches or a squash. It removes a worktree with `git worktree remove` and no `--force`, after it copies the ignored files that are not caches, such as `.env`, to a recovery folder. When the commits are on no remote, it saves a git bundle first. Undo recreates the worktree at the same commit and copies the files back.
- **Noo-Noo** lists caches, build output and the leftovers of agents and tools, with who owns each. Build output of a finished project goes first. Most items go to the Trash. A cache that belongs to a tool is cleaned with the tool's own command, after a copy into a recovery folder.
- **Insomnia** keeps the Mac awake while an agent works and lets it sleep 10 minutes after the last one stops. With lid mode on, it can also keep the Mac awake with the lid closed. On battery, guards pause that for a low battery, heat, a long time unplugged or a long time offline.

Findings of different experts meet through their owners. A dev server and a worktree that share a folder have the same owner, so WorkForest's card shows LocoHost's server, and the link opens LocoHost's card. **Wrap Up** uses the same link. For a worktree whose branch is merged and whose agent sessions all ended, it stops its dev servers, ends the helpers left in it, moves its caches to the Trash and removes the worktree, as one step with one undo record.

## Acting

Every action runs through one function in Act, `MMRunAction`. In order, it:

1. reads the facts again, fresh, and checks that the thing is the same one the menu showed
2. runs the keep checks, which keep anything with work in it, such as uncommitted files, a process inside or an active agent session. Each expert adds its own. What cannot be checked is kept
3. writes the undo record
4. acts: to the Trash, to a recovery folder, through the owning tool's own command, or by a stop signal

A stop sends SIGTERM first. SIGKILL comes only on a second request, and the pid and start time are checked before each. MinMacs never empties the Trash.

The modes decide what an expert does without being asked. Idle acts on nothing. Proactive, the default, acts on what is clearly safe. Eager also acts on what the judge lets go. No mode acts on its own in the first day after the first launch. A notification is sent only after an expert acted without being asked, and it carries one Undo button.

## The app and the CLI

The app starts Core once, makes one menu bar icon per expert and opens a socket, `core.sock`, in the support folder. Only processes of the same user may connect. The CLI is the same binary. When the app runs, the CLI sends it the verb and prints the answer. When no app answers, the CLI builds a snapshot itself. A verb that would change something needs the running app, unless `--dry-run` is given. [CLI.md](CLI.md) lists every verb.

In a debug build, or with `MINMACS_WATCHDOG=1`, a watchdog logs every pass of the main thread's run loop that takes longer than 50 ms, with the stack of where main was.
