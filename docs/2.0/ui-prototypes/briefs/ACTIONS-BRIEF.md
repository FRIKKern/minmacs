# MinMacs 2.0: Hanging Sheet with actions, round 3 brief

You are one of 6 design agents. Each makes **2 new variants**. The owner browses all in a gallery and picks.

## What the owner said this round

"We want more - in general i would like to be able to hover and do actions to the different things - and i would love to be able to do action in general on these - and in general make the menu on left learn from the live index version - because it use the space a lot better than most"

So three musts, in every variant:

1. **Left menu = Live Index.** Study `<scratchpad>/gallery/p/20-a.html` (served at `http://127.0.0.1:8765/p/20-a.html`). The left list has the large section names, each with its own small live ftop graph beside it and a number with a mode verb ("Auto frees 9.3 GB"). It uses the space far better than a plain list. Keep that, you may refine it.
2. **Hover a thing → act on it.** Every item (app, server, worktree, cache, agent) can be acted on from where it is: on hover, show its actions (inline buttons, a hover card beside it, or similar; your direction says which). Actions are real verbs with a result and Undo.
3. **Actions in general.** Each section has its big action(s) for many items at once, and hovering such an action first highlights exactly the items it will touch and what it frees (the menu is the plan: nothing happens that was not shown first). After acting: rows ease out, numbers and graphs ease down, a calm Undo toast.

## Update from the owner: agents and workstreams are a big part

"also agents and workstreams or just one of them is important part i want to see more of"

So every variant also has an **Agents** entry in the Live Index (first or second in the list, with its own mini live graph, e.g. 12 agent dots: working / needs you / idle / finished). Its tab shows 7+ agents (workstreams) and "5 more": each with its tool (Claude Code, Codex, Cursor), where it runs (cmux tab, tmux pane, app), state and time, and what it holds across sections (servers, worktree, caches, keeps the Mac awake) as small section-colored marks. Hover an agent to act: Go to Tab, Wrap Up (finished: stops its servers, removes its merged worktree and caches, one Undo), Stop Its Servers, Let It Sleep. Section action, e.g. **Wrap Up Finished** (1 agent · 2.1 GB). In the other tabs, each item says which agent owns it and links to it. Use your direction's action style here too.

## Keep from before

Read these first:
- `<scratchpad>/gallery/SHEET-BRIEF.md` (the Hanging Sheet brief, including the owner's update: each tab mixes **activity + settings**: right now insight sentence, live graph, the items, and the mode Off / Ask / Auto with rule and value).
- `<scratchpad>/gallery/SETTINGS-BRIEF.md` (names, colors, modes, rules, values).
- Fixture numbers: the "Fixture data" section of `<scratchpad>/gallery/BRIEF.md` (ignore its old app names; sections are Apps, Servers, Worktrees, Disk, Keep Awake), plus the 12 agents listed in SHEET-BRIEF.md.
- Earlier favorites to borrow from: `p/18-b.html` (the original Hanging Sheet), `p/19-a.html`, `p/21-a.html`, `p/24-b.html` (Before and After), `p/03-b.html` (a hover card the owner loved: title, sub, colored status that starts with a word, icon-led facts, a cross-link, then 4 actions).

Rules that still hold: plain names, never the old app names; elegant and spacious, never cramped; every graph says in words what it means; 6+ agents when agents are listed; Keep Awake in plain words.

## Actions to use (pick what fits; real verbs, Title Case, gray tail for size or time)

- **Apps:** Quit, Trim Tabs (Chrome: 14 noise tabs), Keep, Move to Close List, Restore. Section: **MinMacs Now** (2 apps · 9.3 GB), **Restore Last Run** (11:05).
- **Servers:** Stop, Keep, Open in Browser, Go to Agent, Restart. Section: **Close Idle** (3 · 1.45 GB).
- **Worktrees:** Remove (to the Trash, a git bundle if commits are on no remote), Keep, Show in Finder, Open in Editor, Show Commit. Section: **Remove Merged** (4 · 5.65 GB).
- **Disk:** Clean (to the Trash, or the tool's own command for npm/Docker), Keep, Show in Finder. Section: **Clean Safe** (30.1 GB to the Trash).
- **Keep Awake / agents:** Go to Tab, Let It Sleep, Keep Awake 1 h, Wrap Up (finished agent: stops its server, removes its merged worktree and caches, one Undo).
- Unsafe or blocked actions stay visible but dimmed with the reason in gray ("Remove…   1 commit not in main"). Force Quit only after a Quit is refused.

## Output

Write exactly two self-contained HTML files (full `<!doctype html>`, all CSS/JS inline, no network except optionally Google Fonts; font stack `-apple-system, "SF Pro Text", system-ui`; no emoji; icons as inline SVG):

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Same stage as 18-b/20-a (1280×800 `#stage`, scaled to fit, ftop gradient desktop, faked menu bar, "Tue 27 Oct 16:42"). Every action works in the mockup and is undoable. Respect `prefers-reduced-motion`. No `alert/confirm/prompt`. `<title>` = the variant's short name.

Verify each file in a real browser once: served at `http://127.0.0.1:8765/p/<file>`. Use chrome-devtools MCP: `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, `take_screenshot` with a `filePath` in the scratchpad, `close_page` on your own page. Never touch pages you did not open. Click through all tabs, hover rows, run each section action and Undo; check for clipped text (`scrollWidth > clientWidth`), overlap, and console errors. Fix what you find.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Actions: <style name>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence: why it might win>","tradeoff":"<one sentence>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
