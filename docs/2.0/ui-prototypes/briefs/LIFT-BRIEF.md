# Round 76 to 81: lift Agents, Servers, Worktrees and Disk

You are one of 6 design agents. Each makes **2 variants**. IDs 76 to 81 are reserved for this round.

## What the owner said

"120 is best - now do a lift to Agents, Servers, Worktrees and Disk tab" and, right after: "We need to utilize the space better"

- **120** is `p/71-a.html`, "Worth Doing First". Its Performance tab (shown as **Apps** when Advanced mode is on) opens on a ranked list of what is worth doing now, each with its size and its button, then a row of ftop meters (big number, small gray unit, a bar, one plain line under it), then three panels side by side (Apps by fate, Storage, Network and servers). Hover a ranked item and the meters and panels show what it touches.
- The four Advanced tabs in 71-a (Agents, Servers, Worktrees, Disk) are still the old flat lists: one long row per item across the whole 1040 px sheet, a big gap in the middle of every row, a list that runs off the bottom and scrolls while the sheet has room. That is what "utilize the space better" is about. Look at `briefs/lift-before-*.png` (agents, servers, disk, and the Apps tab they should match).

So: keep 71-a exactly as it is for Workstreams, Apps (Performance) and Settings, and give **Agents, Servers, Worktrees and Disk** the same quality as 120's Performance tab, each in the composition your assignment names.

## Using the space

- The sheet stays 1040 × 760 (the owner picked it). Use all of it: no row with a wide empty middle, no column of text that stops at half height, no scroll when the items fit in two or three columns. Scrolling is fine only for the long tail (Peak).
- Every tab gets one focal point at the top (the sentence that matters plus its button, like 120's item 1), then a meter row or one big graph, then panels.
- Elegant and spacious, never cramped: 16 px gaps, 12 px text minimum, labels never cut. Spacious is not the same as empty.
- Check all three scenarios (Quiet, Busy, Peak): Quiet must not look bare, Peak must not overflow badly.

## What each tab should answer

- **Agents**: who asks you (and since when, with Answer in Tab), who works (how long, on what, subagents arriving and leaving), who sits idle and why, the load they put on the Mac (CPU, memory) linked to their workstream, which tool and where each runs (cmux, tmux, Terminal, IDE). Agents have no rule: MinMacs shows them and takes you to them.
- **Servers**: which are busy, which idle and for how long, what each costs in memory, who connects (browser tabs, apps), which workstream owns it, duplicates ("same as :4321"), protected ones (Docker), and the idle rule (Off / Ask / Auto, stop after 2 h) visible on the graph with the countdown. A real graph that says in words what it means.
- **Worktrees**: Ready (merged, sessions ended, Wrap Up takes it), Blocked (and why), In a workstream, Merged with no owner, Stale; disk per tree, dirty files, unpushed commits, stashes, who made it, last commit. The rule and what it would remove, before you press.
- **Disk**: disk used and free, what may go now (no owner), what a workstream holds (goes with its Wrap Up), what is kept or blocked; Trash vs a tool's own command (npm cache clean, docker builder prune); simulators report only. Disk sizes only, clones counted once. Never add memory and disk into one number.

Every action previews what it touches, then acts, then offers Undo. Off / Ask / Auto are explained in plain words where you choose them. Real time keeps running: numbers tick, agents spawn and leave, connections come and go, items shrink when cleaned.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/71-a.html`: open it, turn Advanced mode on in Settings (or run `setAdv(true,true)` then `go('agents')`, `go('servers')`, `go('trees')`, `go('disk')`, `go('perf')` in the console). The tab code is `fAgents`, `fServers`, `fTrees`, `fDisk` (around line 2086) and the Performance tab code you are matching.
- `briefs/REAL-BRIEF.md`: the facts the 2.0 code has, and the rules. Follow it. If you use a fact the code does not have, list it in your JSON as a proposed fact and mark it "proposed" on the page, as 71-a does for network speed.
- `briefs/PERFORMANCE-BRIEF.md` and `briefs/WORKSTREAMS-BRIEF.md` "Owner update" (real time, plain-word actions, Keep Awake is one checkbox).
- Plain names only: Workstreams, Agents, Apps, Servers, Worktrees, Disk. Never the old app names.

## Output

Copy `p/71-a.html` into your two new files and change the four Advanced tabs (fix shared code only if your change needs it). Never edit `p/71-a.html` or any other existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Make the page open with Advanced mode on and the Agents tab showing, so the owner lands on your work (Settings still turns it off). Do not edit `manifest.json` or the README, and do not run git; the lead adds your pages. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot each of the four tabs in Quiet, Busy and Peak with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`, look at each, `close_page` on your own page. Never touch pages you did not open. Check empty areas, clipped text, overlaps and console errors, and fix them.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Lift: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
