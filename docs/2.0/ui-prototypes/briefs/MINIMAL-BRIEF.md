# MinMacs 2.0: minimal round brief (continue 41-b)

You are one of 6 design agents. Each makes **2 variants**.

## What the owner said

"I love 82 [= `p/41-b.html`, Corner Drawer Spotlight] - lets continue that direction - also sidebar - we want to try very minimalistic - try abit different things - but very clean and simple. Making total window smaller. What i dont like in 82 is servers tab - we should be able to fill it up - show a cool graph or something"

## Start here

Open and study `p/41-b.html` in a browser (served at `http://127.0.0.1:8765/p/41-b.html`), clicking every tab, the corner drawer, the live simulation and the actions. Copy it into your new files (never edit 41-b itself) and continue from it. Keep what the owner loved: the Workstreams spotlight (ready workstreams as big cards listing exactly what Wrap Up stops and removes, with the clock the rule counts from), live tiles with hover cards, the corner drawer that lights what the rule would act on, the live simulation (things spawn, finish, timers count), plain-word modes and buttons, Undo, and Keep Awake as one checkbox ("Keep working with the lid closed" + gray note on 20 % battery, Wi-Fi, heat).

Background and rules from earlier rounds: `WORKSTREAMS-BRIEF.md` (its "Owner update" section is current), `COMPOSE-BRIEF.md`, plus fixture data in `BRIEF.md` and `WORKSTREAMS-BRIEF.md`, all in `<scratchpad>/gallery/`. Plain names only (Workstreams, Agents, Apps, Servers, Worktrees, Disk).

## This round's three musts

1. **Smaller window.** Aim for about 600 × 460 for the whole sheet, never above 660 × 520. Fewer, better things; nothing cramped. Every tab must still read clearly at that size; move detail into hover cards and the drawer.
2. **Very minimal sidebar,** clean and simple, in the style your assignment names. The sidebar still lets you switch between the 6 tabs and still gives a live glance (a count, a dot, a tiny mark), but much quieter than the Live Index.
3. **Servers tab filled with a cool graph** that means something in plain words. Servers fixture: :3000 next dev 412 MB in use (speed-3), :5173 vite 188 MB in use (speed-3), :4100 phoenix 260 MB in use (bp-lane-c), :3334 sanity 640 MB idle 40 m (studio-parity), :4000 phoenix 290 MB idle 2 h (fix auth redirect, merged), :6006 storybook 520 MB idle 3 d (nobody), :5432 postgres 140 MB kept (Docker). Live: requests arrive on in-use servers, idle timers count up, :5174 may start. The graph must make "which servers are busy, which are idle and what they cost" obvious at a glance, with the idle rule (stop after 2 h) visible on it.

Also fill the other tabs well at the smaller size: each tab should feel full and composed, with no empty corners.

## Output

Two self-contained HTML files (full `<!doctype html>`, inline CSS/JS, no network except optionally Google Fonts; font stack `-apple-system, "SF Pro Text", system-ui`; no emoji; inline SVG icons):

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Same 1280×800 stage, faked menu bar, the sheet hanging from its icon. Interactions with Undo, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot every tab (save with `filePath` in the scratchpad and look at each), `close_page` on your own page. Never touch pages you did not open. Revise until every tab is clean, full and simple. Check clipped text and console errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Minimal: <sidebar idea> · <servers graph>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence: the sidebar and the servers graph>","good":"<one sentence>","tradeoff":"<one sentence>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
