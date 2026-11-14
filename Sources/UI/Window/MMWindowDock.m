// The dock that closes the window: the ring, Fix Everything with its two thin lines, and the words under it. The two
// numbers beside the ring and the gains are in MMWindowDockNumbers.m, the buttons themselves in MMWindowButton.m.
#import "UI/Window/MMWindowDockParts.h"
#import "UI/MMFormat.h"

#pragma mark The dock

static const NSRect kButton = {{290, 19}, {440, 56}};
// The line under the button, and the dock's quiet inks, from 195-a: the line and the word that stands out in it.
static const CGFloat kUnder = 96.5, kNoteRoom = 48;
static NSColor *Under(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.8 : 0.5]; }
static NSColor *UnderBold(void) { return [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 1 : 0.86]; }

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
    else self.fix.accessibilityLabel = [@"Fix Everything, " stringByAppendingString:MMWindowFixes(self.model.fixCount)];
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
    if (running) title = [self stepShown:&size];
    MMWindowDrawBlock(title, size, running ? size : 12, weight, ink, NSMidX(b), NSMidY(b) + rise, b.size.width - 48, 0, 0, 2 * MMWindowLineHeight(size) + 2 * fabs(rise));
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
        if (n > 1) [runs addObject:MMWindowText([MMWindowFixes(n) stringByAppendingString:@", "], 12, NSFontWeightRegular, under)];
        [runs addObject:MMWindowText(first.title ?: @"", 12, NSFontWeightMedium, UnderBold())];
        if (n > 1) [runs addObject:MMWindowText(@" first", 12, NSFontWeightRegular, under)];
        // One line as a rule. A long fix's name wraps under it, whole.
        MMWindowDrawIn([self under:runs], NSMakeRect(mid - 226, y - 8, 452, kNoteRoom));
    }
}

/// The step as the button holds it: whole, on one or two lines, with the type stepped down as far as 10 points. A
/// step still too long, which only a very long name makes, shows its action alone, "Moving to the Trash", and no
/// name: never a cut one. The count stands under the button, "Fix 3 of 7". VoiceOver's label holds the whole step.
- (NSString *)stepShown:(CGFloat *)size {
    MMWindowRun *run = self.model.run;
    NSString *step = run.step.length ? run.step : @"Fixing";
    for (CGFloat s = 13; s >= 10; s -= 0.5) if (MMWindowLines(step, s, NSFontWeightRegular, kButton.size.width - 48).count <= 2) { if (size) *size = s; return step; }
    if (size) *size = 13;
    return run.stepAction.length ? run.stepAction : @"Fixing";
}

- (NSString *)stepWords { return [self stepShown:NULL]; }

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

/// How the run ended, as it is drawn: whole sentences only. A note too long for its place at 12 points is set at 11.
/// One still too long keeps first what says where removed things went, so its Skipped list is shortened, from its
/// end, to "Skipped 12 agents that ask you and more.", then left out, and only then do the last sentences go.
- (NSString *)endNote {
    NSString *note = self.model.run.endNote ?: @"";
    if (NoteHeight(note, 11) <= kNoteRoom) return note;
    NSString *skipped = nil;
    NSMutableArray<NSString *> *rest = [NSMutableArray new];
    for (NSString *part in [note componentsSeparatedByString:@". "]) {
        NSString *sentence = [part hasSuffix:@"."] ? part : [part stringByAppendingString:@"."];
        if (!skipped && [sentence hasPrefix:@"Skipped "]) skipped = sentence; else [rest addObject:sentence];
    }
    NSString *(^fit)(NSString *) = ^NSString *(NSString *first) {
        NSString *all = [(first ? [@[first] arrayByAddingObjectsFromArray:rest] : rest) componentsJoinedByString:@" "];
        return NoteHeight(all, 11) <= kNoteRoom ? all : nil;
    };
    // "Skipped a, b, c and d.": its items, each a whole phrase.
    NSString *list = [skipped substringWithRange:NSMakeRange(8, MAX((NSInteger)skipped.length - 9, 0))];
    NSMutableArray<NSString *> *items = [[list componentsSeparatedByString:@", "] mutableCopy];
    NSRange and = [items.lastObject rangeOfString:@" and " options:NSBackwardsSearch];
    if (and.location != NSNotFound) {
        NSString *last = items.lastObject;
        [items removeLastObject];
        [items addObject:[last substringToIndex:and.location]];
        [items addObject:[last substringFromIndex:NSMaxRange(and)]];
    }
    for (NSInteger keep = (NSInteger)items.count - 1; skipped && keep >= 1; keep--) {
        NSString *shorter = fit([NSString stringWithFormat:@"Skipped %@ and more.", [[items subarrayWithRange:NSMakeRange(0, (NSUInteger)keep)] componentsJoinedByString:@", "]]);
        if (shorter) return shorter;
    }
    while (rest.count > 1 && !fit(nil)) [rest removeLastObject];
    return fit(nil) ?: rest.firstObject ?: skipped ?: @"";
}

@end
