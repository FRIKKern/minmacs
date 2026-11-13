// The parts the window is made of, issue #62. Only the files in UI/Window and the render tool import this.
// MMWindowUI.h is what the shell sees. Everything here runs on main, in flipped views, and reads only the model.
#import <Cocoa/Cocoa.h>
#import "UI/Window/MMWindowUI.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark Style

/// The window's inks, from 195-a's computed styles. The window is dark glass in every appearance.
typedef NS_ENUM(NSInteger, MMWindowInk) {
    MMWindowInkBase = 0,    // what the render tool puts behind the glass
    MMWindowInkGlass,       // the tint over the blur
    MMWindowInkLine,        // hairlines
    MMWindowInkText,        // names and numbers
    MMWindowInkText2,       // state words, units, explain lines
    MMWindowInkText3,       // the quietest text
    MMWindowInkHot,         // the row under the pointer
    MMWindowInkMemory,      // the memory line and gain
    MMWindowInkDisk,        // the disk line and gain
    MMWindowInkFix,         // Fix Everything and what it touches
    MMWindowInkCard         // a Settings card
};
NSColor *MMWindowColor(MMWindowInk ink);
/// One color per group, by its key: servers, agents, apps, worktrees, caches. Gray for any other.
NSColor *MMWindowGroupColor(NSString *key);
/// Increase Contrast, from the system or forced by the render tool for its contrast PNGs.
BOOL MMWindowContrast(void);
void MMWindowForceContrast(BOOL on);
BOOL MMWindowReduceMotion(void);
/// The system font with tabular digits, cached by size and weight.
NSFont *MMWindowFont(CGFloat size, NSFontWeight weight);

/// One run of text in one font and color. Runs joined into one line share a baseline.
NSAttributedString *MMWindowText(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color);
NSAttributedString *MMWindowJoin(NSArray<NSAttributedString *> *runs);
CGFloat MMWindowWidth(NSAttributedString *line);
/// Text in the window is drawn without font smoothing, as 195-a draws it (antialiased): light letters on dark glass
/// that are not thickened. MMWindowDraw sets it. A view that draws text another way calls this first.
void MMWindowCrisp(void);
/// Draws one line with its middle at midY. align is -1 for left at x, 0 for centered on x, 1 for right at x.
void MMWindowDraw(NSAttributedString *line, CGFloat x, CGFloat midY, NSInteger align);
/// The same text cut at the tail so it fits.
NSAttributedString *MMWindowFit(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat width);
/// The same text with whole words dropped from its end until it fits, and no ellipsis: a shorter true name.
/// A name with no space, such as a branch, loses whole parts at a hyphen, slash, dot or underscore instead.
NSString *MMWindowShorten(NSString *text, CGFloat size, NSFontWeight weight, CGFloat width);
/// A size as its number and its unit, "1.86" and "GB", so the unit can be drawn small and gray. One rule for every
/// size the window shows: megabytes whole, gigabytes with one decimal that stays when it is a zero ("1.0"), a second
/// decimal under 10 GB when it says more ("1.86", but "1.3"), and whole from 100 GB up ("182").
NSArray<NSString *> *MMWindowSize2(uint64_t bytes);
/// The size on one line, "1.86 GB".
NSString *MMWindowBytes(uint64_t bytes);
/// What a thing can hold, such as the Mac's memory: the same, with a round number's ".0" left out, "64 GB".
NSString *MMWindowWhole(uint64_t bytes);
/// What stands between a number and its small gray unit: a thin space, closer than a word.
extern NSString *const MMWindowThin;
/// CPU as the window says it, of one core: "0.3", "12", or nil when it is not known or under 0.05, and then not shown.
NSString *_Nullable MMWindowCPU(double percent);
/// The number in the text color and the unit small and gray, one line.
NSAttributedString *MMWindowNumber(uint64_t bytes, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat unitSize);

/// The filled values of an hour, as doubles with NAN for a gap. `filled` gets how many minutes hold a value.
NSArray<NSNumber *> *MMWindowHourValues(NSArray *_Nullable values, NSInteger *_Nullable filled);
/// An hour draws as a line only once this many of its minutes hold a value. Under that the window says so in words.
static const NSInteger MMWindowHourLeast = 5;
/// The part of an hour from its first filled minute to its last, or nil when fewer than MMWindowHourLeast are filled.
/// `first` and `last` get the two indexes, -1 when none, and `filled` how many minutes hold a value.
NSArray *_Nullable MMWindowHourSpan(NSArray *_Nullable values, NSInteger *_Nullable first, NSInteger *_Nullable last, NSInteger *_Nullable filled);
/// How an hour is drawn: the large graph, a row's small line, or the line in a row's story. Each spreads its filled
/// part across its whole width. The small ones show a wobble as flat, on a scale of at least a quarter of their value.
typedef NS_ENUM(NSInteger, MMWindowHourLook) { MMWindowHourGraph = 0, MMWindowHourRow, MMWindowHourStory };
/// An hour in the rect: the fill, the line, and a dot at the newest minute. Nothing when fewer than
/// MMWindowHourLeast minutes are filled.
void MMWindowDrawHour(NSArray *_Nullable values, NSRect rect, NSColor *color, MMWindowHourLook look);

/// The Mac as a ring around `center`: memory by holder inside, the disk as the thin outer track, each row an arc of
/// its own. Large in the dock, 108 points across, or small in a row's story, 62. With `lit`, that row's arc is white
/// and lifted and the rest step back. With `after`, the rows Fix Everything touches are left out: the Mac after it.
void MMWindowDrawRing(MMWindowModel *model, NSPoint center, BOOL small, MMWindowRow *_Nullable lit, BOOL after);

#pragma mark Presses

/// After Start the menu takes no press and no key for as long as it takes to arrive, and this much longer.
extern const NSTimeInterval MMWindowStartGuard;
/// How long the welcome's parts take to rise in, from the window's opening to Start in its place: 0.9 s. Until a part
/// has landed it takes no press, so this is also how long Start waits. Nothing rises under Reduce Motion.
extern const NSTimeInterval MMWindowWelcomeRise;
/// NO for a view that is hidden, not fully there yet or on its way out, or that the window holds back for now. Every
/// button of the window asks this before it acts and before it takes the keyboard, and the window's hit test asks it
/// too. So a view at alpha 0 or in the middle of a fade never takes a press.
BOOL MMWindowTakesPresses(NSView *view);

#pragma mark Icons

/// A row's small mark. `backing` is the color behind it, for the badge's edge.
void MMWindowDrawIcon(MMWindowRow *row, NSRect rect, NSColor *backing);
/// Called on main when an app's own icon arrived, so the lists can draw again.
void MMWindowIconsOnLoad(void (^_Nullable block)(void));
void MMWindowDrawDiamond(NSRect rect, NSColor *color);
void MMWindowDrawGear(NSRect rect, NSColor *color);
void MMWindowDrawPower(NSRect rect, NSColor *color);

#pragma mark Views

@interface MMWindowFlipped : NSView
@end

/// One side: its groups, each with a still header and its own scrolling. Drawn in one drawRect.
@interface MMWindowListView : MMWindowFlipped
@property (nonatomic, copy) NSArray<MMWindowGroup *> *groups;
@property (nonatomic, copy, nullable) NSString *hotKey;             // the row drawn as pointed at
/// The Mac's whole numbers, for the lines that close a side with room left: "This disk", free, held here, the rest.
@property (nonatomic, strong, nullable) MMWindowRing *ring;
@property (copy, nullable) void (^onPoint)(NSString *_Nullable key); // the pointer came to rest on a row, or left
- (void)reveal:(NSString *)key;                                      // scroll so the row shows
- (void)rest;                                                        // the window closed: no pending calls, every group back at its top
/// Each row's name as it is drawn at this width, in order, for the checks: whole, or with whole words dropped.
- (NSArray<NSString *> *)drawnNames;
/// How far each group is scrolled, by its key, for the checks.
- (NSDictionary<NSString *, NSNumber *> *)offsets;
/// For the checks: a row's height on this side now, each group's frame with its header, whether the side closes
/// with its whole number, and those lines as label and value.
@property (readonly) CGFloat rowHeight;
- (NSArray<NSValue *> *)groupFrames;
@property (readonly) BOOL showsSum;
- (NSArray<NSArray<NSString *> *> *)sumLines;
@end

/// The middle: the two last-hour graphs, or one row's story.
@interface MMWindowMiddleView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowHour *memoryHour, *diskHour;
@property (nonatomic, strong, nullable) MMWindowRow *row;
/// The whole model, for a story's ring and for where its row stands in its group.
@property (nonatomic, strong, nullable) MMWindowModel *model;
@end

typedef NS_ENUM(NSInteger, MMWindowDockPhase) { MMWindowDockCalm = 0, MMWindowDockRunning, MMWindowDockEnded };

/// A button the window draws itself: a real NSButton, so keyboard, tooltips and accessibility come with it.
typedef NS_ENUM(NSInteger, MMWindowButtonKind) { MMWindowButtonClear = 0, MMWindowButtonGear, MMWindowButtonPower, MMWindowButtonPill, MMWindowButtonOutline };
@interface MMWindowButton : NSButton
@property (nonatomic) MMWindowButtonKind kind;
@property (nonatomic) BOOL lit;                                      // the gear while Settings shows
@property (readonly) BOOL hovered;
- (void)setHover:(BOOL)on;                                           // the pointer came or left; the render tool calls it too
@property (copy, nullable) void (^onHover)(void);
+ (instancetype)kind:(MMWindowButtonKind)kind title:(NSString *)title target:(nullable id)target action:(nullable SEL)action;
@end

/// The dock: the ring, the two numbers beside it, Fix Everything with its two lines, and the gains.
@interface MMWindowDockView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowModel *model;
@property (nonatomic) MMWindowDockPhase phase;
@property (nonatomic) double memoryShare, diskShare;                 // how far the two lines are filled, 0 to 1
@property (nonatomic) double memoryShown, diskShown;                 // the gains while they count up, in bytes
@property (nonatomic) double glow;                                   // 1 right as a run ends, then down to 0
@property (nonatomic) double stepIn;                                 // 0 as a new step's words arrive in the button, up to 1
@property (nonatomic, strong, nullable) MMWindowRow *pointed;        // the row under the pointer: the ring and the numbers beside it tell its share
@property (readonly) MMWindowButton *fix;
@property (readonly) MMWindowButton *stop;                           // the small Stop under the button, there only while a run plays
/// The gains as the dock draws them now, top to bottom, such as "2.9 GB memory back". A side that is zero is not
/// there, so the list holds two lines, one, or none.
@property (readonly) NSArray<NSString *> *gainLines;
@end

/// Settings in place: a card per rule and one for the switches.
@interface MMWindowSettingsView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowSettings *settings;
@property (weak, nullable) id<MMWindowHost> host;
@property (copy, nullable) void (^onDone)(void);
@end

/// The welcome of the first launch, alone in the window: one centered column. An answer the person touched is the
/// view's own until Start, so a newer model never takes it back. One they left alone follows the model.
@interface MMWindowWelcomeView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowWelcome *welcome;
@property (copy, nullable) void (^onStart)(BOOL openAtLogin, NSInteger removal);
@property (nonatomic) CGFloat arrival;                               // 0 to 1: how far the parts have risen in
@property (readonly) BOOL loginOn;
@property (readonly) NSInteger picked;
- (void)pressStart;                                                  // Start, as a press or Return
- (void)rest;                                                        // the panel left: no timer
- (void)willArrive;                                                  // the panel is about to come on screen
- (void)arrive;                                                      // the panel came on screen: the parts rise in, or stand still under Reduce Motion
/// For the checks: the frame of each part, top to bottom, and the buttons a key or VoiceOver reaches, in order.
- (NSArray<NSValue *> *)partFrames;
- (NSArray<NSButton *> *)controls;
@end

@interface MMWindowView ()
/// The render tool sets this: an opaque dark base under the glass, since no blur is behind it there.
@property (nonatomic) BOOL drawsBacking;
- (void)willOpen;                                                    // the panel is about to come on screen
- (void)opened;                                                      // the panel came on screen
- (void)rest;                                                        // the panel left: no timers, no hover
- (BOOL)holdsBack:(NSView *)view;                                    // for MMWindowTakesPresses
@property (readonly) BOOL showsWelcome;                              // the welcome is what shows now
/// The render tool sets this: draw as if the pointer rested on Fix Everything.
@property (nonatomic) BOOL pointsAtFix;
@property (readonly, nullable) MMWindowWelcomeView *welcomeView;
/// Every string the window can show for this model, for the render tool's word check.
+ (NSArray<NSString *> *)shownStrings:(MMWindowModel *)model;
@end

NS_ASSUME_NONNULL_END
