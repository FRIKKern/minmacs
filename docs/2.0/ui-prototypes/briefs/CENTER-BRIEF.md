# Round 163: 149-a with a bigger center, scrolling groups, CPU and real icons

You are the one design agent this round. Make **2 variants**, `p/163-a.html` and `p/163-b.html`, from a copy of `p/149-a.html` "Bars Under Names". The owner pointed at exact things on 149-a. Change those, keep the rest of 149-a as it is. Do not start a new layout.

## What the owner said, point by point

1. **Scroll inside each group.** "We should be able to scroll within the different parts like servers etc ... be able to scroll in there to see all servers." Servers, Agents, Apps and helpers, Worktrees, and Caches and leftovers each scroll on their own inside their fixed height, so every server (and every agent, app, worktree, cache) can be reached without a More row. Keep each group's header still while its rows scroll. A thin, quiet scroll hint (a soft fade at the bottom edge, or the macOS overlay scrollbar on hover) shows there is more. The halves still end level. The two More rows go away.
2. **Swap the bottom and the center.** "The things in the bottom are what should be in the center and opposite." The first fix in full ("Wrap Up fix-auth-redirect · 380 MB memory, 1.86 GB disk") and Fix Everything ("6 fixes · 2.36 GB memory, 31.1 GB disk") move into the center column, under the ring. What sat under the ring (the icons and the caption lines) moves to the bottom strip, where the fixes were.
3. **No Hide Icon.** "Hide icon should not exist." The footer is two small icons: Settings (gear, ⌘,) and Quit MinMacs (power, ⌘Q), with their name and shortcut on hover. They sit in the bottom strip with the caption.
4. **CPU is more important.** Today CPU is missing. Give it real weight: the center shows the Mac's CPU now (a big number with a small gray unit, and heat) beside memory and disk, with its last hour as a small labeled line ("CPU, last hour"). Rows that use CPU show it: a: CPU as a second number on each process row, as visible as memory. b: CPU as a short live meter beside memory, with the number on hover and in the center. Sorting stays by memory unless the owner asks.
5. **Hover or select shows it in the center.** "When we are selecting / hovering - it will be shown in the center part." Pointing at a row (or moving to it with the arrow keys) shows its full story in the center column, in place of the Mac's own view: its icon, name, big numbers (memory, CPU, disk where it has one), its owner and workstream, its slice lit in the ring, its facts, and its actions. Leaving the row brings the Mac's view back after a short beat. The side hover card goes away; the center is the card. The two fixes in the center light the rows they touch when pointed at, as now.
6. **A bigger center.** "We will make the center part a bit larger so we are able to show more info." Widen the center column (about 340 to 400 px; the menu may grow to about 960 to 1040 px wide), so the ring, CPU, the two fixes and a row's full story all fit, nothing cut.
7. **Screenshots of localhost pages.** "On localhosts where we show websites etc we should see screenshot from the url." A server with a web page shows a small screenshot of its page: a thumbnail on the row (a: a small 40 × 26 thumbnail at the row's left; b: no thumbnail on the row, a large one in the center on hover), and a big one in the center when you point at it, with its URL under it ("localhost:6006"). Draw the screenshots as made-up stand-in pages (a Storybook-like sidebar and canvas, a Next.js-like landing page, a Phoenix-like dashboard, an Astro-like docs page), in plain shapes and gray text bars, never copies of real sites.
8. **Icons for what each thing is.** "Show icons based on what it is - like next favicon for next server - and app icon for the app itself." Every row starts with its own icon: a server shows its framework's mark (Next.js, Storybook, Phoenix, Astro, Vite, Jupyter, Hugo), an app its app icon (Chrome, Spotify, cmux, Cursor), an agent its tool (Claude Code, Codex, Cursor), a worktree a branch mark, a cache its kind (Xcode for DerivedData, npm, Docker, Playwright). Draw them as simple inline SVG stand-ins that suggest each one (a rounded square in the brand's color with a letter or a simple shape), not copies of the real logos. The state mark (dot, triangle) moves to sit small on the icon's corner, or beside the number, so the row does not get wider.

## Keep from 149-a

The two halves (memory left, disk right) and the ring between them, memory inside and disk as the outer track, never one number. Bars under names. The agent that asks on top. Fix Everything's pacing, skipping what needs you or is blocked and saying why. Short rewards that let go, deletes "for good", no Undo in the menu. The copy never claims a result. Plain names only. No cut lines, no ellipsis. The lid setting only in Settings.

## Facts

Read `briefs/REAL-BRIEF.md` and `/Volumes/SATECHI/github/minmacs/Sources/Core/MMPerformance.h`. Mark as "proposed" on the page and in your JSON: screenshots of a server's page, favicons or framework marks, app icons in the model (macOS has them, Core does not send them), CPU of apps and helpers (Core reads CPU for servers and agent trees). The Mac's CPU and its last hour are real (`minmacs history`).

## Output and checks

Keep 149-a's fixture data, live simulation, Quiet / Busy / Peak and its Settings sheet (the gear opens it), so `go(tab)`, `setScn(k)` and `setAdv(v)` keep working. Name new functions and classes `m163…`; check with `grep -o '^function [A-Za-z0-9_$]*' <file> | sort | uniq -d`. Never edit an existing page. Do not edit `manifest.json` or the README, and do not run git. Self-contained HTML, inline CSS/JS/SVG, no network, no emoji, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name. Open with the menu down, at Busy, with fixes to do.

The owner's Mac is busy: run one page at a time and close it when done. Use chrome-devtools MCP: `new_page` with `isolatedContext` = 163 and `background: true`, `resize_page` 1280×800, and pass your own pageId on every call. Keep scripts and screenshots in `/Volumes/SATECHI/dev-caches/tmp/claude-code/claude-501/-Volumes-SATECHI-github/19176dec-a0b1-4ffd-98d0-4074bcc11504/scratchpad/center-163/`. Screenshot Quiet, Busy and Peak at rest, a server hovered (its screenshot in the center), an app hovered, a group scrolled to its end, a fix hovered, mid Fix Everything, and Settings from the gear. Look at each. Run an overflow scan in all three scenarios, at rest, hovered, scrolled and mid-run: no text element with `scrollWidth > clientWidth + 1`, no ellipsis, nothing clipped. Check the console has no errors, then `close_page` your page.

Reply with ONLY this JSON:

```json
{"id":"163","direction":"Center: <idea>","variants":[
 {"file":"163-a.html","name":"<2-4 word name>","idea":"<one sentence>","good":"<one sentence>","tradeoff":"<one sentence>","proposed_facts":"<facts the code does not have yet>","surface":"menu"},
 {"file":"163-b.html", ...}
]}
```
