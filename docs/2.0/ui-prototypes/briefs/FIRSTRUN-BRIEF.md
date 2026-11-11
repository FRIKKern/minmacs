# Round 198 to 200: the first launch, a premium welcome

You are one of 3 design agents. Each makes **2 variants** from a copy of `p/197-b.html` "Settings Whole Menu" (195-a's menu with the gear flipping to Settings in place; this is the design the real app now builds, issue #62). Your ID is one of 198 to 200, and your direction is the one under your ID below. The Mac has 16 GB of RAM and many agents: keep one browser page open at a time and close it when done.

## What the owner said

About the app adding itself to the login items at first launch: "Ahh yeah we have to make that very premium ux".

Today the real app, on its first launch, quietly adds itself to the login items and shows one gray line ("MinMacs opens at login. Settings can turn that off."). The window opens on empty graphs ("The line fills in as the hour passes.") and lists that fill over a few seconds. That first minute should feel like a welcome, calm and premium, and the person should choose "Open at login" knowingly.

## What the first launch must do

Design the **first time the window opens**, inside the same window at the same size (no separate onboarding window, no wizard with many pages, no other panels):

1. **A welcome that is short.** What MinMacs is in one or two plain sentences: it watches what your agents, servers and apps hold, and gives memory and disk back when you press Fix Everything.
2. **Open at login, asked.** One clear choice with its consequence in plain words ("MinMacs starts when you sign in" / "MinMacs starts only when you open it"), default on, changeable later in Settings. No system password is needed for it.
3. **What it will and will not do on its own.** Facts of the real app: for the first day it only watches; every rule can be Off, Careful or Eager (Careful is the start); nothing is deleted without a way back (things go to the Trash or a recovery folder); it asks for no permission at launch. Say this in a few calm lines, not a wall of text.
4. **The first look.** While the first numbers arrive (a few seconds: servers, agents, apps, then worktrees and caches), the window shows that it is looking, group by group, as a pleasant moment and not a spinner. The last-hour graphs are empty at first: say so gracefully ("The line fills in as the hour passes").
5. **Then let go.** One press ("Start" or similar) or simply the first look ending lands on the normal menu (195-a). The welcome never shows again; "Open at login" lives on in Settings.

It must feel premium: generous space, one focal point, careful type, a little motion with weight (and none under `prefers-reduced-motion`). Calm, never salesy: no exclamation marks, no feature tour, no emoji, no confetti.

## Rules that hold

Plain names only, never the old app names (LocoHost, WorkForest, Noo-Noo, Insomnia); say MinMacs. The copy never claims a result ("The Mac is clean", "Everything is fine", "Nothing needs you" are banned). Memory and disk never one number. Nothing says "for good". No Hide Icon; only Settings (gear, ⌘,) and Quit (power, ⌘Q). No cut lines, no ellipsis, nothing clipped, no empty middles. The window keeps its size and place.

## Directions

- **198 Welcome over the menu.** The normal menu is there, quiet and dimmed, filling in behind; the welcome sits in the middle column where the graphs will be. a: the welcome and the login choice as one calm card in the middle, the lists filling in live on both sides. b: the dock is the welcome: the ring fills as the first look runs, and the Fix Everything pill's place holds "Start" with the login choice beside it.
- **199 Welcome first, then reveal.** The window opens on the welcome alone, then the menu arrives. a: one centered column (the mark, two sentences, the login choice, the three calm facts, Start), then the menu fades up in place. b: the first look is the welcome: each group appears as it is found ("Found 20 servers", "Found 16 agents"), the facts sit beside it, the login choice last.
- **200 The lightest touch.** As little ceremony as possible. a: the normal menu at once, with one slim welcome strip on top holding the two sentences and the login choice with a Done; it folds away when pressed. b: your own most premium idea for this moment.

## Output

Copy `p/197-b.html` into your two new files and change it. Add a scenario control on the stage to replay the first launch ("First launch" beside Quiet / Busy / Peak, or a Replay button), and open on the first launch. Keep the fixture data, live simulation, Quiet / Busy / Peak (`setScn`), the gear's Settings in place, and `go(tab)`, `setAdv(v)`, `tabList()` existing and not throwing. Never edit an existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Name new functions with your ID (`m198…`); check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, no network, no emoji, no `alert/confirm/prompt`, `<title>` = variant name (2 to 4 words).

## Verify

chrome-devtools MCP: `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800, your own pageId on every call, never touch pages you did not open (pages are served at `http://127.0.0.1:8766/p/<file>`). Scratch files in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/first-<ID>/`. Screenshot: the first frame, mid first look, the login choice toggled off and on, the moment it lets go, and the normal menu after; then Replay. Look at each: does it feel calm and premium, is there one focal point, is anything cut or empty? Check the welcome does not show again after it let go (until Replay), the window box keeps its size, the overflow scan is clean in every state (no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped), and the console has no errors. Then `close_page`.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"First launch: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts the code does not have yet>","surface":"menu"},
 {"file":"<ID>-b.html", ...}
]}
```
