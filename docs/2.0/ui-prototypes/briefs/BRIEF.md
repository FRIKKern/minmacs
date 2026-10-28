# MinMacs 2.0 UI prototypes: shared brief

You are one of 12 design agents. Each makes **2 prototype variants** of one direction. The owner wants to browse many alternatives in a gallery and pick favorites. Make each variant clearly different from the other, and both clearly yours.

## The product

MinMacs 2.0 is one macOS menu bar app with **five experts**, one shared core. Each expert keeps its own menu bar icon (or "One Icon" mode merges them into one flat menu).

| Expert | Field | Its color (suggested, may change) |
|---|---|---|
| MinMacs | Performance: apps, agents, RAM, CPU, energy, heat. Quits useless apps gracefully, trims noise browser tabs, Restore brings them back | blue `#5B9BFF` |
| LocoHost | Localhost servers your agents left running: port, owner, worktree, cost, idle or in use. Close idle | teal `#3FD0B8` |
| WorkForest | Git worktrees agents left behind: merged, stale, in use, what each holds. Remove with restore | green `#4CC96B` |
| Noo-Noo | Developer clutter: caches, build output, node_modules, DerivedData, leftovers. Clean to Trash | amber `#F2B544` |
| Insomnia | Keeps the Mac awake while an agent works, lets it sleep when nothing does. Lid-closed mode, battery/network/thermal guards | violet `#B18CFF` |

Experts help each other: a worktree knows its servers, a server knows its worktree, a cache knows its project, keep-awake knows which agent works. A **workstream** = one agent session (e.g. Claude Code in cmux tab "speed-3") with its servers + worktree + caches + browsers. **Wrap Up** a finished workstream = stop its servers, remove its merged worktree and its caches, in one undoable step.

Rules that shape the UI (from docs/DESIGN.md, the current standard):
- Nothing is closed that wasn't shown first. The menu is the plan. Every action has Undo/Restore.
- Every line earns its place. A number appears once. A row = name + at most three facts (owner · size · state). State marks differ in shape as well as color.
- Plain words. "Squash-merged", "Remote branch deleted", "1 commit not in main". Energy is a rank ("uses the most energy"), never watts.
- Hover card: title, colored status starting with a word ("Stays", "Goes at 18:00"), ≤5 aligned facts, ≤4 actions.
- Agent-used things are spared and the UI says why ("Playwright drives it").
- Current standard says native NSMenu, since a popover felt slow. **The owner now wants ftop as the inspiration**, so you may break from NSMenu. Say in your summary whether your design is an NSMenu, a popover, a floating panel, or a window.

## The inspiration: ftop

ftop (github.com/Nongfsq/ftop) is a small, quiet system monitor: one floating dark glass panel that works at any size. Look at these images before you design (use the Read tool on them):

- `<scratchpad>/ftop/docs/media/large.png`
- `<scratchpad>/ftop/docs/media/sizes.png`
- `<scratchpad>/ftop/docs/media/settings.png`
- `<scratchpad>/ftop/docs/media/menubar.png`
- README: `<scratchpad>/ftop/README.md` (read "What it shows" and "How it feels")

What makes ftop ftop:
- Dark translucent glass panel (~#1c1d26 at ~85%, backdrop blur, 1px faint light border, ~22px radius) over a deep purple→blue→rose desktop gradient.
- Every figure is led by the same small **round badge**; a badge with an **arc** is a gauge. Color says what it belongs to. Almost no text to read.
- **Big number, small gray unit**: "21.5 / 36 GB", "47 %". SF Pro, tabular numerals, medium weight.
- **Columns** with rounded fill and a white **tick** (fill = usage, tick = a second value). Memory as a thin horizontal bar with a darker segment.
- Process rows: real app icon, name, right-aligned value with small gray %. Helpers fold into their app.
- One panel, every size: small keeps essentials, large shows *more*, never bigger type. Also tiny forms: a strip, a corner of three badges.
- Current state only, no history graphs. Calm motion: values ease, rows rest and slide rather than jump.
- Settings: a grid of round colored toggle buttons with a label under each; "More" opens a plain list of value rows. Themes: Sea, Graphite, Warm.
- Menu bar: glyph + number, up to three readings.

Take the spirit, not a copy. MinMacs shows *things to act on* (apps, servers, worktrees, caches), not just meters. The trick is making actionable lists feel as calm and glanceable as ftop's meters.

## Fixture data (use this, so all prototypes are comparable)

Mac: MacBook Pro 16" M1 Pro, 10 cores (8P+2E), 32 GB. macOS 27. Time now 16:42.

MinMacs: system load 63%, memory 24.1 / 32 GB, compressed 3.4 GB, swap 1.1 GB, pressure "Normal", thermal nominal.
- Will close (2): Google Chrome 21% · 8.7 GB (trim 14 noise tabs: youtube.com ×6, x.com ×5, reddit.com ×3; keep 31 work tabs), Spotify 1% · 578 MB.
- Unsorted (2): FigmaAgent 0% · 13 MB, Raycast 0.4% · 210 MB.
- Kept, essentials: cmux 44% · 6.8 GB, Cursor 12% · 3.1 GB, Docker 6% · 2.4 GB, Claude 3% · 900 MB, Finder.
- Spared: Chrome for Testing 9% · 1.2 GB, "Playwright drives it".
- "MinMacs Now" frees 22% CPU · 9.3 GB. Restore: 2 closed apps, 14 tabs (last run 11:05).

Agents/workstreams:
- Claude Code · cmux tab "speed-3" · working (2m) · worktree speed-3-base · servers :3000, :5173
- Claude Code · cmux tab "studio-parity" · idle 40m · worktree studio-parity · server :3334
- Codex · thread "fix auth redirect" · finished 2h ago · worktree auth-redirect (squash-merged) · server :4000

LocoHost (6 servers): 
- :3000 next dev · speed-3-base · in use · 412 MB
- :5173 vite · speed-3-base · in use · 188 MB
- :3334 sanity · studio-parity · idle 40m · 640 MB
- :4000 phoenix · auth-redirect · idle 2h · 290 MB · worktree squash-merged
- :6006 storybook · nobody · idle 3d · 520 MB
- :5432 postgres · Docker · kept · 140 MB
"Close Idle: 3 servers, 1.45 GB"

WorkForest (14 worktrees): 3 in use, 4 merged, 2 stale (no commits 21d), 5 fine.
- auth-redirect · squash-merged · 1.8 GB · server :4000
- lane-e-sort · merged · 2.3 GB
- sb-fieldsets · merged · 940 MB
- w19-fire · merged · 610 MB
- bp7-studio-dogfood · stale 21d · 1 commit not in main · 3.2 GB
- bp8-sweep-studio403 · stale 34d · remote branch deleted · 1.1 GB
"Remove Merged: 4 worktrees, 5.65 GB"

Noo-Noo (disk 812 / 994 GB, 182 GB free): reclaimable 38.4 GB
- Xcode DerivedData 14.2 GB (7 projects, 4 gone)
- node_modules in merged worktrees 9.8 GB
- npm cache 6.1 GB (tool's own clean command)
- Playwright browsers, old versions 3.3 GB
- Docker build cache 4.2 GB
- Simulator runtimes 0.8 GB (report only)
"Clean Safe: 30.1 GB to Trash"

Insomnia: on, because Claude Code works in "speed-3". Battery 64%, on power adapter. Lid mode off. Guards: battery <20% ends, network lost ends, thermal serious ends. "Sleeps when speed-3 finishes".

Review (model): last review 9m ago with Haiku, 14k tokens today.

## Your output

Write exactly two files, each a **self-contained HTML document** (full `<!doctype html>` page, all CSS/JS inline, no external requests at all except optionally Google Fonts; use `-apple-system, "SF Pro Text", system-ui` as the font stack). Draw app icons as small inline SVG/CSS shapes (no image URLs). Paths:

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Each page:
- Is shown in an iframe of about 1280×800 in the gallery. Fill that frame: the ftop-like desktop gradient as the background, a faked macOS menu bar strip at the top (with the relevant icons, time 16:42), and your UI placed where it would really appear. Scale down gracefully if the frame is smaller (use a wrapper with `transform: scale()` computed from window size, or responsive layout).
- Uses the fixture data. Real words, no lorem ipsum.
- Is interactive where it helps: hover cards, pressing a row, toggling a size, a "Now" confirmation with Undo. Use subtle easing motion (values ease, rows slide) and respect `prefers-reduced-motion`. A static first frame must already look complete.
- Never uses `alert()`, `confirm()`, `prompt()`, external images or network calls.
- Has `<title>` = the variant's short name.

Quality bar: this is a design review for a picky owner who loves ftop. Pixel care matters: alignment, tabular numerals, consistent badge sizes, calm spacing, low-contrast hairlines. No emoji as icons. No clutter. Less is more.

When both files are written, open each in your head once more and fix anything clipped or misaligned. Then reply with ONLY this JSON (no other text):

```json
{"id":"<ID>","direction":"<direction name>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence: what it is>","good":"<one sentence: why it might win>","tradeoff":"<one sentence: the cost or risk>","surface":"NSMenu | popover | panel | window | other"},
 {"file":"<ID>-b.html", ...}
]}
```
