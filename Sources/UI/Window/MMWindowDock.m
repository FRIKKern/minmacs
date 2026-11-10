// The dock that closes the window: the ring, the two numbers beside it, Fix Everything with its two thin lines,
// and the two gains. And the window's own buttons, which are real NSButtons that draw themselves.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

#pragma mark The buttons

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

#pragma mark The dock

static const NSRect kButton = {{290, 19}, {440, 56}};

@implementation MMWindowDockView

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _fix = [MMWindowButton kind:MMWindowButtonClear title:@"Fix Everything" target:nil action:NULL];
        _fix.frame = kButton;
        __weak typeof(self) me = self;
        _fix.onHover = ^{ me.needsDisplay = YES; };
        [self addSubview:_fix];
    }
    return self;
}

- (void)setModel:(MMWindowModel *)model { _model = model; [self refresh]; }
- (void)setPhase:(MMWindowDockPhase)phase { if (_phase == phase) return; _phase = phase; [self refresh]; }
- (void)setMemoryShare:(double)v { if (_memoryShare == v) return; _memoryShare = v; self.needsDisplay = YES; }
- (void)setDiskShare:(double)v { if (_diskShare == v) return; _diskShare = v; self.needsDisplay = YES; }
- (void)setMemoryShown:(double)v { if (_memoryShown == v) return; _memoryShown = v; self.needsDisplay = YES; }
- (void)setDiskShown:(double)v { if (_diskShown == v) return; _diskShown = v; self.needsDisplay = YES; }
- (void)setGlow:(double)v { if (_glow == v) return; _glow = v; self.needsDisplay = YES; }

- (BOOL)dimmed { return self.phase == MMWindowDockCalm && self.model.fixCount == 0; }

/// The button says what a press does now, to VoiceOver too.
- (void)refresh {
    MMWindowRun *run = self.model.run;
    if (self.phase == MMWindowDockRunning) self.fix.accessibilityLabel = [NSString stringWithFormat:@"Stop, %@", run.step ?: @"a fix runs"];
    else if (self.phase == MMWindowDockEnded) self.fix.accessibilityLabel = run.endTitle ?: @"Fix Everything";
    else if (self.dimmed) self.fix.accessibilityLabel = @"Fix Everything, nothing to fix now";
    else self.fix.accessibilityLabel = [NSString stringWithFormat:@"Fix Everything, %@", MMPlural(self.model.fixCount, @"fix")];
    self.fix.enabled = self.phase == MMWindowDockRunning || (self.phase == MMWindowDockCalm && !self.dimmed);
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirty {
    if (!self.model) return;
    [self drawRing];
    [self drawButton];
    [self drawGains];
}

#pragma mark The ring

static void Arc(NSPoint c, CGFloat radius, CGFloat width, CGFloat from, CGFloat sweep, NSColor *color) {
    if (sweep <= 0) return;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p appendBezierPathWithArcWithCenter:c radius:radius startAngle:from endAngle:from + sweep clockwise:NO];
    p.lineWidth = width;
    [color setStroke];
    [p stroke];
}

/// Memory by group inside, the disk as the thin outer track. Both start at the lower left and run three quarters round.
- (void)drawRing {
    MMWindowRing *ring = self.model.ring;
    NSPoint c = NSMakePoint(62, 66);
    const CGFloat start = 135, whole = 270;
    BOOL hc = MMWindowContrast();
    NSColor *track = [NSColor colorWithWhite:1 alpha:hc ? 0.2 : 0.07];
    Arc(c, 37.6, 7, start, whole, track);
    Arc(c, 48.1, 2.4, start, whole, track);
    CGFloat at = start;
    if (ring.memoryTotal) for (MMWindowSlice *s in ring.memory) {
        CGFloat sweep = MIN(whole * s.bytes / (double)ring.memoryTotal, start + whole - at);
        BOOL other = [s.group isEqualToString:@"other"];
        Arc(c, 37.6, 7, at, sweep, other ? [NSColor colorWithSRGBRed:0.92 green:0.92 blue:0.96 alpha:hc ? 0.45 : 0.22] : [MMWindowGroupColor(s.group) colorWithAlphaComponent:hc ? 1 : 0.8]);
        at += sweep;
    }
    at = start;
    if (ring.diskTotal) for (MMWindowSlice *s in ring.disk) {
        CGFloat sweep = MIN(whole * s.bytes / (double)ring.diskTotal, start + whole - at);
        BOOL other = [s.group isEqualToString:@"other"];
        Arc(c, 48.1, 2.4, at, sweep, [MMWindowGroupColor(other ? @"caches" : s.group) colorWithAlphaComponent:other ? (hc ? 0.55 : 0.32) : (hc ? 1 : 0.8)]);
        at += sweep;
    }

    // Beside it, memory and disk as two numbers, never one.
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2);
    NSArray<NSString *> *used = MMWindowSize2(ring.memoryUsed), *total = MMWindowSize2(ring.memoryTotal);
    BOOL same = [used[1] isEqualToString:total[1]];
    NSString *tail = same ? [NSString stringWithFormat:@" / %@ %@", total[0], total[1]] : [NSString stringWithFormat:@" %@ / %@ %@", used[1], total[0], total[1]];
    MMWindowDraw(MMWindowJoin(@[MMWindowText(used[0], 25, NSFontWeightMedium, text), MMWindowText(tail, 11.5, NSFontWeightRegular, t2)]), 128, 48, -1);
    MMWindowDraw(MMWindowText(@"memory in use", 11.5, NSFontWeightRegular, t2), 128, 73, -1);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(MMWindowBytes(ring.diskFree), 11.5, NSFontWeightMedium, MMWindowColor(MMWindowInkDisk)),
                                MMWindowText(@" disk free", 11.5, NSFontWeightRegular, t2)]), 128, 91, -1);
}

#pragma mark Fix Everything

/// A pill outline that starts at the top center and runs clockwise, as the two lines fill.
static NSBezierPath *Track(NSRect r) {
    CGFloat rad = r.size.height / 2, l = NSMinX(r) + rad, rt = NSMaxX(r) - rad;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(NSMidX(r), NSMinY(r))];
    [p lineToPoint:NSMakePoint(rt, NSMinY(r))];
    [p appendBezierPathWithArcWithCenter:NSMakePoint(rt, NSMidY(r)) radius:rad startAngle:-90 endAngle:90 clockwise:NO];
    [p lineToPoint:NSMakePoint(l, NSMaxY(r))];
    [p appendBezierPathWithArcWithCenter:NSMakePoint(l, NSMidY(r)) radius:rad startAngle:90 endAngle:270 clockwise:NO];
    [p closePath];
    p.lineWidth = 2.5;
    return p;
}

static void DrawTrack(NSRect r, double share, NSColor *color) {
    NSBezierPath *base = Track(r);
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.22 : 0.08] setStroke];
    [base stroke];
    if (share <= 0.001) return;
    CGFloat rad = r.size.height / 2, length = 2 * (r.size.width - 2 * rad) + 2 * M_PI * rad;
    NSBezierPath *fill = Track(r);
    fill.lineCapStyle = NSLineCapStyleRound;
    CGFloat dash[2] = {length * MIN(share, 1), length * 2};
    [fill setLineDash:dash count:2 phase:0];
    [color setStroke];
    [fill stroke];
}

- (void)drawButton {
    MMWindowRun *run = self.model.run;
    NSRect b = kButton;
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:b xRadius:28 yRadius:28];
    BOOL dimmed = self.dimmed, running = self.phase == MMWindowDockRunning, ended = self.phase == MMWindowDockEnded;
    NSColor *t2 = MMWindowColor(MMWindowInkText2), *fixInk = MMWindowColor(MMWindowInkFix);

    // The two thin lines: memory back inside, disk back outside.
    DrawTrack(NSInsetRect(b, -6, -6), running || ended ? self.memoryShare : 0, MMWindowColor(MMWindowInkMemory));
    DrawTrack(NSInsetRect(b, -11, -11), running || ended ? self.diskShare : 0, MMWindowColor(MMWindowInkDisk));

    NSString *title = @"Fix Everything";
    NSColor *ink = [NSColor colorWithSRGBRed:43 / 255.0 green:20 / 255.0 blue:4 / 255.0 alpha:1];
    if (dimmed) {
        // Nothing to fix: the button stays in place, dimmed, with the reason under it.
        [[NSColor colorWithWhite:1 alpha:0.05] setFill]; [pill fill];
        [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.1] setStroke]; pill.lineWidth = 1; [pill stroke];
        ink = MMWindowColor(MMWindowInkText3);
    } else if (running) {
        // While it runs the button is an outline with the step inside. A press stops the run.
        [NSGraphicsContext saveGraphicsState];
        NSShadow *glow = [NSShadow new];
        glow.shadowColor = [fixInk colorWithAlphaComponent:0.3]; glow.shadowBlurRadius = 30;
        [glow set];
        [[fixInk colorWithAlphaComponent:self.fix.hovered ? 0.16 : 0.09] setFill];
        [pill fill];
        [NSGraphicsContext restoreGraphicsState];
        [[fixInk colorWithAlphaComponent:0.75] setStroke]; pill.lineWidth = 1; [pill stroke];
        title = run.step.length ? run.step : @"Fixing";
        ink = [NSColor colorWithWhite:1 alpha:0.86];
    } else {
        [NSGraphicsContext saveGraphicsState];
        NSShadow *glow = [NSShadow new];
        glow.shadowColor = [NSColor colorWithSRGBRed:1 green:0.55 blue:0.235 alpha:0.3 + 0.4 * (ended ? self.glow : 0)];
        glow.shadowBlurRadius = 22 + 16 * (ended ? self.glow : 0); glow.shadowOffset = NSMakeSize(0, ended ? 0 : -6);
        [glow set];
        [fixInk setFill];
        [pill fill];
        [NSGraphicsContext restoreGraphicsState];
        BOOL bright = ended || self.fix.hovered;
        NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:1 green:(bright ? 213 : 182) / 255.0 blue:(bright ? 150 : 99) / 255.0 alpha:1]
                                                      endingColor:[NSColor colorWithSRGBRed:1 green:(bright ? 164 : 138) / 255.0 blue:(bright ? 86 : 61) / 255.0 alpha:1]];
        [g drawInBezierPath:pill angle:90];
        [[NSColor colorWithWhite:1 alpha:0.4] setStroke];
        NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.25, 0.25) xRadius:28 yRadius:28];
        edge.lineWidth = 0.5; [edge stroke];
        if (ended) title = run.endTitle.length ? run.endTitle : @"Done";
    }
    MMWindowDraw(MMWindowFit(title, running ? 14 : 17, running ? NSFontWeightMedium : NSFontWeightSemibold, ink, b.size.width - 48), NSMidX(b), NSMidY(b), 0);

    // Under the button: what a press would do, how far the run is, or how it ended.
    CGFloat mid = NSMidX(b), y = 98;
    if (running) {
        NSString *count = run.total > 0 ? [NSString stringWithFormat:@"Fix %ld of %ld. ", (long)MIN(run.done + 1, run.total), (long)run.total] : @"";
        MMWindowDraw(MMWindowJoin(@[MMWindowText(count, 12, NSFontWeightRegular, t2), MMWindowText(@"Press to stop", 12, NSFontWeightMedium, MMWindowColor(MMWindowInkText))]), mid, y, 0);
    } else if (ended) {
        if (!run.endNote.length) return;
        NSMutableParagraphStyle *center = [NSMutableParagraphStyle new];
        center.alignment = NSTextAlignmentCenter; center.lineBreakMode = NSLineBreakByWordWrapping;
        NSAttributedString *note = [[NSAttributedString alloc] initWithString:run.endNote attributes:@{
            NSFontAttributeName: MMWindowFont(12, NSFontWeightRegular), NSForegroundColorAttributeName: t2, NSParagraphStyleAttributeName: center}];
        [note drawWithRect:NSMakeRect(mid - 226, y - 8, 452, 46) options:NSStringDrawingUsesLineFragmentOrigin];
    } else if (dimmed) {
        MMWindowDraw(MMWindowText(@"Nothing to fix now", 12, NSFontWeightRegular, t2), mid, y, 0);
    } else {
        MMWindowFix *first = nil;
        for (MMWindowFix *f in self.model.fixes) if (!f.needsYou) { first = f; break; }
        NSInteger n = self.model.fixCount;
        NSString *lead = [MMPlural(n, @"fix") stringByAppendingString:@", "];
        CGFloat room = 452 - MMWindowWidth(MMWindowText([lead stringByAppendingString:@" first"], 12, NSFontWeightRegular, t2));
        NSMutableArray *runs = [NSMutableArray arrayWithObjects:MMWindowText(lead, 12, NSFontWeightRegular, t2),
                                MMWindowFit(first.title ?: @"", 12, NSFontWeightMedium, MMWindowColor(MMWindowInkText), room), nil];
        if (n > 1) [runs addObject:MMWindowText(@" first", 12, NSFontWeightRegular, t2)];
        MMWindowDraw(MMWindowJoin(runs), mid, y, 0);
    }
}

#pragma mark The gains

/// What Fix Everything gives back, memory and disk as two large numbers. While a run plays they count up.
- (void)drawGains {
    BOOL live = self.phase != MMWindowDockCalm;
    if (!live && self.model.fixCount == 0) return;
    uint64_t memory = live ? (uint64_t)MAX(self.memoryShown, 0) : self.model.memoryBack, disk = live ? (uint64_t)MAX(self.diskShown, 0) : self.model.diskBack;
    NSString *tail = self.phase == MMWindowDockRunning ? @" so far" : @"";
    NSColor *t2 = MMWindowColor(MMWindowInkText2);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(MMWindowBytes(memory), 23, NSFontWeightMedium, MMWindowColor(MMWindowInkMemory)),
                                MMWindowText([@"  memory back" stringByAppendingString:tail], 12, NSFontWeightRegular, t2)]), 764, 50, -1);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(MMWindowBytes(disk), 23, NSFontWeightMedium, MMWindowColor(MMWindowInkDisk)),
                                MMWindowText([@"  disk back" stringByAppendingString:tail], 12, NSFontWeightRegular, t2)]), 764, 81, -1);
}

@end
