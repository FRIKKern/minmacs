# Round 192 to 196: the same information and behavior, other layouts

You are one of 5 design agents. Each makes **2 variants** from a copy of `p/187-b.html` "Gains Fill the Button". Your ID is one of 192 to 196, and your direction is the one under your ID below. The owner's Mac has 16 GB of RAM and many agents: keep one browser page open at a time and close it when done.

## What the owner said

Looking at 187: "I love this - but i think its because the information and how it put it out is really good. But maybe there are many other layouts out there? Maybe something smarter exist. We love the way things work."

So: **keep the information and the way things work. Change the layout.** Find an arrangement that is smarter than "graph and lists left, ring and button in the middle, graph and lists right".

## What must stay (the information and how it works)

- "N agents ask you" with the question, on top, only when something needs the person.
- **Memory in use · the last hour** and **Disk free · the last hour** as filled line graphs with their plain words ("up 2.26 GB", "an hour ago, 39.9 GB", "now, 42.2 GB").
- The five groups, each with its count and scrolling on its own with a still header, no More rows: Servers, Agents, Apps and helpers (memory); Worktrees, Caches (disk). Each row: icon for what it is, name, state word, CPU where known, its own small hour line, one number. "hours proposed" chips stay where they are.
- The ring: memory by holder inside, disk as the outer track.
- **Fix Everything as the one big glowing button** with memory back and disk back (never one number); the two thin lines that fill as each step lands; the honest pace; the short end words ("7 fixes done", "Skipped 2 agents that ask you and 4 blocked. Deleted for good.") that let go.
- Pointing at a row shows its story (with the page picture for a server) in the calm area, then the calm view comes back.
- Settings (gear, ⌘,) and Quit (power, ⌘Q) icons only. No Hide Icon. No header lines "Memory · every process…", no skip note at rest, no long caption.
- Zen: calm, roomy, joyful, the button is the focus. No cut lines, no ellipsis, nothing clipped, no empty middles; composed, not empty. The copy never claims a result. Plain names only, never old app names. Quiet / Busy / Peak, the live simulation and the Settings sheet keep working.

The menu still hangs from the menu bar icon on the 1280×800 stage; it may be any size that fits (up to about 1040 × 740).

## Directions

- **192 Tall and narrow.** a: one column about 440 px wide: button and ring on top, the two graphs side by side under it, then the five groups stacked, each scrolling. b: two columns about 640 px: left the ring, button and both graphs, right all five groups in one calm stack.
- **193 A hero band on top.** a: a full-width band on top holds memory graph, ring with the button, disk graph in one line; below it the five groups as five equal columns. b: the band holds only the ring and the button, large; the two graphs sit as the first thing in the memory columns and the disk columns below.
- **194 One group at a time.** a: the five groups are five quiet words in a row (with their counts and totals); one is open as a big roomy list, the ring and button beside it. b: the ring's slices are the way in: pointing at or pressing a part of the ring opens that group's list beside it.
- **195 The button at the bottom.** a: lists and graphs fill the menu top to bottom; a dock along the bottom holds the ring (small), Fix Everything (wide) and the two gains. b: the same dock on top, right under "agents ask you", so the button is the first thing under the menu bar icon.
- **196 Smarter.** Two of your own layouts that you believe are smarter than all of the above for this information (for example ordered by what the fix will touch, or memory and disk as two calm cards that open). Say in your JSON why it is smarter.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`): `p/187-b.html` (base; it layers `m187…` over `m182…`, `m174…`, `m164…`), `briefs/ZEN-BRIEF.md`.

## Output

Copy `p/187-b.html` into your two new files and change it. Keep its fixture data, live simulation, Quiet / Busy / Peak and Settings sheet. Never edit an existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Open with the menu down, at Busy. Name new functions with your ID (`m192…`); check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

## Verify

chrome-devtools MCP: `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800, your own pageId on every call, never touch pages you did not open. Scratch files in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/lay-<ID>/`. Screenshot Quiet, Busy and Peak at rest, a row hovered, the button hovered, mid Fix Everything and just after it. Look at each: is it calm, composed, is the button the focus, is every piece of information above still there? Run an overflow scan in all three: no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped, the menu inside the stage. Check the console has no errors, then `close_page`.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Layout: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts the code does not have yet>","surface":"menu"},
 {"file":"<ID>-b.html", ...}
]}
```
