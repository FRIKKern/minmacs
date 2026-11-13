// The dock that closes the window: the ring, the two numbers beside it, Fix Everything with its two thin lines,
// and the gains, each side only when it has something. The buttons themselves are in MMWindowButton.m.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

#pragma mark The dock

static const NSRect kButton = {{290, 19}, {440, 56}};
// The line under the button, and the dock's quiet inks, from 195-a: the line, the word that stands out in it, a label.
static const CGFloat kUnder = 96.5, kNoteRoom = 48;
static NSColor *Under(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.8 : 0.5]; }
static NSColor *UnderBold(void) { return [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 1 : 0.86]; }
static NSColor *Label(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.86 : 0.6]; }

static const CGFloat kGlowPad = 84;
static NSBitmapImageRep *RestGlow(BOOL hot, int part);

@implementation MMWindowDockView {
    CALayer *_breath;                   // the part of the button's glow that breathes, while it does
    BOOL _resting;                      // the window closed: nothing breathes until it comes back
    NSString *_said;                    // the run's count as VoiceOver last heard it
}

- (NSString *)announced { return _said; }

- (BOOL)breathes { return _breath != nil; }

/// The glow breathes only at rest with something to fix, away from the pointer, in a window that shows.
- (void)wake { _resting = NO; [self syncBreath]; }

- (BOOL)wantsBreath {
    return !_resting && self.model && self.phase == MMWindowDockCalm && self.model.fixCount > 0 && !self.fix.hovered && self.window.isVisible && !self.isHiddenOrHasHiddenAncestor && !MMWindowReduceMotion();
}

- (void)syncBreath {
    BOOL want = self.wantsBreath && self.layer;
    if (want == (_breath != nil)) return;
    if (want) _breath = MMWindowBreathLayer(self, RestGlow(NO, 2), NSInsetRect(kButton, -kGlowPad, -kGlowPad), 5);
    else { [_breath removeFromSuperlayer]; _breath = nil; }
    if (want == (_breath != nil)) self.needsDisplay = YES;
}

- (void)rest {
    _resting = YES;
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
    if (running) self.fix.accessibilityLabel = [@[@"Stop", self.count, run.step ?: @"a fix runs"] componentsJoinedByString:@", "];
    else if (self.phase == MMWindowDockEnded) self.fix.accessibilityLabel = run.endTitle ?: @"Fix Everything";
    else if (self.dimmed) self.fix.accessibilityLabel = @"Fix Everything, dimmed";
    else self.fix.accessibilityLabel = [NSString stringWithFormat:@"Fix Everything, %@", MMPlural(self.model.fixCount, @"fix")];
    // VoiceOver hears the run move on: "Fix 3 of 7" is said when the count changes, not only drawn.
    NSString *said = running ? self.count : nil;
    if (said.length && ![said isEqualToString:_said] && self.window.isVisible)
        NSAccessibilityPostNotificationWithUserInfo(self.fix, NSAccessibilityAnnouncementRequestedNotification,
            @{NSAccessibilityAnnouncementKey: said, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
    _said = said;
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
/// share, and while it rests on Fix Everything they are the Mac after it: what is in use now less what the fixes that
/// need nobody give back, and what is free now plus what they free, each side on its own.
/// Each line is its words, with the large number and its unit apart where it has one.
- (NSArray<NSDictionary *> *)mac {
    MMWindowRing *ring = self.model.ring;
    MMWindowRow *row = self.pointed;
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    if (row) {
        BOOL onDisk = row.kind == MMWindowWorktree || row.kind == MMWindowCache;
        [out addObject:@{@"name": row.shownName}];
        NSArray<NSString *> *size = row.showsSize ? MMWindowSize2(row.bytes, onDisk) : @[@(row.tabs).stringValue, row.tabs == 1 ? @"tab" : @"tabs"];
        [out addObject:@{@"big": size[0], @"unit": size[1]}];
        if (row.showsSize) {
            uint64_t used = ring.diskTotal > ring.diskFree ? ring.diskTotal - ring.diskFree : 0;
            [out addObject:@{@"label": onDisk ? [NSString stringWithFormat:@"of %@ disk in use", MMWindowBytes(used, YES)]
                                              : [NSString stringWithFormat:@"of %@ memory in use", MMWindowBytes(ring.memoryUsed, NO)]}];
        }
        NSString *cpu = MMWindowCPU(row.cpuPercent);
        if (cpu) [out addObject:@{@"label": [NSString stringWithFormat:@"CPU %@ %%", cpu]}];
    } else if (self.showsAfter) {
        NSInteger n = self.model.fixCount;
        uint64_t back = MIN(self.model.memoryBack, ring.memoryUsed);
        NSArray<NSString *> *after = MMWindowSize2(ring.memoryUsed - back, NO);
        [out addObject:@{@"label": n == 1 ? @"After the fix" : [NSString stringWithFormat:@"After all %ld", (long)n]}];
        [out addObject:@{@"big": after[0], @"unit": after[1]}];
        [out addObject:@{@"label": [NSString stringWithFormat:@"memory, now %@", MMWindowBytes(ring.memoryUsed, NO)]}];
        [out addObject:@{@"disk": MMWindowBytes(ring.diskFree + self.model.diskBack, YES), @"label": @"disk free"}];
    } else {
        NSArray<NSString *> *used = MMWindowSize2(ring.memoryUsed, NO);
        NSString *total = MMWindowWhole(ring.memoryTotal, NO);
        [out addObject:@{@"big": used[0], @"unit": [total hasSuffix:used[1]] ? [@"/ " stringByAppendingString:total] : [NSString stringWithFormat:@"%@ / %@", used[1], total]}];
        [out addObject:@{@"label": @"memory in use"}];
        [out addObject:@{@"disk": MMWindowBytes(ring.diskFree, YES), @"label": @"disk free"}];
    }
    return out;
}

- (NSArray<NSString *> *)macLines {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSDictionary *l in self.mac) {
        NSMutableArray *words = [NSMutableArray new];
        for (NSString *k in @[@"name", @"big", @"unit", @"disk", @"label"]) if (l[k]) [words addObject:l[k]];
        [out addObject:[words componentsJoinedByString:@" "]];
    }
    return out;
}

- (void)drawMac {
    NSColor *text = MMWindowColor(MMWindowInkText), *label = Label(), *unit = MMWindowColor(MMWindowInkText2), *disk = MMWindowColor(MMWindowInkDisk);
    NSArray<NSDictionary *> *lines = self.mac;
    CGFloat x = 128, width = 150;
    BOOL lead = self.pointed || self.showsAfter;
    // Three lines sit at 46.5, 73.5 and 92. With a line above the number, four sit at 31.5, 54, 81 and 99.5. A
    // pointed row's name is whole: when it needs more lines than one, it grows upward first and then pushes the rest down.
    CGFloat at[4] = {lead ? 31.5 : 46.5, lead ? 54 : 73.5, lead ? 81 : 92, 99.5}, push = 0;
    for (NSUInteger i = 0; i < lines.count && i < 4; i++) {
        NSDictionary *l = lines[i];
        if (l[@"name"]) {
            CGFloat size = MMWindowFitSize(l[@"name"], 11.5, 10, NSFontWeightRegular, width), line = MMWindowLineHeight(size);
            NSInteger n = (NSInteger)MMWindowLines(l[@"name"], size, NSFontWeightRegular, width).count;
            push = MAX(0, (n - 2) * line);
            MMWindowDrawBlock(l[@"name"], 11.5, 10, NSFontWeightRegular, label, x, at[i] + line / 2 + push, width, -1, 1);
        } else if (l[@"big"]) {
            MMWindowDraw(MMWindowJoin(@[MMWindowText(l[@"big"], 25, NSFontWeightMedium, text),
                                        MMWindowText([[l[@"unit"] hasPrefix:@"/"] ? @" " : MMWindowThin stringByAppendingString:l[@"unit"]], 12, NSFontWeightRegular, unit)]), x, at[i] + push, -1);
        } else if (l[@"disk"]) {
            MMWindowDraw(MMWindowJoin(@[MMWindowText(l[@"disk"], 11.5, NSFontWeightMedium, disk),
                                        MMWindowText([@" " stringByAppendingString:l[@"label"]], 11.5, NSFontWeightRegular, label)]), x, at[i] + push, -1);
        } else MMWindowDraw(MMWindowText(l[@"label"], 11.5, NSFontWeightRegular, label), x, at[i] + push, -1);
    }
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
    MMWindowDrawBlock(title, size, running ? 10.5 : 12, weight, ink, NSMidX(b), NSMidY(b) + rise, b.size.width - 48, 0, 0);
    [NSGraphicsContext restoreGraphicsState];

    // Under the button: what a press would do, how far the run is, or how it ended. A dimmed button has no line.
    CGFloat mid = NSMidX(b), y = kUnder;
    NSColor *under = Under();
    if (running) {
        if (self.count.length) MMWindowDraw(MMWindowText(self.count, 12, NSFontWeightRegular, under), NSMinX(self.stop.frame) - 8, y, 1);
    } else if (ended) {
        NSString *note = self.endNote;
        if (note.length) MMWindowDrawIn([self under:@[MMWindowText(note, [self endNoteSize:note], NSFontWeightRegular, under)]], NSMakeRect(mid - 226, y - 8, 452, kNoteRoom));
    } else if (!dimmed) {
        MMWindowFix *first = nil;
        for (MMWindowFix *f in self.model.fixes) if (!f.needsYou) { first = f; break; }
        NSInteger n = self.model.fixCount;
        NSMutableArray *runs = [NSMutableArray new];
        if (n > 1) [runs addObject:MMWindowText([MMPlural(n, @"fix") stringByAppendingString:@", "], 12, NSFontWeightRegular, under)];
        [runs addObject:MMWindowText(first.title ?: @"", 12, NSFontWeightMedium, UnderBold())];
        if (n > 1) [runs addObject:MMWindowText(@" first", 12, NSFontWeightRegular, under)];
        // One line as a rule. A long fix's name wraps under it, whole.
        MMWindowDrawIn([self under:runs], NSMakeRect(mid - 226, y - 8, 452, kNoteRoom));
    }
}

/// Words for the place under the button: centered, wrapped at spaces.
- (NSAttributedString *)under:(NSArray<NSAttributedString *> *)runs {
    NSMutableAttributedString *s = [MMWindowJoin(runs) mutableCopy];
    NSMutableParagraphStyle *center = [NSMutableParagraphStyle new];
    center.alignment = NSTextAlignmentCenter; center.lineBreakMode = NSLineBreakByWordWrapping;
    [s addAttribute:NSParagraphStyleAttributeName value:center range:NSMakeRange(0, s.length)];
    return s;
}

static CGFloat NoteHeight(NSString *note, CGFloat size) {
    NSMutableParagraphStyle *wrap = [NSMutableParagraphStyle new];
    wrap.lineBreakMode = NSLineBreakByWordWrapping;
    NSAttributedString *a = [[NSAttributedString alloc] initWithString:note attributes:@{NSFontAttributeName: MMWindowFont(size, NSFontWeightRegular), NSParagraphStyleAttributeName: wrap}];
    return ceil([a boundingRectWithSize:NSMakeSize(452, 10000) options:NSStringDrawingUsesLineFragmentOrigin].size.height);
}

- (CGFloat)endNoteSize:(NSString *)note { return NoteHeight(note, 12) <= kNoteRoom ? 12 : 11; }

/// How the run ended, as it is drawn: whole sentences only. A note too long for its place at 12 points is set at 11,
/// and one still too long loses whole sentences from its end.
- (NSString *)endNote {
    NSString *note = self.model.run.endNote ?: @"";
    if (NoteHeight(note, 11) <= kNoteRoom) return note;
    NSMutableArray<NSString *> *sentences = [[note componentsSeparatedByString:@". "] mutableCopy];
    while (sentences.count > 1) {
        [sentences removeLastObject];
        NSString *shorter = [[sentences componentsJoinedByString:@". "] stringByAppendingString:@"."];
        if (NoteHeight(shorter, 11) <= kNoteRoom) return shorter;
    }
    return sentences.firstObject ?: @"";
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
    for (NSArray *g in self.gains) [out addObject:[NSString stringWithFormat:@"%@ %@", MMWindowBytes([g[0] unsignedLongLongValue], [g[1] integerValue] == MMWindowInkDisk), g[2]]];
    return out;
}

- (void)drawGains {
    NSColor *t2 = Label();
    NSMutableArray<NSAttributedString *> *lines = [NSMutableArray new];
    for (NSArray *g in self.gains)
        [lines addObject:MMWindowJoin(@[MMWindowText(MMWindowBytes([g[0] unsignedLongLongValue], [g[1] integerValue] == MMWindowInkDisk), 23, NSFontWeightMedium, MMWindowColor((MMWindowInk)[g[1] integerValue])),
                                        MMWindowText([@"  " stringByAppendingString:g[2]], 12, NSFontWeightRegular, t2)])];
    // Two lines sit at 50 and 81. One line sits between them, level with the middle of the button.
    if (lines.count == 1) MMWindowDraw(lines[0], 764, 65.5, -1);
    else for (NSUInteger i = 0; i < lines.count; i++) MMWindowDraw(lines[i], 764, 50 + 31 * i, -1);
}

@end
