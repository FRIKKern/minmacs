// A side's list asks for a row's menu, MMWindowParts.h: on a right-click or a control-click on a row. It only asks:
// the window makes the row active and builds the menu, MMWindowViewMenu.m, and AppKit shows it.
#import "UI/Window/MMWindowListParts.h"

@implementation MMWindowListView (Menu)

- (NSMenu *)menuAt:(NSPoint)p {
    MMWindowRow *row = NSPointInRect(p, self.bounds) ? [self rowAt:p] : nil;
    return row && self.onMenu ? self.onMenu(row.key) : nil;
}

/// AppKit asks on a right-click and on a control-click, and shows what comes back.
- (NSMenu *)menuForEvent:(NSEvent *)e { return [self menuAt:[self convertPoint:e.locationInWindow fromView:nil]]; }

@end
