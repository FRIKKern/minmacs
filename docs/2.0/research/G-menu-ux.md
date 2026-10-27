# Research G: menu bar UX at the highest standard

**Summary.** Apple's guidance fits our menu standard well. It asks for a menu, not a popover, template symbols, short labels, one level of submenus and few settings. Three things in it change our plan. First, Apple says the app must never rely on its menu bar icon being visible, and since macOS 26 people can turn off an app's menu bar items in System Settings without the app being told. Whether one toggle covers all of one app's icons is a guess (unverified). Second, the system hides extras that do not fit, and `isVisible` still says YES when that happens, so five icons on a notched MacBook can vanish without a trace. Third, an app with several status items should name each one with `autosaveName`, and none of our four Objective-C apps does that today. The proposals below add a "The menu bar" section, a "First launch" section and a "Notifications" section to docs/DESIGN.md, and change four existing rules. Every source is linked inline. Code facts cite file and line.

## Sources used

- Apple Human Interface Guidelines, read as JSON from `developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json` on 2026-10-27, for the pages [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications), [Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications), [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), [Launching](https://developer.apple.com/design/human-interface-guidelines/launching), [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) and [Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls). The HIG has no page named "progressive disclosure". The URL returned 404, so the disclosure controls page stands in for it.
- AppKit headers in the macOS 26.1 SDK at `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/`, files `NSStatusItem.h`, `NSMenuItem.h` and `NSMenu.h`. `xcrun --show-sdk-version` prints 26.1.
- Apple developer documentation for [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem), [isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible) and [expandedInterfaceDelegate](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate), which is new in macOS 27.
- Apple Developer Forums threads [788101](https://developer.apple.com/forums/thread/788101) and [836113](https://developer.apple.com/forums/thread/836113).
- Apple Support pages [Change Menu Bar settings on Mac](https://support.apple.com/en-gb/guide/mac-help/mchlad96d366/26/mac/27), [Scale to fit below built-in camera](https://support.apple.com/en-us/102125) and [Mac keyboard shortcuts](https://support.apple.com/en-us/102650).
- Prior art from the [Ice README](https://github.com/jordanbaird/Ice), the [Bartender site](https://www.macbartender.com/), the [iStat Menus 7 App Store listing](https://apps.apple.com/app/id6499559693) and a [MacRumors article on iStat Menus 7](https://macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/).
- Our code: `~/Documents/GitHub/locohost`, `~/Documents/GitHub/workforest`, `~/Documents/GitHub/minmacs` on branch `main`, which still holds MinMacs 1.2, and the Insomnia and Noo-Noo clones in the session scratchpad under `family/`.
- This Mac: `sysctl -n hw.model` prints `MacBookPro18,1`, a 16-inch MacBook Pro with the camera housing. `system_profiler SPDisplaysDataType` shows the built-in Liquid Retina XDR display plus a 3440 x 1440 external display. `sw_vers` prints macOS 27.0.1.

## 1. What Apple says about menu bar extras

The HIG's menu bar page has a short section on menu bar extras. Its rules, quoted from [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar):

- "When necessary, the system hides menu bar extras to make room for app menus. Similarly, if there are too many menu bar extras, the system may hide some to avoid crowding app menus."
- "Consider using a symbol to represent your menu bar extra." Symbols use black and clear so the system can recolor them. "The menu bar's height is 24 pt."
- "Display a menu — not a popover — when people click your menu bar extra." This matches the first rule in docs/DESIGN.md, "The menu is native".
- "Let people — not your app — decide whether to put your menu bar extra in the menu bar." Apple adds that the app can offer that choice during setup.
- "Avoid relying on the presence of menu bar extras. The system hides and shows menu bar extras regularly, and you can't be sure which other menu bar extras people have chosen to display or predict the location of your menu bar extra."
- "Consider exposing app-specific functionality in other ways, too." Apple's example is a Dock menu. Our apps set `LSUIElement` in `Info.plist` and have no Dock icon, so a Dock menu does not apply. See `locohost/Info.plist:36`, `workforest/Info.plist:34` and `insomnia/Info.plist:34`.

The same page says, for the app's own menus: "Always show the same set of menu items" and "If a menu bar item isn't actionable, disable the action instead of hiding it from the menu." That advice is written for an app's main menus. Our rule 3 in "Every line earns its place" shows actions "only when they can do something". Section 6 treats this conflict.

## 2. What the AppKit API allows

From `NSStatusItem.h` in the 26.1 SDK:

- Line 26: `NSStatusItemBehaviorRemovalAllowed` "should be set if your application remains usable without the status item. It is the application's responsibility to allow the user to re-add the item. Upon removal, -visible is set to NO. This is observable through KVO."
- Line 57: `visible` is "currently visible in the status bar, even if it is obscured by the application menu. Defaults to YES. Persisted based on the -autosaveName."
- Line 61: `autosaveName` "Apps with multiple status bar items should set an autosave after creation."
- Lines 84 to 86: custom views "should not be set on a status item. The button property with a template image will allow proper styling."

The [isVisible documentation](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible) adds: "This property returns YES even if the status item is temporarily hidden due to insufficient space in the menu bar." So the app cannot tell from `visible` that the notch or a full menu bar has hidden it.

[Forum thread 836113](https://developer.apple.com/forums/thread/836113) reports that on macOS 27 betas the button window's `occlusionState` "no longer reflects hidden menu bar visibility", and the poster says this was still unresolved in August 2026. An Apple DTS engineer asked for a sample project and did not say it would change. The same thread says the new `expandedInterfaceDelegate` fixes the missing highlight only while the user interacts with the status item, and does not fix a highlight that app code sets, such as when it shows a window from the item. The [expandedInterfaceDelegate page](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate) says: "Status items that assign an NSMenu to their button don't receive expanded interface callbacks — the system handles the expanded menu interface automatically." Our apps assign an `NSMenu`, so this new macOS 27 API does not affect us. See `locohost/Sources/main.m:1357` and `workforest/Sources/main.m:748`.

From `NSMenuItem.h` and `NSMenu.h`:

- `NSMenuItem.h:29-32`: `+sectionHeaderWithTitle:` makes "a menu item representing a section header", non-interactive, macOS 14 and later.
- `NSMenuItem.h:54-58`: `subtitle` is shown below the title. It needs macOS 14.4, per `API_AVAILABLE(macos(14.4))` at line 58. On macOS 14 it does not show with an attributed title. It works on 15 and later.
- `NSMenuItem.h:89`: `alternate`, the item shown in place of the one before it while a modifier key is held.
- `NSMenuItem.h:118-122`: `badge`, macOS 14, "to provide additional quantitative information".
- `NSMenu.h:27` and `NSMenu.h:235`: `NSMenuPresentationStylePalette`, macOS 14, lays a submenu's items out in a row.

All four MinMacs-family apps on Objective-C, MinMacs 1.2, LocoHost, WorkForest and Insomnia, set `LSMinimumSystemVersion` to 13.0, per PlistBuddy on each `Info.plist`. The macOS 14 APIs above need that floor raised, or a fallback.

## 3. Menu bar settings in macOS 26 and 27

[Apple's Mac User Guide](https://support.apple.com/en-gb/guide/mac-help/mchlad96d366/26/mac/27) describes a Menu Bar pane in System Settings with an "Allow in the Menu Bar" section: "Some applications provide menu bar items for extra functionality", and people choose per application whether its items show. In [forum thread 788101](https://developer.apple.com/forums/thread/788101) an Apple DTS engineer confirms the app cannot read that setting: the answer is "No." He suggests `removalAllowed` with KVO instead. The poster filed FB18341478 to expose the setting.

Guess, not tested: the toggle is per application, so with one `MinMacs.app` it hides all five icons at once. Today the five standalone apps each get their own toggle.

The [MacSales blog](https://eshop.macsales.com/blog/97824-macos-tahoe-makes-it-extremely-easy-to-clean-up-a-messy-menu-bar/) says macOS 26 can also move menu bar items into Control Center. The article does not say which kinds of items this covers. That it applies only to Control Center modules is unverified, and if so status items are not those, so it is not a path for us without a widget or control extension. That last point is a guess and needs checking in research B.

## 4. Five icons, the notch, Bartender and Ice

**The notch.** On this Mac the built-in display has the camera housing. The HIG says the system hides extras that do not fit, and Apple's [Scale to fit below built-in camera](https://support.apple.com/en-us/102125) page shows the problem is real enough that Apple offers a per-app workaround. That workaround disappears for apps whose developer updated them. An extra that is hidden this way still reports `visible == YES`, as section 2 shows.

**What Bartender and Ice do.** Both move extras out of sight and bring them back on demand:
- Ice: "Hide menu bar items", an "Always-hidden" section, a separate "Ice Bar" for hidden items "for MacBooks with the notch", show on hover or on a click on empty menu bar, drag and drop order, and item spacing in beta. Ice needs macOS 14. Source: the [Ice README](https://github.com/jordanbaird/Ice).
- Bartender: hides items the notch would cover, shows items on triggers such as unplugging power, offers a Bartender Bar on hover, click or hotkey, offers tighter spacing, and searches items from the keyboard. Bartender 7 targets macOS 27. Source: the [Bartender site](https://www.macbartender.com/).

Both tools track items by owner and name (unverified). If `autosaveName` is not set, AppKit picks a name for each item, per `NSStatusItem.h:61` and the [autosaveName documentation](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property). Guess: the picked names follow creation order, so when one expert is hidden and the others are created in a new order, saved positions and hidden states can land on the wrong icon. None of our apps sets `autosaveName` or `behavior` today. `grep -rn "autosaveName\|removalAllowed\|NSStatusItemBehavior"` over all four `Sources` folders returns nothing.

**Width today.** LocoHost and WorkForest use `NSVariableStatusItemLength` and put text beside the icon, such as " 4 · 2 idle" and " 12 · 3 stale". See `locohost/Sources/main.m:850` and `:920`, and `workforest/Sources/main.m:364` and `:424`. MinMacs 1.2 and Insomnia use `NSSquareStatusItemLength`, an icon with no text. See `minmacs/Sources/main.m:411` and `insomnia/Sources/main.m:263`. Guess, not measured: five items with text titles take two to three times the width of five square icons, and on a 16-inch display with an app's menus open that is the difference between showing and being hidden.

**One icon.** iStat Menus 7 has a Combined mode that "combines multiple iStat Menus items into a single menu bar item", which the listing says is useful on laptops with little menu bar space. Sources: the [App Store listing](https://apps.apple.com/app/id6499559693) and [MacRumors](https://macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/). A one-icon mode has to fit the HIG's submenu limit. The HIG says "it's generally best to restrict them to a single level" and "if a submenu contains more than about five items, consider creating a new menu" ([Menus](https://developer.apple.com/design/human-interface-guidelines/menus)). Our rows already open a hover card as a submenu, so a one-icon menu that nests each expert as a submenu would put cards two levels deep. A flat menu with one section per expert keeps cards at one level.

## 5. Setup without a wizard

Apple's guidance supports the plan's "no setup screen":
- "Ideally, people can understand your app or game simply by experiencing it." Prefer "a collection of context-specific tips instead of a single onboarding flow", shown "near that area". "Postpone nonessential setup flows or customization steps. Provide reasonable default settings." Ask for a permission "when people first access the specific function that relies on" it. Source: [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding).
- "Avoid using settings to ask for setup information you can get in other ways." "Minimize the number of settings you offer." On macOS, Settings is a window opened with Command-Comma, titled "App Name Settings" when it has one pane. Source: [Settings](https://developer.apple.com/design/human-interface-guidelines/settings).
- "Restore the previous state when your app restarts." Source: [Launching](https://developer.apple.com/design/human-interface-guidelines/launching).

What our apps do today on first launch:
- LocoHost and WorkForest ask for notification permission at launch, before they have anything to say. See `locohost/Sources/main.m:861` and `workforest/Sources/main.m:369`. This goes against the Onboarding rule on permissions.
- LocoHost's README says macOS asks for the Documents folder on first launch, at `locohost/README.md:86`.
- Insomnia starts switched on, so it keeps the Mac awake from the first launch, and its agent mode is off by default. See `insomnia/README.md:61`, `insomnia/README.md:106` and `insomnia/Sources/main.m:25` and `:243`. PLAN.md section 5 says Insomnia "keeps the Mac awake while agents work". The two defaults differ, and 2.0 must pick one.
- No app explains itself on first launch. Since the apps have no Dock icon, a person who double-clicks the app sees only a new icon appear, if it fits. No app implements `applicationShouldHandleReopen:`, per `grep` over the four `Sources` folders, so opening the app again does nothing visible.

## 6. Every DESIGN.md rule against the sources

| DESIGN.md rule | Source check | Verdict |
|---|---|---|
| The menu is an NSMenu, not a popover | HIG menu bar extras: "Display a menu — not a popover" | Confirmed. Keep |
| Custom views only for text meant to be read | `NSStatusItem.h:84` warns against custom views on the status item itself, not inside menus | Confirmed. Keep |
| Text that should be read is never a disabled item | Our own code breaks it. `Header()` makes a disabled item at `locohost/Sources/main.m:968` and `minmacs/Sources/main.m:445`, used for sentences such as `locohost/Sources/main.m:1305`. `+sectionHeaderWithTitle:` exists from macOS 14, at `NSMenuItem.h:32` | Change: name the replacement |
| 1. No SF Symbols on items, no unlabeled icon rows | HIG Menus: "Use menu item icons sparingly", and "provide icons for all menu items in a group, or none of them". MinMacs 1.2 puts symbols on items at `minmacs/Sources/main.m:517` and `:550` | Confirmed. Keep, and the 1.2 menu is not a model |
| 2. A number appears once | No HIG rule either way. MinMacs 1.2 repeats counts in section headers, such as "Will quit (%lu)" at `minmacs/Sources/main.m:555`. LocoHost puts a count in a submenu title, "Other Listeners (%lu)", at `locohost/Sources/main.m:1341` | Keep. The code needs fixing |
| 3. At most four sections of six rows, two actions shown only when they can act | HIG Menus: "Be mindful of menu length". The HIG says dim unavailable items rather than hide them, for app menus | Keep the limits. Keep hiding for the two actions, since a dimmed item cannot be read, which is the rule above. Record this as a deliberate break from the HIG |
| 3. Footer of Recently Stopped, Settings, Quit | In one process, "Quit LocoHost" at `locohost/Sources/main.m:1355` would quit all five experts | Change: see rule G9 |
| 4. Row: name and three facts, owner · size · state | HIG Accessibility: "Convey information with more than color alone". LocoHost marks state with a colored dot only, at `locohost/Sources/main.m:974`. MinMacs 1.2 already uses different shapes, at `minmacs/Sources/main.m:522` | Change: see rule G6 |
| 5. Hover card limits | HIG Menus: one level of submenus, about five items. A card is one level below its row | Confirmed. Keep at one level |
| Words: plain words, no parentheses | HIG Menus: title-style capitalization for items, no articles, an ellipsis when more input follows. HIG Notifications: title case titles, sentence case bodies. LocoHost's notification body uses "(still running)" at `locohost/Sources/main.m:953` | Add capitalization and ellipsis. Fix the notification |
| Gray tails carry only time and size | No HIG rule. Keep | Keep |
| Truncate at the tail | No HIG rule. Keep | Keep |
| Checked, not assumed: render to PNG in light and dark | HIG Accessibility asks for contrast checks in both appearances and with Increase Contrast | Extend: see rule G10 |

DESIGN.md has no rule today about the status item itself, first launch or notifications. Those gaps hold most of what follows.

## 7. Proposed rules

Each rule names its source and the DESIGN.md section it adds to or changes.

**G1. Every icon has a name and can be removed.** Each expert's status item sets `autosaveName` to `minmacs.<expert>`, such as `minmacs.locohost`, right after creation, and sets `behavior = NSStatusItemBehaviorRemovalAllowed`. The core observes `visible` with KVO and shows the same state in Settings, where the icon can be turned back on. Sources: `NSStatusItem.h:26` and `:61`, [forum 788101](https://developer.apple.com/forums/thread/788101), and HIG "Let people — not your app — decide". Section: new "The menu bar".

**G2. The icon is a template symbol, square, with no text by default.** Each expert uses `NSSquareStatusItemLength` and one template SF Symbol at the same point size, with a state variant at most. A number appears in the bar only when it asks the person to act, and then at most three characters, such as "3". Today LocoHost and WorkForest show counts and words in the bar. Sources: HIG "Consider using a symbol", menu bar height 24 pt, and `NSStatusItem.h:84-86`. The width claim is a guess until measured. Section: new "The menu bar".

**G3. Never rely on the icon.** The system can hide any icon for space, and the app cannot tell, because `visible` stays YES and `occlusionState` no longer helps on macOS 27. People can also hide all icons in System Settings without the app knowing. So every finding that matters also reaches the person another way: opening MinMacs again from Finder, Spotlight or `open -a MinMacs` calls `applicationShouldHandleReopen:` and opens one overview window with all five experts. The CLI and notifications cover the rest. Sources: HIG "Avoid relying on the presence of menu bar extras", the [isVisible documentation](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible), [forum 836113](https://developer.apple.com/forums/thread/836113) and [forum 788101](https://developer.apple.com/forums/thread/788101). Section: new "The menu bar".

**G4. One-icon mode is flat.** Settings offers "One Icon". In that mode the MinMacs icon's menu holds one section per visible expert. Each section shows the expert's one-line header and its top rows, with hover cards one level deep as today, and a "More" item that opens the expert's full list. The per-expert icons go away. Experts never nest as submenus, so a card is never two levels deep. Sources: HIG Menus "restrict them to a single level", and iStat Menus Combined mode in the [App Store listing](https://apps.apple.com/app/id6499559693). Section: new "The menu bar", and "Every line earns its place" rule 3 for the section limits in that mode.

**G5. Readable text uses a section header or a view, never a disabled item.** Section titles use `+[NSMenuItem sectionHeaderWithTitle:]` where macOS 14 is the floor, and the menu kit's text view otherwise. Sentences that explain a mode or a setting belong in a hover card or the Settings window, not in disabled rows. The menu kit drops the `Header()` helper that LocoHost and MinMacs 1.2 share. Sources: `NSMenuItem.h:29-32`, and our own rule broken at `locohost/Sources/main.m:968` and `:1305`. Section: "The menu is native".

**G6. State is never color alone.** A row's state mark differs in shape as well as color, as MinMacs 1.2 already does with ◆ ● ◌ ○. The hover card status keeps its color and leads with a word, such as "Stays" or "Goes at 18:00". Each status item's `accessibilityDescription` names the expert and its state, such as "LocoHost, 2 idle servers". Insomnia passes the symbol name, as its accessibility description at `insomnia/Sources/main.m:34`, so VoiceOver likely reads "moon.fill" (unverified, not tested). Sources: HIG Accessibility "Convey information with more than color alone", and `locohost/Sources/main.m:974`. Section: "Every line earns its place" rules 4 and 5.

**G7. First launch teaches in place.** No window, no wizard. On the first day each expert's summary line says what it watches and when it will first act, such as "Watching 6 servers. Acts on nothing until tomorrow." That line replaces the usual summary until the first review. The first time an expert acts on its own, it asks for notification permission, not at launch. An expert whose field is empty on this Mac, such as WorkForest with no linked worktrees, starts with its icon hidden and turns it on when its field appears, once. Sources: HIG Onboarding "context-specific tips", "Postpone nonessential setup", and permission "when people first access the specific function". Our launch-time requests are at `locohost/Sources/main.m:861` and `workforest/Sources/main.m:369`. Section: new "First launch".

**G8. Notifications report what was done and offer Undo.** A notification is sent only after an expert acted without being asked, one per review across all experts. The title is short, in title case, with no app name and no final period, such as "Stopped 2 Servers, Freed 1.2 GB". The body uses full sentences in sentence case and no parentheses. Each carries one `UNNotificationAction` named "Undo", and uses the `passive` interruption level unless disk is nearly full. The body never tells the person to go somewhere in the menu. Today it does, with "Recently Stopped keeps each restart command." at `locohost/Sources/main.m:957` and "Recently Removed can restore each one." at `workforest/Sources/main.m:461`. Errors go in an alert, not a notification. Sources: HIG [Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications) "Avoid sending a notification that tells people to perform specific tasks within your app", "Avoid sending multiple notifications for the same thing", "Use an alert — not a notification — to display an error message", and title and body style. HIG [Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications) on accurate interruption levels. Section: new "Notifications".

**G9. One app, one Quit, one Settings window.** Every expert's footer says "Quit MinMacs", since quitting ends all five. A "Hide Icon" item sits beside it, so hiding one expert never needs Quit. "Settings…" with an ellipsis opens the one window that PLAN.md section 7 describes, with Command-Comma. That window replaces the deep Settings submenus, which today go two levels down, such as Settings, Mode, then the modes, at `locohost/Sources/main.m:1295-1306`. Sources: HIG Settings for macOS, HIG Menus "restrict them to a single level" and "Append an ellipsis". Section: "Every line earns its place" rule 3, the footer.

**G10. Labels follow Apple's case rules, and the check covers more.** Menu items use title-style capitalization and drop articles. An item that opens more input ends in an ellipsis, as "Edit Rules…" already does. Summary lines, hover cards and notification bodies use sentence case. The render check adds Increase Contrast, the macOS 14 floor if adopted, the menu opened from the keyboard with Control-F8, and a test that each status item's accessibility label is not a symbol name. Sources: HIG Menus on labels, HIG Accessibility on contrast and keyboard use, and [Mac keyboard shortcuts](https://support.apple.com/en-us/102650): "Control-F8 or Fn-Control-F8: Move focus to the status menu in the menu bar." Sections: "Words" and "Checked, not assumed".

**G11. Power actions sit behind Option.** An action the person rarely needs, such as "Stop Now Without Review" or "Remove, Skip the Trash Check", is an `alternate` item shown while Option is held, beside its normal action. It never counts against the two-action limit. Sources: `NSMenuItem.h:89`, and HIG Disclosure controls "more advanced functionality hidden by default". Section: "Every line earns its place" rule 3. This is optional and should not be the only way to reach anything.

## Recommendations

1. **PLAN.md section 7, Menus and CLI.** Add rules G1 to G4 as a new "The menu bar" section in docs/DESIGN.md. Say in the plan that each expert's icon is square and named `minmacs.<expert>`, and that "One Icon" is a Settings choice with a flat menu. Shared pattern: the menu kit's status item factory in `UI/`.
2. **PLAN.md section 1, Principle 6, "Each expert is optional".** Extend it with G3: with every icon hidden, opening MinMacs again shows an overview window, because the app cannot know whether its icons are visible. Shared pattern: one `applicationShouldHandleReopen:` handler in the core.
3. **PLAN.md section 5, Out of the box.** Add G7: no permission prompts at launch, a first-day summary line in place of onboarding, and icons hidden for experts with an empty field. Decide Insomnia's first-launch default, since its README says "on" and the plan says "while agents work". Shared pattern: `Act/Notify` asks for permission on first use.
4. **PLAN.md section 3, the `Act` line with Notify.** Add G8: one notification per review across experts, title case title, one Undo action, passive level. Shared pattern: one notifier in `Act`, with categories registered once.
5. **PLAN.md section 7, Settings.** Add G9: one Settings window opened with Command-Comma, and footer items "Hide Icon" and "Quit MinMacs". Remove the nested Settings submenus. Shared pattern: one settings window in `UI/`.
6. **PLAN.md section 9, Phase 0 and Phase 1.** When the menu kit is extracted in phase 0, apply G5 and G6: drop the disabled `Header()` helper and give state marks shapes. Decide whether 2.0 needs macOS 14 for `sectionHeaderWithTitle:`, `badge` and palette menus. Shared pattern: the menu kit.
7. **PLAN.md section 9, Phase 1 "Done when".** Add to the render check from G10: Increase Contrast, keyboard focus with Control-F8, and a label test for every status item. Measure the width of all five icons in the bar on this Mac's 16-inch display with an app's menus open, to replace the guess in section 4. Shared pattern: the render harness.
8. **PLAN.md section 8, Migration.** When the old apps are removed, carry over each one's hidden or visible state onto the new `minmacs.<expert>` autosave names, so a person who hid Insomnia does not see it come back. Shared pattern: the migration step in `Store`.

## Open questions

1. **The macOS floor.** Raise `LSMinimumSystemVersion` from 13.0 to 14 for section headers, badges and palette menus, or keep 13 and draw them with the menu kit's views?
2. **Allow in the Menu Bar.** Is the System Settings toggle really per app, so one switch hides all five icons? This needs a test on macOS 27 with a build that has two status items. Research did not settle it.
3. **One icon by default.** On a notched MacBook with many extras, should "One Icon" be the default, with five icons as the choice, or the other way round? The HIG says people decide. Nothing in the sources picks a default.
4. **Cross-expert links.** PLAN.md section 7 says a server's card "opens WorkForest's card". AppKit closes one status menu before another opens (unverified). Whether the core can open a second status item's menu at a given row, for example with `performClick:` on its button after the first menu closes, is untested. In one-icon mode the link stays inside one menu, so the question applies only to five-icon mode.
5. **Dim or hide.** The HIG says dim unavailable actions so the menu keeps its shape. DESIGN.md hides them because dimmed text cannot be read. Should the two action slots stay in place with a readable gray tail that says why nothing can run, or stay hidden as today?
6. **Control Center.** Can an Objective-C app built with clang alone ship a Control Center control for Insomnia's keep-awake toggle, so it lives outside the menu bar? This belongs with research B, item "Other surfaces".

## Verification

Checked on 2026-10-27 by re-reading each cited source. Counts: 82 confirmed, 4 corrected, 5 unsupported.

What was checked:
- This Mac. `xcrun --show-sdk-version` prints 26.1. `sysctl -n hw.model` prints MacBookPro18,1. `sw_vers -productVersion` prints 27.0.1. `system_profiler SPDisplaysDataType` shows a built-in Liquid Retina XDR display at 3456 x 2234 and a 3440 x 1440 external display.
- AppKit headers. `NSStatusItem.h` lines 26, 57, 61 and 84 to 85 match the quotes. `NSMenuItem.h` lines 29 to 32, 54 to 58, 89 and 118 to 122 match. `NSMenu.h` lines 27 and 235 match.
- HIG pages, fetched as JSON with curl from `developer.apple.com/tutorials/data/design/human-interface-guidelines/`. Every quote in sections 1, 4, 5 and 7 was found on the cited page: The menu bar, Menus, Notifications, Managing notifications, Onboarding, Launching, Settings, Accessibility and Disclosure controls. `progressive-disclosure.json` returns 404.
- Apple documentation JSON for `isVisible`, `expandedInterfaceDelegate` and `autosaveName`. The quotes match. `expandedInterfaceDelegate` lists macOS 27.0 as its first version.
- Forum threads 788101 and 836113, read with WebFetch. The "No." answer, the `removalAllowed` and KVO advice, FB18341478, the occlusionState report, the August 2026 status and the request for a sample project all match.
- Apple Support pages 102125, 102650 and the Menu Bar settings guide. The quotes match.
- Ice README from raw.githubusercontent.com, the Bartender site, the iStat Menus 7 App Store listing, the MacRumors article and the MacSales post.
- Code. Every cited line in `locohost/Sources/main.m`, `workforest/Sources/main.m`, `minmacs/Sources/main.m` on branch `main`, `insomnia/Sources/main.m`, `locohost/README.md:86` and `insomnia/README.md:61` and `:106` was printed with `sed -n` and matches. `Info.plist` `LSUIElement` lines and `LSMinimumSystemVersion` values were checked. `grep` for `autosaveName`, `removalAllowed`, `NSStatusItemBehavior` and `applicationShouldHandleReopen` over the four `Sources` folders returns nothing. LocoHost's Settings submenu holds a Mode submenu, at lines 1307 and 1354.
- PLAN.md sections 1, 5, 7, 8 and 9 and DESIGN.md rules, read in this repo.

Corrected:
1. Forum 836113 on `expandedInterfaceDelegate`. The thread says it fixes highlight during user interaction, not highlight set by app code. The old text said "only for windows shown from a status item".
2. `subtitle` needs macOS 14.4, not 14, per `NSMenuItem.h:58`.
3. Four Objective-C apps set the 13.0 floor, not three. MinMacs 1.2 also does.
4. `locohost/Sources/main.m:1341` is a submenu title with a count, not a section header.

Unsupported, now marked "(unverified)":
1. The summary's claim that one System Settings toggle turns off all of an app's icons. The support page shows a toggle per application but does not say what it hides.
2. The MacSales post does not say the Control Center move applies only to Control Center modules.
3. "Both tools track items by owner and name" has no source.
4. VoiceOver reading "moon.fill" was not tested. The code only shows the symbol name passed as the description.
5. "AppKit closes one status menu before another opens" has no source.

Not checked: the Noo-Noo app's `Info.plist`, since `noo-noo-app` in the clone is a built arm64 binary and the app is Go, not Objective-C.
