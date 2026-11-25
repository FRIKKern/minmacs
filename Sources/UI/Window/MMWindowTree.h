// An app row that opens into its insides in the list, MMWindowInsides.h: cmux, then its workspaces, panes and tabs,
// then the agent or server in a tab. Each level is a real row, with the three looks, its own numbers and its own
// story. A disclosure stands left of the row's icon: a press on it, Option and a press anywhere on the row, or → and
// ← open and close it. What is open is remembered for each row while MinMacs runs. When the side runs out of room,
// the deepest levels close first, all but the one the person opened last.
#import <Cocoa/Cocoa.h>
#import "UI/Window/MMWindowInsides.h"
#import "UI/Window/MMWindowUI.h"

NS_ASSUME_NONNULL_BEGIN

/// YES for a row with insides to open: an app that knows its insides, a workspace, a pane, a tab with an agent.
BOOL MMWindowTreeOpens(MMWindowRow *row);
/// Whether a row is open now, and opening or closing it. Memory only, for as long as MinMacs runs.
BOOL MMWindowTreeIsOpen(NSString *key);
void MMWindowTreeSetOpen(NSString *key, BOOL open);
/// Forgets every open row. For the render tool and the checks.
void MMWindowTreeCloseAll(void);
/// Open and shown open: NO for an open row whose insides the side had no room for, drawn closed.
BOOL MMWindowTreeShowsOpen(NSString *key);
/// The rows of a group that are its own, not an open row's insides: what its header counts.
NSInteger MMWindowTreeTopRows(MMWindowGroup *g);
/// The groups as the list shows them: each open row followed by its insides, as deep as the side's height holds.
NSArray<MMWindowGroup *> *MMWindowTreeGroups(NSArray<MMWindowGroup *> *groups, CGFloat height);
/// The part of a row's rect its content takes: right of its indent.
NSRect MMWindowTreeContent(MMWindowRow *row, NSRect r);
/// Where a row's disclosure is drawn, NSZeroRect for a row that does not open.
NSRect MMWindowTreeDisclosure(MMWindowRow *row, NSRect r);
/// Draws a row of the list: its look across the whole width, its disclosure, and the row itself right of its indent.
void MMWindowTreeDrawRow(MMWindowRow *row, NSString *shown, NSRect r, MMWindowSide side, BOOL hasHour, NSInteger look, BOOL tall);
/// Sets what VoiceOver hears of a row: its level in the outline, and whether it opens and is open.
void MMWindowTreeAccessibility(NSAccessibilityElement *el, MMWindowRow *row);

/// The window's part, MMWindowTree.m.
@interface MMWindowView (Tree)
/// The lists take the model's groups with what is open, and the host hears which app rows show their insides.
- (void)treeShow;
/// A press on a row's disclosure, or Option and a press on the row: it opens or closes. NO for any other press.
- (BOOL)treePress:(nullable NSString *)key;
/// → opens the active row, ← closes it or goes to the row it is in. NO when the key does nothing to the tree.
- (BOOL)treeArrow:(unsigned short)code;
/// Opens every row above key, so it shows in its list.
- (void)treeReveal:(nullable NSString *)key;
/// Opens or closes a row, as a press on its disclosure does.
- (void)treeToggle:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
