# Round 88 to 90: an elegant notice on 82-a

You are one of 3 design agents. Each makes **2 variants**. IDs 88 to 90 are reserved for this round.

## What the owner said

"82-a, we like [it] the most, but we need to make the notice a lot more elegant - it feels like its just in the way - when it should be something that should make dopamin pop - in an elegant way - like for example put it under main ring - and when hover we will see the message and stuff in bottom right inspect view for example"

- **82-a** is `p/82-a.html`, "Ring and Gauges": each Advanced tab (Agents, Servers, Worktrees, Disk) has a hero with a large split ring on the left, a legend beside it, and four round gauges on the right; under it, 77-a's list on the left and a live detail (the "inspect view") on the right.
- **The notice** is the focal line at the top right of the hero: a white bar, a bold sentence ("4 servers idle, holding 1 GB memory"), a gray line ("Auto stops :1313 now, then sends a notice with Undo.") and a big button ("Stop 4 Idle Servers", or a dead "Nothing to do" when calm). See `briefs/notice-before-servers.png`. The owner finds it heavy and in the way, and the dead "Nothing to do" button is the worst of it.
- The toast at the bottom ("Auto stopped :6007 Storybook, idle 3 d. 520 MB memory back. Undo") covers the list and detail for seconds. Treat it as part of the same problem: the moment something was done for you deserves the same elegant pop, not a bar over the content.

## What to make

- **Small and placed, not a banner.** The notice moves out of the hero's top right, for example as a small element under or on the main ring (the owner's own idea), so the gauges get the room.
- **Dopamine, elegantly.** When there is something to do, the notice invites you: a soft glow, a count that eases, the ring slice it means lighting up. When you press, or Auto acts, it rewards you: the ring closes the gap, the freed memory or disk counts up ("1 GB back"), a short shimmer, then it settles. When calm, it says so beautifully ("All 12 busy, nothing idle"), never a dead button. Calm, short motion; ftop's look; no confetti, no emoji.
- **Hover to inspect.** Hovering the notice opens its full story in the bottom-right inspect view (the detail): the sentence, why, exactly what the action touches (the items, lit in the list and on the ring), Off / Ask / Auto in plain words with the countdown, and the action button with its preview. Leaving it brings back the picked item. Clicking the notice keeps it in the inspect view.
- **Undo stays easy.** After an action (yours or Auto's), the Undo lives in the notice and in the inspect view for a while, so nothing covers the content.
- Same on all four tabs. Check Quiet, Busy and Peak, keyboard focus, and `prefers-reduced-motion` (no shimmer, still clear).

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/82-a.html`: open it, click each Advanced tab, Quiet / Busy / Peak, press its buttons, watch Auto act.
- `briefs/HERO-BRIEF.md`, `briefs/LIFT-BRIEF.md` (space rules), `briefs/REAL-BRIEF.md` (facts and rules; never add memory and disk into one number).
- Plain names only (Workstreams, Agents, Apps, Servers, Worktrees, Disk), never the old app names; say MinMacs.
- Name your new functions so they cannot clash with the page's existing ones (a clash broke the Workstreams tab last round): check with `grep -o '^function [A-Za-z0-9_]*' | sort | uniq -d`.

## Output

Copy `p/82-a.html` into your two new files and change the notice (and the toast). Never edit `p/82-a.html` or any other existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Keep opening on Advanced mode and Agents. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot each tab in Quiet, Busy and Peak, the notice hovered, and the reward moment after an action, with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`. Look at each, then `close_page` on your own page. Never touch pages you did not open. Switch every tab (Workstreams, Apps and Settings too) and check the console has no errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Notice: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
