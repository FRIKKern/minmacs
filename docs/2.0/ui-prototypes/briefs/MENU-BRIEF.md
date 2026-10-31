# Round 133 to 142: the menu again, 03-b with what we learned

You are one of 10 design agents. Each makes **2 variants**. Your ID is one of 133 to 142, and your direction is the one under your ID below.

## What the owner said

"We want to see 20 new versions inspired by the 6/240 and what we learned so far". Gallery number 6 is **03-b "One Icon, ftop Lines"**: one flat menu that drops from the MinMacs icon in the menu bar. Each section opens with an ftop mini header (a badge with an arc, a big number, a small gray unit), then a few rows with owner, size and a state mark. A hover card sits beside a row, its facts link to other sections, and pointing at a link lights the matching row.

So this round goes back to the **menu** surface of 03-b. It is not a 1040 × 760 sheet. It carries everything learned in rounds 13 to 132.

## What we learned (all of it holds)

- **Plain names only.** Apps, Servers, Worktrees, Disk, Agents, Workstreams. Never LocoHost, WorkForest, Noo-Noo or Insomnia; say MinMacs. 03-b still uses the old names: drop them.
- **ftop's look.** Dark glass, rings and arcs, a big number with a small gray unit. Every graph says in plain words what it means.
- **Calm at rest (from 127 to 132).** 113-a was "very busy". At rest **at most 15 points** show. A point is a row, a fix, a number with its own label, or a badge. No badge at rest, except on a row that needs the person. One number per row at most; the rest goes in the hover card. Peak may hold more parts, never more points: it folds harder, under a "More" row.
- **Servers and Worktrees matter most** (131). They usually show the most rows. Agents, Apps, tabs, helpers and caches get fewer.
- **The ring of 132-a / 204** is the owner's favorite gauge: one ftop gauge, memory by holder inside, disk as the outer track. **Memory and disk are never one number.**
- **Ranked fixes and Fix Everything** (97 to 99, 132). Biggest move first (a whole finished workstream's Wrap Up usually leads). Show the first fix in full and the rest as one line, "and 6 more fixes · 3.4 GB memory, 31.1 GB disk". Fix Everything plays each kind at its own pace (Wrap Up in steps, tabs one by one, a server's memory back a beat after its port frees, caches counting down). It skips what needs the person and what is blocked, and says why.
- **The copy never claims a result.** No "The Mac is clean", "Everything is fine" or "Nothing needs you". A line of text shows only when something needs the person, such as "1 agent asks you". A calm Mac shows only numbers: memory and disk back this week and today, small.
- **Rewards are short and let go.** Far less Undo: after an action, go to the next. Deletes say "for good". No Undo in the menu.
- **The button always shows; the glow comes on hover.** No dead buttons. Hover any row to light its slice in the ring and its parts elsewhere.
- **Keep working with the lid closed** lives only in Settings. Never in the menu.
- **No cut lines, ever.** No "...", no ellipsis, no clipped text. Fit by shorter words or a wider menu.
- **Real time.** Rows arrive, tick and leave. Agents spawn and finish.

## The menu standard

Read `../../DESIGN.md` (in this repo, `docs/DESIGN.md`), sections "The menu is native", "The menu bar", "Every line earns its place" and "Words". 03-b followed it. Your page draws the menu as a macOS menu: a menu bar strip at the top of the 1280 × 800 stage with the MinMacs icon, and the menu hanging from it, about 320 to 520 px wide unless your direction says otherwise, never taller than the stage. Keyboard: arrow keys move a highlight, like a real menu. The footer is Hide Icon, Settings… and Quit MinMacs. Directions may bend the standard on purpose; say where in your JSON tradeoff.

## Facts

What the code really knows is in `briefs/REAL-BRIEF.md`, and since wave 7 on `main` also:
- `/Volumes/SATECHI/github/minmacs/Sources/Core/MMPerformance.h`: 132-a's Performance as a model. Read its top comment: it lists what 132-a draws that Core does not measure (per-tab memory, the time a fix takes, CPU and network beside the ring).
- A kept log of what came back (`minmacs gains`): memory and disk apart, by day, kind and who did it.
- The last hour in memory (`minmacs history`): the Mac, disk, agent and server rings, agent states, subagent starts.
- The whole Mac's network (`minmacs net`), and the home volume's size.
- Wrap Up closes a workstream's localhost tabs.

A fact the code does not have is marked "proposed" on the page and listed in your JSON.

## Directions

- **133 Native, by the book.** The strict DESIGN.md menu with today's facts. a: a two-line header with two small ftop gauges (memory, disk), then Servers, Worktrees and one more section, Fix Everything as one of the two actions. b: the same, with the header as one small split ring like 132-a and the summary as the one thing that needs you.
- **134 The ring on top.** 132-a's gauge as the menu's header view, a little smaller, with rows below that each have a home on the ring. a: the ring centered, rows below in two sections. b: the ring left in the header, the first fix to its right.
- **135 Fix first.** The menu opens on what to do. a: the first fix in full and "and 6 more" that opens a submenu-like list; Fix Everything plays inside the menu rows. b: the fixes are the sections, each fix a row with its two numbers; the Mac's state is one thin header line.
- **136 By workstream.** Sections are workstreams, not kinds, as 03-b's cross-links hinted. a: each workstream one ftop mini header with what it holds (servers, worktree, agents) and Wrap Up on hover; Leftovers last. b: only the 4 heaviest workstreams open, the rest one line each.
- **137 The card carries it.** A very short menu (well under 15 points), and a rich hover card beside it that holds the detail: the ring, the row's story, its links. a: card to the right of the menu, like 03-b. b: the card replaces the menu body in place while you point, and steps back when you leave.
- **138 Balanced wide menu.** A menu about 600 to 720 px wide with two halves: Servers and memory on the left, Worktrees and disk on the right, ending level (as 131). a: the ring in the middle between them. b: no ring, each half has its own arc gauge header.
- **139 Lines that open.** Each section is one ftop line (badge, arc, big number, gray unit) and nothing else at rest. a: pointing at a line opens its rows in place, the others shrink. b: lines open as a submenu to the side, like a native menu.
- **140 The last hour.** Use the new history. a: each section line has a small graph of its last hour, labeled ("memory, last hour"). b: one hour graph under the header with memory and disk apart, and each row shows where it started on that graph when you point at it.
- **141 Type to find.** Like the macOS Help menu: a search field at the top of the menu. a: at rest the menu is the 132-a picture small; typing filters every part (servers, worktrees, agents, apps, caches) into one list with its fix. b: no rest view at all beyond the ring and the field; typing or arrow keys bring the parts.
- **142 The icon and the bar.** Start at the menu bar icon itself. a: the icon is a tiny ring with a number only when the person must act; the menu under it is very short and the ring opens big on hover. b: one icon per section in the menu bar (DESIGN.md allows each part its own icon), each with its own short menu; show two or three of them open in turn on the stage.

## Read first

All in `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/` (served at `http://127.0.0.1:8766/p/<file>`):
- `p/03-b.html`: the menu to start from. Hover the rows and the cross-links.
- `p/132-a.html` and `p/132-b.html`: the current favorite sheet: its ring, groups, fix deck, Fix Everything and look-back. Its README section "Performance, latest".
- `briefs/CALM-BRIEF.md` (the 15-point rule), `briefs/IMPACT-BRIEF.md` (fixes and the pace of each kind), `briefs/REAL-BRIEF.md` (facts).

## Output

Copy `p/132-a.html` into your two new files: keep its fixture data, its live simulation, Quiet / Busy / Peak, Fix Everything's pacing and its Settings sheet. Replace what shows at rest with your menu. **Settings… in the menu opens the 132-a sheet on Settings**, and the sheet keeps its tabs and Advanced mode, so `go(tab)`, `setScn(k)` and `setAdv(v)` keep working. Never edit an existing page.

- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-a.html`
- `/Volumes/SATECHI/github/minmacs-worktrees/ui-prototypes/docs/2.0/ui-prototypes/p/<ID>-b.html`

Open with the menu down, at Busy, with fixes to do. Name new functions and classes with your ID so they cannot clash (`m133…`); check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

**Count the points at rest at Busy and write the count in the stage caption.**

## Verify

Many agents share one Chrome and one scratchpad. Use chrome-devtools MCP: `new_page` with `isolatedContext` = your ID and `background: true`, then `resize_page` 1280×800, and **pass your own pageId on every call**. Never select or close a page you did not open. Keep scripts and screenshots in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/menu-<ID>/`.

Screenshot the menu in Quiet, Busy and Peak, a row hovered, its hover card, mid Fix Everything, the end of the run, and Settings… open. Look at each. Run an overflow scan in all three, at rest, hovered and mid-run: no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped. Check the console has no errors, then `close_page` your own page.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Menu: <idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts you used that the code does not have yet, or none>","points_at_rest":<number at Busy>,"surface":"menu"},
 {"file":"<ID>-b.html", ...}
]}
```
