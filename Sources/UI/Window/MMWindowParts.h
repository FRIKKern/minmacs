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
    MMWindowInkHot,         // the active row, the one a press picked: solid blue
    MMWindowInkHover,       // the row under the pointer: a quiet white wash
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
/// A row's small hour draws as a line only once this many of its minutes hold a value. Under that it shows nothing.
static const NSInteger MMWindowHourLeast = 5;
/// The middle's strip draws as soon as two minutes hold a value, the least that makes a line. It spans the
/// minutes kept so far and says how long that is, "the last 4 min", so a young hour is a real line.
static const NSInteger MMWindowHourGraphLeast = 2;
/// The part of an hour from its first filled minute to its last, or nil when fewer than MMWindowHourLeast are filled.
/// `first` and `last` get the two indexes, -1 when none, and `filled` how many minutes hold a value.
NSArray *_Nullable MMWindowHourSpan(NSArray *_Nullable values, NSInteger *_Nullable first, NSInteger *_Nullable last, NSInteger *_Nullable filled);
/// MMWindowHourSpan with its own least, for the large graph's MMWindowHourGraphLeast.
NSArray *_Nullable MMWindowHourSpanAtLeast(NSArray *_Nullable values, NSInteger least, NSInteger *_Nullable first, NSInteger *_Nullable last, NSInteger *_Nullable filled);
/// How long the kept part of a graph is, as its title says it: "the last hour" once it spans 60 minutes, else
/// "the last 4 min".
NSString *MMWindowHourSpanWords(NSInteger minutes);
/// How an hour is drawn: the large graph, a row's small line, the line in a row's story, or one side of the middle's
/// strip. Each spreads its filled part across its whole width. The small ones, a row's and the strip's, show a wobble
/// as flat, on a scale of at least a quarter of their value.
/// MMWindowHourWeek is the strip's 7 days: it spreads MMWindowWeekSpan, from the first hour that holds a value to the
/// newest hour, so hours with none at its end stay a gap there, and an hour alone between two gaps is a dot.
typedef NS_ENUM(NSInteger, MMWindowHourLook) { MMWindowHourGraph = 0, MMWindowHourRow, MMWindowHourStory, MMWindowHourStrip, MMWindowHourWeek };
/// An hour in the rect: the fill, the line, and a dot at the newest minute. Nothing when fewer than
/// MMWindowHourLeast minutes are filled, or MMWindowHourGraphLeast for the large graph and the strip.
void MMWindowDrawHour(NSArray *_Nullable values, NSRect rect, NSColor *color, MMWindowHourLook look);

/// The Mac as a ring around `center`: memory by holder inside, the disk as the thin outer track, each row an arc of
/// its own. In the dock, 45 points across, or in a row's story, 62 (`small`). With `lit`, that row's arc is white
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
/// Fix Everything's two short moments, each once and gone in under a second: `MMWindowPulse` sends a soft ring of
/// the button's ink out from its pill as a press starts a run, and `MMWindowShine` runs one light across the pill as
/// the run ends. Nothing under Reduce Motion, for a view with no layer, or in a window that does not show.
void MMWindowPulse(NSView *view, NSRect pill, NSColor *color);
void MMWindowShine(NSView *view, NSRect pill);

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
/// A Settings mark by name: "cup", "sun", "spark", "laptop", "sparkles", "server", "memory", "branch", "layers",
/// "display", "power", "trash". `solid` fills the tile with the tint and draws the mark dark, for a card's head; else
/// the tile is the tint deepened and the mark is the tint, as a row's icon. `dim` steps a row that changes nothing back.
void MMWindowDrawSettingMark(NSString *name, NSRect rect, NSColor *tint, BOOL solid, BOOL dim);

#pragma mark Views

@interface MMWindowFlipped : NSView
@end

/// Where each part of one row stands, worked out once from the right: the size, the row's own hour, CPU, the state
/// word, and the name in what is left. A part that is not there has an empty rect, and the parts left of it move
/// right into its place. Every part is drawn in its rect, so no part reaches into the next. Each rect is as high as
/// the row.
typedef struct { NSRect size, hour, cpu, state, name; NSInteger lines; } MMWindowRowColumns;
/// A row's name as the lines it is drawn in, whole, and where each part of the row stands. The name first takes the
/// room of a column with nothing to show in this row, then of the state word, then of the row's own hour, then of
/// CPU, and wraps when it is still too long. `rect` is the row's. MMWindowRow.m.
NSArray<NSString *> *MMWindowRowName(MMWindowRow *row, MMWindowSide side, BOOL hasHour, NSRect rect, MMWindowRowColumns *_Nullable columns);
/// The same for the name the row shows under its project's sub-header, `name` in place of its shown name.
NSArray<NSString *> *MMWindowRowNameAs(MMWindowRow *row, NSString *name, MMWindowSide side, BOOL hasHour, NSRect rect, MMWindowRowColumns *_Nullable columns);
/// The height each line of a name beyond its first adds to a row.
extern const CGFloat MMWindowNameLine;
/// A row's second line, where its side has the room: why it stays, or its first facts that the name does not say
/// already, each as the phrase a person would say. Whole phrases only: one that does not fit is left out. nil for none.
NSString *_Nullable MMWindowRowSecondLine(MMWindowRow *row, CGFloat width);
/// How a row is drawn: at rest; under the pointer, a quiet white wash with its text as at rest; or active, the row a
/// press picked, solid blue with white text.
typedef NS_ENUM(NSInteger, MMWindowRowLook) { MMWindowRowRest = 0, MMWindowRowHover, MMWindowRowActive };
void MMWindowDrawRow(MMWindowRow *row, NSRect rect, MMWindowSide side, BOOL hasHour, MMWindowRowLook look, BOOL tall);
void MMWindowDrawRowAs(MMWindowRow *row, NSString *name, NSRect rect, MMWindowSide side, BOOL hasHour, MMWindowRowLook look, BOOL tall);

/// One side: its groups, each with a still header and its own scrolling. Drawn in one drawRect.
@interface MMWindowListView : MMWindowFlipped
@property (nonatomic, copy) NSArray<MMWindowGroup *> *groups;
@property (nonatomic, copy, nullable) NSString *hotKey;             // the active row, drawn in blue and read as selected
@property (nonatomic, copy, nullable) NSString *hoverKey;           // the row under the pointer, drawn with a white wash
/// The Mac's whole numbers, for the lines that close a side with room left: "This disk", free, held here, the rest.
@property (nonatomic, strong, nullable) MMWindowRing *ring;
/// A new model: both at once, laid out once.
- (void)setGroups:(NSArray<MMWindowGroup *> *)groups ring:(nullable MMWindowRing *)ring;
@property (copy, nullable) void (^onPoint)(NSString *_Nullable key); // the pointer came to rest on a row, or left
@property (copy, nullable) void (^onPress)(NSString *_Nullable key); // a press on a row, or on the list's empty space: nil
/// Every row's key, group after group, each group in the order it is drawn: the order the arrow keys go.
- (NSArray<NSString *> *)rowKeys;
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

/// The pointer at a point, and a press at a point, in the list's own coordinates: what the mouse does, and what the
/// checks do in its place. MMWindowListInput.m.
@interface MMWindowListView (Pointer)
- (void)pointAt:(NSPoint)p;
- (void)pressAt:(NSPoint)p;
@end

/// What a list says of its groups with projects, for the checks. MMWindowListProjects.m.
@interface MMWindowListView (ProjectChecks)
/// Each row's name as the list shows it, in the order of drawnNames: under a project's sub-header a worktree leaves
/// out its repo.
- (NSArray<NSString *> *)listNames;
/// A group's rows in the order they are drawn, top to bottom, each by its key. A group with projects shows each
/// project's most active rows first, and the rest of each project under them.
- (NSArray<NSString *> *)drawnOrder:(NSInteger)group;
/// The rows of a group that show now, by key, and the lines under its projects, "3 more in barkbot", top to bottom.
- (NSArray<NSString *> *)shownKeys:(NSInteger)group;
- (NSArray<NSString *> *)moreLines:(NSInteger)group;
/// The heights a group's box may take, each ending on a whole row, smallest first.
- (NSArray<NSNumber *> *)steps:(NSInteger)group;
@end

@class MMWindowButton;

/// The log under the middle's strip, MMWindowLogView.m: the entries newest first, grouped by day, each a sentence and
/// a quiet line. Only whole entries are drawn: the fingers move it an entry at a time, and the foot says how many
/// wait above and below. A new log keeps the entry at the top where it was.
@interface MMWindowLogView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowLog *log;
/// The index of the entry at the top. Setting it moves the log there, as far as the entries below it fill the view.
@property (nonatomic) NSInteger first;
/// For the checks: the sentences drawn at the last drawing, top to bottom, and the line at the foot.
@property (readonly) NSArray<NSString *> *drawnSentences;
@property (readonly, nullable) NSString *footLine;
/// The Undo presses of the entries shown, top to bottom, for the checks.
@property (readonly) NSArray<MMWindowButton *> *undoButtons;
/// A press on an entry's Undo, with the record's rid. The window's view hands it to its host.
@property (copy, nullable) void (^onUndo)(NSString *rid);
- (void)rest;                                                        // the window closed: back at the newest entry
@end

/// How long ago the minute at this index of an hour was: "now", "12 min ago", "an hour ago".
NSString *MMWindowAgo(NSInteger index, NSInteger count);
/// How high the middle's strip stands: the two sides, then the row of its two words "hour · 7 days".
static const CGFloat MMWindowStripHeight = 92;

/// The middle: a strip with the two last hours or 7 days small, and the log under it. Or one row's story, over all of it.
@interface MMWindowMiddleView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowHour *memoryHour, *diskHour;
@property (nonatomic, strong, nullable) MMWindowRow *row;
/// The whole model, for a story's ring, for where its row stands in its group, and for the log.
@property (nonatomic, strong, nullable) MMWindowModel *model;
@property (readonly) MMWindowLogView *logView;
/// How high the strip of the two hours stands, from the middle's top to the log.
@property (readonly) CGFloat stripHeight;
/// Open pull request, under a worktree's pull request in its story. Hidden while the story has none to open.
@property (readonly) MMWindowButton *pullButton;
/// Called on main when the story shown changes to another row, with its key, or nil when no story shows.
@property (copy, nullable) void (^onStory)(NSString *_Nullable rowKey);
/// A press on a story's fact that names another row, with that row's key: the window makes it the active row.
@property (copy, nullable) void (^onLink)(NSString *rowKey);
/// A press on Go to in an agent's story, with the agent row's key.
@property (copy, nullable) void (^onGoTo)(NSString *rowKey);
/// The pointer came onto the middle, YES, or left it, NO: the window keeps the story that shows while it rests here.
@property (copy, nullable) void (^onPointer)(BOOL over);
/// The story's presses as they stand now, for the checks: Go to and each link.
@property (readonly) NSArray<MMWindowButton *> *storyPresses;
@end

@class MMWindowStripState;
/// The strip's own state, made and used by MMWindowStrip.m alone.
@interface MMWindowMiddleView ()
@property (strong, nullable) MMWindowStripState *strip;
@end

/// The strip, MMWindowStrip.m: its two sides, its two words and the reading under the pointer.
@interface MMWindowMiddleView (MMWindowStrip)
/// The 7 days of each side, one value an hour, MMWindowWeekSpan. nil until the shell has read them.
@property (nonatomic, strong, nullable) MMWindowHour *memoryWeek, *diskWeek;
/// What the strip shows: NO the last hour, YES the last 7 days, as the model's stripWeek says. A press on one of its
/// two words sets it at once and tells onWeek, and a model that still says the other keeps the press's choice until
/// one says the same.
@property (nonatomic) BOOL stripWeek;
/// The two words, real buttons: "hour" and "7 days", the one shown bright. Hidden while a story shows.
@property (readonly) MMWindowButton *hourPress, *weekPress;
/// A press on one of the two words, with the choice: the window tells its host, which keeps it as a pref.
@property (copy, nullable) void (^onWeek)(BOOL week);
/// The reading under the pointer, as the strip draws it, "Tue 14:00 · 41.2 GB", or nil when the pointer is off the lines.
@property (readonly, nullable) NSString *stripReading;
- (void)makeStripPresses;
- (void)placeStripPresses;
- (void)drawStrips;
/// A model's choice, unless a press asked for the other and no model has said so yet.
- (void)takeStripWeek:(BOOL)week;
/// The pointer at p, in the middle's points: over a side's line it shows the reading there. Off the lines it shows none.
- (void)pointStripAt:(NSPoint)p;
@end

typedef NS_ENUM(NSInteger, MMWindowDockPhase) { MMWindowDockCalm = 0, MMWindowDockRunning, MMWindowDockEnded };

/// A button the window draws itself: a real NSButton, so keyboard, tooltips and accessibility come with it.
/// Link is the log's small Undo press, in the quiet line's size.
/// Segment is one word of a choice of two, such as the strip's "hour" and "7 days": lit is the one chosen, bright on a
/// quiet pill, and the other is quiet type.
typedef NS_ENUM(NSInteger, MMWindowButtonKind) { MMWindowButtonClear = 0, MMWindowButtonGear, MMWindowButtonPower, MMWindowButtonPill, MMWindowButtonOutline, MMWindowButtonLink, MMWindowButtonSegment };
@interface MMWindowButton : NSButton
@property (nonatomic) MMWindowButtonKind kind;
@property (nonatomic) BOOL lit;                                      // the gear while Settings shows
@property (readonly) BOOL hovered;
- (void)setHover:(BOOL)on;                                           // the pointer came or left; the render tool calls it too
@property (copy, nullable) void (^onHover)(void);
+ (instancetype)kind:(MMWindowButtonKind)kind title:(NSString *)title target:(nullable id)target action:(nullable SEL)action;
@end

/// The dock, one slim band at the window's foot: a small ring with memory and disk as two quiet numbers at left,
/// Fix Everything in the middle, and at right what it gives back, or how far a run is and how it ended.
@interface MMWindowDockView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowModel *model;
@property (nonatomic) MMWindowDockPhase phase;
@property (nonatomic) double progress;                               // how far the running button is filled, 0 to 1: fixes landed of all
@property (nonatomic) double memoryShown, diskShown;                 // the gains while they count up, in bytes
@property (nonatomic) double glow;                                   // 1 right as a run ends, then down to 0
@property (nonatomic) double stepIn;                                 // 0 as a new step's words arrive in the button, up to 1
@property (nonatomic, strong, nullable) MMWindowRow *pointed;        // the row under the pointer, else the active row: the ring and the numbers beside it tell its share
@property (readonly) MMWindowButton *fix;
/// YES while the glow around the button breathes: at rest, with something to fix, in a window that shows.
@property (readonly) BOOL breathes;
- (void)wake;                                                        // the window came on screen
- (void)rest;                                                        // the window closed: nothing breathes
@property (readonly) MMWindowButton *stop;                           // the small Stop beside "Fix 3 of 7", there only while a run plays
/// The gains as the dock draws them now, one side each, such as "+2.9 GB memory". A side that is zero is not there,
/// so the list holds two, one, or none. `gainWord` is what stands with them: "back today", "so far", or nil.
@property (readonly) NSArray<NSString *> *gainLines;
@property (readonly, nullable) NSString *gainWord;
/// The lines beside the ring as the dock says them now, top to bottom: "42.4 / 64 GB", "memory in use",
/// "182 GB disk free", or a pointed row's, or the Mac after the fixes. The number and its label share a drawn line.
@property (readonly) NSArray<NSString *> *macLines;
/// What the button says now, as drawn: "Fix Everything", "No fixes to run", the step, or how the run ended.
@property (readonly) NSString *buttonWords;
/// How the run ended as it is drawn: whole sentences only, with trailing ones left out when the place is too small.
@property (readonly) NSString *endNote;
/// The step as the running button holds it: whole, or its action alone when a name is too long for two lines.
@property (readonly) NSString *stepWords;
/// The run's count as VoiceOver last heard it, "Fix 3 of 7", for the checks.
@property (readonly, nullable) NSString *announced;
@end

/// Settings in place: three cards of switch rows, each with its own color and mark.
@interface MMWindowSettingsView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowSettings *settings;
@property (weak, nullable) id<MMWindowHost> host;
@property (copy, nullable) void (^onDone)(void);
@end

/// The welcome of the first launch, alone in the window: one centered column. An answer the person touched is the
/// view's own until Start, so a newer model never takes it back. One they left alone follows the model.
@interface MMWindowWelcomeView : MMWindowFlipped
@property (nonatomic, strong, nullable) MMWindowWelcome *welcome;
@property (copy, nullable) void (^onStart)(BOOL openAtLogin);
@property (nonatomic) CGFloat arrival;                               // 0 to 1: how far the parts have risen in
@property (readonly) BOOL loginOn;
- (void)pressStart;                                                  // Start, as a press or Return
- (void)rest;                                                        // the panel left: no timer
- (void)willArrive;                                                  // the panel is about to come on screen
- (void)arrive;                                                      // the panel came on screen: the parts rise in, or stand still under Reduce Motion
/// For the checks: the frame of each part, top to bottom, and the buttons a key or VoiceOver reaches, in order.
- (NSArray<NSValue *> *)partFrames;
- (NSArray<NSButton *> *)controls;
@end

@interface MMWindowPanel ()
/// What -toggleUnder: does once it knows where: the first frame drawn, then on screen. key NO orders it in without
/// the keyboard, for the checks, which open it far off every screen.
- (void)openInFrame:(NSRect)frame key:(BOOL)key;
/// For the checks: called right before the panel comes on screen, after its first frame was drawn.
@property (copy, nullable) void (^onWillShow)(void);
/// Closed for good: the views and their layers go now. AppKit may hold on to an ordered-out window for a while, as
/// the window that was key last, so the panel does not wait for its own end to let them go. MMWindowHolder calls it.
- (void)emptyOut;
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
/// A press on a row, as the lists send it: the row becomes active, or stops being active when it was, and nil, a
/// press on empty space, leaves none active. It only selects: it never acts.
- (void)pressRow:(nullable NSString *)key;
/// What Escape does, for the checks: leaves Settings, else lets go of the active row, else closes the window.
- (void)escape;
/// The pointer left the window, for the checks too: with an active row, its story comes back at once.
- (void)pointLeft;
@property (readonly, nullable) MMWindowWelcomeView *welcomeView;
@end

@interface MMWindowView (Words)
/// Every string the window can show for this model, for the render tool's word check. In MMWindowWords.m.
+ (NSArray<NSString *> *)shownStrings:(MMWindowModel *)model;
@end

NS_ASSUME_NONNULL_END
