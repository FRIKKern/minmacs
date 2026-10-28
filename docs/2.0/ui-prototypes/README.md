# MinMacs 2.0 UI prototypes

165 clickable HTML mockups of the 2.0 menu bar UI, made in rounds on 2026-10-27 and 28 with [ftop](https://github.com/Nongfsq/ftop) as the visual inspiration. Each is one self-contained page at a 1280 × 800 stage. They use fixture data, not live data.

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

## Direction so far

- Inspiration is ftop: dark glass, round badges with arcs, a big number and a small gray unit.
- Sections use plain names: Workstreams, Agents, Apps, Servers, Worktrees, Disk. Never the old app names.
- Workstreams are the main unit. A workstream holds its agents, worktree, PR, servers, caches and browser, and Wrap Up clears it in one undoable step. The owner runs 12 or more agents at once.
- Keep Awake is one checkbox, "Keep working with the lid closed", with a short note on when it stops.
- Every graph says in words what it means. Every button says exactly what it does. Off, Ask and Auto are explained where you choose them.
- The UI is live: numbers tick and agents come and go.
- Favorites so far: 89-a Ring Is the Notice, 82-a Ring and Gauges, 77-a List and Detail, 71-a Worth Doing First, 60-a A bigger sheet, 41-b Corner Drawer Spotlight, 18-b Hanging Sheet, 20-a Live Index, 09-a Workstream Cards, 03-b One Icon ftop Lines.

These are design explorations. They break [DESIGN.md](../../DESIGN.md) in places on purpose, most of all its rule that the menu is a native NSMenu, and the rules there change only by decision.
