# Round 91 to 93: upgrade the Performance tab of 89-a

You are one of 3 design agents. Each makes **2 variants**. IDs 91 to 93 are reserved for this round.

## What the owner said

"Now upgrade performance tab"

- The favorite is **89-a** (`p/89-a.html`, "Ring Is the Notice", gallery #156). Its Agents, Servers, Worktrees and Disk tabs have a hero (a large split ring, a legend, four round ftop gauges) over a list on the left and a live inspect view on the right. The ring's center is the notice: it names the next thing worth doing and shows a small, always-visible button for it ("Stop 3 idle", "762 MB to free" above it). Hover the button and its slices lift and glow, and the same rows light in the list; at rest the ring is calm. Press it: a short pop of about 1.5 s (slices fly out, the gap closes, a quick count of what came back), then the next action's button appears. No Undo in the ring; Undo lives only quietly in the inspect view's "Done today" (stopped servers, Restore for quit apps).
- Its **Performance tab** (shown as **Apps** in Advanced mode, **Performance** in the simple three-tab mode) is still the older 71-a design: a ranked "Worth doing now" list of four rows with four buttons, a meter row (CPU, memory, disk, network), then three short panels (Apps by fate, Storage, Network and servers) that scroll and cut their lines. See `briefs/perf-before-89a.png`. It does not yet speak 89-a's language.

So: give the Performance tab 89-a's language and quality, and keep its job: the whole Mac at a glance and the place to free memory and disk.

## What Performance must do

- **The whole Mac.** CPU (with the agents' share and heat in words), memory (with pressure in words), disk used and free, network (online, over what, the live total if you use it, marked proposed), and Keep Awake as one checkbox with its note.
- **The next action, as a chain.** One button names the best next thing across the whole Mac (close Chrome's noise tabs, clean up leftovers, quit an app on the close list, wrap up a finished workstream, stop idle servers). Press, short pop with what came back, next. The ranked order is still there (in the inspect view or as a quiet queue), but the eye goes to one button.
- **Apps by fate** (Will close, Unsorted, Kept, Spared with its reason), agents' load linked to their workstream; **storage and leftovers** (who owns each, deleted for good vs a tool's own command, simulators report only); **network and servers' cost**.
- **Hover lights, press acts.** Hover the button or a part of the hero and the items it touches light; the inspect view tells the full story (what it touches, its size, the rule with Off / Ask / Auto in words and the countdown).
- **Never add memory and disk into one number.** Show them as two numbers, two rings or two bars.
- Fill the 1040 × 760 sheet: no cut lines, no half-empty panels, no empty middles. Check Quiet, Busy and Peak.

Owner rules that hold now:
- **Far less Undo.** After an action, go to the next one. No Undo in the main view. Undo only quietly in the inspect view's "Done today", and only for quitting an app (Restore) and stopping a server.
- **Deletes are permanent.** Nothing goes to the Trash. Say "deleted for good" or "deletes". The preview before you press is the safety. A merged worktree is blocked from the delete while it has changed files, untracked files, unpushed commits, stashes or a session, and it says why.
- **The button always shows; the glow comes on hover.**
- The reward is a short moment that lets go. Navigation (Open, Answer in Tab, Go to Tab) gets no reward.
- Plain names only (Workstreams, Agents, Apps, Servers, Worktrees, Disk), never the old app names; say MinMacs.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/89-a.html`: open it, click Servers, Disk and Worktrees, press through the chain, hover the button, then open Apps (the tab you redo). Turn Advanced mode off in Settings to see it as Performance in the three-tab mode; it must work in both.
- `briefs/PERFORMANCE-BRIEF.md` (what Performance shows and the network facts), `briefs/REAL-BRIEF.md` (facts and rules), `briefs/NOTICE-BRIEF.md`, `briefs/HERO-BRIEF.md`.
- Name new functions so they cannot clash with the page's existing ones (a clash once broke the Workstreams tab). Check with `grep -o '^function [A-Za-z0-9_]*' <file> | sort | uniq -d`.

## Output

Copy `p/89-a.html` into your two new files and change the Performance tab (fix shared code only if your change needs it). Never edit `p/89-a.html` or any other existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Make the page open in Advanced mode on the Apps (Performance) tab, so the owner lands on your work. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot the Performance tab in Quiet, Busy and Peak, hovered, and mid-chain, in both Advanced and three-tab mode, with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`. Look at each, then `close_page` on your own page. Never touch pages you did not open. Switch through every tab and check the console has no errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Performance: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
