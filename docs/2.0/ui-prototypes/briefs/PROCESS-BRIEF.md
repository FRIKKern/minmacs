# Round 143 to 162: 138-a with more processes and a footer of icons

You are one of 20 design agents. Each makes **2 variants**. Your ID is one of 143 to 162, and your direction is the one under your ID below.

## What the owner said

"We want to see more inspired by 251 - but for example, i would like to see more of the processes. and i think [the footer] could become icons and take less space etc - play around - boil the ocean"

- Gallery 251 is **138-a "Two Halves, Ring Between"**: a 720 px menu from the MinMacs icon. Servers and memory on the left, Worktrees and disk on the right, 132-a's ring between them (memory by holder inside, disk as the outer track, the Mac's two numbers in its center), each half with its 4 biggest rows and a More row, the halves ending level. Under them the first fix in full and Fix Everything with its totals. The agent that asks is one line on top.
- **More of the processes.** Four rows a side is too few. The owner wants to see much more of what is running: servers, agents and their subagents, apps, helpers, and what each one costs.
- **The footer as icons.** "Hide Icon", "Settings…" and "Quit MinMacs" take three full rows (about 110 px). Make them three small icons that take far less space: hide, settings (gear), quit (power). Each says its name and shortcut on hover (Settings ⌘, and Quit ⌘Q), and works from the keyboard. This bends DESIGN.md's footer rule on purpose, at the owner's word.
- "Play around - boil the ocean": be bold within your direction. The two variants should differ clearly, and one of them may be wild.

## Keep from 138-a

- The two halves, memory left and disk right, ending level, with the ring between them. **Memory and disk are never one number.** Your direction may move or shrink the ring, but every part keeps a home on it, and pointing at a row lifts its slice.
- The first fix in full and Fix Everything, with each kind's pace, skipping what needs the person or is blocked, and saying why. Rewards are short and let go. Deletes say "for good". No Undo in the menu.
- The hover card beside the menu, with links that light the matching row.
- The copy never claims a result: no "The Mac is clean", "Everything is fine" or "Nothing needs you". Text shows only when something needs the person, such as "2 agents ask you".
- Keep working with the lid closed lives only in Settings.
- Plain names only, never the old app names (say MinMacs). ftop's look. Every graph says in plain words what it means.
- **No cut lines, ever.** No "...", no ellipsis, nothing clipped. Fit by shorter words, wrapping, or a wider column.
- The button always shows; the glow comes on hover. No dead buttons.

## The 15 points rule, loosened

127 to 142 held at most 15 points at rest. The owner now asks for more processes, so the cap is lifted **for process rows**. Keep it calm by how rows look, not by how few there are: one number per row, a second fact in small gray type at most, aligned columns, no badges at rest except on what needs the person, grouping and quiet dividers. The fixes area and the header stay as calm as 138-a. Write in your stage caption how many process rows show at Busy.

## Processes: what the code knows

Read `briefs/REAL-BRIEF.md` and `/Volumes/SATECHI/github/minmacs/Sources/Core/MMPerformance.h` (its top comment lists what Core does not measure). In short:
- **Servers:** name, framework, ports, launcher ("pnpm dev · Claude Code · cmux"), repo and branch, CPU, memory footprint, process count, connections now, state (active, recent, idle), duplicates, orphaned.
- **Agents:** tool (Claude Code, Codex, Cursor), state (working, waiting, idle), the tree's CPU and memory, the session title, subagent starts as a count, the question when one asks.
- **Apps:** each app's memory with its helper processes rolled up by responsible pid or parent, its fate (will close, unsorted, kept, spared).
- **Helpers:** found only inside a finished workstream's Wrap Up, such as a headless browser whose parent exited.
- **The last hour** (`minmacs history`): the Mac, disk, agent and server rings, agent states, subagent starts.
- Per-process child lists inside a server or agent tree, per-tab memory, and live step text are **not** known: mark them "proposed" on the page and in your JSON.

## Directions

Each direction is about showing more processes. **In both variants, the footer becomes icons**, and a and b place the icons differently (choose from: the header's top-right corner, beside the "asks you" line, in the ring's open bottom gap, at the end of the Fix Everything row, a slim icon strip at the bottom left, or your own idea).

- **143 More rows.** 8 to 10 rows a side, rows 22 to 24 px, tight but calm. a: the same layout as 138-a, just fuller. b: rows grouped by kind inside each half with thin headers.
- **144 Process trees.** A server or agent row opens to its child processes, indented. a: the two biggest open at rest. b: all folded, one line each with a child count, opening on hover.
- **145 Agents get a place.** Agents and their subagents are a third zone. a: under the ring, a row of agent chips with state and memory. b: the left half splits into Servers and Agents, side by side.
- **146 Activity Monitor.** The left half is one list of every process ranked by memory, like Activity Monitor, with its kind as a small mark. a: memory only. b: a column switch between memory and CPU.
- **147 Three columns.** Servers | ring | Worktrees, and under the ring a column of Agents and Apps. a: equal columns. b: the ring column narrow, the lists wide.
- **148 Tiles.** Processes as small tiles in a grid, sized or toned by memory. a: tiles in both halves. b: tiles for processes on the left, rows for worktrees on the right.
- **149 Bars in rows.** Each row has a thin bar of its share, so a long list reads at a glance. a: bars under the names. b: bars as the row background.
- **150 Live arrivals.** Processes arrive and leave visibly: a new one slides in with "new" in gray, a stopped one fades. a: a small feed of the last few arrivals under the ring. b: the lists themselves show arrival time as the second fact.
- **151 Halves that scroll.** Each half holds every process and scrolls calmly inside a fixed height, with the biggest on top and a sticky group header. a: one scroll per half. b: groups that fold.
- **152 A switch per half.** Each half has a small segmented switch: left Servers / Agents / Apps / Helpers, right Worktrees / Caches. a: text switch. b: icon switch.
- **153 Around the ring.** Processes sit around the ring as callouts at their slices, with lines to them. a: the 12 biggest around the ring, the lists below. b: the ring bigger, every process around it, no lists.
- **154 CPU and memory.** Each process shows CPU and memory as two small meters, and the header has a CPU line from the last hour. a: two numbers per row, CPU gray. b: a dot for CPU heat, memory as the number.
- **155 Ports.** Servers as a grid of ports (":3000", ":4000"), each cell toned by memory and state, with the framework under the port. a: ports grid left, worktrees list right. b: ports grid plus agents grid on the left.
- **156 By workstream.** Inside each half, rows group by workstream, so you see which work holds which processes and worktrees. a: groups with a thin label. b: a color per workstream shared by both halves and the ring.
- **157 Small ring, big lists.** The ring shrinks to a header strip or a small badge, and the room goes to processes. a: a 90 px ring in the header. b: no center ring, a thin split bar on top.
- **158 Tall menu.** The menu runs to the bottom of the stage, so each half shows about 15 processes. a: 720 px wide. b: 880 px wide with three columns of processes.
- **159 Rows open in place.** Each row opens inline to show its processes, ports, CPU, connections and owner, with the rest moving down. a: one open at a time. b: the first fix's rows open at rest.
- **160 Idle heat.** Rows toned by how long each process has been idle, so the ones to stop stand out among many. a: tone on the number. b: a small idle clock bar per row.
- **161 Who started it.** Group processes by who started them: Claude Code, Codex, Cursor, you, cmux, launchd. a: groups with counts. b: a small owner icon per row.
- **162 Wild.** Your own idea for showing every process in this menu. a and b two different wild ideas, still calm and readable.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/138-a.html`: the base. Hover rows, the ring, the card links, press Fix Everything, switch Quiet / Busy / Peak. Its code uses `m138…` names.
- `p/138-b.html`, `p/133-b.html` and `p/141-a.html` for other menus of the last round.
- `briefs/MENU-BRIEF.md` (last round's rules), `briefs/REAL-BRIEF.md` (facts), `../../DESIGN.md` (the menu standard, which this round bends where the owner says).

## Output

Copy `p/138-a.html` into your two new files and change it. Keep its fixture data, live simulation, Quiet / Busy / Peak and its Settings sheet (the gear icon opens it), so `go(tab)`, `setScn(k)` and `setAdv(v)` keep working. Never edit an existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Open with the menu down, at Busy, with fixes to do. Name new functions and classes with your ID so they cannot clash (`m143…`); check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji (draw icons as inline SVG), `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

## Verify

Twenty agents share one Chrome and one scratchpad. Use chrome-devtools MCP: `new_page` with `isolatedContext` = your ID and `background: true`, then `resize_page` 1280×800, and **pass your own pageId on every call**. Never select or close a page you did not open. Keep scripts and screenshots in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/proc-<ID>/`.

Screenshot the menu in Quiet, Busy and Peak, a row hovered with its card, the footer icons hovered, mid Fix Everything and the end of the run, and Settings open from the gear. Look at each. Run an overflow scan in all three scenarios, at rest, hovered and mid-run: no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped. Check the console has no errors, then `close_page` your own page.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Processes: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","process_rows_at_busy":<number>,"footer_icons":"<where the icons sit>","surface":"menu"},
 {"file":"<ID>-b.html", ...}
]}
```
