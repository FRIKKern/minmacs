# Round 82 to 87: a hero on top of 77-a's tabs

You are one of 6 design agents. Each makes **2 variants**. IDs 82 to 87 are reserved for this round.

## What the owner said

"I love 77-a, but top part of each should be showing more overall details - abit more like an hero above - also cool way to grasp it all in a beautiful way"

- **77-a** is `p/77-a.html`, "List and Detail": in Advanced mode, Agents, Servers, Worktrees and Disk each have one focal line with its button on top, then a compact list on the left grouped by state, and a large live detail of the picked item on the right (graph, facts, panels, actions).
- The owner loves that, but the top is only one line. It should be a **hero**: a beautiful band above the list and detail that shows the whole section at a glance (how many, in what state, what it costs, how it changes, what needs you), so you grasp it all before you look at any one item.

So: keep 77-a's list and detail, and give each of the four Advanced tabs a hero on top, in the style your assignment names. The focal sentence and its button stay inside the hero (they are the "what to do now"), but the hero adds the overall picture.

## The hero

- Shows the **whole section**, not one item: for Agents, every agent's state, their load on the Mac, where they run, subagents arriving; for Servers, busy vs idle, memory, connections, the idle rule and its next action; for Worktrees, every tree by fate, disk, dirty and unpushed work, what the rule takes; for Disk, used and free, what fills it, what may go, Trash vs own command.
- **Beautiful first.** ftop's look: dark glass, round badges with arcs, a big number with a small gray unit, quiet labels, one accent color per section. Calm, not busy. Every graph says in words what it means.
- **Live.** It moves with the simulation: numbers tick, marks arrive and leave, bars ease.
- **Connected.** Hover a part of the hero and the list below lights the items it means; hover a list item and its mark in the hero lights. Click a part to filter or pick.
- About 180 to 260 px tall on the 1040 × 760 sheet. The list and detail below get less height, so tune them to stay clean (fewer lines per row, the detail's lower panels can fold). Nothing cut, nothing cramped, no empty middles. Check Quiet, Busy and Peak.
- The same hero idea on all four tabs, so the tabs feel like one family, with content that fits each section.

Off / Ask / Auto stay explained in plain words where you choose them, with the countdown. Every action previews, acts, offers Undo. Keep Awake stays one checkbox.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/77-a.html`: it opens in Advanced mode on Agents; click Servers, Worktrees and Disk, and Quiet / Busy / Peak.
- `p/71-a.html` Performance tab (shown as Apps): its meter row is the owner's favorite style of numbers.
- `briefs/LIFT-BRIEF.md` (the space rules from the last round), `briefs/REAL-BRIEF.md` (facts the 2.0 code has, and the rules: never add memory and disk into one number, disk sizes with clones counted once). A fact the code does not have is listed in your JSON as proposed and marked "proposed" on the page.
- Plain names only: Workstreams, Agents, Apps, Servers, Worktrees, Disk. Never the old app names (not even in visible notes; say MinMacs).

## Output

Copy `p/77-a.html` into your two new files and change the four Advanced tabs. Never edit `p/77-a.html` or any other existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Keep opening on Advanced mode and Agents. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot each of the four tabs in Quiet, Busy and Peak with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`, look at each, `close_page` on your own page. Never touch pages you did not open. Check empty areas, clipped text, overlaps and console errors, and fix them.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Hero: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
