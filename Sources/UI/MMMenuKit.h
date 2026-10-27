// The menu kit every expert builds its menu with, to docs/DESIGN.md (A11, P57).
// It started as WorkForest's menu code, with one width and one label column for every expert.
// The menu stays a native NSMenu. Custom views are used only for text meant to be read:
// the header, the summary and the hover card. Menu items never carry SF Symbols.
// Everything here is AppKit, so it runs on the main thread only.
#import <Cocoa/Cocoa.h>

/// One width for every expert's header, summary and card, in points.
extern const CGFloat MMMenuWidth;
/// The side margin of the kit's text views. Text is MMMenuWidth minus two margins wide.
extern const CGFloat MMMenuInset;
/// The label column of every card, so facts line up from card to card and expert to expert.
extern const CGFloat MMLabelColumn;

/// The limits in DESIGN.md, rule 3 and rule 5 of "Every line earns its place".
enum {
    MMMaxHeaderLines = 2,
    MMMaxSummaryLines = 3,
    MMMaxMenuActions = 2,
    MMMaxSections = 4,
    MMMaxSectionRows = 6,
    MMMaxRowFacts = 3,
    MMMaxCardTitleLines = 2,
    MMMaxCardStatusLines = 2,
    MMMaxCardFacts = 5,
    MMMaxCardNoteLines = 2,
    MMMaxCardActions = 4,
};

/// A row's state. Each mark differs in shape as well as color, so state never rests on color alone.
/// MMRowMark in Core/MMExpert.h follows it member for member. Change both together.
typedef NS_ENUM(NSInteger, MMMark) {
    MMMarkNone = 0,
    MMMarkWorking,      // ● green: in use now
    MMMarkRecent,       // ◐ yellow: used a short while ago
    MMMarkQuiet,        // ○ gray: quiet, nothing decided
    MMMarkGoes,         // ◇ orange: goes at the next review or at a set time
    MMMarkBlocked,      // ◆ red: waits on the person
    MMMarkUnknown,      // ◌ gray: not known yet
};
NSString *MMMarkGlyph(MMMark mark);
/// The mark's color, for the glyph and for a card's status word. Green, yellow and orange are darker
/// in light appearances than the system colors, so a bold status word stays readable on a light menu.
NSColor *MMMarkColor(MMMark mark);
/// The mark in words, such as "in use", for tooltips and accessibility.
NSString *MMMarkWord(MMMark mark);

#pragma mark Text

/// Wrapped, readable text of a fixed width and at most `lines` lines, 0 for no limit, sized to fit.
NSTextField *MMPara(NSString *text, NSFont *font, NSColor *color, CGFloat width, NSInteger lines);
/// The same for styled text.
NSTextField *MMParaRich(NSAttributedString *text, CGFloat width, NSInteger lines);
/// A bold colored head, then plain text: "Stays. 3 files are not committed."
NSAttributedString *MMRich(NSString *bold, NSColor *boldColor, NSString *rest, CGFloat size);
/// A menu line with a gray tail, such as "Review Now   9m ago".
NSAttributedString *MMTitled(NSString *title, NSString *tail);
/// Whole sentences of text that fit in `lines` lines at this width, so text never stops mid-word.
/// The first sentence is kept even when it alone is longer.
NSString *MMFitSentences(NSString *text, NSFont *font, CGFloat width, NSInteger lines);
/// The text cut at the tail with an ellipsis so it fits `width` points in this font.
NSString *MMFitWidth(NSString *text, NSFont *font, CGFloat width);
/// The height of `lines` lines of this font, as the kit's text views use it.
CGFloat MMLinesHeight(NSFont *font, NSInteger lines);

#pragma mark Menu items

/// The top of a menu, two lines. The big figure and its unit, such as "1.9 GB" and "in servers",
/// an optional figure on the right, such as "12% CPU", and one line of counts below.
NSMenuItem *MMHeaderItem(NSString *big, NSString *unit, NSString *side, NSString *line);
/// Text meant to be read, at the kit's width, cut at a whole sentence to at most `lines` lines.
/// A view in secondary text color, never a disabled item.
NSMenuItem *MMTextItem(NSString *text, NSInteger lines);
/// A section title, from +[NSMenuItem sectionHeaderWithTitle:].
NSMenuItem *MMSectionItem(NSString *title);
/// A row: a state mark, the name, an optional tag such as ":3000", and at most three facts under it,
/// ordered owner · size · state. The name is cut at the tail so the row fits the kit's width, and the tag
/// is never cut. Empty facts are left out. macOS 14 shows no subtitle on an item with an attributed title,
/// so there the facts follow the name as a gray tail, and a long name keeps its room before the facts.
NSMenuItem *MMRowItem(NSString *name, NSString *tag, NSArray<NSString *> *facts, MMMark mark);
/// An action with an optional gray tail of time, size or count: "Close Idle   2 servers, 1.2 GB".
NSMenuItem *MMActionItem(NSString *title, NSString *tail, SEL action, id target);
/// An action that cannot run right now. It stays in place, dimmed, with the reason in a readable gray tail:
/// "Remove…   3 uncommitted files". An action that never applies is left out instead.
NSMenuItem *MMDimmedItem(NSString *title, NSString *reason);
/// The colors of a dimmed action's title and of its reason. They are tertiaryLabelColor and secondaryLabelColor,
/// except under Increase Contrast, which darkens those to more than half and three quarters of labelColor, so a
/// dimmed line there would read as an enabled one with a gray tail. There the title keeps at most 0.31 of
/// labelColor's ink and the reason at most 0.59, the shares they have in the plain light appearance.
NSColor *MMDimmedColor(void);
NSColor *MMDimmedReasonColor(void);
/// The Option alternate of the item just before it. It does not count against the action limit,
/// and nothing may be reachable only through it.
NSMenuItem *MMAlternateItem(NSString *title, NSString *tail, SEL action, id target);
/// "More", with these items in its submenu.
NSMenuItem *MMMoreItem(NSArray<NSMenuItem *> *items);
/// Clears the image of every item in the menu and its submenus. macOS 26 and later add a symbol to items
/// whose action it knows, such as copy: and terminate:, and DESIGN.md allows no symbols on items.
/// The kit's own items are already clear. Setting a known action on an item later brings its symbol back,
/// so call this last, on the finished menu, whenever it holds items the kit did not make or items you changed.
void MMRemoveSymbols(NSMenu *menu);

#pragma mark Menus

/// A section: its title, its first six rows, and the rest under "3 More". Nothing is added for no rows.
void MMAddSection(NSMenu *menu, NSString *title, NSArray<NSMenuItem *> *rows);
/// The footer every expert ends with: Hide Icon, Settings… and Quit MinMacs.
/// Hide Icon sends hideIcon: and Settings… sends showSettings: to the target.
void MMAddFooter(NSMenu *menu, id target);
