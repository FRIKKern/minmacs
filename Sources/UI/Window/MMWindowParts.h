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
/// No text in the window is ever cut and none ends on an ellipsis. Text that may be longer than its place is drawn
/// with one of these:
/// The text as lines no wider than `width`, broken at spaces. A word wider than the line breaks between characters.
NSArray<NSString *> *MMWindowLines(NSString *text, CGFloat size, NSFontWeight weight, CGFloat width);
/// A line's height for a type size, as the window sets wrapped text.
CGFloat MMWindowLineHeight(CGFloat size);
/// The largest size, from `size` down to `floor` in half points, at which the text is one line of `width`. `floor` when none is.
CGFloat MMWindowFitSize(NSString *text, CGFloat size, CGFloat floor, NSFontWeight weight, CGFloat width);
/// Draws the text whole: on one line when it fits, with the type stepped down to `floor` when that makes it fit, and
/// wrapped to as many lines as it needs when not. No floor is under 10 points. anchor is -1 for the block's top at y,
/// 0 for its middle, 1 for its foot. `room` is the height the place has for it, 0 when the block may grow as it needs
/// and the caller moves what follows: the checks hold a block to its room. Returns the block's height, which
/// MMWindowBlockHeight says without drawing.
CGFloat MMWindowDrawBlock(NSString *text, CGFloat size, CGFloat floor, NSFontWeight weight, NSColor *color, CGFloat x, CGFloat y, CGFloat width, NSInteger align, NSInteger anchor, CGFloat room);
CGFloat MMWindowBlockHeight(NSString *text, CGFloat size, CGFloat floor, NSFontWeight weight, CGFloat width);
/// Draws wrapped text of several fonts into the rect's width, from its top, at its whole height even when the rect is
/// lower. Returns the height it took.
CGFloat MMWindowDrawIn(NSAttributedString *text, NSRect rect);
/// For the checks: called for every string the window draws, with the rect it took, the rect it was allowed (zero
/// for a single line with no box) and the bounds of the view it was drawn in. nil stops it.
void MMWindowWatchDraws(void (^_Nullable seen)(NSString *text, NSRect used, NSRect allowed, NSRect bounds));
/// A size as its number and its unit, "1.86" and "GB", so the unit can be drawn small and gray: MMWindowSizeParts of
/// the model, where the one rule is written. `disk` counts in thousands, as the Finder does.
NSArray<NSString *> *MMWindowSize2(uint64_t bytes, BOOL disk);
/// The size on one line, "1.86 GB".
NSString *MMWindowBytes(uint64_t bytes, BOOL disk);
/// What a thing can hold, such as the Mac's memory: the same, with a round number's ".0" left out, "64 GB".
NSString *MMWindowWhole(uint64_t bytes, BOOL disk);
/// What stands between a number and its small gray unit: a thin space, closer than a word.
extern NSString *const MMWindowThin;
/// CPU as the window says it, of one core: "0.3", "12", or nil when it is not known or under 0.05, and then not shown.
NSString *_Nullable MMWindowCPU(double percent);
/// The number in the text color and the unit small and gray, one line.
NSAttributedString *MMWindowNumber(uint64_t bytes, BOOL disk, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat unitSize);

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
/// The keys of the rows the ring gives an arc, for the checks: all of them, or with `after` all but the rows Fix
/// Everything touches. The drawing asks the same rule.
NSArray<NSString *> *MMWindowRingRows(MMWindowModel *model, BOOL after);

#pragma mark Motion, MMWindowMotion.m

@class CALayer;
/// A layer over the view that shows the picture in the rect and breathes: its opacity goes from none to full and back,
/// once a `period`, for as long as it is there. nil under Reduce Motion and for a view with no layer.
CALayer *_Nullable MMWindowBreathLayer(NSView *view, NSBitmapImageRep *glow, NSRect rect, NSTimeInterval period);
/// A short light under a rect of the view that fades over 0.7 s and takes itself away: a row that is new.
/// Nothing under Reduce Motion, for a view with no layer, or in a window that does not show.
void MMWindowFlash(NSView *view, NSRect rect);

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

/// What a row shows beside its name and its number, where its name may reach to, and how many lines the name takes.
typedef struct { BOOL state, cpu, hour; CGFloat edge; NSInteger lines; } MMWindowRowFit;
/// A row's name as the lines it is drawn in, whole. It first takes the room of the state word, then of the row's own
/// hour, then of CPU, and wraps when it is still too long. MMWindowRow.m.
NSArray<NSString *> *MMWindowRowName(MMWindowRow *row, MMWindowSide side, BOOL hasHour, CGFloat nameLeft, CGFloat right, MMWindowRowFit *_Nullable fit);
/// The height each line of a name beyond its first adds to a row.
extern const CGFloat MMWindowNameLine;
/// A row's second line, where its side has the room: why it stays, or its first facts that the name does not say
/// already, each as the phrase a person would say. Whole phrases only: one that does not fit is left out. nil for none.
NSString *_Nullable MMWindowRowSecondLine(MMWindowRow *row, CGFloat width);
void MMWindowDrawRow(MMWindowRow *row, NSRect rect, MMWindowSide side, BOOL hasHour, BOOL hot, BOOL tall);

/// One side: its groups, each with a still header and its own scrolling. Drawn in one drawRect.
@interface MMWindowListView : MMWindowFlipped
@property (nonatomic, copy) NSArray<MMWindowGroup *> *groups;
@property (nonatomic, copy, nullable) NSString *hotKey;             // the row drawn as pointed at
/// The Mac's whole numbers, for the lines that close a side with room left: "This disk", free, held here, the rest.
@property (nonatomic, strong, nullable) MMWindowRing *ring;
/// A new model: both at once, laid out once.
- (void)setGroups:(NSArray<MMWindowGroup *> *)groups ring:(nullable MMWindowRing *)ring;
@property (copy, nullable) void (^onPoint)(NSString *_Nullable key); // the pointer came to rest on a row, or left
- (void)reveal:(NSString *)key;                                      // scroll so the row shows
- (void)rest;                                                        // the window closed: no pending calls, every group back at its top
/// Each row's name as it is drawn at this width, in order, for the checks: whole, its lines joined by a newline.
- (NSArray<NSString *> *)drawnNames;
/// How far each group is scrolled, by its key, for the checks.
- (NSDictionary<NSString *, NSNumber *> *)offsets;
/// For the checks: a row's height on this side now, each group's frame with its header, whether the side closes
/// with its whole number, and those lines as label and value.
@property (readonly) CGFloat rowHeight;
- (NSArray<NSValue *> *)groupFrames;
/// For the checks: where a row is drawn now, in the list's own coordinates. Empty for a row that does not show.
- (NSRect)frameOfRow:(NSString *)key;
/// For the checks: where each row of each group starts in its group, with the end of the last.
- (NSArray<NSArray<NSNumber *> *> *)rowTops;
@property (readonly) BOOL showsSum;
- (NSArray<NSArray<NSString *> *> *)sumLines;
/// How many rows got the short light of a new row at the last change of the groups, for the checks.
@property (readonly) NSInteger flashed;
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
/// YES while the glow around the button breathes: at rest, with something to fix, in a window that shows.
@property (readonly) BOOL breathes;
- (void)wake;                                                        // the window came on screen
- (void)rest;                                                        // the window closed: nothing breathes
@property (readonly) MMWindowButton *stop;                           // the small Stop under the button, there only while a run plays
/// The gains as the dock draws them now, top to bottom, such as "2.9 GB memory back". A side that is zero is not
/// there, so the list holds two lines, one, or none.
@property (readonly) NSArray<NSString *> *gainLines;
/// The lines beside the ring as the dock draws them now, top to bottom: "42.4 / 64 GB", "memory in use",
/// "182 GB disk free", or a pointed row's, or the Mac after the fixes.
@property (readonly) NSArray<NSString *> *macLines;
/// How the run ended as it is drawn: whole sentences only, with trailing ones left out when the place is too small.
@property (readonly) NSString *endNote;
/// The step as the running button holds it: whole, or its action and the count when a name is too long for two lines.
@property (readonly) NSString *stepWords;
/// The run's count as VoiceOver last heard it, "Fix 3 of 7", for the checks.
@property (readonly, nullable) NSString *announced;
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
@end

@interface MMWindowView (Words)
/// Every string the window can show for this model, for the render tool's word check. In MMWindowWords.m.
+ (NSArray<NSString *> *)shownStrings:(MMWindowModel *)model;
@end

NS_ASSUME_NONNULL_END
