# MinMacs 2.0 Settings: round 2 brief

You are one of 6 design agents. Each makes **2 variants** of the MinMacs Settings window in your assigned style. The owner will browse all of them in a gallery and pick.

## What the owner said (their words)

- About the overview pane: "I love the Expert Overview Pane - being able to choose mode - but way too much things"
- "we should not name them after their old names - now it is just settings - less is more"
- "We want it alot smaller and abit smarter with more details"
- About the last attempt: "Like, more choices - now it just looks ugly - i want it to be more elegant and spacey than this"

So: **elegant, spacious, calm, airy**. Generous whitespace, fewer lines, nothing cramped. Still compact as a window (not a full-screen page). Smart: each section says its rule and what it sees now.

Look at the last two attempts to see the content and what NOT to do (cramped rows, tiny text, everything the same weight):
- `<scratchpad>/gallery/p/11-b.html` (round 3, judged "ugly")
- `<scratchpad>/gallery/11-b.v2.html` (round 2, "too much things" before that)

Inspiration is **ftop** (github.com/Nongfsq/ftop). Read these images with the Read tool before designing, especially settings.png:
- `<scratchpad>/ftop/docs/media/settings.png`
- `<scratchpad>/ftop/docs/media/large.png`

ftop's look: dark translucent glass (~#1c1d26 at 85%, blur, 1px faint light border, ~22px radius) over a deep purple→blue→rose desktop gradient; round badges; big number, small gray unit; SF Pro, tabular numerals; low-contrast hairlines; calm easing motion.

## The content (use exactly these names, never the old app names MinMacs/LocoHost/WorkForest/Noo-Noo/Insomnia for sections)

The app is MinMacs. Its Settings has five sections, each with a mode **Off / Ask / Auto**:

| Section | Color | Ask does | Auto does | One tunable value | What it sees now |
|---|---|---|---|---|---|
| Apps | #5B9BFF | Shows noise apps to close | Closes noise apps when the Mac is busy | load threshold: 60 / 70 / 80 / 90 % (70) | 2 closed today |
| Servers | #3FD0B8 | Shows idle localhost servers | Stops servers nobody used | idle time: 30 min / 1 h / 2 h / 4 h / 1 day (2 h) | 3 idle now, 3 stopped today |
| Worktrees | #4CC96B | Shows merged git worktrees | Removes merged worktrees (Undo brings back) | after: 1 h / 1 day / 1 week (1 day) | 4 merged · 5.7 GB |
| Disk | #F2B544 | Shows caches and build output safe to clean | Moves safe clutter to the Trash | how often: daily / weekly / monthly (weekly) | 30 GB safe to clean, next on Sunday |
| Keep Awake | #B18CFF | Asks when an agent starts working | Keeps the Mac awake while agents work, then sleeps | ends at battery: 10 / 20 / 30 % / never (20 %) | 4 agents working now |

Defaults: all Auto except Worktrees on Ask. Off means "not watching" (or for Keep Awake, "the Mac sleeps as usual").

Also: "Today" summary of what Auto did ("Closed 2 apps, stopped 3 servers") with one Undo. Two app switches: **One icon in the menu bar** (off) and **Open at login** (on). A faked macOS menu bar at the top shows one small white icon per section that is not Off (and collapses to one icon when One icon is on), time "Tue 27 Oct 16:42".

You may leave things out if your design is better without them, but the five sections with their mode must be there, and the smart line (rule + its value + what it sees) must be reachable (visible, or on hover/press).

## Output

Write exactly two self-contained HTML files (full `<!doctype html>`, all CSS/JS inline, no network requests except optionally Google Fonts; font stack `-apple-system, "SF Pro Text", system-ui`; no emoji; icons as inline SVG):

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Each page is a 1280×800 stage (`#stage`, scaled to fit the window with `transform: scale()` like the reference files do), ftop gradient desktop, faked menu bar, your Settings window placed where it would appear. Interactive: modes switch with easing, values change on click, the menu bar icons react, Undo works. Respect `prefers-reduced-motion`. No `alert/confirm/prompt`. `<title>` = the variant's short name.

Quality bar: a picky owner who called the last one ugly. Pixel care: alignment, rhythm, consistent sizes, generous spacing, restrained color (section color as an accent, not everywhere), one clear focal point. Check that no text is clipped (scrollWidth > clientWidth) and fix it.

Verify each file in a real browser once if you can (the files are served at `http://127.0.0.1:8765/p/<file>`; use the chrome-devtools MCP tools: new_page with isolatedContext set to your ID, resize_page 1280×800, take_screenshot, close_page when done; never touch other pages or the owner's tabs).

When done, reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Settings: <style name>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence: why it might win>","tradeoff":"<one sentence>","surface":"window"},
 {"file":"<ID>-b.html", ...}
]}
```
