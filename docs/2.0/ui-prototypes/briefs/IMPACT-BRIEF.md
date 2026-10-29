# Round 97 to 99: Performance ranked by impact, and Fix Everything

You are one of 3 design agents. Each makes **2 variants**. IDs 97 to 99 are reserved for this round.

## What the owner said

"I want to see the hero part focus on the biggest most useful movement to the least - so for example that we start with fixing full workstreams etc - but continuing with less and less important. Goal is to have a view where we see list with items of 7, and we should be able to see impact of fixing. Also on here, try like "Fix everything". And we will see it happen in a sophisticated realistic sequence based on how it likely will feel based on the kind of action that we are doing"

- The base is **94-a** (`p/94-a.html`, "Rings and Section Cards"): it opens in Advanced mode on the new **Performance** tab (tab key `over`): four ftop rings (CPU, Memory, Disk, Network) with one chain button, over six section cards. Apps (`perf`) and every other tab stay as they are.
- Change the **Performance tab only**. Its hero becomes the ranked list of what to fix.

## What to make

**1. A ranked list of 7, biggest move first.**
- The hero is a list of exactly **7 fixes**, ordered by how much each one helps the Mac and you, biggest first. A finished workstream wrapped up in full (its tabs, servers, worktree and memory in one go) usually comes first. Then smaller and smaller moves: stop idle servers, quit apps on the close list, close noise tabs, delete merged worktrees, delete caches and leftovers.
- Rank by a clear, shown measure: memory back, disk back, CPU back, and things that stop needing you. Say in words why each row sits where it does ("Biggest: frees 2.4 GB memory and 3 servers").
- **Never add memory and disk into one number.** Show them as two numbers, two bars or two rings.
- All 7 rows fit with no scroll, nothing cut. More than 7 → a quiet "and 4 smaller" line. Fewer → the list says so calmly ("Only 3 things left. The Mac is nearly clean.").
- Live: the list re-ranks when the simulation changes things, and new items slide in at their rank.

**2. See the impact of fixing.**
- Each row shows what it gives back: memory, disk, CPU, servers, tabs, attention (asking agents).
- Hover a row: the rings (or your hero graphic) show the after-state as a ghost ("Memory 71 % → 58 %"), and the items it touches light in their places. Hover goes calm when you leave.
- Show the whole picture too: **now vs after all 7**, so you see where the Mac lands.

**3. Fix Everything.**
- One button, **Fix Everything**, always visible next to the list. Before it runs it says in one line what it will do ("7 fixes: 3.1 GB memory back, 12 GB disk back. About 20 s."). Pressing it runs the fixes top to bottom.
- **The sequence must feel real, shaped by each kind of action.** Each kind has its own steps, rhythm and timing, like the real Mac would:
  - **Wrap up a workstream:** several steps in order, each visible: check the worktree is clean → stop its servers → close its tabs → delete the merged worktree for good → done. Slower, about 4 to 6 s.
  - **Close tabs:** tabs go one by one, fast and light, about 1 to 2 s for 14.
  - **Stop servers:** each server stops in turn, its port goes free, its memory comes back a beat later, about 0.5 s each.
  - **Quit apps:** the app saves and quits, its memory falls a moment after, about 1 to 2 s each.
  - **Delete caches and leftovers:** the size counts down as the files go, bigger takes longer, about 2 to 4 s.
  - **Delete merged worktrees:** quick, about 1 s each, "deleted for good".
  - Memory, disk and CPU numbers move **with** each step, not all at the end.
- **Honest about what it cannot do.** An agent asking a question needs you: Fix Everything skips it and leaves it at the top as "Needs you". A blocked worktree (changed files, untracked files, unpushed commits, stashes or a session) is skipped with its reason. A rule set to Off is not touched.
- During the run: the current step is clear, the done rows settle, the rest wait. A quiet **Stop** finishes the current step and stops. You can watch, and nothing covers the content.
- At the end: one short reward that lets go ("3.1 GB memory and 12 GB disk back"), then the calm view ("Everything is fine. Nothing needs you." or the rows that are left). No Undo in the view.

Owner rules that hold:
- Far less Undo: go to the next thing. Undo only quietly in an inspect view, for a stopped server and Restore for a quit app.
- Deletes are permanent and say "deleted for good". Nothing goes to the Trash.
- The buttons always show. The glow comes on hover.
- Rewards are short and let go. Navigation (Open, Answer in Tab) gets no reward.
- Plain names only, never the old app names; say MinMacs. Keep Awake stays one checkbox.
- Elegant and spacious, ftop's look. Fill the 1040 × 760 sheet: no cut lines, no empty middles. Every graph says in words what it means. Check Quiet, Busy and Peak.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/94-a.html`: open it (it starts on Performance), press through its chain, switch Quiet / Busy / Peak, open Apps and Settings, and turn Advanced mode off. Its Performance code is the `p94*` functions and `tab==='over'`.
- `briefs/OVERVIEW-BRIEF.md` (the last round), `briefs/REAL-BRIEF.md` (facts and rules).
- Name new functions so they cannot clash; check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`.

## Output

Copy `p/94-a.html` into your two new files and change the Performance tab (fix shared code only if your change needs it). Never edit `p/94-a.html` or any other existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Open in Advanced mode on Performance. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion` (the run still steps through, no flourish), no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**. Screenshot Performance in Quiet, Busy and Peak, a row hovered, Fix Everything at three moments (early, mid Wrap Up, the end), and the calm view after, in Advanced and simple mode, with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`. Look at each, then `close_page` on your own page. Never touch pages you did not open. Switch through every tab and check the console has no errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Impact: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
