// The dock that closes the window: the ring, the two numbers beside it, Fix Everything with its two thin lines,
// and the gains, each side only when it has something. And the window's own buttons, which are real NSButtons that draw themselves.
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

#pragma mark The dock

static const NSRect kButton = {{290, 19}, {440, 56}};
// The line under the button, and the dock's quiet inks, from 195-a: the line, the word that stands out in it, a label.
static const CGFloat kUnder = 96.5;
static NSColor *Under(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.8 : 0.5]; }
static NSColor *UnderBold(void) { return [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 1 : 0.86]; }
static NSColor *Label(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.86 : 0.6]; }

static const CGFloat kGlowPad = 84;
static NSBitmapImageRep *RestGlow(BOOL hot, int part);

@implementation MMWindowDockView {
    CALayer *_breath;                   // the part of the button's glow that breathes, while it does
}

- (BOOL)breathes { return _breath != nil; }

/// The glow breathes only at rest with something to fix, away from the pointer, in a window that shows.
- (void)wake { [self syncBreath]; }

- (BOOL)wantsBreath {
    return self.model && self.phase == MMWindowDockCalm && self.model.fixCount > 0 && !self.fix.hovered && self.window.isVisible && !self.isHiddenOrHasHiddenAncestor && !MMWindowReduceMotion();
}

- (void)syncBreath {
    BOOL want = self.wantsBreath && self.layer;
    if (want == (_breath != nil)) return;
    if (want) _breath = MMWindowBreathLayer(self, RestGlow(NO, 2), NSInsetRect(kButton, -kGlowPad, -kGlowPad), 5);
    else { [_breath removeFromSuperlayer]; _breath = nil; }
    if (want == (_breath != nil)) self.needsDisplay = YES;
}

- (void)rest {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncBreath) object:nil];
    [_breath removeFromSuperlayer]; _breath = nil; self.needsDisplay = YES;
}
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self syncBreath]; }
- (void)viewDidHide { [super viewDidHide]; [self syncBreath]; }
- (void)viewDidUnhide { [super viewDidUnhide]; [self syncBreath]; }

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _fix = [MMWindowButton kind:MMWindowButtonClear title:@"Fix Everything" target:nil action:NULL];
        _fix.frame = kButton;
        __weak typeof(self) me = self;
        _fix.onHover = ^{ me.needsDisplay = YES; [me syncBreath]; };
        [self addSubview:_fix];
        // The small Stop under the button, 195-a's. The large button stops the run too.
        _stop = [MMWindowButton kind:MMWindowButtonOutline title:@"Stop" target:nil action:NULL];
        _stop.accessibilityLabel = @"Stop after this step";
        _stop.hidden = YES;
        [self addSubview:_stop];
        _stepIn = 1;
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
- (void)setStepIn:(double)v { if (_stepIn == v) return; _stepIn = v; self.needsDisplay = YES; }
- (void)setPointed:(MMWindowRow *)row { if (_pointed == row) return; _pointed = row; self.needsDisplay = YES; }

- (BOOL)dimmed { return self.phase == MMWindowDockCalm && self.model.fixCount == 0; }

/// "Fix 3 of 7", beside the small Stop while a run plays.
- (NSString *)count {
    MMWindowRun *run = self.model.run;
    return run.total > 0 ? [NSString stringWithFormat:@"Fix %ld of %ld", (long)MIN(run.done + 1, run.total), (long)run.total] : @"";
}

/// The button says what a press does now, to VoiceOver too. A dimmed button says only that it is dimmed: the window
/// never claims there is nothing to fix.
- (void)refresh {
    MMWindowRun *run = self.model.run;
    BOOL running = self.phase == MMWindowDockRunning;
    if (running) self.fix.accessibilityLabel = [NSString stringWithFormat:@"Stop, %@", run.step ?: @"a fix runs"];
    else if (self.phase == MMWindowDockEnded) self.fix.accessibilityLabel = run.endTitle ?: @"Fix Everything";
    else if (self.dimmed) self.fix.accessibilityLabel = @"Fix Everything, dimmed";
    else self.fix.accessibilityLabel = [NSString stringWithFormat:@"Fix Everything, %@", MMPlural(self.model.fixCount, @"fix")];
    self.fix.enabled = running || (self.phase == MMWindowDockCalm && !self.dimmed);
    // "Fix 3 of 7" and Stop sit under the button as one centered line.
    self.stop.hidden = !running;
    if (running) {
        CGFloat lead = self.count.length ? MMWindowWidth(MMWindowText(self.count, 12, NSFontWeightRegular, Under())) + 8 : 0;
        CGFloat pill = MMWindowWidth(MMWindowText(self.stop.title, 12, NSFontWeightRegular, Under())) + 24;
        self.stop.frame = NSMakeRect(round(NSMidX(kButton) - (lead + pill) / 2 + lead), kUnder - 10, pill, 20);
    }
    [self syncBreath];
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    if (!self.model) return;
    MMWindowDrawRing(self.model, NSMakePoint(62, 66), NO, self.pointed, self.showsAfter);
    [self drawMac];
    [self drawButton];
    [self drawGains];
    // A window that just came on screen has its layer only now, at its first drawing: the breath starts right after.
    if (!_breath && self.layer && self.wantsBreath) [self performSelector:@selector(syncBreath) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
}

#pragma mark The Mac's two numbers

/// The pointer rests on Fix Everything while it can be pressed: the dock shows the Mac after it.
- (BOOL)showsAfter { return !self.pointed && self.phase == MMWindowDockCalm && self.model.fixCount > 0 && self.fix.hovered; }

/// Beside the ring, memory and disk as two numbers, never one. While the pointer rests on a row they are that row's
/// share, and while it rests on Fix Everything they are the Mac after it.
- (void)drawMac {
    MMWindowRing *ring = self.model.ring;
    NSColor *text = MMWindowColor(MMWindowInkText), *label = Label(), *unit = MMWindowColor(MMWindowInkText2), *disk = MMWindowColor(MMWindowInkDisk);
    CGFloat x = 128;
    MMWindowRow *row = self.pointed;
    if (row) {
        BOOL onDisk = row.kind == MMWindowWorktree || row.kind == MMWindowCache;
        MMWindowDraw(MMWindowFit(row.shownName, 11.5, NSFontWeightRegular, label, 150), x, 31.5, -1);
        NSAttributedString *big = row.showsSize ? MMWindowNumber(row.bytes, 25, NSFontWeightMedium, text, 12)
            : MMWindowJoin(@[MMWindowText(@(row.tabs).stringValue, 25, NSFontWeightMedium, text), MMWindowText(row.tabs == 1 ? @" tab" : @" tabs", 12, NSFontWeightRegular, unit)]);
        MMWindowDraw(big, x, 54, -1);
        if (row.showsSize) {
            uint64_t used = ring.diskTotal > ring.diskFree ? ring.diskTotal - ring.diskFree : 0;
            MMWindowDraw(MMWindowText(onDisk ? [NSString stringWithFormat:@"of %@ disk in use", MMWindowBytes(used)]
                                             : [NSString stringWithFormat:@"of %@ memory in use", MMWindowBytes(ring.memoryUsed)], 11.5, NSFontWeightRegular, label), x, 81, -1);
        }
        NSString *cpu = MMWindowCPU(row.cpuPercent);
        if (cpu) MMWindowDraw(MMWindowText([NSString stringWithFormat:@"CPU %@ %%", cpu], 11.5, NSFontWeightRegular, label), x, 99.5, -1);
        return;
    }
    if (self.showsAfter) {
        NSInteger n = self.model.fixCount;
        uint64_t back = MIN(self.model.memoryBack, ring.memoryUsed);
        MMWindowDraw(MMWindowText(n == 1 ? @"After the fix" : [NSString stringWithFormat:@"After all %ld", (long)n], 11.5, NSFontWeightRegular, label), x, 31.5, -1);
        MMWindowDraw(MMWindowNumber(ring.memoryUsed - back, 25, NSFontWeightMedium, text, 12), x, 54, -1);
        MMWindowDraw(MMWindowText([NSString stringWithFormat:@"memory, now %@", MMWindowBytes(ring.memoryUsed)], 11.5, NSFontWeightRegular, label), x, 81, -1);
        MMWindowDraw(MMWindowJoin(@[MMWindowText(MMWindowBytes(ring.diskFree + self.model.diskBack), 11.5, NSFontWeightMedium, disk),
                                    MMWindowText(@" disk free", 11.5, NSFontWeightRegular, label)]), x, 99.5, -1);
        return;
    }
    NSArray<NSString *> *used = MMWindowSize2(ring.memoryUsed);
    NSString *total = MMWindowWhole(ring.memoryTotal);
    BOOL same = [total hasSuffix:used[1]];
    NSString *tail = same ? [@" / " stringByAppendingString:total] : [NSString stringWithFormat:@" %@ / %@", used[1], total];
    MMWindowDraw(MMWindowJoin(@[MMWindowText(used[0], 25, NSFontWeightMedium, text), MMWindowText(tail, 12, NSFontWeightRegular, unit)]), x, 46.5, -1);
    MMWindowDraw(MMWindowText(@"memory in use", 11.5, NSFontWeightRegular, label), x, 73.5, -1);
    MMWindowDraw(MMWindowJoin(@[MMWindowText(MMWindowBytes(ring.diskFree), 11.5, NSFontWeightMedium, disk),
                                MMWindowText(@" disk free", 11.5, NSFontWeightRegular, label)]), x, 92, -1);
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

static void DrawTrack(NSRect r, double share, NSColor *color, BOOL lit) {
    NSBezierPath *base = Track(r);
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.22 : 0.08] setStroke];
    [base stroke];
    if (share <= 0.002) return;
    CGFloat rad = r.size.height / 2, length = 2 * (r.size.width - 2 * rad) + 2 * M_PI * rad;
    NSBezierPath *fill = Track(r);
    fill.lineCapStyle = NSLineCapStyleRound;
    CGFloat dash[2] = {length * MIN(share, 1), length * 2};
    [fill setLineDash:dash count:2 phase:0];
    [NSGraphicsContext saveGraphicsState];
    if (lit) {
        // Once the run ended, what it filled glows a little.
        NSShadow *glow = [NSShadow new];
        glow.shadowColor = [NSColor colorWithSRGBRed:1 green:235 / 255.0 blue:200 / 255.0 alpha:0.7]; glow.shadowBlurRadius = 4;
        [glow set];
    }
    [color setStroke];
    [fill stroke];
    [NSGraphicsContext restoreGraphicsState];
}

static NSColor *Orange(CGFloat g, CGFloat b, CGFloat a) { return [NSColor colorWithSRGBRed:1 green:g / 255.0 blue:b / 255.0 alpha:a]; }

/// Fills the pill once with a shadow under it, for a glow. The gradient goes over the fill.
static void Glow(NSBezierPath *pill, NSColor *color, CGFloat blur, CGFloat down) {
    if (color.alphaComponent <= 0.004) return;
    [NSGraphicsContext saveGraphicsState];
    NSShadow *glow = [NSShadow new];
    glow.shadowColor = color; glow.shadowBlurRadius = blur; glow.shadowOffset = NSMakeSize(0, -down);
    [glow set];
    [[color colorWithAlphaComponent:1] setFill];
    [pill fill];
    [NSGraphicsContext restoreGraphicsState];
}

/// The glow under the button at rest and under the pointer, drawn once and kept: two blurred shadows are the dearest
/// thing in the dock, and they never change. The picture is the button's rect with `kGlowPad` around it.
/// `part` 0 is the whole resting glow. 1 is the same with the outer glow at the low end of its breath, and 2 is what
/// the breath adds on top, with the button's own shape cut out, for the layer that fades in and out.
static NSBitmapImageRep *RestGlow(BOOL hot, int part) {
    static NSBitmapImageRep *kept[2][3];
    if (kept[hot][part]) return kept[hot][part];
    NSSize size = NSMakeSize(kButton.size.width + 2 * kGlowPad, kButton.size.height + 2 * kGlowPad);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)(size.width * 2) pixelsHigh:(NSInteger)(size.height * 2)
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = size;
    NSGraphicsContext *was = NSGraphicsContext.currentContext;
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(kGlowPad, kGlowPad, kButton.size.width, kButton.size.height) xRadius:28 yRadius:28];
    // 195-a's outer glow breathes between 0.22 and 0.62 of its strength, once in 5 s. Still, it stands at 0.4.
    Glow(pill, Orange(159, 69, 0.5 * (hot ? 1 : part == 1 ? 0.22 : 0.4)), 32, 0);
    if (part == 2) {
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
        [NSColor.blackColor setFill]; [pill fill];
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationSourceOver;
    } else Glow(pill, hot ? Orange(150, 70, 0.5) : Orange(140, 60, 0.3), hot ? 34 : 22, hot ? 10 : 6);
    NSGraphicsContext.currentContext = was;
    return kept[hot][part] = rep;
}

- (void)drawButton {
    MMWindowRun *run = self.model.run;
    NSRect b = kButton;
    BOOL dimmed = self.dimmed, running = self.phase == MMWindowDockRunning, ended = self.phase == MMWindowDockEnded;
    BOOL hot = !dimmed && !running && !ended && self.fix.hovered;
    NSColor *fixInk = MMWindowColor(MMWindowInkFix);

    // The two thin lines: memory back inside, disk back outside. While the pointer rests on the button they show,
    // faintly, which sides a press gives back.
    double memory = running || ended ? self.memoryShare : hot && self.model.memoryBack > 0 ? 1 : 0;
    double disk = running || ended ? self.diskShare : hot && self.model.diskBack > 0 ? 1 : 0;
    CGFloat faint = hot ? 0.34 : 1;
    DrawTrack(NSInsetRect(b, -6, -6), memory, [MMWindowColor(MMWindowInkMemory) colorWithAlphaComponent:faint], ended);
    DrawTrack(NSInsetRect(b, -11, -11), disk, [MMWindowColor(MMWindowInkDisk) colorWithAlphaComponent:faint], ended);

    [NSGraphicsContext saveGraphicsState];
    // Under the pointer the button lifts a point. As a run ends it is a touch larger, and settles.
    NSAffineTransform *move = [NSAffineTransform transform];
    double joy = ended ? self.glow : 0;
    if (hot) [move translateXBy:0 yBy:-1];
    if (joy > 0) { [move translateXBy:NSMidX(b) yBy:NSMidY(b)]; [move scaleBy:1 + 0.04 * joy]; [move translateXBy:-NSMidX(b) yBy:-NSMidY(b)]; }
    [move concat];
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:b xRadius:28 yRadius:28];
    NSString *title = @"Fix Everything";
    NSColor *ink = [NSColor colorWithSRGBRed:43 / 255.0 green:20 / 255.0 blue:4 / 255.0 alpha:1];
    CGFloat size = 17, rise = 0;
    NSFontWeight weight = NSFontWeightSemibold;
    if (dimmed) {
        // Nothing to fix: the button stays in place, dimmed, and says no more.
        [[NSColor colorWithWhite:1 alpha:0.06] setFill]; [pill fill];
        [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.1] setStroke]; pill.lineWidth = 1; [pill stroke];
        ink = [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.7 : 0.5];
    } else if (running) {
        // While it runs the button is an outline with the step inside, and each new step's words rise in.
        Glow(pill, [fixInk colorWithAlphaComponent:0.13], 34, 0);
        [[NSColor colorWithSRGBRed:36 / 255.0 green:35 / 255.0 blue:46 / 255.0 alpha:1] setFill]; [pill fill];
        [[fixInk colorWithAlphaComponent:self.fix.hovered ? 0.17 : 0.11] setFill]; [pill fill];
        [[fixInk colorWithAlphaComponent:MMWindowContrast() ? 0.9 : 0.55] setStroke];
        NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:27.5 yRadius:27.5];
        edge.lineWidth = 1; [edge stroke];
        title = run.step.length ? run.step : @"Fixing";
        size = 13; weight = NSFontWeightRegular;
        ink = [NSColor colorWithWhite:1 alpha:MIN(MAX(self.stepIn, 0), 1)];
        rise = 6 * (1 - MIN(MAX(self.stepIn, 0), 1));
    } else {
        // At rest a warm glow; brighter under the pointer; and a burst as a run ends, which fades.
        if (ended) {
            Glow(pill, Orange(159, 69, 0.45), 32, 0);
            if (joy > 0) Glow(pill, Orange(170, 80, 0.7 * joy), 70, 0);
            Glow(pill, Orange(140, 60, 0.3), 22, 6);
        } else {
            [RestGlow(hot, !hot && _breath ? 1 : 0) drawInRect:NSInsetRect(b, -kGlowPad, -kGlowPad) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        }
        NSGradient *g = ended ? [[NSGradient alloc] initWithStartingColor:Orange(213, 150, 1) endingColor:Orange(164, 86, 1)]
                        : hot ? [[NSGradient alloc] initWithStartingColor:Orange(198, 124, 1) endingColor:Orange(149, 72, 1)]
                              : [[NSGradient alloc] initWithStartingColor:Orange(182, 99, 1) endingColor:Orange(138, 61, 1)];
        [g drawInBezierPath:pill angle:90];
        // A light line along the top inside, and a hair of an edge all round.
        [NSGraphicsContext saveGraphicsState];
        [pill addClip];
        NSBezierPath *top = [NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(b, 0, 1) xRadius:28 yRadius:28];
        top.lineWidth = 1; [[NSColor colorWithWhite:1 alpha:hot ? 0.45 : 0.35] setStroke]; [top stroke];
        [NSGraphicsContext restoreGraphicsState];
        [[NSColor colorWithWhite:1 alpha:hot ? 0.5 : 0.4] setStroke];
        NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.25, 0.25) xRadius:28 yRadius:28];
        edge.lineWidth = 0.5; [edge stroke];
        if (ended) { title = run.endTitle.length ? run.endTitle : @"Done"; size = 13.5; }
    }
    MMWindowDraw(MMWindowFit(title, size, weight, ink, b.size.width - 48), NSMidX(b), NSMidY(b) + rise, 0);
    [NSGraphicsContext restoreGraphicsState];

    // Under the button: what a press would do, how far the run is, or how it ended. A dimmed button has no line.
    CGFloat mid = NSMidX(b), y = kUnder;
    NSColor *under = Under();
    if (running) {
        if (self.count.length) MMWindowDraw(MMWindowText(self.count, 12, NSFontWeightRegular, under), NSMinX(self.stop.frame) - 8, y, 1);
    } else if (ended) {
        if (!run.endNote.length) return;
        NSMutableParagraphStyle *center = [NSMutableParagraphStyle new];
        center.alignment = NSTextAlignmentCenter; center.lineBreakMode = NSLineBreakByWordWrapping;
        NSAttributedString *note = [[NSAttributedString alloc] initWithString:run.endNote attributes:@{
            NSFontAttributeName: MMWindowFont(12, NSFontWeightRegular), NSForegroundColorAttributeName: under, NSParagraphStyleAttributeName: center}];
        [note drawWithRect:NSMakeRect(mid - 226, y - 8, 452, 46) options:NSStringDrawingUsesLineFragmentOrigin];
    } else if (!dimmed) {
        MMWindowFix *first = nil;
        for (MMWindowFix *f in self.model.fixes) if (!f.needsYou) { first = f; break; }
        NSInteger n = self.model.fixCount;
        NSString *lead = n > 1 ? [MMPlural(n, @"fix") stringByAppendingString:@", "] : @"";
        CGFloat room = 452 - MMWindowWidth(MMWindowText([lead stringByAppendingString:@" first"], 12, NSFontWeightRegular, under));
        NSMutableArray *runs = [NSMutableArray arrayWithObjects:MMWindowText(lead, 12, NSFontWeightRegular, under),
                                MMWindowFit(first.title ?: @"", 12, NSFontWeightMedium, UnderBold(), room), nil];
        if (n > 1) [runs addObject:MMWindowText(@" first", 12, NSFontWeightRegular, under)];
        MMWindowDraw(MMWindowJoin(runs), mid, y, 0);
    }
}

#pragma mark The gains

/// What Fix Everything gives back, memory and disk, each a large number of its own. A side shows only when it has
/// something: a zero is no gain, so it is never drawn as one.
/// - Before a press: what the fixes give back, each side that is above zero.
/// - While a run plays: each side the run set out to give back, counting up from zero.
/// - Once it ended: each side that did come back.
/// - With nothing to fix: what came back today, each side that is above zero.
/// Each entry is the bytes, the ink and the words.
- (NSArray<NSArray *> *)gains {
    MMWindowModel *m = self.model;
    MMWindowRun *run = m.run;
    NSMutableArray<NSArray *> *out = [NSMutableArray new];
    void (^add)(double, MMWindowInk, NSString *) = ^(double bytes, MMWindowInk ink, NSString *words) {
        [out addObject:@[@((uint64_t)MAX(bytes, 0)), @(ink), words]];
    };
    if (self.phase == MMWindowDockRunning) {
        if (run.memoryPlanned > 0 || run.memoryBack > 0) add(self.memoryShown, MMWindowInkMemory, @"memory back so far");
        if (run.diskPlanned > 0 || run.diskBack > 0) add(self.diskShown, MMWindowInkDisk, @"disk back so far");
    } else if (self.phase == MMWindowDockEnded) {
        if (run.memoryBack > 0) add(self.memoryShown, MMWindowInkMemory, @"memory back");
        if (run.diskBack > 0) add(self.diskShown, MMWindowInkDisk, @"disk back");
    } else if (m.fixCount == 0) {
        if (m.memoryBackToday > 0) add(m.memoryBackToday, MMWindowInkMemory, @"memory back today");
        if (m.diskBackToday > 0) add(m.diskBackToday, MMWindowInkDisk, @"disk back today");
    } else {
        if (m.memoryBack > 0) add(m.memoryBack, MMWindowInkMemory, @"memory back");
        if (m.diskBack > 0) add(m.diskBack, MMWindowInkDisk, @"disk back");
    }
    return out;
}

- (NSArray<NSString *> *)gainLines {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSArray *g in self.gains) [out addObject:[NSString stringWithFormat:@"%@ %@", MMWindowBytes([g[0] unsignedLongLongValue]), g[2]]];
    return out;
}

- (void)drawGains {
    NSColor *t2 = Label();
    NSMutableArray<NSAttributedString *> *lines = [NSMutableArray new];
    for (NSArray *g in self.gains)
        [lines addObject:MMWindowJoin(@[MMWindowText(MMWindowBytes([g[0] unsignedLongLongValue]), 23, NSFontWeightMedium, MMWindowColor((MMWindowInk)[g[1] integerValue])),
                                        MMWindowText([@"  " stringByAppendingString:g[2]], 12, NSFontWeightRegular, t2)])];
    // Two lines sit at 50 and 81. One line sits between them, level with the middle of the button.
    if (lines.count == 1) MMWindowDraw(lines[0], 764, 65.5, -1);
    else for (NSUInteger i = 0; i < lines.count; i++) MMWindowDraw(lines[i], 764, 50 + 31 * i, -1);
}

@end
