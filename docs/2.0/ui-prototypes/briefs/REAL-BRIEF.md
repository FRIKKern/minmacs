# Round 55 to 57: Row Poster with real facts

The owner leans toward 53-b, Row Poster. Their words: "It is important that we are nuanced - because the design might be abit off compared to functionality - but we should understand its intentions." Then: "please set up realistic design".

This round keeps 53-b's intent and draws only what the 2.0 code knows or can know cheaply. Read `p/53-b.html` first. Read `p/54-a.html` for the Next sentence. Each page stays one self-contained file at the 1280 x 800 stage, with the sheet hanging from one menu bar icon, as in 53-b.

## What 53-b is for

- A 300 px list on the left keeps the whole picture. The picked row becomes a poster on the right.
- The poster answers three questions about one workstream: what is it doing, what does it hold, and what will Wrap Up take.
- Wrap Up is one undoable step. The poster must show exactly what it takes, and what blocks it.
- Performance, Settings and the Advanced tabs (Agents, Servers, Worktrees, Disk) use the same list and poster.

## The facts the code has

These are the only facts a page may show. Field names are in the Objective-C sources named.

**Agents** (`Sources/Core/Know/MMRegistry.h`, MMAgent).
- The tool: Claude Code, Codex, Cursor and others. The surface: terminal app, GUI app, IDE or daemon.
- The state is one of working, waiting or idle, with a short why such as "status file busy".
- The tree's CPU percent and memory footprint.
- The session from WorkForest: its title, when it started and when it was last active. The title is the real "stage" text. There is no live step text such as "writing route tests" or "tests running".
- A waiting agent's question is known only when the hook reports it, such as "Allow npm run build?".
- Subagents: the hooks report that one started. Show a count or a small dot, never a label.

**Servers** (`Sources/Experts/LocoHost/MMLHHost.h`).
- Name, framework, ports and bind address, and the package.json script such as "dev".
- The launcher, such as "pnpm dev · Claude Code · cmux".
- Its repo, branch and worktree, and whether that worktree is merged.
- CPU percent, memory footprint and process count.
- Connections now, new connections per sample, and the apps connected right now, such as Safari. A heartbeat graph shows new connections per sample over the last hour, kept in memory. Label it connections, not requests.
- State: active, recent or idle. Also when it was last active, whether it is orphaned, and whether it has duplicates on the same folder and branch.

**Worktrees** (`Sources/Experts/WorkForest/MMWFTree.h`).
- Repo, branch, and the maker: person, Claude Code, Cursor or Conductor.
- Merged state: ancestor, squash, pr and so on. Upstream state: pushed, gone or never pushed.
- Counts: dirty, untracked, stashes, unpushed, and commits not in the default branch.
- Disk bytes, the bytes deleting frees, and cache bytes inside it.
- The last commit, when it was last touched, how long it has been quiet, and the processes with a working directory inside.
- PR draft or open state is not known. Show merged or not merged only.

**Caches and leftovers** (`Sources/Core/Know/MMClutter.h`, `MMSizer.h`).
- Each item has a kind such as node_modules, .next, DerivedData or Playwright browsers.
- Its size counts APFS clones once.
- When it was last used, its owner path, and whether that owner is gone.
- Its state, with a why: live, kept, or may go.
- These are disk sizes. A map of them is a disk map, not a memory map.

**Wrap Up** (`Sources/Core/Act/MMAct.h`, MMWrapUpPlan). The plan for a worktree has parts in this order:
1. Servers: LocoHost stops the servers that run in it.
2. Helpers: MinMacs stops the helpers left in it, such as a headless browser whose parent exited. A browser the user opened is never a part.
3. Caches: Noo-Noo moves its caches and build output to the Trash.
4. Config: WorkForest moves its untracked config files, such as .env.local, to the Trash.
5. Worktree: WorkForest saves its ignored files, such as .env, and removes the worktree.

- Each part has a title, such as "Stop :3000 Python http.server".
- Each part can have a whyNot that blocks it, such as "3 commits not in main" or "unpushed changes".
- The plan has freedBytes on disk. Stopped servers and helpers free memory, which is a separate number.
- Undo restores the worktree at its commit and its saved files. It restarts each stopped server with the command its stop recorded, through a login zsh. A helper whose parent exited has no restart.

**Rules.** Off, Ask or Auto for each of Wrap Up, Apps, Leftovers, Servers and Worktrees. Some rules have an "after" value. Auto acts after that delay, and a countdown to it is real.

**Mac.** Keep working with the lid closed (Insomnia), One icon, Open at login.

## How to draw what the design overstated

- **Never add memory and disk into one number.** "Frees 1.4 GB disk · 380 MB memory" is right. A single "held 2.9 GB" is wrong. A bar uses one unit and names it.
- **Draw the Wrap Up bar or list from the plan parts**, in plan order, Config included. Show each part's title and a blocked part's whyNot.
- **Stage text is the session title or the state.** Do not write invented step text.
- **Make the Next sentence from real facts**, as in 54-a. Examples: "Asks you · Allow npm run build?", "Merged 2 h ago · Auto wraps it up in 22 h", "Blocked · 3 commits not in main".
- **Do not draw a timeline since 9:00.** There is no day log. "Since" values come from timestamps the facts hold: started, last active, last commit, merged.
- **Fixture names stay neutral.** Use repos such as atlas, lexicon, studio, speed. Never use client or company names.
- **Scale matters.** The owner runs 12 or more agents at once. The fixture has at least 12 workstreams, and the list must still read at that size.

## The three directions

- **55: Faithful.** This is 53-b as drawn, corrected to the facts above. Keep its composition, colors and motion, and change only what the facts force.
- **56: Plan first.** The poster leads with the Wrap Up plan as a short checklist. Each line says what the part does, what it frees, and what blocks it. The live state sits above it in one line with the Next sentence.
- **57: Twelve at once.** The list groups rows by what they need from you: Asks you, Working, Ready to wrap up, Blocked. Rows are compact so 15 workstreams fit. The poster is tighter, and the list carries a small live state on each row.

All three keep the 53-b look: dark glass, the tab colors, big numbers with a small gray unit, and live ticking. Each page says on itself, in a small caption, which facts it draws.
