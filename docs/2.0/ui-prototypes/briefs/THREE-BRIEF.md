# MinMacs 2.0: more space + three tabs, brief

You are one of 6 design agents. Each makes **2 variants**.

## What the owner said

"Nice, lets have versions with more space - and i also want versions where we try to make Workstreams be the only tab we need. So that we have Workstreams, Performance & Settings. Inside of settings we can switch to "Advanced mode" which is the mode we have where we have all the tabs back again"

## Context you must read first

All in `<scratchpad>/gallery/` (pages served at `http://127.0.0.1:8765/p/<file>`):
- `p/41-b.html`: the owner's favorite (Corner Drawer Spotlight): Workstreams spotlight cards listing exactly what Wrap Up stops and removes, live tiles with hover cards, the corner drawer, the live simulation, plain-word modes, Undo, the lid checkbox. Click through it in a browser.
- The minimal round, `p/43-a.html` to `p/48-b.html`, and `MINIMAL-BRIEF.md`: smaller sheets, minimal sidebars, Servers graphs (heartbeat lanes, memory map, flow, port clock, stacked area, drift).
- `WORKSTREAMS-BRIEF.md` (its "Owner update" section is current: real time, obvious actions, Keep Awake is one checkbox "Keep working with the lid closed" with a gray note on 20 % battery, Wi-Fi, heat, no values), `COMPOSE-BRIEF.md`, and fixture data in `BRIEF.md` and `WORKSTREAMS-BRIEF.md`.
- Owner-starred older pages you may borrow from: `p/04-a.html` (Fate Rows: CPU and memory bars whose colored end is what MinMacs Now frees, apps grouped Will close / Unsorted / Kept / Spared), `p/14-b.html` (Settings as one sentence), `p/15-a.html` (refined native grouped list), `p/09-a.html` (Workstream Cards), `p/03-b.html` (hover card).

Rules that hold: plain names only; elegant, spacious, never cramped; every graph says in words what it means; hover any item to act, section actions that preview what they touch, Undo; Off / Ask / Auto explained in plain words where you choose it, with a live countdown to the next automatic action; buttons name exactly what they do ("Wrap Up 2 Workstreams · 4.4 GB").

**More space:** every variant this round uses a roomier sheet than the minimal round: about 760 × 580 (between 720 × 540 and 840 × 620).

## Three-tab structure (agents 51–54)

- **Workstreams**: the tab you need. Every workstream shows everything it holds: its agents (with live state, subagents arriving and leaving), servers (busy/idle, with a small version of a good servers graph), worktree and PR, caches, headless browser; with hover actions (Go to Tab, Wrap Up, Stop Servers, Open PR, Keep, Open in Editor). Stuff no workstream owns gathers in a calm **Leftovers** area (:6006 storybook idle 3 d, bp8-sweep-studio403 stale, DerivedData of gone projects, npm cache, Docker build cache…) with its own action ("Clean Up Leftovers · 31.4 GB"). The setting for Wrap Up lives here, woven in, not bolted on.
- **Performance**: what is using the Mac right now: CPU and memory (the colored end = what MinMacs Now frees), the apps by fate (Will close, Unsorted, Kept, Spared with reason), MinMacs Now and Restore. Agents' load shows here too, linked to their workstream.
- **Settings**: short and plain. The modes for Wrap Up, closing apps and leftovers (Off / Ask / Auto, each explained), the lid checkbox with its note, One icon in the menu bar, Open at login, and **Advanced mode**. Turning Advanced mode on animates the full tab set back in (Workstreams, Agents, Apps, Servers, Worktrees, Disk, with Performance folding into Apps or staying, your call) and each advanced tab works; turning it off folds them away again. Make that transition a delightful, clear moment, and show in plain words what Advanced mode adds.

The tab switcher for three tabs should be very simple (three words, three icons, or a segmented control). With Advanced on it grows to the full set.

## Output

Two self-contained HTML files (full `<!doctype html>`, inline CSS/JS, no network except optionally Google Fonts; font stack `-apple-system, "SF Pro Text", system-ui`; no emoji; inline SVG icons):

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Never edit existing pages; copy what you reuse. Same 1280×800 stage, faked menu bar, the sheet hanging from its icon, live simulation, Undo, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot every tab (and Advanced on/off) with `filePath` in the scratchpad and look at each, `close_page` on your own page. Never touch pages you did not open. Revise until every view is clean, full and simple. Check clipped text and console errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"<More space | Three tabs>: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
