# Round 175 to 184: more on 174, the last hour over each half

You are one of 10 design agents. Each makes **2 variants**. Your ID is one of 175 to 184, and your direction is the one under your ID below. The owner's Mac is busy: only about 6 agents run at once, so keep one page open at a time and close it when done.

## What the owner said

After 174: "More more". So this round explores more on **174** (`briefs/HOUR-BRIEF.md`):
- **174-a "Hour Over Each Half"**: a 1020 px menu. Over the left half, "Memory in use · the last hour · up 7.6 GB", a filled line from "an hour ago, 34.8 GB" to "now, 42.4 GB". Over the right half, "Disk free · the last hour · down 6.1 GB". Under each graph the groups scroll on their own (Servers, Agents, Apps and helpers; Worktrees, Caches), each row with its icon, CPU and one number. In the center, the ring alone, then CPU now with its last hour, Busiest now, and the two fixes. Settings and Quit icons in the bottom strip.
- **174-b "Hour Answers the Pointer"**: the same, and the graphs show a pointed row's share as a band and a fix's "after this fix" dashed line.

## Rules that hold (from 163 and earlier)

Each group scrolls on its own, header still, no More rows, halves end level. Fixes in the center. No Hide Icon: only Settings (⌘,) and Quit (⌘Q). CPU matters. Pointing at a row shows its story in the center. Page screenshots for local servers, icons for what each thing is (stand-ins, never real logos or sites). Memory and disk never one number. Every graph says in plain words what it means. Fix Everything's pacing and honesty; deletes "for good"; no Undo in the menu; rewards short. The copy never claims a result. Plain names, never old app names. **No cut lines, no ellipsis, nothing clipped, no empty middles.** The lid setting only in Settings.

## Facts

`minmacs history` keeps the last hour in memory: the Mac's memory and disk, the agent and server rings, agent states and subagent starts, and CPU. Anything beyond that (a per-process hour, more than one hour, a forecast, events the code does not log) is "proposed" on the page and in your JSON. See `briefs/REAL-BRIEF.md` and `/Volumes/SATECHI/github/minmacs/Sources/Core/MMPerformance.h`.

## Directions

- **175 Taller hours with a scale.** The two graphs grow taller and get a quiet scale. a: two or three faint GB gridlines with labels, min and max of the hour marked. b: no gridlines; the line's value shows under the pointer as you move along it ("16:22, 39.1 GB").
- **176 Events on the hour.** Mark what happened on the graphs: an agent started, a server stopped, Auto acted, a fix ran. a: small dots on the line with a word on hover. b: a thin event strip under each graph with marks by kind.
- **177 Time range.** A switch for the graphs: 1 h, 6 h, today (more than 1 h is proposed). a: one switch in the center that drives both graphs. b: each graph has its own small switch.
- **178 By kind over the hour.** Memory in use as stacked bands by kind (servers, agents, apps, other), disk free with worktrees and caches marked; the agent and server rings are real in the history. a: stacked areas. b: one line per kind, the total as the top line.
- **179 CPU's hour too.** CPU gets the same weight. a: a CPU last-hour graph across the bottom of the menu, under both halves. b: CPU as a thin line drawn over the memory graph, with its own scale on the right.
- **180 Now meets the ring.** Make the two "now" ends touch the ring. a: the disk graph runs mirrored (now on its left), so both nows meet at the ring and the ring reads as the present. b: the two graphs run as one band behind the ring, the ring sitting on "now".
- **181 What comes next.** Past "now", a dashed line: "after Fix Everything" and "at this pace" (proposed). a: both lines on each graph. b: only the after-fix line, with the time it lands.
- **182 Each row has its hour.** Each process row and worktree row gets a tiny sparkline of its last hour (proposed per row; the agent and server rings are real). a: sparkline before the number. b: sparkline as the row's background.
- **183 The pointed thing everywhere.** Pointing at a row lights it in the graph (its band, as 174-b), in the ring (its slice), in CPU (its share) and tells its story in the center, all at once. a: hover only. b: click pins one, so you can move the pointer while it stays.
- **184 Wild.** Two of your own ideas that keep the last hour over each half and the rules above.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`): `p/174-a.html` and `p/174-b.html` (base; they use `m174…` names on top of `m164…`), `briefs/HOUR-BRIEF.md`, `briefs/SKYLINE-BRIEF.md`, `briefs/CENTER-BRIEF.md`.

## Output

Copy `p/174-a.html` (or `p/174-b.html` when your direction builds on its pointer bands) into your two new files and change it. Keep its fixture data, live simulation, Quiet / Busy / Peak and its Settings sheet. Never edit an existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Open with the menu down, at Busy. Name new functions with your ID (`m175…`); check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

## Verify

chrome-devtools MCP: `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800, your own pageId on every call, never touch pages you did not open. Scratch files in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/hour-<ID>/`. Screenshot Quiet, Busy and Peak at rest, a row hovered, a fix hovered and mid Fix Everything. Look at each. Run an overflow scan in all three: no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped. Check the console has no errors, then `close_page`.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Hour: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts the code does not have yet>","surface":"menu"},
 {"file":"<ID>-b.html", ...}
]}
```
