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

## Round 58: Holdings Map with real facts

The owner also wants to try 54-b, Holdings Map, with real facts. Read `p/54-b.html` as the base, and read the facts above.

**What 54-b is for.** You see ownership. A line from a workstream to a server, worktree or cache means the workstream owns it. No line means it is a leftover. Turning Advanced on lifts the same holdings out into their own tabs.

**How each element maps to facts:**
- **The lines.** Draw a line only where a fact links the two things. A server links through its worktree or repoRoot field, and an agent through its cwd inside the worktree. A cache links through its ownerPath. A leftover is an item with no owner, or whose owner is gone.
- **The agent ring.** It breathes while working and turns white while waiting. Idle has its own calm look.
- **Subagents.** The hooks report only that one started. Draw small dots that appear when one starts. They never fade on an end event, because no end event exists. The dots clear when the agent's turn ends.
- **Server ripples.** A ripple shows a new connection in a sample, not a request. Ripple size can follow the newConnections count.
- **The worktree node.** It shows merged or not merged, with the merge kind. It does not show PR draft or open state.
- **Cache nodes.** These are disk sizes, with clones counted once.
- **Browser nodes.** The owner loves these, so they stay and get richer. The facts behind them are real.
  - MinMacs reads every tab's URL, title and host per browser process: Chrome and the other Chromium browsers, and Safari (`Sources/Experts/MinMacs/MMMinMacs.h`, MMMinMacsTab). It cannot read Arc or Firefox tabs.
  - A tab whose host is localhost or 127.0.0.1 on one of a workstream's server ports belongs to that workstream. Draw it as a browser node on the server's line, such as "Chrome · 3 tabs on :3000".
  - LocoHost knows which apps are connected to a server right now (MMLHHost clients, such as "Safari ×2"). A node can glow while its browser has a live connection.
  - A headless browser helper whose parent exited also belongs to the workstream. It is a Wrap Up part that MinMacs stops.
  - MinMacs can close tabs by id and reopen their URLs on Undo. Closing a workstream's localhost tabs during Wrap Up is new: the code can do it, but no Wrap Up part does it yet. Show it as the plan's own line, "Close 3 localhost tabs in Chrome", marked new in the caption.
  - A browser the user opened is never stopped or quit by Wrap Up. Only its matching tabs close.
- **Ready islands and Wrap Up.** The Wrap Up button and its card list the plan parts in order, with any whyNot. Disk and memory stay two numbers.

**Scale is the open question.** The owner is afraid the map does not scale, because no prototype so far shows a lot of activity. Every page in this round has a scenario switch on the stage, outside the sheet, with three settings.
- **Quiet.** 4 workstreams and 2 leftovers.
- **Busy.** 12 workstreams, 16 agents, about 20 servers, 30 localhost tabs in two browsers, and 10 leftovers. Subagents start often.
- **Peak.** 20 workstreams, 28 agents with many subagent starts, 35 servers with ripples every few seconds, 60 localhost tabs, and 25 leftovers. Several agents ask at once, and two Auto wrap ups fire in the first minute.

Peak is the test. The map must stay readable and smooth there, with no overlapping labels and no frame drops visible to the eye. Say on the page what the design gives up to get there.

**Two directions:**
- **58-a: Faithful map.** 54-b as drawn, corrected to the facts. Keep the islands, the lines, the browser nodes, the Advanced pour-out and the motion. Make it hold up at Busy, and show what happens at Peak honestly.
- **58-b: Map at peak.** The map designed for Peak first. Islands pack by what they need from you: Asks you, Working, Ready, Blocked. A quiet island shrinks to a ring with a count. Hovering over an island, or picking it, expands it to full size with its nodes and browser tabs. Leftovers stay unowned at the edge, and a crowd of them merges into one bubble with a count.

## Round 59: Faithful map as a bento grid

The owner prefers 58-a, Faithful map, over 58-b. Their words, in Norwegian: "Størrelsen kan være litt sånn bentogrid, ved tanke på at ting som har flere detaljer kan ta mer plass osv - vi liker bedre faithful." In English: the sizes can be a bit like a bento grid, so things with more details take more space.

Start from a copy of `p/58-a.html`. Keep its look, its islands, lines, browser nodes, the Advanced pour-out, the motion and the Quiet, Busy and Peak switch. Keep every fact rule above. Only the layout of the islands changes.

**The grid.** The Workstreams body is a bento grid of tiles, one per island.
- A tile spans one, two or four cells, such as 1 x 1, 2 x 1 or 2 x 2, picked from what the island holds: its agents, servers, browser tabs, caches and helpers.
- A tile with more holdings is bigger, so its nodes and labels show in full and need no merge such as ":3000 +2".
- A small tile shows the name, the state and one line of counts, with no node field.
- Tiles pack with no holes, in a stable order, so a tile does not jump when one number changes.
- A tile changes size only when a holding is added or removed, and it animates to its new size.
- Leftovers are one tile at the edge of the grid.

**Two directions:**
- **59-a: Bento by holdings.** Tile size follows what the island holds, and nothing else.
- **59-b: Bento by holdings and need.** As 59-a, but an island that asks you something, or is ready to wrap up, gets one size step bigger, so what needs you is the largest thing on the sheet.

At Peak, both say on the page what they give up, as 58-a does.

## Round 60: the bento grid with room to breathe

The owner looked at 59-b and said: "far too tight - need more space". Their screenshot is `briefs/59-b-too-tight.png`. In it, tiles are 126 px cells with 8 px gaps, nodes sit on top of their labels, server labels and tab counts collide, and the session titles are cut at every tile edge.

Start from a copy of `p/59-b.html`. Keep its rules: tiles sized by holdings, one size step bigger for what asks you or is ready, ready first, stable order, no holes, the facts, the browser nodes and the Quiet, Busy and Peak switch.

**Room rules for both pages:**
- Tile padding is at least 16 px. Gaps between tiles are at least 14 px.
- A node never touches its label, and a label never touches another label or the tile edge. Leave at least 6 px around every label.
- Body text in a tile is at least 12 px, and captions at least 11 px.
- A session title or question gets its own full line and is not cut on a 2 x 1 or 2 x 2 tile.
- The scroll is fine. Readability wins over fitting everything in one view.

**Two directions:**
- **60-a: A bigger sheet.** The sheet grows to about 1040 x 760. Cells grow to about 170 x 88, in four or five columns. Move the stage caption and the scenario switch so the sheet still hangs from its menu bar icon on the 1280 x 800 stage.
- **60-b: Show less per tile.** The sheet stays about 760 x 760. Fewer tiles get full detail. Only what asks you, what is ready, and the one or two busiest islands get node fields. The rest are 1 x 1 summary tiles with a name, a state and one line of counts. Hover or pick opens the full island as a card. Use three columns, so each cell is wider.

**Leftovers move off the right side.** The owner said: "I dont think we should have leftovers on the right side like that". The right-hand Leftovers column is gone in both pages, and the grid takes the full width.
- Leftovers are one calm line pinned to the bottom of the Workstreams body, below the grid. For example: "Leftovers · 10 things nobody holds · 19 GB disk · 1.3 GB memory", with the Clean Up button at its right end.
- The line shows a few small chips for the biggest items, such as "DerivedData 14.2 GB", and a count for the rest.
- Pressing the line, or hovering it, opens a card that lists every leftover with its why, its size and its own action.
- Leftovers never look like a workstream tile, because nobody owns them.

## Round 60, part two: Settings for the bigger sheet

The owner picked 60-a, A bigger sheet: "I like the Bigger sheet one, but the settings panel need update to match the new size". Edit `p/60-a.html` in place. Change only the Settings tab, and Performance where it shares the problem. The Workstreams tab stays as it is.

The screenshots before the change are `briefs/60-a-settings-before.png` and `briefs/60-a-performance-before.png`. Settings still has the 760 px layout: one long column of rules, a narrow Mac column, and an empty lower half. Performance leaves a band empty at the bottom.

**What Settings holds**, as before, from the facts above:
- The rules, each with Off / Ask / Auto, what each mode does in one sentence, the "after" value chips, and a live line saying what it sees now. In simple mode these are Wrap Up workstreams, Close apps and Clean up leftovers. With Advanced on, add Stop idle servers and Remove merged worktrees.
- This Mac: Keep working with the lid closed, One icon in the menu bar, and Open at login.
- The Advanced mode card, with its four tabs and what each holds.

**How to use the room:**
- Lay the rules out as cards in a grid that fills the 1040 px width, with at least 16 px of padding and 14 px gaps, as the Workstreams tiles have.
- Each rule card can now show what that rule did today, from the undo records, such as "Auto wrapped up lane-e-sort at 14:02 · Undo". Show it only when something happened.
- This Mac and Advanced mode sit in their own column or row, and are not squeezed.
- The page fills the sheet without a big empty band. It scrolls only when Advanced adds rules and the room runs out.
- Performance uses the width for its two columns and lets them grow to the bottom, so no empty band is left.
