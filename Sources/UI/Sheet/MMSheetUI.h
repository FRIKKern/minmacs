// The sheet's views, prototype 54-a, Day Lanes. The model is Sources/Core/MMSheet.h.
// The shell owns the panel, the tab bar, the Advanced unfold, cards, the rule popover and the toast (MMSheetPanel).
// Each tab is one view that draws an MMSheet and asks the host for everything that floats above it.
// Every view runs on main and draws only what the MMSheet holds: no disk, no process, no log, no model.
#import <Cocoa/Cocoa.h>
#import "Core/MMSheet.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Style, taken from 54-a.html's :root

/// The sheet is dark glass in both appearances, as in the prototype. Increase Contrast raises the text and line alphas.
typedef NS_ENUM(NSInteger, MMSheetColor) {
    MMSheetGlass = 0,      // rgba(28,29,38,.9) over an NSVisualEffectView
    MMSheetLine,           // hairlines, white at .07
    MMSheetText,           // white at .94
    MMSheetText2,          // rgba(235,235,245,.62)
    MMSheetText3,          // rgba(235,235,245,.36)
    MMSheetRowHover,       // #2c2c3a
    MMSheetWorkstream,     // #FF8A66, also the ready color
    MMSheetAgent,          // #EE85B5
    MMSheetApp,            // #5B9BFF
    MMSheetServer,         // #3FD0B8
    MMSheetWorktree,       // #4CC96B, also PR marks
    MMSheetDisk            // #F2B544
};
NSColor *MMSheetColorFor(MMSheetColor c);
/// The tab's own color: Workstreams coral, Agents pink, Performance and Apps blue, Servers teal, Worktrees green, Disk amber.
NSColor *MMSheetTabColor(MMSheetTab tab);
/// The system font at the prototype's sizes: 30 big numbers, 20 headings, 13 body, 11 captions; tabular digits.
NSFont *MMSheetFont(CGFloat size, NSFontWeight weight);

/// The sheet is 760 x 580 points. The body below the tab bar is 704 x 492, at 28 from the sides and 68 from the top.
extern const NSSize MMSheetSize;
extern const NSRect MMSheetBodyFrame;

#pragma mark - What floats above a tab

/// The shell implements this. A tab calls it on main, and the shell draws above every tab.
@protocol MMSheetHost <NSObject>
/// A hover card for this spec, beside rect in the view's coordinates. nil hides it.
- (void)showCard:(nullable MMCardSpec *)card near:(NSRect)rect inView:(NSView *)view;
/// The rule's Off / Ask / Auto popover, as the Wrap Up chip in the Next column header opens it.
- (void)showRule:(MMSheetRule *)rule near:(NSRect)rect inView:(NSView *)view;
/// Runs an action, then shows a toast with its result and an Undo button when the action left an undo record.
- (void)runAction:(MMActionSpec *)action;
/// Changes a rule's mode or its "after" value. The shell hands it to the owning expert off main.
- (void)setRule:(NSString *)ruleID mode:(MMSheetMode)mode value:(NSInteger)value;
/// The switches of Settings: "lid", "oneIcon", "openAtLogin", "advanced".
- (void)setSwitch:(NSString *)key on:(BOOL)on;
/// A row that links to a lane, such as an agent under Performance, switches to Workstreams and shows that lane.
- (void)showLane:(NSString *)laneID;
@end

#pragma mark - One tab

/// A tab view is MMSheetBodyFrame.size and redraws from each new MMSheet without losing hover or scroll.
/// Live time: the shell calls -tick each second, so countdowns and the now line move between snapshots.
@protocol MMSheetTabView <NSObject>
@property (weak) id<MMSheetHost> host;
@property (readonly) MMSheetTab tab;
- (void)showSheet:(MMSheet *)sheet;
- (void)tick:(NSDate *)now;
@end

/// Workstreams: lanes, the axis from dayStart to now, Next and Holds, the legend, Leftovers.
@interface MMSheetWorkstreamsView : NSView <MMSheetTabView>
/// Scrolls to and flashes one lane, for -[MMSheetHost showLane:].
- (void)revealLane:(NSString *)laneID;
@end

/// Performance, or Apps in Advanced mode: CPU and memory bars, apps by fate in two columns, agents under their app.
@interface MMSheetPerformanceView : NSView <MMSheetTabView>
@end

/// Settings: the three rules, the Mac column with the lid checkbox, One icon and Open at login, and the Advanced card.
@interface MMSheetSettingsView : NSView <MMSheetTabView>
@end

/// One advanced tab: its rule line, then its groups of rows. Servers draws each row's heartbeat.
@interface MMSheetListView : NSView <MMSheetTabView>
- (instancetype)initWithTab:(MMSheetTab)tab;
@end

#pragma mark - The panel

/// The sheet itself: a borderless, non-activating panel under the MinMacs status item with a nub, the tab bar,
/// the head line, the tab views, and the card, popover and toast layers. It must open as fast as a native menu:
/// first frame within one display refresh of the click, with every tab already built from the latest MMSheet.
@interface MMSheetPanel : NSPanel <MMSheetHost>
- (instancetype)initForStatusItem:(NSStatusItem *)item;
- (void)showSheet:(MMSheet *)sheet;                     // main; a new snapshot's sheet
- (void)toggle;                                         // open under the item, or close
@property (nonatomic) MMSheetTab currentTab;          // NSPanel already has a tab property
@property (nonatomic) BOOL advanced;                    // animates the four tabs in or out, as 54-a does
@end

/// Draws one tab of a sheet to a PNG for the render tool and the checks: the whole panel at 2x, in the dark glass,
/// with Increase Contrast on or off. Main thread.
BOOL MMSheetRender(MMSheet *sheet, MMSheetTab tab, BOOL advanced, BOOL increaseContrast, NSString *path);

NS_ASSUME_NONNULL_END
