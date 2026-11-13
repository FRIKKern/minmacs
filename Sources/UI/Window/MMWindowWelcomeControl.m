// The welcome's controls: the switch, a removal choice and Start, each a real button that draws itself, and the
// group that holds the three choices. MMWindowWelcome.m lays them out.
#import "UI/Window/MMWindowWelcomeParts.h"

@implementation MMWelcomeGroup
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityRadioGroupRole; }
@end

@implementation MMWelcomeControl {
    BOOL _hover;
    NSTrackingArea *_tracking;
}

- (BOOL)isFlipped { return YES; }
/// Tab reaches it whatever the system's keyboard navigation setting says, once it has landed.
- (BOOL)canBecomeKeyView { return MMWindowTakesPresses(self); }
- (BOOL)sendAction:(SEL)action to:(id)target { return MMWindowTakesPresses(self) && [super sendAction:action to:target]; }

/// The arrow keys move the pick among the removal choices, as in any radio group.
- (void)keyDown:(NSEvent *)e {
    NSInteger by = e.keyCode == 125 || e.keyCode == 124 ? 1 : e.keyCode == 126 || e.keyCode == 123 ? -1 : 0;
    if (self.kind != MMWelcomeOption || !by) { [super keyDown:e]; return; }
    if (MMWindowTakesPresses(self)) [(MMWindowWelcomeView *)self.target move:by from:self.index];
}
- (void)setKnob:(CGFloat)knob { _knob = knob; self.needsDisplay = YES; }

- (void)setOn:(BOOL)on {
    _on = on;
    self.accessibilityValue = on ? @1 : @0;
    // The knob slides only in a window that shows. The welcome's timer moves it.
    if (self.kind != MMWelcomeSwitch || !self.window.isVisible || MMWindowReduceMotion()) self.knob = on ? 1 : 0;
}

/// One step of the knob toward its side. Returns whether it still moves.
- (BOOL)slide:(NSTimeInterval)dt {
    CGFloat to = self.on ? 1 : 0;
    if (fabs(to - self.knob) < 0.01) { if (self.knob != to) self.knob = to; return NO; }
    self.knob += (to - self.knob) * (1 - exp(-dt / 0.06));
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent *)e { _hover = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)e { _hover = NO; self.needsDisplay = YES; }

- (CGFloat)radius { return self.kind == MMWelcomeStart ? self.bounds.size.height / 2 : self.kind == MMWelcomeSwitch ? 14 : 9; }
- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.radius yRadius:self.radius] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }

/// How tall a choice is at this width: one line, or as many as its sentence needs, so nothing is cut.
+ (CGFloat)optionHeight:(NSString *)explain width:(CGFloat)width {
    return MAX(30, 12 + Height(Para(explain, 12.5, NSFontWeightRegular, NSColor.whiteColor, 18, NSTextAlignmentLeft), width - kExplainX - 12));
}

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    BOOL contrast = MMWindowContrast();
    switch (self.kind) {
        case MMWelcomeSwitch: {
            NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:14 yRadius:14];
            [[NSColor colorWithWhite:1 alpha:_hover ? 0.08 : 0.055] setFill]; [card fill];
            [[NSColor colorWithWhite:1 alpha:contrast ? 0.4 : 0.12] setStroke]; card.lineWidth = 0.5; [card stroke];
            DrawIn(Para(self.label, 14.5, NSFontWeightMedium, NSColor.whiteColor, 19, NSTextAlignmentLeft), NSMakeRect(18, 12, b.size.width - 100, 19));
            DrawIn(Para(self.explain, 12.5, NSFontWeightRegular, Soft(0.62), 17, NSTextAlignmentLeft), NSMakeRect(18, 33, b.size.width - 100, 17));
            // The knob sits right and the track fills when it is on, so the state shows in place as well as in color.
            NSRect track = NSMakeRect(NSMaxX(b) - 16 - 42, round(NSMidY(b) - 12.5), 42, 25);
            CGFloat k = MIN(1, MAX(0, self.knob));
            [[[NSColor colorWithWhite:1 alpha:contrast ? 0.3 : 0.16] blendedColorWithFraction:k ofColor:Accent()] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:track xRadius:12.5 yRadius:12.5] fill];
            NSRect knob = NSMakeRect(track.origin.x + 2 + 17 * self.knob, track.origin.y + 2, 21, 21);
            [[NSColor colorWithWhite:0 alpha:0.25] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSOffsetRect(knob, 0, 1)] fill];
            [NSColor.whiteColor setFill];
            [[NSBezierPath bezierPathWithOvalInRect:knob] fill];
            return;
        }
        case MMWelcomeOption: {
            if (self.on || _hover) {
                [[NSColor colorWithWhite:1 alpha:self.on ? (contrast ? 0.16 : 0.075) : 0.035] setFill];
                [[NSBezierPath bezierPathWithRoundedRect:b xRadius:9 yRadius:9] fill];
            }
            // The picked choice has a filled mark with a white center. The others have an empty ring.
            NSRect mark = NSMakeRect(10, 7.5, 15, 15);
            if (self.on) {
                [Accent() setFill];
                [[NSBezierPath bezierPathWithOvalInRect:mark] fill];
                [NSColor.whiteColor setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(mark, 4.5, 4.5)] fill];
            } else {
                NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(mark, 0.75, 0.75)];
                ring.lineWidth = 1.5;
                [[NSColor colorWithWhite:1 alpha:contrast ? 0.6 : 0.3] setStroke];
                [ring stroke];
            }
            DrawIn(Para(self.label, 13, NSFontWeightMedium, self.on ? NSColor.whiteColor : Soft(0.86), 18, NSTextAlignmentLeft), NSMakeRect(35, 6, kExplainX - 35, 18));
            DrawIn(Para(self.explain, 12.5, NSFontWeightRegular, Soft(self.on ? 0.86 : 0.6), 18, NSTextAlignmentLeft), NSMakeRect(kExplainX, 6, b.size.width - kExplainX - 12, b.size.height - 12));
            return;
        }
        case MMWelcomeStart: {
            NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:b xRadius:b.size.height / 2 yRadius:b.size.height / 2];
            [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:1 green:0.714 blue:0.388 alpha:1]
                                           endingColor:[NSColor colorWithSRGBRed:1 green:0.541 blue:0.239 alpha:1]] drawInBezierPath:pill angle:90];
            if (_hover || self.isHighlighted) {
                [(self.isHighlighted ? [NSColor colorWithWhite:0 alpha:0.1] : [NSColor colorWithWhite:1 alpha:0.1]) setFill];
                [pill fill];
            }
            NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:b.size.height / 2 yRadius:b.size.height / 2];
            edge.lineWidth = 0.5;
            [[NSColor colorWithWhite:1 alpha:0.4] setStroke]; [edge stroke];
            MMWindowDraw(MMWindowText(self.label, 16, NSFontWeightSemibold, [NSColor colorWithSRGBRed:0.169 green:0.078 blue:0.016 alpha:1]), NSMidX(b), NSMidY(b), 0);
            return;
        }
    }
}

@end
