# MinMacs 2.0: Workstreams round brief

You are one of 6 design agents. Each makes **2 variants**. You extend one composition from the last round and add a **Workstreams** tab.

## What the owner said

"Please have another round now adding Workstreams tab also"

Earlier, on agents: "also agents and workstreams or just one of them is important part i want to see more of". On composition: "We have to be more creative, it is so boring that this thing is always the same in same position... we need perfect compositions". The owner starred **Workstream Cards** (`p/09-a.html`): one card per piece of work showing its servers, worktree, caches and keep-awake as badges, with Wrap Up on the finished one. Study it.

## Owner update (overrides anything below that conflicts)

"I think we should focus abit more on the realtime aspects - numbers change - things are moving - agents are spawning - agents are disappearing. Also we want to make it more easy to understand the actions of "auto" etc. I think its still very hard to understand what we press. Also the "Keep awake" thing is far too much represented. It kinda only need like a check. And its most focus of commincating is that you can close the lid without turning off the agent, and some notices about how it work with 20% power, wifi etc. Lets start with no adjustable settings on this"

1. **Real time.** The mockup runs a live simulation: numbers tick (CPU, memory, idle timers counting up, "Working 2m" becoming 3m), graphs ease, and things come and go. Every 5–10 s something happens: a subagent spawns in speed-3, one finishes and leaves, media-scope's tests finish, a server starts on :5174, an idle server crosses its threshold. Arrivals slide in with a soft "New" glow; departures show "Finished" briefly, then fold away. Counts in the Live Index update live. Calm, never jumpy. Respect `prefers-reduced-motion` (fades only). A small pause toggle is fine.
2. **Make Off / Ask / Auto and every button obvious.** At the point of choice, say in plain words what will happen: **Off**: "Not watching." **Ask**: "Shows a button. Nothing happens until you press it." **Auto**: "Does it for you after 2 h and sends a notice with Undo." Show the next automatic action with a live countdown ("Auto stops :3334 in 1 h 18 m"). Button labels state exactly what happens and to what: "Stop 3 Servers Now · 1.45 GB", not "Close Idle". Hovering a button shows its result first (what goes, what stays), then press, then Undo.
3. **Keep Awake shrinks to one check.** Remove it from the Live Index and from the tabs. Put a single checkbox where it belongs (in the Agents or Workstreams view, or the sheet footer): "☑ Keep working with the lid closed". Its main message: you can close the lid and your agents keep working. One small gray note: "Stops at 20 % battery, if Wi-Fi drops, or if the Mac runs hot." No adjustable values. When on, a tiny live line can say "4 agents working · lid can close".

Left Live Index order is now: **Workstreams, Agents, Apps, Servers, Worktrees, Disk** (6 entries, no Keep Awake).

## Everything from before still holds

Read `COMPOSE-BRIEF.md` (composition rules, what must stay), `ACTIONS-BRIEF.md` (hover actions, section actions, Agents tab), `SHEET-BRIEF.md`, `SETTINGS-BRIEF.md` and the fixture data in `BRIEF.md` (ignore its old app names). All in `<scratchpad>/gallery/`. Files are served at `http://127.0.0.1:8765/p/<file>`.

## Workstreams vs Agents

- **Agents** = the running processes: tool, where it runs, state, time. Keep this tab.
- **Workstreams** = the pieces of work. One workstream holds its agent(s), worktree and branch, PR, servers, caches, headless browsers, and whether it keeps the Mac awake. This is the "Wrap Up" unit.

Left Live Index order: **Workstreams, Agents, Apps, Servers, Worktrees, Disk, Keep Awake** (7 entries). Workstreams' mini graph shows the 8 workstreams by stage (e.g. 8 short lanes: working, needs you, idle, ready to wrap up).

## Workstreams fixture (use exactly this)

| Workstream | Agents | Stage | Worktree / branch | PR | Servers | Caches & browsers | Awake |
|---|---|---|---|---|---|---|---|
| speed-3 | Claude Code + 2 subagents, cmux tab speed-3 | Working 2m | speed-3-base, 3 commits ahead | #214 draft | :3000 next 412 MB, :5173 vite 188 MB | node_modules 1.3 GB, Chrome for Testing (Playwright) | Yes |
| bp-lane-c | Claude Code, cmux tab bp-lane-c | Working 14m | barkpark-lane-c | none | :4100 phoenix 260 MB | .next 640 MB | Yes |
| media-scope | Codex, Codex app | Working 6m, tests running | media-scope | none | none | none | Yes |
| studio-icons | Cursor, barkpark-studio window | Working 1m | main checkout | none | none | none | Yes |
| lexicon-judge | Claude Code, tmux pane lexicon:1 | Needs you 3m: "Allow npm run build?" | lexicon-judge | none | none | none | No |
| studio-parity | Claude Code, cmux tab studio-parity | Idle 40m | studio-parity | #209 open, checks pass | :3334 sanity 640 MB | none | No |
| fix auth redirect | Codex | Finished 2h, ready to wrap up | auth-redirect, squash-merged | #207 merged | :4000 phoenix idle 2h 290 MB | node_modules 1.8 GB | No |
| lane-e-sort | none (ended yesterday) | Ready to wrap up | lane-e-sort, merged | #201 merged | none | node_modules 2.3 GB | No |

Plus a calm **"No workstream"** group: :6006 storybook idle 3d 520 MB, bp8-sweep-studio403 stale 34d 1.1 GB, Xcode DerivedData of 4 gone projects.

Workstream actions (hover): **Go to Tab**, **Wrap Up** (stops its servers, removes its merged worktree, cleans its caches, closes its headless browser; one Undo), **Open PR**, **Stop Servers**, **Keep**, **Open in Editor**. Blocked stays visible with the reason ("Wrap Up…   3 commits not in main"). Section action: **Wrap Up Ready** (2 workstreams · 4.4 GB).

Workstreams setting: mode Off / Ask / Auto; rule "Wraps up a workstream [1 h] after its PR merges and its agents finish"; values 1 h / 1 day / 1 week; live "2 ready · 4.4 GB".

The other tabs should link items to their workstream (e.g. :4000 → fix auth redirect).

## Your two variants

- **a:** take the composition file named in your assignment, keep its composition idea, and add the Workstreams tab composed in that same idea (and the extra Live Index entry). Improve anything that looked off.
- **b:** the same composition idea, but with a **different, bolder composition for the Workstreams tab** itself (it may also become the default tab that opens first).

## Output

Two self-contained HTML files (full `<!doctype html>`, inline CSS/JS, no network except optionally Google Fonts; font stack `-apple-system, "SF Pro Text", system-ui`; no emoji; inline SVG icons):

- `<scratchpad>/gallery/p/<ID>-a.html`
- `<scratchpad>/gallery/p/<ID>-b.html`

Never edit the source file you start from; copy it into your new file. Same stage, interactions with Undo, `prefers-reduced-motion`, no `alert/confirm/prompt`, `<title>` = variant name.

Verify in a real browser: chrome-devtools MCP, `new_page` with `isolatedContext` = your ID and `background: true`, `resize_page` 1280×800 **on your own page id only**, screenshot every tab (save with `filePath` in the scratchpad and look at each), `close_page` on your own page. Never touch pages you did not open. Revise until each tab looks deliberate. Check clipped text and console errors.

Reply with ONLY this JSON:

```json
{"id":"<ID>","direction":"Workstreams: <composition idea>","variants":[
 {"file":"<ID>-a.html","name":"<2-4 word name>","idea":"<one sentence: the Workstreams tab and how it fits>","good":"<one sentence>","tradeoff":"<one sentence>","surface":"menubar"},
 {"file":"<ID>-b.html", ...}
]}
```
