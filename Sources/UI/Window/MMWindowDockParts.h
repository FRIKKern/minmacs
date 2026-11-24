// What the dock's two files share: MMWindowDock.m draws Fix Everything and the words right of it, and
// MMWindowDockNumbers.m the small ring with the two numbers beside it and the gains. Only they import this.
#import "UI/Window/MMWindowParts.h"

NS_ASSUME_NONNULL_BEGIN

// A label's ink, from 195-a.
static inline NSColor *Label(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.86 : 0.6]; }

// The slim dock, 64 points high, as one row: the ring and the Mac's two numbers at left, Fix Everything in the middle
// of the window, and right of it what the button gives back, how far a run is, or how it ended. The gear and the
// power icon stand right of the dock, in the window.
static const CGFloat kDockMid = 32;
static const NSRect kButton = {{372, 12}, {276, 40}};
static const CGFloat kMacX = 72, kMacWidth = 372 - 24 - 72;          // the Mac's numbers, right of the ring
static const CGFloat kRightX = 672, kRightWidth = 950 - 672 - 8;      // the words right of the button

@interface MMWindowDockView (Numbers)
/// The pointer rests on Fix Everything while it can be pressed: the dock shows the Mac after it.
@property (readonly) BOOL showsAfter;
- (void)drawMac;
/// The gains as one line: each side a colored number and its word, with `gainWord` where it stands. `dark` draws
/// them for the face of the button, as a run ends.
- (nullable NSAttributedString *)gainText:(CGFloat)size dark:(BOOL)dark bright:(BOOL)bright;
@end

NS_ASSUME_NONNULL_END
