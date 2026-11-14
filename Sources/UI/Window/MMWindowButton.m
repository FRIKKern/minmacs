// The window's own buttons: real NSButtons that draw themselves, so keyboard, tooltips and accessibility come with them.
#import "UI/Window/MMWindowParts.h"

@implementation MMWindowButton {
    NSTrackingArea *_tracking;
}

+ (instancetype)kind:(MMWindowButtonKind)kind title:(NSString *)title target:(nullable id)target action:(nullable SEL)action {
    MMWindowButton *b = [[self alloc] initWithFrame:NSZeroRect];
    b.kind = kind; b.title = title; b.target = target; b.action = action;
    b.bordered = NO;
    [b setButtonType:NSButtonTypeMomentaryChange];
    b.accessibilityLabel = title;
    return b;
}

- (void)setLit:(BOOL)lit { _lit = lit; self.needsDisplay = YES; }

/// Tab reaches every button of the window that takes presses now, whatever the system's keyboard setting says.
- (BOOL)canBecomeKeyView { return self.enabled && MMWindowTakesPresses(self); }
/// A press, Space or a VoiceOver press: none acts on a button that is hidden, fading or held back.
- (BOOL)sendAction:(SEL)action to:(id)target { return MMWindowTakesPresses(self) && [super sendAction:action to:target]; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)setHover:(BOOL)on { _hovered = on; self.needsDisplay = YES; if (self.onHover) self.onHover(); }
- (void)mouseEntered:(NSEvent *)e { [self setHover:YES]; }
- (void)mouseExited:(NSEvent *)e { [self setHover:NO]; }
- (void)viewDidHide { [super viewDidHide]; if (_hovered) [self setHover:NO]; }

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    BOOL on = self.lit || (self.hovered && self.enabled);
    switch (self.kind) {
        case MMWindowButtonClear: return;   // the dock draws what is under it
        case MMWindowButtonGear:
        case MMWindowButtonPower: {
            if (on) {
                [[NSColor colorWithWhite:1 alpha:self.lit ? 0.16 : 0.09] setFill];
                [[NSBezierPath bezierPathWithRoundedRect:b xRadius:6 yRadius:6] fill];
            }
            NSColor *ink = on ? NSColor.whiteColor : MMWindowColor(MMWindowInkText2);
            NSRect icon = NSMakeRect(NSMidX(b) - 7.5, NSMidY(b) - 7.5, 15, 15);
            if (self.kind == MMWindowButtonGear) MMWindowDrawGear(icon, ink); else MMWindowDrawPower(icon, ink);
            return;
        }
        case MMWindowButtonOutline: {
            // A small outlined pill, such as Stop under the button while a run plays.
            NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:b.size.height / 2 - 0.5 yRadius:b.size.height / 2 - 0.5];
            if (on) { [[NSColor colorWithWhite:1 alpha:0.14] setFill]; [pill fill]; }
            [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.5 : 0.2] setStroke]; pill.lineWidth = 1; [pill stroke];
            MMWindowDraw(MMWindowText(self.title, 12, NSFontWeightRegular, [NSColor colorWithWhite:1 alpha:on ? 1 : 0.82]), NSMidX(b), NSMidY(b), 0);
            return;
        }
        case MMWindowButtonPill: {
            [[NSColor colorWithWhite:1 alpha:on ? 0.14 : 0.07] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:b xRadius:b.size.height / 2 yRadius:b.size.height / 2] fill];
            MMWindowDraw(MMWindowText(self.title, 12, NSFontWeightRegular, on ? NSColor.whiteColor : MMWindowColor(MMWindowInkText)), NSMidX(b), NSMidY(b), 0);
            return;
        }
    }
}

- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:MIN(self.bounds.size.height / 2, 28) yRadius:MIN(self.bounds.size.height / 2, 28)] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }

@end
