# MinMacs 2.0: composition round brief

You are one of 6 design agents. Each makes **2 variants**. This round is about **composition**, not features.

## What the owner said

"We have to be more creative, it is so boring that this thing is always the same in same position - [the Off / Ask / Auto block: three big words with an underline, a rule sentence under it, value words '1 h  4 h  1 day' under that, between two hairlines] - it feels out of place - we need perfect compositions"

The problem: every tab is a stack (insight, graph, rows, then the same settings block bolted on at the bottom). The settings block looks like a form glued under the content, and every tab has the same shape. The owner wants each view to feel **composed**: a deliberate layout with one focal point, a clear reading path, rhythm and asymmetry where it helps, where the setting is woven into the content instead of parked under it.

## What must stay (from earlier rounds, all owner requests)

- The **Hanging Sheet** from the menu bar icon, ftop dark glass, the gradient desktop.
- **Left menu = Live Index:** large section names, each with its own mini live graph and a number with a mode verb. Study `p/20-a.html`.
- An **Agents** tab (7 agents + "5 more", each with tool, where, state, what it holds) plus Apps, Servers, Worktrees, Disk, Keep Awake. Plain names only.
- Each tab mixes **activity and settings**: what is going on right now (an insight sentence, the live graph, the items) and the mode Off / Ask / Auto with its rule and one value.
- **Hover any item to act on it**, and **section actions** that first light up what they touch, then act, with Undo.
- Every graph says in words what it means. Elegant and spacious, never cramped.

Read for content and data: `SHEET-BRIEF.md`, `ACTIONS-BRIEF.md`, `SETTINGS-BRIEF.md` and the fixture data in `BRIEF.md` (ignore its old app names), all in `<scratchpad>/gallery/`. Look at the latest round to see what exists and what to move past: `p/25-b.html`, `p/26-a.html`, `p/29-a.html` (served at `http://127.0.0.1:8765/p/<file>`). Look at ftop's images for the visual language: `<scratchpad>/ftop/docs/media/large.png` and `sizes.png`.

## How to work

1. Before any code, decide the composition of each tab on paper: grid, focal point, reading order, where the setting lives and why that spot. Write it as a short comment at the top of your file.
2. The setting must not be a generic block in the same spot on every tab. It can differ per tab if that serves each tab's content, as long as it reads as one system.
3. Perfect craft: a real grid and baseline, consistent spacing scale, optical alignment, no orphan words, no clipped text, calm type hierarchy (at most 3 sizes per view plus the big ftop numbers).

## Output

Two self-contained HTML files (full `<!doctype html>`, inline CSS/JS, no network except optionally Google Fonts; font stack `-apple-system, "SF Pro Text", system-ui`; no emoji; inline SVG icons):

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Same stage as before (1280×800 `#stage` scaled to fit, faked menu bar, "Tue 27 Oct 16:42"). All interactions work with Undo. Respect `prefers-reduced-motion`. No `alert/confirm/prompt`. `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot every tab (save with `filePath` in the scratchpad and look at each), `close_page` on your own page. Never touch pages you did not open. Judge each screenshot as a composition and revise until each tab looks deliberate. Check clipped text and console errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Compose: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence: the composition and where the setting lives>","good":"<one sentence>","tradeoff":"<one sentence>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
