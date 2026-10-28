# MinMacs 2.0: Hanging Sheet, round 2 brief

You are one of 6 design agents. Each makes **2 new variants** of the "Hanging Sheet" design. The owner browses them all in a gallery and picks.

## What the owner said

Picked from 12 Settings styles: **"Hanging Sheet 18-b. We want to see many new versions of this - with more details - graphs and such"**

Earlier, in their words:
- "we should not name them after their old names - now it is just settings - less is more"
- "i want it to be more elegant and spacey" (a dense, cramped version was called "ugly")
- On another mockup: "the graphs up on the left feels useless - dont understand". So every graph must answer a question in plain words (e.g. the colored part of a bar is exactly what Auto will free). No decorative charts, no graph without a label that says what it means.
- They run **a lot of agents** (12+). Anything listing agents must show at least 6.
- Keep Awake should say in plain words why the Mac is awake and what stops it.

## Update from the owner (applies to both variants)

"We want to mix the tabs with insight and details what is going on right now - so both activity and settings kinda"

So every section tab is **activity + settings in one view**, not settings alone:
- **Right now:** a plain-words insight sentence about what is happening (e.g. "3 servers idle. :6006 storybook has been idle 3 days and nobody owns it."), the live graph, and the actual items (apps, servers, worktrees, caches, agents) with their state.
- **Settings:** the mode (Off / Ask / Auto), the rule and its value, placed so you see how the setting acts on what is shown above (e.g. items that Auto will act on are marked).

## Start here

1. Open and study the design you are extending: `<scratchpad>/gallery/p/18-b.html` (served at `http://127.0.0.1:8765/p/18-b.html`). Keep its soul: a calm sheet hanging from the menu bar icon it belongs to, a nub and highlighted status item that slide to the picked section, five large section names on the left with a mode dot and word, the big Off / Ask / Auto words with a sliding underline, the rule, the value choices as plain words, a large "Now" number.
2. Read the Settings content table in `<scratchpad>/gallery/SETTINGS-BRIEF.md` (names, colors, modes, rules, values, live state, Today line, the two switches).
3. Read the fixture data in `<scratchpad>/gallery/BRIEF.md` ("Fixture data" section: apps, servers, worktrees, disk clutter, battery). Use those real numbers for your graphs and detail rows. **Ignore that file's old app names**: sections are Apps, Servers, Worktrees, Disk, Keep Awake. Extra agents you may use (12 in total): speed-3 (Claude Code, cmux, working 2m), bp-lane-c (Claude Code, working 14m), media-scope (Codex, working 6m), studio-icons (Cursor, working 1m), lexicon-judge (Claude Code, needs you 3m), studio-parity (Claude Code, idle 40m), fix auth redirect (Codex, finished 2h), plus 5 more idle over 1h.
4. Look at ftop for the visual language (Read the images): `<scratchpad>/ftop/docs/media/large.png` and `.../sizes.png` in the same folder.

## What "more details, graphs and such" means here

Each section gets real detail about what it is watching, drawn in ftop's language (round badge + arc, big number small gray unit, rounded columns with a tick, thin bars with a colored segment, app/server/worktree rows with icons). Ideas per section, use or beat them:
- **Apps:** CPU and memory bars where the colored end is what Auto frees; the apps on the close list with icon, CPU, memory.
- **Servers:** each server with a small arc filling toward when it goes idle-out; memory per server; which worktree/agent owns it.
- **Worktrees:** worktrees as ftop columns (height = size, fill style = merged/stale/in use); what Remove Merged frees.
- **Disk:** the disk bar 812 / 994 GB with the 38.4 GB reclaimable split by kind; what Clean Safe moves to the Trash.
- **Keep Awake:** which agents hold the Mac awake right now (show 6+ agents), battery 64 % as a gauge with the 20 % stop tick, the guards in words.
- **Today:** what Auto did today, with Undo. A small history (a 24-hour strip of when things happened) is allowed if it helps trust; ftop itself shows current state only, so justify any history.

Still elegant and spacious: details are calm and aligned, hierarchy is clear, one focal point per section, generous margins. The sheet may grow (up to about 760 × 620) but must not feel crowded.

## Output

Write exactly two self-contained HTML files (full `<!doctype html>`, all CSS/JS inline, no network requests except optionally Google Fonts; font stack `-apple-system, "SF Pro Text", system-ui`; no emoji; icons as inline SVG):

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Same stage setup as 18-b (1280×800 `#stage`, scaled to fit, ftop gradient desktop, faked menu bar, time "Tue 27 Oct 16:42"). Interactive: switching sections slides the nub, modes and values change with easing, graphs ease to new values, Undo works. Respect `prefers-reduced-motion`. No `alert/confirm/prompt`. `<title>` = the variant's short name.

Verify each file in a real browser once: it is served at `http://127.0.0.1:8765/p/<file>`. Use the chrome-devtools MCP tools: `new_page` with `isolatedContext` set to your ID and `background: true`, then `resize_page` 1280×800 **on your own page id only**, `take_screenshot` with a `filePath` in the scratchpad, then `close_page` on your own page. Never resize, screenshot, navigate or close any page you did not open. Check every section (click through all five) for clipped text (`scrollWidth > clientWidth`) and overlap, and fix what you find.

When done, reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Hanging Sheet: <style name>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence: why it might win>","tradeoff":"<one sentence>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
