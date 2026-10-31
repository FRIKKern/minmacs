# Round 174: the last-hour graphs replace the skyline bars

You are the one design agent this round. Make **2 variants**, `p/174-a.html` and `p/174-b.html`, from a copy of `p/164-a.html` "Hour Beside the Ring". The owner pointed at one exact thing. Change that, keep the rest of 164-a as it is. Do not start a new layout.

## What the owner said

Round 164 to 173 put 158-b's "Memory in use" and "Disk free" last-hour graphs beside the ring. The owner meant something else: "I wanted to replace the bars on the left and right side with that graphs."

So:
- The **memory skyline** at the top of the left half (the bars by servers, agents, apps, helpers, tabs, with its legend line "51 processes. Taller holds more memory") is **replaced by the "Memory in use" last-hour graph**: a filled line from "an hour ago" to "now", titled "Memory in use", with "the last hour" and how far it moved ("up 7.6 GB"), at the full width of the half.
- The **disk skyline** at the top of the right half is **replaced by the "Disk free" last-hour graph** the same way ("Disk free · the last hour · down 6.1 GB").
- The two small graphs beside the ring go away, since they now live at the top of each half. The ring's row is just the ring.
- Every other part of 164-a stays: the scrolling groups with icons and CPU, the center with the ring, CPU now and its last hour, Busiest now, the two fixes, the story of a pointed row in the center, the Settings and Quit icons in the bottom strip.

Read `m158Hour` / `m158Hist` in `p/158-b.html` and how 164-a draws its two hour graphs, and reuse them.

## The two variants

- **174-a** is the plain change: the two graphs take the skylines' place and height, and the ring row is the ring alone, a little larger if the freed room allows.
- **174-b** is the same change, and the graphs answer the pointer: pointing at a row draws that row's own share as a darker band inside its side's graph (memory for a process, disk for a worktree or cache) where the code knows it, and pointing at a fix draws a dashed "after this fix" line on both graphs. Mark a row's own hour as proposed if the code does not have it.

## Keep everywhere

Memory and disk never one number. Each graph says in plain words what it means. No cut lines, no ellipsis, nothing clipped, no empty middles. The copy never claims a result. Plain names only. No Hide Icon. Fix Everything's pacing and honesty. Deletes "for good". The lid setting only in Settings.

## Output and checks

Keep 164-a's fixture data, live simulation, Quiet / Busy / Peak and its Settings sheet. Name new functions `m174…`; check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Never edit an existing page. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name. Open with the menu down, at Busy.

The owner's Mac is busy: one page open at a time. chrome-devtools MCP: `new_page` with `isolatedContext` = 174 and `background: true`, `resize_page` 1280×800, your own pageId on every call. Scratch files in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/hour-174/`. Screenshot Quiet, Busy and Peak at rest, a row hovered, a fix hovered and mid Fix Everything. Look at each. Run an overflow scan in all three: no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped. Check the console has no errors, then `close_page`.

Reply with ONLY this JSON:

```json
{"id":"174","direction":"Hour: the last-hour graphs replace the skyline bars","variants":[
 {"file":"174-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts the code does not have yet>","surface":"menu"},
 {"file":"174-b.html", ...}
]}
```
