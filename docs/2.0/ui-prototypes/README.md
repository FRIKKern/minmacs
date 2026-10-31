# MinMacs 2.0 UI prototypes

322 clickable HTML mockups of the 2.0 menu bar UI, made in rounds on 2026-10-27 and 28 with [ftop](https://github.com/Nongfsq/ftop) as the visual inspiration. Each is one self-contained page at a 1280 × 800 stage. They use fixture data, not live data.

## View them

```sh
cd docs/2.0/ui-prototypes && python3 -m http.server 8765
```

Then open <http://127.0.0.1:8765/>. Arrow keys step through them, `S` stars one, `G` shows a grid, `W` switches between the full window and the list. Stars and notes stay in that browser. One page alone opens at `http://127.0.0.1:8765/p/<id>.html`.

`manifest.json` holds each page's name, idea, strength and cost. `briefs/` holds the brief each round's design agents worked from, with the owner's words for that round. The briefs name scratchpad paths from the session that made them.

## Rounds

| Pages | Round | What the owner asked for |
|---|---|---|
| 01–12 | First spread | Many alternatives in ftop's style: one panel, the menu bar, native menus, one page per expert, workstreams, cards, settings, wild cards |
| 13–18 | Settings | "More elegant and spacey", plain names instead of the old app names, Off / Ask / Auto per section |
| 19–24 | Hanging Sheet | Picked 18-b, "more details - graphs and such", each tab mixing activity and settings |
| 25–30 | Actions | Hover to act on any item, section actions, the Live Index sidebar from 20-a, an Agents tab |
| 31–36 | Composition | "Perfect compositions": the setting woven into each view, not a block at the bottom |
| 37–42 | Workstreams | A Workstreams tab, real time (things spawn and finish), plain-word actions, Keep Awake as one checkbox |
| 43–48 | Minimal | Continue 41-b, a much smaller sheet, a very minimal sidebar, a Servers tab with a real graph |
| 49–54 | More space and three tabs | Roomier sheets, and a simple mode of Workstreams, Performance and Settings with an Advanced mode that brings every tab back |
| 55–57 | Row Poster with real facts | 53-b kept to its intent but drawn only from facts the 2.0 code has, with each page checked against the sources |
| 58 | Holdings Map with real facts | 54-b with its browser nodes drawn from real localhost tabs, and a Quiet, Busy and Peak switch to test the map at 20 workstreams |
| 59 | Faithful map as a bento grid | 58-a with tiles sized by what each workstream holds, and in 59-b also by what it needs from you |
| 60 | Room to breathe | 59-b with padding, gaps and label room set as rules, leftovers as one line under the grid, and either a bigger sheet or fewer full tiles |
| 70–75 | Performance as the Mac's panel | 60-a kept, its Performance tab made "a very improved version of" 01-a: one live insight line, CPU and memory, apps by fate, storage with the leftovers, network and servers. Each page lists in the manifest the facts it uses that the code does not have yet |
| 76–81 | Lift the Advanced tabs | 71-a kept, its Agents, Servers, Worktrees and Disk tabs brought to its Performance tab's level, and "utilize the space better": no flat full-width rows, no scroll when the items fit in columns. Six layouts: 71-a's own, list and detail, one big graph, columns by fate, workstream blocks, ftop tiles |
| 82–87 | A hero on top of 77-a | 77-a kept (list left, live detail right), and each Advanced tab gets a hero band above it that shows the whole section at a glance, "a cool way to grasp it all in a beautiful way": ftop gauges, a panorama graph, a map of every item, a sentence with inline graphs, strata bars, a small bento. Hero and list light each other |
| 88–90 | An elegant notice on 82-a | 82-a kept. The focal sentence and big button felt "just in the way", so the notice becomes small and placed (a pill under the ring, the ring itself, or a badge), gives an elegant reward when something is done, shows its full story in the inspect view on hover, and keeps Undo there instead of a toast |
| 91–93 | Performance in 89-a's language | 89-a kept (the favorite: the ring is the notice, press, pop, next, far less Undo, deletes are permanent). Its Performance tab gets the same hero and one chain button for the best next thing on the whole Mac: a memory ring like the other tabs, the queue as the ring, or four ftop rings for CPU, memory, disk and network |
| 94–96 | Performance as a clear view of everything | "Apps and performance is different". 89-a's Apps tab kept as it is, and a new Performance tab (after Workstreams; in the simple mode it is the overview) shows the whole Mac and every section in short, with the one next action: four rings over six section cards, one ring with a live index, or one picture of everything |
| 97–99 | Performance ranked by impact, and Fix Everything | "start with fixing full workstreams ... continuing with less and less important". On 94-a, the Performance hero is a list of 7 fixes, biggest move first, each with its memory back and disk back, and a Fix Everything run whose steps and pace fit each kind of action: an impact ladder or two waterfalls, now and after rings or a timed plan, a live run beside one ring or a stack of cards |
| 100 | What got better lately | "177 is nice. When nothing left to fix, show a summary of what how much we have improved lately". On 99-b, the calm Performance view looks back over today and the week: memory back and disk back as two numbers, a 7-day chart and counts by kind, or the deck turned into done cards, newest first |
| 101–103 | More ways to show what got better lately | "I want more variations of this screen". The calm view on 100-a, opening already calm: the week as two rings or the Mac then and now as gauges, a day strip hour by hour or the week as sentences, split by who did it or by workstream |
| 104–106 | New layouts for Performance, the parts and the whole | "using left to see all processes and stuff - and right for the overall things - just as an example". On 100-a: every running part on the left by kind or by owner with the Mac and the fix deck on the right, three columns or the whole above a sortable table, or a right side that follows what you pick and a list sorted by the ring you point at |
| 107–126 | Forty more layouts for Performance | "Give me 20 more", then "More". On 100-a, each pair a different way to hold the parts and the whole: a live index, treemaps, owner rings and lanes, a live feed and process strips, search and filters, bento, the Mac in the middle, fate columns, drill down, sentences and huge numbers, constellations and a floor plan, Sankey flows, stacks, kind pages, rankings, age, a pro table and pivot, explanations and questions, hot spots and forecasts, glance and lens |
| 127–129 | Mac at Center, calm | 113-a was liked but "very busy": at most 15 points at rest, details on pointing, and the lid setting only in Settings |
| 130 | Split Ring, the owner's cuts | "205 is still better": 113-b without the side headings and the lid footer, and a calmer fix deck, as a quiet list or one fix and a line |
| 131 | Servers and worktrees first | "Servers top left, Worktrees top right ... they should show a lot usually. We should feel balance on left and right side": 130 with Servers leading the left, more rows for both, fewer for the rest, and both sides ending level |
| 132 | 204's ring | "204 had the best ring in my opinion": 131 with 113-a's gauge, memory inside and disk as the outer track |
| 133–142 | The menu again, 03-b with what we learned | "20 new versions inspired by the 6/240 and what we learned so far". Gallery 6 is 03-b, One Icon ftop Lines: one flat menu from the MinMacs icon. On 132-a's data, at most 15 points at rest: the strict native menu with gauges or a small split ring, the ring on top, fix first, by workstream, a short menu with a rich card, a wide menu with servers left and worktrees right, ftop lines that open, the last hour, type to find, and the menu bar icon itself |
| 143–162 | 251 with more processes and a footer of icons | "more inspired by 251 - but for example, i would like to see more of the processes", and Hide Icon, Settings and Quit "could become icons and take less space ... boil the ocean". On 138-a, each pair a way to show many more processes, with the footer as three small icons: more rows, process trees, a place for agents, an Activity Monitor list, three columns, tiles and a treemap, bars in rows, live arrivals, halves that scroll, a switch per half, callouts around the ring, CPU beside memory, a port grid, by workstream, a small ring, a tall menu, rows that open, idle heat, who started it, and a wall of words or a skyline |
| 163 | 149-a with the owner's changes | On 149-a, gallery 273, only what the owner pointed at: each group scrolls on its own, the fixes move to the center and the caption to the bottom, no Hide Icon, CPU on every row and in the center, a wider center that shows the row you point at, page screenshots for local servers, and an icon for what each thing is |
| 164–173 | 162-b's skyline with the last hour beside the ring | "we also love 162b - but on left and right of the center thing - we would like the memory in use + disk free from 158b - also learning from the one we just made". On 162-b with every rule of 163: a straight merge, the skyline as the list, three graphs a side, the hour behind the skyline, a CPU skyline, the center as a stage, icons first, screenshots everywhere, calm at rest, and two wild ones (scrub the hour, the skyline as scrollbar) |

## Direction so far

- Inspiration is ftop: dark glass, round badges with arcs, a big number and a small gray unit.
- Sections use plain names: Workstreams, Agents, Apps, Servers, Worktrees, Disk. Never the old app names.
- Workstreams are the main unit. A workstream holds its agents, worktree, PR, servers, caches and browser, and Wrap Up clears it in one undoable step. The owner runs 12 or more agents at once.
- Keep Awake is one checkbox, "Keep working with the lid closed", with a short note on when it stops.
- Every graph says in words what it means. Every button says exactly what it does. Off, Ask and Auto are explained where you choose them.
- The UI is live: numbers tick and agents come and go.
- Favorites so far: 89-a Ring Is the Notice, 82-a Ring and Gauges, 77-a List and Detail, 71-a Worth Doing First, 60-a A bigger sheet, 41-b Corner Drawer Spotlight, 18-b Hanging Sheet, 20-a Live Index, 09-a Workstream Cards, 03-b One Icon ftop Lines.

### Performance, latest

The owner's picks on 2026-10-30, newest last:

- 113-b Split Ring, gallery 205, is the base. 113-a, gallery 204, has the best ring: one gauge with memory by holder inside and disk as the outer track.
- 130-a and 130-b cut from 113-b only what the owner named: the side headings "Memory, the left half" and "Disk, the right half", the lid footer, and a busy fix deck.
- 131 puts Servers at the top left and Worktrees at the top right. They are the most important groups, they show many rows, and the two sides stay balanced.
- 132-a and 132-b are 131 with 204's ring. They are the current favorite. The run view is quiet, and the look-back shows only small numbers: memory and disk this week and today.
- "Keep working with the lid closed" lives only in Settings, in the This Mac card. It is never on Performance or another tab.
- The copy never claims a result. No "The Mac is clean", "Everything is fine" or "Nothing needs you". A line of text shows only when something needs the person, such as "1 agent asks you".
- When the owner points at specific elements, change exactly those on that page. Do not start a new layout.
- "Deletes are permanent" from 89-a changes the Trash-first behavior and needs the owner's decision before any code.

Wave 6, the sheet UI, waits for the owner's final pick. Sources/Core/MMSheet.h on main still describes 54-a.

These are design explorations. They break [DESIGN.md](../../DESIGN.md) in places on purpose, most of all its rule that the menu is a native NSMenu, and the rules there change only by decision.
