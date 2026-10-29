# Round 101 to 103: more ways to show what got better lately

You are one of 3 design agents. Each makes **2 variants**. IDs 101 to 103 are reserved for this round.

## What the owner said

"177 is nice. When nothing left to fix, show a summary of what how much we have improved lately" and then, after round 100: "I want more variations of this screen".

- The favorite is **99-b** "Fix Cards Stack" (gallery #177): Performance (tab key `over`) as a deck of up to 7 fixes, biggest first, and Fix Everything that plays each kind of action at its own pace.
- Round 100 added the **calm view**: when nothing is left to fix, the deck area becomes a look back. `p/100-a.html` "Week in Review" (one sentence, today and this week as two numbers each, a 7-day chart with memory and disk apart, counts by kind, the Mac now vs a week ago) and `p/100-b.html` "Done Cards" (done cards newest first, one card per earlier day). The owner wants **more variations of this calm screen**.

## What to make

Copy `p/100-a.html` (it has the kept log of what came back, the seeded week and the calm-state switch) and redesign **only the calm view**: the deck area and, if it helps, the right column while calm. The running deck, Fix Everything and every other tab stay as they are.

The calm view must:
- Look back over **today and the last 7 days**: what MinMacs gave back, from Fix Everything, single fixes and Auto. Memory back and disk back are **always two numbers, never summed**.
- Answer in one look: "how much better is my Mac lately, and from what".
- Every graph says in words what it means. ftop's look: dark glass, rings and arcs, a big number with a small gray unit. Elegant and spacious, fill the space with no empty middles and no cut lines.
- Be quiet and proud, not a reward pop. No dead buttons: when calm, the top right says "The Mac is clean" with a green dot, as in 100-a.
- Live: a fix that lands while you look joins the summary. When a new fix appears, its card rises on top and the summary steps aside gracefully; when it is done, the summary comes back.
- Keep Needs you (Answer in Tab) visible when an agent asks.

Owner rules that hold: far less Undo (none here); deletes say "deleted for good"; plain names only, never the old app names (say MinMacs); Keep Awake stays one checkbox; check Quiet, Busy and Peak.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/100-a.html` and `p/100-b.html`: press Fix Everything, wait for the run to end (about 30 s), and look at the calm view. Find the calm code (the `P100*` / `p100*` names).
- `p/99-b.html` for the deck itself, `briefs/IMPACT-BRIEF.md` and `briefs/REAL-BRIEF.md` (facts and rules).
- Name new functions so they cannot clash; check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`.

## Output

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Never edit `p/100-a.html` or any other existing page. Open in Advanced mode on Performance. So the owner sees your work at once, **open already in the calm view**: run the fixes through on load with no animation (or seed the state as if Fix Everything just finished), while the simulation keeps running so new fixes can appear later. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**. Screenshot the calm view in Quiet, Busy and Peak, a fix landing live, a new fix appearing (the summary stepping aside), and simple mode, with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`. Look at each, then `close_page` on your own page. Never touch pages you did not open. Switch through every tab and check the console has no errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Calm: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
