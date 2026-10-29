# Round 104 to 106: new layouts for Performance, the parts and the whole

You are one of 3 design agents. Each makes **2 variants**. IDs 104 to 106 are reserved for this round.

## What the owner said

After the calm views of round 101 to 103: "Like overall - think about for example using left to see all processes and stuff - and right for the overall things - just as an example - think around about ways we can do this"

- The owner likes where Performance is going: **99-b** "Fix Cards Stack" (up to 7 fixes as a deck, biggest first, Fix Everything playing each kind of action at its own pace) and its **calm view** (rounds 100 to 103: when nothing is left, a look back over today and the week).
- Now they want to rethink the **layout** of the whole Performance tab (tab key `over`). Their example: **left shows every process and running thing in detail, right shows the overall picture.** It is only an example: think around it and find other good ways to put the parts and the whole together.

## What Performance must hold

- **The parts:** everything running that MinMacs knows: agents and their subagents, servers (port, framework, memory, connections), helpers, apps (with their fate: will close, unsorted, kept, spared), browser tabs (noise and localhost), worktrees, caches and leftovers. Each with who owns it (its workstream, or nobody) and what it costs (CPU, memory, disk). Live: rows arrive, tick and leave.
- **The whole:** the Mac (CPU with heat, memory with pressure, disk free, network), the ranked fixes with Fix Everything, and the calm look back when nothing is left.
- **Connected:** hover a part and the whole shows its share (its slice in a ring, its row in a fix); hover a fix or a ring and the parts it touches light. Click a part to see its full story.
- Memory and disk are **never one number**. Every graph says in words what it means.

Owner rules that hold:
- Fill the 1040 × 760 sheet: elegant, spacious, ftop's look (dark glass, rings and arcs, a big number with a small gray unit). No cut lines, no empty middles, no flat rows with empty middles. Many rows must still fit (the owner runs 12+ agents), so lists group, fold and scroll calmly.
- Fix Everything and the fix deck keep 99-b's pacing and honesty (skips Needs you and blocked, says why). Far less Undo; deletes say "deleted for good". The button always shows, the glow comes on hover, rewards are short and let go. No dead buttons; calm says "The Mac is clean".
- Plain names only, never the old app names (say MinMacs). Keep Awake stays one checkbox. Check Quiet, Busy and Peak.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/100-a.html` (99-b plus the calm view and the kept log): press Fix Everything, watch, wait for the calm view.
- `p/101-a.html`, `p/101-b.html`, `p/102-a.html`, `p/102-b.html`, `p/103-a.html`, `p/103-b.html`: more calm views; reuse what fits your layout.
- The Agents, Apps, Servers, Worktrees and Disk tabs of the same page show how each kind of part is drawn today.
- `briefs/IMPACT-BRIEF.md`, `briefs/CALM-BRIEF.md`, `briefs/REAL-BRIEF.md` (facts and rules). A fact the code does not have (for example processes MinMacs does not track today) is marked "proposed" on the page and listed in your JSON.
- Name new functions and classes so they cannot clash (a shared class name broke a layout last round); check functions with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`.

## Output

Copy `p/100-a.html` into your two new files and redesign the Performance tab's layout (fix shared code only if your change needs it). Never edit an existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Open in Advanced mode on Performance with fixes to do (not calm), so the owner sees the parts, the whole and the deck at once. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**. Screenshot Performance in Quiet, Busy and Peak, a part hovered, a fix hovered, mid Fix Everything and the calm view after, and simple mode, with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`. Look at each, then `close_page` on your own page. Never touch pages you did not open. Switch through every tab and check the console has no errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Layout: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
