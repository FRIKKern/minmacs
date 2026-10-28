# Round 70 to 75: Performance as the Mac's panel

You are one of 6 design agents. Each makes **2 variants**. IDs 70 to 75 are reserved for this round, so they do not collide with other rounds on the same branch.

## What the owner said

"116 is favorite. Performance need to be more important and smarter - it should be where we handle leftovers / storage, see networks etc. It should be like... more a very improved version of 1/117"

- **116** is `p/60-a.html`, "A bigger sheet": the bento grid of workstreams on a 1040 × 760 sheet, with Performance and Settings tabs.
- **1/117** is `p/01-a.html`, "One Panel, Medium": one ftop glass panel that shows the whole Mac at once (load, memory, apps and their plan, servers, worktrees, disk, agents) in a calm grid, each block with a badge, a big number, a few rows and one action.

So: keep 60-a exactly as it is for Workstreams and Settings, and turn its **Performance tab** into a far better, smarter version of 01-a's whole-Mac panel. Performance becomes the place for the Mac itself: what uses CPU and memory, what fills the disk and the **leftovers** (moved here from the Workstreams footer, with Clean Up), and the **network**.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/60-a.html` (open every tab in a browser) and `p/01-a.html`.
- `briefs/REAL-BRIEF.md`: the facts the 2.0 code has, field by field, and the rules (never add memory and disk into one number; neutral fixture names; leftovers are disk sizes with clones counted once; subagents as dots without labels). Follow it.
- `p/04-a.html`: CPU and memory bars whose colored end is exactly what MinMacs Now frees, and apps grouped Will close / Unsorted / Kept / Spared. The owner liked this; the core-column graph was "useless - dont understand".
- `briefs/WORKSTREAMS-BRIEF.md` "Owner update" (real time, plain-word actions, Keep Awake is one checkbox) and `briefs/COMPOSE-BRIEF.md` (perfect compositions, no bolted-on settings block).
- `../../DESIGN.md` for words and rows, and `/Volumes/SATECHI/github/minmacs/Sources/Core/Senses/MMSenses.h` for the power, pressure and network facts.

## What Performance shows (smarter, not busier)

1. **One insight line on top**, in plain words, that names the biggest thing worth doing now, with its button. Example: "Chrome holds 8.7 GB, 14 of its tabs are noise. MinMacs Now frees 9.3 GB memory." It changes live as the situation changes.
2. **CPU and memory**, 04-a style: the colored end of each bar is what MinMacs Now frees. Memory pressure in words (Normal). Heat in words (Nominal). No core columns.
3. **Apps by fate** (Will close, Unsorted, Kept, Spared with its reason), agents' load linked to their workstream.
4. **Storage and leftovers**: disk used and free (812 / 994 GB, 182 GB free), the reclaimable part split by kind (DerivedData, node_modules in merged worktrees, npm cache, Playwright browsers, Docker build cache, simulators report only), who owns each and whether the owner is gone, and **Clean Up Leftovers** with exactly what goes to the Trash and what a tool's own command cleans. Disk sizes only.
5. **Network**: what the code knows today is whether the Mac is online and over what (Wi-Fi, Ethernet, tethering) and, per server, its connections now and the apps connected. Total download and upload from interface counters is cheap and not yet in the code: you may show it, marked in your JSON as a proposed fact. Per-app bytes are **not** known (nettop is forbidden in a tick); do not invent them. Make the network block useful anyway: online state, the live total if you use it, which local servers have connections and from what, and what MinMacs pauses when offline.
6. **Servers' cost** in short (memory and connections), linked to Workstreams, with idle ones marked.
7. **Keep Awake** stays one checkbox with its note, wherever it fits best.

Real time: numbers tick, bars ease, leftovers shrink when cleaned, a server's connections come and go. Every action previews what it touches, then acts, then offers Undo.

## Output

Copy `p/60-a.html` into your two new files and change the Performance tab (fix anything in other tabs only if your change needs it). Never edit `p/60-a.html` or any other existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Do not edit `manifest.json` or the README, and do not run git; the lead adds your pages. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot the Performance tab in each state (and the other tabs once) with `filePath` in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/`, look at each, `close_page` on your own page. Never touch pages you did not open. Check clipped text, overlaps and console errors, and fix them.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Performance: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
