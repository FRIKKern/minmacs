# Menu standard

MinMacs 2.0 and its five experts share one standard for their menus. It started in LocoHost and WorkForest, and research track G checked it against Apple's Human Interface Guidelines ([G-menu-ux.md](2.0/research/G-menu-ux.md)). A change that breaks a rule here is a bug.

## The menu is native

The menu is an NSMenu. A popover was tried and felt slow next to the system's own menus. Custom views are used only for text meant to be read: the header, the summary and the hover card. Text that should be read is never a disabled item, because macOS greys those out. Section titles use `+[NSMenuItem sectionHeaderWithTitle:]`. A sentence that explains a mode or a setting goes in a hover card or the Settings window.

## The menu bar

1. **The icon.** Each expert's icon is a square template symbol at one point size, with no text. A number shows beside it only when it asks the person to act, and then at most three characters.
2. **Saved position.** Each status item sets `autosaveName` to `minmacs.<expert>` and allows removal. Settings shows the same visible or hidden state.
3. **Never rely on the icon.** The system hides icons that do not fit, and still reports them visible. Opening MinMacs again opens the Settings window on its overview pane. The CLI and notifications carry the rest.
4. **"One Icon" mode is flat.** The MinMacs menu holds one section per visible expert, with its header line and top rows. Experts never nest as submenus, so a card is never two levels deep.
5. **Accessibility label.** Each status item's label names the expert and its state, such as "LocoHost, 2 idle servers", never a symbol name.

## Every line earns its place

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

- **Plain words.** "Squash-merged", not "merged (squash)". "Remote branch deleted", not "upstream gone". "1 commit not in main", not "1 not in main".
- **No parentheses** as asides.
- **Gray tails** carry only time, size, or why an action can't run: "Review Now   9m ago", "Close Idle   2 servers, 1.2 GB".
- **Truncate** at the tail, never in the middle.
- **Capitalization.** Menu items use title-style capitalization and no articles. An item that opens more input ends in an ellipsis. Summaries, cards and notification bodies use sentence case.
- **Sizes.** A size is what deleting frees. When du says more, show du's figure only beside the freed figure, such as "2.8 MB freed, 1.5 GB on disk".
- **Energy** is a rank, such as "uses the most energy". Never show joules or watts.
- **Owned items.** A protected or owned item says who owns it and where its setting lives, such as "Claude Code keeps transcripts for 30 days".

## First launch

No window and no wizard. On the first day each expert's summary says what it watches and when it will first act, such as "Watching 6 servers. Acts on nothing until tomorrow." An expert asks for notification permission the first time it acts on its own, never at launch. An expert whose field is empty on this Mac starts with its icon hidden, and shows it once, when the field appears.

## Notifications

A notification is sent only after an expert acted without being asked, one per review across all experts.
- **The title** is short, in title case, with no app name and no final period, such as "Stopped 2 Servers, Freed 1.2 GB".
- **The body** is full sentences in sentence case. It never sends the person somewhere in the menu.
- **One Undo action,** and the passive interruption level unless the disk is nearly full.
- **An error** goes in an alert, not a notification.

## Checked, not assumed

After any change to a menu, run the render tool from Core. It renders every expert's header, menu and hover cards from fixture subjects to PNG, in light, dark and Increase Contrast. CI runs it and keeps the PNGs. Look at them and check that:

- titles and the first fact on each line are not cut off
- the fact columns line up from card to card
- spacing stays even
- nothing says the same thing twice
- each status item's accessibility label is not a symbol name
- the menu opens from the keyboard with Control-F8
- a card's status starts with a word, and its state mark has a shape
