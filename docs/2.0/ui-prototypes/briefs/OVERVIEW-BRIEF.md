# Round 94 to 96: Performance as a clear view of everything

You are one of 3 design agents. Each makes **2 variants**. IDs 94 to 96 are reserved for this round.

## What the owner said

"Apps and performance is different. Keep apps as it is, but performance need to have clear view of everything"

- The favorite is **89-a** (`p/89-a.html`, "Ring Is the Notice"). In Advanced mode its tabs are Workstreams, Agents, Apps, Servers, Worktrees, Disk, Settings, and the **Apps** tab holds what was once Performance (ranked "Worth doing now", meters, Apps by fate, Storage, Network and servers). In the simple mode the same view is called Performance.
- Last round (91 to 93) redid that tab. The owner says that was wrong: **Apps and Performance are two different tabs.**
  - **Apps stays exactly as it is in 89-a.** Do not change it.
  - **Performance is a new, separate tab: a clear view of everything** on the Mac at once.

So: copy 89-a, keep every existing tab as it is, and add a **Performance** tab.
- Advanced mode tabs: Workstreams, **Performance**, Agents, Apps, Servers, Worktrees, Disk, Settings (Performance right after Workstreams).
- Simple mode tabs: Workstreams, Performance, Settings, where Performance is the new overview (Apps returns with Advanced mode). Update the Settings text that explains what Advanced mode adds so it is true.

## What Performance shows

A clear view of everything, so you understand the whole Mac in one look and know where to go:
- **The Mac itself:** CPU (with the agents' share, heat in words), memory (pressure in words), disk used and free, network (online, over what; a live total only marked proposed). Memory and disk are never one number.
- **Every section in short:** Workstreams (how many, ready, asking), Agents (working, asking, idle), Apps (will close, unsorted, memory), Servers (busy, idle, the rule's countdown), Worktrees (ready, blocked, disk), Disk (may go, own command). Each part says its state in plain words and its one number, and clicking it goes to that tab.
- **The one next thing for the whole Mac,** as 89-a does it: an always-visible button naming the best next action anywhere ("Close 14 tabs", "Stop 3 idle", "Delete 2 caches"), its parts glowing only on hover, press for a short pop, then the next. No Undo in the view.
- Keep Awake stays one checkbox with its note.
- Calm, beautiful, ftop. Clear first: one look should answer "is my Mac fine, and what should I do". Fill the 1040 × 760 sheet with no cut lines, no empty middles. Live: numbers tick, things arrive and leave. Check Quiet, Busy and Peak.

Owner rules that hold: far less Undo (only quietly in an inspect view, for a stopped server and Restore for a quit app); deletes are permanent and say "deleted for good"; the button always shows and the glow comes on hover; rewards are short and let go; navigation gets no reward; plain names only, never the old app names (say MinMacs).

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/89-a.html`: click every tab in Advanced and simple mode, press through the chains.
- `p/93-a.html` (four equal ftop rings for CPU, Memory, Disk, Network, the button inside the ring it frees most) and `p/91-a.html`: last round's ideas, good material for the Mac part of the overview.
- `p/20-a.html` (Live Index: big section names each with a mini live graph and a number; the owner liked how it uses space).
- `briefs/PERF2-BRIEF.md`, `briefs/REAL-BRIEF.md` (facts and rules).
- Name new functions so they cannot clash with existing ones; check with `grep -o '^function [A-Za-z0-9_]*' <file> | sort | uniq -d`. Use a new tab key (e.g. `over`) so the existing `perf` code (the Apps tab) keeps working.

## Output

Copy `p/89-a.html` into your two new files and add the Performance tab. Never edit `p/89-a.html` or any other existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Make the page open in Advanced mode on the new Performance tab. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot Performance in Quiet, Busy and Peak, hovered and mid-chain, in Advanced and simple mode, and Apps once to confirm it is unchanged, with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`. Look at each, then `close_page` on your own page. Never touch pages you did not open. Switch through every tab and check the console has no errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Performance overview: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
