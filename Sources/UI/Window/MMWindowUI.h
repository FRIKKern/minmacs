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
/// The power icon, or Command and Q.
- (void)windowQuit;
@end

/// The whole window as one view, MMWindowSize large: the top line, the two sides with the middle between them,
/// the dock and the strip with the gear and the power icon. The gear flips it to Settings in place and back.
@interface MMWindowView : NSView
@property (weak, nullable) id<MMWindowHost> host;
@property (nonatomic, strong, nullable) MMWindowModel *model;   // setting it redraws, keeping hover and scroll
@property (nonatomic) BOOL showsSettings;               // the gear's state
/// For the render tool: draw as if the pointer rested on this row, so its story shows in the middle. nil for none.
@property (nonatomic, copy, nullable) NSString *pointedRow;
/// Moving numbers and lines advance on this, so the shell ticks it only while the window is open.
- (void)tick:(NSDate *)now;
@end

/// The panel that holds the view: borderless, dark glass, non-activating, hanging under the status item's button.
/// It opens with its first frame already built from the latest model, and closes on a click outside or Escape
/// (Escape first leaves Settings when Settings shows).
@interface MMWindowPanel : NSPanel
- (instancetype)initWithHost:(nullable id<MMWindowHost>)host;
@property (readonly) MMWindowView *view;
@property (readonly) BOOL isOpen;
- (void)show:(MMWindowModel *)model;                    // a new model, open or not
- (void)toggleUnder:(NSStatusBarButton *)button;
- (void)close;
@end

/// A model of made-up values for the render tool and the checks: "quiet", "busy", "peak", "running", "done", "empty".
MMWindowModel *MMWindowFixture(NSString *name);

NS_ASSUME_NONNULL_END
