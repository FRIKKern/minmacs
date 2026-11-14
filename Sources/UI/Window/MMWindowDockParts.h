// What the dock's two files share: MMWindowDock.m draws the ring, Fix Everything and the words under it, and
// MMWindowDockNumbers.m the two numbers beside the ring and the gains. Only they import this.
#import "UI/Window/MMWindowParts.h"

// A label's ink, from 195-a.
static inline NSColor *Label(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.86 : 0.6]; }

@interface MMWindowDockView (Numbers)
/// The pointer rests on Fix Everything while it can be pressed: the dock shows the Mac after it.
@property (readonly) BOOL showsAfter;
- (void)drawMac;
- (void)drawGains;
@end
