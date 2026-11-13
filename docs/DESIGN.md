# Design standard

MinMacs 2.0 has one face: the menu window, which opens from the one MinMacs icon. This page says how it looks, what it says and how it is built. The menus of before are still in the app and open when the pref `core.window` is off. Their rules are the second half of this page. A change that breaks a rule here is a bug.

## The menu window

One icon sits in the menu bar. A click opens a window under it, 1020 by 728 points, dark glass in every appearance. It never resizes. It closes as a menu does: on Escape, on a click outside, when another app comes to the front and when the space changes. Its first frame is drawn before it comes on screen.

The layout is prototype 195-a, Dock Below:

```
+-----------------------------------------------------------------+
| 2 agents ask you             (folded away when nobody asks)     |
+------------------+--------------------------+-------------------+
| Servers          | Memory in use, last hour | Worktrees         |
| Agents           | Disk free, last hour     | Caches            |
| Apps and helpers | (or a pointed row's story)|                  |
+------------------+--------------------------+-------------------+
| ring  42.4 / 64 GB   [ Fix Everything ]   3.1 GB memory back    |
|       182 GB free    7 fixes, x first     18.6 GB disk back     |
+-----------------------------------------------------------------+
|                                                    gear  power  |
+-----------------------------------------------------------------+
```

1. **Memory left, disk right.** What holds memory is on the left: servers, agents, apps and helpers. What holds disk is on the right: worktrees and caches. Memory and disk are two numbers everywhere and are never added into one.
2. **The middle.** It shows memory in use and disk free over the last hour. While the pointer rests on a row it shows that row's story: its name and group, its number, and one line that says whether it asks, goes or stays and why, then its facts and where it stands in its group. The dock's ring lights that row's arc, and the numbers beside it are the row's. The first minutes of an hour show the newest value large over an empty track, never a made-up line.
3. **The top line** says who asks the person, such as "2 agents ask you". When nobody asks it folds away and the lists get its height.
4. **The dock.** The ring shows memory by group, with the disk as the thin outer track. Fix Everything runs every fix that does not need the person, in order. Under it one line says what a press does: "7 fixes, Wrap Up fix-auth-redirect first". While the pointer rests on the button, the numbers beside the ring are the Mac after the fixes. While a run plays, the button holds the step, "Fix 3 of 7" and a small Stop stand under it, and a press on either stops the run after that step. With nothing to fix the button stays in place, dimmed, with no line under it: the window never claims a result.
5. **The gains** stand right of the button, a number for memory and a number for disk. A side shows only when it is above zero, so a fix that gives no disk back shows no "0 MB disk back". One side alone sits level with the middle of the button. With nothing to fix, what came back today stands there, by the same rule.
6. **Two buttons only:** the gear for Settings, also Command-comma, and the power icon for Quit, also Command-Q. There is no Hide Icon.
7. **A row's name is never cut with an ellipsis.** A name longer than its column loses whole words from the end.
8. **No row is cut in half.** Each group is a whole number of rows high. Where rows wait below, the last row shown fades as a whole and the header says "9 more below". A side with room to spare makes its rows taller, with a second line each, and closes with its whole number: "This disk", free, held by these rows, and the rest.
9. **One rule for sizes.** Megabytes are whole. Gigabytes have one decimal, which stays when it is a zero, and a second one under 10 GB when it says more: "1.0 GB", "6.6 GB", "1.86 GB". From 100 GB up the number is whole.
10. **Quiet rows step back.** An idle server or agent, a helper, a cache nothing uses or a worktree with nothing uncommitted has its name drawn a step dimmer, unless a fix touches it or it asks.

### Settings in place

Settings is prototype 197-b. The gear turns the area under the top line into cards, in the same window, and back. Escape leaves Settings first. Opening MinMacs again and `minmacs://settings` open the window turned over to Settings.

- One card for each rule: "Stop idle servers", "Quit apps", "Remove finished worktrees" and "Clean caches and leftovers". Each has three choices, Off, Careful and Eager, and each choice has one sentence that says what it does today. `test/window.sh` checks each sentence against the expert's own rule.
- One card for the removal choice, "When MinMacs removes things": Smart, Trash or Delete, each with Core's own sentence.
- One card for this Mac: "Keep working with the lid closed" and "Open at login".

A press applies at once. There is no Save.

### The welcome

The first time the window opens it shows the welcome alone, prototype 199-a: what MinMacs is in two sentences, the Open at login switch, the removal choice, three facts and Start. Nothing is applied until Start, and Return presses Start. After Start the welcome never comes back.

- No login item is added before Start. For a person whose first launch had the window, the switch starts on. For a person who had MinMacs before, it starts on what their login item is now.
- The removal choice starts on the one the person already made, else on Smart.
- Each fact is read from the code that makes it true, so it changes when the code does.

### The removal choice

Where a removed thing goes is one setting, the pref `core.removal`, shown in the welcome, on its Settings card and by `minmacs removal`. Smart deletes what git or its tool can give back, and the rest goes to the Trash. Trash sends everything to the Trash. Delete deletes everything at once. Every word about a removal follows the choice. [AGENTS.md](../AGENTS.md) invariant 1 has the whole rule.

### Words in the window

- Plain names: Servers, Agents, Apps, Worktrees, Caches. The app is MinMacs. No shown string names LocoHost, WorkForest, Noo-Noo or Insomnia.
- Never claim a result, such as "all clean". Say what is there and what a press does.
- No exclamation marks, no emoji, no ellipsis, no asides in parentheses.
- "For good" and "permanently" are not used.

### How it is built

```
MMGraph snapshot --> MMPerformance --> MMWindowModelFrom --> MMWindowModel --> MMWindowPanel, MMWindowView
     any queue        window queue        the feed, off main    plain values       main: draws only the model
                                                ^                                        |
                MMWindowController <------------+------------- MMWindowHost: presses ----+
```

- **The view model**, `Sources/UI/Window/MMWindowModel.h`, is plain values with no AppKit and no Core type. Every string in it is shown as is.
- **The feed**, `Sources/Shell/MMWindowFeed.h`, makes one model from one snapshot and its `MMPerformance`, off main. `minmacs window --json` prints what it makes.
- **The controller**, `Sources/Shell/MMWindowController.h`, works only while the window is open. It builds one model per snapshot, applies a press that comes through `MMWindowHost`, and sends a new model. Fix Everything runs through `MMFixRunner`, which acts only through `MMRunAction` and `MMRunWrapUp`.
- **The views**, `Sources/UI/Window`, run on main and read only the model: no disk, no process, no graph.

### Checked, not assumed

`tools/render.sh` draws the window from fixture models into `build/render/window/`, in dark and in dark with Increase Contrast: the main view, a pointed row, Settings, a run and its end, nothing to fix, one gain alone, and the welcome. It runs its checks of this page into `checks.txt`, and writes how long a first frame took to `window/open-ms.txt`. After a change to the window, look at the PNGs.

## The menus of before

With `defaults write no.guerrilla.minmacs core.window -bool NO`, and MinMacs opened again, each expert has its own icon and menu, or all five share one in "One Icon" mode, and Settings is a window of its own. The rules from here to "Words" are for those menus. They started in LocoHost and WorkForest, and research track G checked them against Apple's Human Interface Guidelines ([G-menu-ux.md](2.0/research/G-menu-ux.md)).

### The menu is native

The menu is an NSMenu. A popover was tried and felt slow next to the system's own menus. Custom views are used only for text meant to be read: the header, the summary and the hover card. Text that should be read is never a disabled item, because macOS greys those out. Section titles use `+[NSMenuItem sectionHeaderWithTitle:]`. A sentence that explains a mode or a setting goes in a hover card or the Settings window.

### The menu bar

1. **The icon.** Each expert's icon is a square template symbol at one point size, with no text. A number shows beside it only when it asks the person to act, and then at most three characters.
2. **Saved position.** Each status item sets `autosaveName` to `minmacs.<expert>` and allows removal. Settings shows the same visible or hidden state.
3. **Never rely on the icon.** The system hides icons that do not fit, and still reports them visible. Opening MinMacs again opens the Settings window on its overview pane. The CLI and notifications carry the rest.
4. **"One Icon" mode is flat.** The MinMacs menu holds one section per visible expert, with its header line and top rows. Experts never nest as submenus, so a card is never two levels deep.
5. **Accessibility label.** Each status item's label names the expert and its state, such as "LocoHost, 2 idle servers", never a symbol name.

### Every line earns its place

1. Every line answers a question the person has. Nothing decorative: no SF Symbols on items, no bars that need a legend, no unlabeled icon rows.
2. A number appears once. The header counts. Section headers do not repeat counts, and rows do not repeat what their section says.
3. The main menu holds at most:
   - a header of two lines
   - a summary of at most three lines, cut at a whole sentence and never mid-word
   - two actions
   - four sections of at most six rows each, with the rest under a "More" item
   - a footer of exactly three items: Hide Icon, Settings… and Quit MinMacs. Recently Stopped and its peers move into the expert's More item

   **When an action can't run.**
   - An action that cannot run right now stays in place, dimmed, with the reason in a readable gray tail, as the HIG advises. For example: "Remove…   3 uncommitted files".
   - An action that never applies here is hidden, such as Close Idle with nothing idle.
   - An Option alternate of an action does not count against the limit, and nothing is reachable only through Option.
4. A row is a name and at most three facts, ordered owner · size · state. No badge when the section already says it. A row's state mark differs in shape as well as color. Every expert uses the kit's one width.
5. A hover card holds:
   - a title of one or two lines
   - a colored status of at most two lines. It starts with a word, such as "Stays" or "Goes at 18:00", and says in plain words why the item stays or when it goes, and what happens next
   - at most five aligned facts, leaving out the empty ones. A fact that belongs to another expert links there, such as "Worktree   speed-3-base, merged", and counts as one of the five
   - the model's note in at most two lines, and only when it adds to the status
   - at most four actions, with the rest under More

## Words

These hold for the window, the menus, the CLI and notifications.

- **Plain words.** "Squash-merged", not "merged (squash)". "Remote branch deleted", not "upstream gone". "1 commit not in main", not "1 not in main".
- **Say where a removed thing goes.** What a removal does follows the person's removal choice, so its words do too: "Move to Trash" and "Undo moves it back" when it goes to the Trash, "Delete" and "cannot be brought back" when it is deleted at once. Never promise an undo for a deleted thing. "For good" and "permanently" are not used.
- **No parentheses** as asides.
- **Gray tails** carry only time, size, or why an action can't run: "Review Now   9m ago", "Close Idle   2 servers, 1.2 GB".
- **Truncate** at the tail, never in the middle.
- **Capitalization.** Menu items use title-style capitalization and no articles. An item that opens more input ends in an ellipsis. Summaries, cards and notification bodies use sentence case.
- **Sizes.** A size is what deleting frees. When du says more, show du's figure only beside the freed figure, such as "2.8 MB freed, 1.5 GB on disk".
- **Energy** is a rank, such as "uses the most energy". Never show joules or watts.
- **Owned items.** A protected or owned item says who owns it and where its setting lives, such as "Claude Code keeps transcripts for 30 days".

## First launch

With the menu window, the first open shows the welcome, as above. With the menus of before there is no window and no wizard, and the login item is added at the first launch, with a line in the menu for a day that says so. On the first day each expert's summary says what it watches and when it will first act, such as "Watching 6 servers. Acts on nothing until tomorrow." An expert asks for notification permission the first time it acts on its own, never at launch. An expert whose field is empty on this Mac starts with its icon hidden, and shows it once, when the field appears.

## Notifications

A notification is sent only after an expert acted without being asked, one per review across all experts.
- **The title** is short, in title case, with no app name and no final period, such as "Stopped 2 Servers, Freed 1.2 GB".
- **The body** is full sentences in sentence case. It never sends the person somewhere in the menu.
- **One Undo action,** and the passive interruption level unless the disk is nearly full.
- **An error** goes in an alert, not a notification.

## The menus, checked

After any change to a menu, run `tools/render.sh`. It draws every expert's status item, header, menu and hover cards, the shell's One Icon menu and the Settings panes from the fixture subjects in `tools/render.m`, with the same kit the app uses, to PNG in `build/render/`, in light, dark and Increase Contrast. It also runs its own checks of this standard, writes them to `checks.txt`, and exits 1 when one fails. CI keeps the PNGs. The README's pictures in `docs/img/` are copies of some of them, and `./test.sh docs` reports when they differ from a new render. Look at the PNGs and check that:

- titles and the first fact on each line are not cut off
- the fact columns line up from card to card
- spacing stays even
- nothing says the same thing twice
- each status item's accessibility label is not a symbol name
- the menu opens from the keyboard with Control-F8
- a card's status starts with a word, and its state mark has a shape
