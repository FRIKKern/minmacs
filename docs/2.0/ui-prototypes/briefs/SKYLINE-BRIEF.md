# Round 164 to 173: 162-b's skyline, 158-b's last hour beside the ring, and round 163's lessons

You are one of 10 design agents. Each makes **2 variants**. Your ID is one of 164 to 173, and your direction is the one under your ID below. The owner's Mac is busy: only about 6 agents run at once, so keep one page open at a time and close it when done.

## What the owner said

"We are going to make many versions - we also love 162b - but on left and right of the center thing - we would like the 'memory in use' + 'disk free' from 158b - also learning from the one we just made as well"

- **Base: 162-b "Process Skyline"** (gallery 300). A 760 px menu. Over each half, a skyline draws every holder as one thin bar grouped by kind, taller holds more: memory on the left (servers, agents, apps, helpers, tabs, with pink dots for subagents and a white diamond for an agent that asks), disk on the right (worktrees, caches). Under each skyline, 138-a's rows (six a side), the ring in the middle.
- **Add 158-b's last hour beside the ring.** 158-b (and 158-a) show "The last hour" under the ring: "Memory in use · up 7.6 GB" as a filled line from "an hour ago" to "now", and "Disk free · down 6.1 GB" the same way. The owner wants these two **on the left and right of the center ring**: memory in use on the memory side, disk free on the disk side. Read `m158Hour` / `m158Hist` in `p/158-b.html`.
- **"The one we just made"** is round 163 on 149-a (`briefs/CENTER-BRIEF.md`; its pages `p/163-a.html` and `p/163-b.html` may still be in progress). Its owner rules hold here too:
  1. **Each group scrolls on its own** (Servers, Agents, Apps, Worktrees, Caches), header still, a quiet fade or overlay scrollbar, no More rows. The halves end level.
  2. **The fixes sit in the center, under the ring**: the first fix in full and Fix Everything with their memory back and disk back. The bottom strip holds what was in the center (caption, icons).
  3. **No Hide Icon.** Two icons only: Settings (gear, ⌘,) and Quit MinMacs (power, ⌘Q), name and shortcut on hover.
  4. **CPU matters more.** The Mac's CPU now (big number, small gray unit, heat) and its last hour, and CPU on the process rows.
  5. **Hover or select shows it in the center.** Pointing at a row or a skyline bar (or moving to it with the arrow keys) shows its full story in the center in place of the Mac's view: icon, name, big numbers, owner, its slice lit, facts, actions. Leaving brings the Mac back after a short beat. No side card.
  6. **A bigger center**, about 340 to 400 px; the menu may grow to about 960 to 1040 px wide.
  7. **Screenshots of localhost pages**: a server with a web page shows a screenshot of its page, big in the center on hover, with its URL under it. Draw made-up stand-in pages (Storybook-like, Next.js-like, Phoenix-like, Astro-like) from plain shapes, never copies of real sites.
  8. **Icons for what each thing is**: a framework mark for a server, the app's icon for an app, the tool for an agent, a branch for a worktree, the kind for a cache. Simple inline SVG stand-ins in the brand's color with a letter or shape, never copies of real logos.

## Keep everywhere

Memory and disk are never one number. Fix Everything's pacing, skipping what needs you or is blocked and saying why. Short rewards that let go, deletes "for good", no Undo in the menu. The copy never claims a result ("The Mac is clean" and its kind are banned); text only when something needs the person. Plain names only, never the old app names. **No cut lines, no ellipsis, nothing clipped.** No empty middles. Every graph says in plain words what it means. The lid setting only in Settings.

## Directions

- **164 Straight merge.** 162-b plus every point above, as plainly as possible. a: memory-in-use line left of the ring, disk-free line right of it, at the ring's height. b: the two lines wrap the ring as two arcs of their own, memory hugging its left side, disk its right.
- **165 Skyline is the list.** The skyline bars are tall and wide enough to be the main way in: point at a bar to see it in the center, rows below are a short scrolling list. a: skyline over each half. b: one long skyline across the whole menu top, split at the ring.
- **166 Three graphs a side.** Each side stacks the skyline, the last hour, and the group lists. a: last hour between skyline and lists. b: last hour beside the ring, CPU line under the ring.
- **167 Hour behind the skyline.** The last-hour line draws faintly behind each skyline as its backdrop, so now and the hour read together. a: line behind. b: the skyline bars are themselves the hour (each bar a minute) when no process is pointed at, and turn into processes on hover of the side.
- **168 CPU skyline.** A third skyline for CPU, under the ring or across the bottom, with the Mac's CPU last hour beside it. a: CPU bars by process. b: memory skyline bars carry a CPU tint on top.
- **169 Center as a stage.** The center is big (about 400 px) and always shows one thing large: the Mac at rest, a row's story on hover, the run during Fix Everything, a server's page screenshot. a: the ring stays small at the center top. b: the ring becomes the frame around the stage.
- **170 Icons first.** Every bar in the skyline carries its icon at its foot when wide enough, every row starts with its icon, and the center shows the icon big. a: icons on bars. b: an icon strip under each skyline (the biggest 12 holders) as a quick way in.
- **171 Screenshots everywhere.** Servers show their page screenshot as the row itself (a small card per server in a scrolling strip), apps show their window as a thumbnail. a: server cards in the memory half. b: a page strip under the ring.
- **172 Calm at rest.** Show the skyline, the two last-hour lines, the ring, the two fixes, and nothing else at rest; rows open when the pointer enters a side. a: the rows slide down under the skyline. b: the skyline grows into rows in place.
- **173 Wild.** Two of your own ideas that keep the skyline, the last hour beside the ring and round 163's rules.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`): `p/162-b.html` (base; its code uses `m162…`), `p/158-b.html` (the last hour), `briefs/CENTER-BRIEF.md` (round 163), `p/163-a.html` and `p/163-b.html` if they exist yet, `briefs/PROCESS-BRIEF.md`, `briefs/REAL-BRIEF.md` and `/Volumes/SATECHI/github/minmacs/Sources/Core/MMPerformance.h` (facts). Mark as "proposed" on the page and in your JSON: page screenshots, framework marks or favicons, app icons in the model, CPU of apps and helpers. The Mac's memory, disk and CPU over the last hour are real (`minmacs history`).

## Output

Copy `p/162-b.html` into your two new files and change it. Keep its fixture data, live simulation, Quiet / Busy / Peak and its Settings sheet (the gear opens it), so `go(tab)`, `setScn(k)` and `setAdv(v)` keep working. Never edit an existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Open with the menu down, at Busy, with fixes to do. Name new functions and classes with your ID (`m164…`); check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS/SVG, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

## Verify

Use chrome-devtools MCP: `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800, and **pass your own pageId on every call**. Never select or close a page you did not open. Keep scripts and screenshots in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/sky-<ID>/`.

Screenshot Quiet, Busy and Peak at rest, a server hovered (its page in the center), a skyline bar hovered, a group scrolled to its end, a fix hovered, mid Fix Everything, and Settings from the gear. Look at each. Run an overflow scan in all three scenarios, at rest, hovered, scrolled and mid-run: no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped. Check the console has no errors, then `close_page` your page.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Skyline: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts the code does not have yet>","surface":"menu"},
 {"file":"<ID>-b.html", ...}
]}
```
