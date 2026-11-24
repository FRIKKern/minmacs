// The window's views, issue #62. The model is UI/Window/MMWindowModel.h.
// Everything here runs on main and draws only what an MMWindowModel holds. It names no Core type, so the render tool
// and the kit checks link it with Sources/UI alone. Sources/Shell owns the feed, the runner and the status item.
#import <Cocoa/Cocoa.h>
#import "UI/Window/MMWindowModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The window is this size in both states, the main view and Settings. It never resizes.
extern const NSSize MMWindowSize;                       // 1020 x 728 points, as 195-a

/// What the window asks of the shell. Every call comes on main; the shell does the work off main.
@protocol MMWindowHost <NSObject>
/// The press on Fix Everything. The shell runs the fixes in order and sends models whose run moves.
- (void)windowRunFixEverything;
/// The press on the button while a run plays: finish the current step, then stop.
- (void)windowStopRun;
/// A rule's choice changed in Settings.
- (void)windowSetRule:(NSString *)ruleID picked:(NSInteger)choice;
/// A switch changed in Settings.
- (void)windowSetSwitch:(NSString *)switchID on:(BOOL)on;
/// Start in the welcome, once: the answer, applied now. Open at login is added or left out, and the welcome never
/// shows again.
- (void)windowWelcomeStart:(BOOL)openAtLogin;
/// The power icon, or Command and Q.
- (void)windowQuit;
/// A press on Undo in the log: take back the record rid, as the notification's Undo does. Only an entry that can
/// still be taken back carries the press.
- (void)windowUndo:(NSString *)rid;
@optional
/// A press on Go to in an agent's story: bring forward the terminal tab, pane or app the agent of this row runs in.
/// Only a person's press sends it. The shell goes there off main.
- (void)windowGoTo:(NSString *)rowKey;
@end

/// The whole window as one view, MMWindowSize large: the top line, the two sides with the middle between them,
/// and the slim dock with the gear and the power icon at its right end. The gear flips it to Settings in place and back.
@interface MMWindowView : NSView
@property (weak, nullable) id<MMWindowHost> host;
@property (nonatomic, strong, nullable) MMWindowModel *model;   // setting it redraws, keeping hover and scroll
@property (nonatomic) BOOL showsSettings;               // the gear's state
/// For the render tool: draw as if the pointer rested on this row, so its story shows in the middle. nil for none.
@property (nonatomic, copy, nullable) NSString *pointedRow;
/// The active row: the one a press or the arrow keys picked. It is drawn in blue, the middle holds its story while the
/// pointer goes over other rows, and it stays until it is pressed again, a press lands on empty space, Escape, the
/// window closes or the row leaves the model. nil for none. The render tool sets it too.
@property (nonatomic, copy, nullable) NSString *activeRow;
/// Moving numbers and lines advance on this, so the shell ticks it only while the window is open.
- (void)tick:(NSDate *)now;
@end

/// The panel that holds the view: borderless, dark glass, non-activating, hanging under the status item's button.
/// It opens with its first frame already built from the latest model. It closes on Escape (which first leaves
/// Settings when Settings shows), on a click outside, when it is no longer the key window, when another app comes
/// to the front and when the space changes.
@interface MMWindowPanel : NSPanel
- (instancetype)initWithHost:(nullable id<MMWindowHost>)host;
@property (readonly) MMWindowView *view;
@property (readonly) BOOL isOpen;
- (void)show:(MMWindowModel *)model;                    // a new model, open or not
- (void)toggleUnder:(NSStatusBarButton *)button;
- (void)close;
/// For a window opened by a way to Settings, not by the icon: for this long, another app coming to the front, or
/// the panel losing the keyboard to it, does not close the panel. A second copy of MinMacs that handed over quits
/// right then, and the app that was in front before it comes back. Escape and a press outside still close it.
- (void)holdOpen:(NSTimeInterval)seconds;
@property (readonly) BOOL held;
/// YES while the panel holds an event monitor or an observer. It holds them only while it is open.
@property (readonly) BOOL watching;
/// Called on main after the panel opened or closed, however it closed. The shell works only while it is open.
@property (copy, nullable) void (^onOpenChange)(BOOL open);
@end

/// Who holds the panel, for the shell. Drawn once, the panel, its views and their layers hold about 100 MB, and a
/// panel only ordered out keeps it all. So after the window stayed closed for `rest` seconds the panel is let go, and
/// the next ask for it makes it again, given the last model first, so its first frame is drawn before it comes on
/// screen. Nothing is let go while it is open, nor while `busy` answers YES: then it is asked again a while later.
extern const NSTimeInterval MMWindowRestSeconds;        // 45 s: a quick reopen keeps the same panel
@interface MMWindowHolder : NSObject
- (instancetype)initWithHost:(nullable id<MMWindowHost>)host;
/// The panel, made when there is none.
@property (readonly) MMWindowPanel *panel;
/// The panel when there is one, nil once it was let go. Asks for nothing to be made.
@property (readonly, nullable) MMWindowPanel *madePanel;
@property (readonly) BOOL isOpen;
/// A new model: shown now when there is a panel, and kept for the first frame of the next.
- (void)show:(MMWindowModel *)model;
/// Called on main after the panel opened or closed, as -[MMWindowPanel onOpenChange].
@property (copy, nullable) void (^onOpenChange)(BOOL open);
/// YES keeps the panel past its rest, as while a run of Fix Everything plays.
@property (copy, nullable) BOOL (^busy)(void);
/// How long the window stays closed before its panel goes. Below 0, never. Set it before the first close.
@property NSTimeInterval rest;
/// How many panels were made, and the last one let go while anything still holds it, for the checks.
@property (readonly) NSUInteger made;
@property (readonly, weak, nullable) MMWindowPanel *lastLetGo;
@end

/// A model of made-up values for the render tool and the checks: "quiet", "busy", "peak", "running", "done", "empty",
/// and three days that came from the first look at the real window: "young", "calm" and "long".
/// "memory-only" and "disk-only" are the busy day with fixes that give only that side back.
/// "welcome" is the young day with the welcome on it, and "welcome-off" is the same with the switch off.
/// "welcome-watched" is the welcome a person meets who
/// used MinMacs for more than a day before.
MMWindowModel *MMWindowFixture(NSString *name);

NS_ASSUME_NONNULL_END
