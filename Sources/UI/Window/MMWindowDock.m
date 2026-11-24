// The slim dock that closes the window: Fix Everything in the middle, and right of it what a press gives back, how
// far a run is, or how it ended. The ring and the Mac's two numbers at left, and the gains, are in
// MMWindowDockNumbers.m, the buttons themselves in MMWindowButton.m.
#import "UI/Window/MMWindowDockParts.h"
#import "UI/MMFormat.h"

#pragma mark The dock

// The words right of the button: their quiet ink and the word that stands out in it.
static NSColor *Under(void) { return [NSColor colorWithSRGBRed:235 / 255.0 green:235 / 255.0 blue:245 / 255.0 alpha:MMWindowContrast() ? 0.8 : 0.5]; }
static NSColor *UnderBold(void) { return [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 1 : 0.86]; }
// The end note's place, right of the button, and the line under it for the gains.
static const CGFloat kNoteRoom = 56;

static const CGFloat kGlowPad = 34;
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
        // The small Stop beside the run's count, right of the button. The large button stops the run too.
        _stop = [MMWindowButton kind:MMWindowButtonOutline title:@"Stop" target:nil action:NULL];
        _stop.accessibilityLabel = @"Stop after this step";
        _stop.hidden = YES;
        [self addSubview:_stop];
        _stepIn = 1;
    }
    return self;
}

- (void)setModel:(MMWindowModel *)model { _model = model; [self refresh]; }
- (void)setPhase:(MMWindowDockPhase)phase {
    if (_phase == phase) return;
    MMWindowDockPhase was = _phase;
    _phase = phase;
    // A press that starts a run sends a soft ring out from the button, and the end runs one light across it.
    if (phase == MMWindowDockRunning && was == MMWindowDockCalm) MMWindowPulse(self, kButton, MMWindowColor(MMWindowInkFix));
    if (phase == MMWindowDockEnded && was == MMWindowDockRunning) { MMWindowShine(self, kButton); MMWindowPulse(self, kButton, MMWindowColor(MMWindowInkFix)); }
    [self refresh];
}
- (void)setProgress:(double)v { if (_progress == v) return; _progress = v; self.needsDisplay = YES; }
- (void)setMemoryShown:(double)v { if (_memoryShown == v) return; _memoryShown = v; self.needsDisplay = YES; }
- (void)setDiskShown:(double)v { if (_diskShown == v) return; _diskShown = v; self.needsDisplay = YES; }
- (void)setGlow:(double)v { if (_glow == v) return; _glow = v; self.needsDisplay = YES; }
- (void)setStepIn:(double)v { if (_stepIn == v) return; _stepIn = v; self.needsDisplay = YES; }
- (void)setPointed:(MMWindowRow *)row { if (_pointed == row) return; _pointed = row; self.needsDisplay = YES; }

/// Nothing for Fix Everything to run: the button rests, calm, and takes no press.
- (BOOL)stillAtRest { return self.phase == MMWindowDockCalm && self.model.fixCount == 0; }

/// "Fix 3 of 7", beside the small Stop while a run plays.
- (NSString *)count {
    MMWindowRun *run = self.model.run;
    return run.total > 0 ? [NSString stringWithFormat:@"Fix %ld of %ld", (long)MIN(run.done + 1, run.total), (long)run.total] : @"";
}

/// What the resting button says with nothing to run. It says what a press does, nothing about the Mac: the window
/// never claims a result.
static NSString *const kNoFixes = @"No fixes to run";

/// The button says what a press does now, to VoiceOver too.
- (void)refresh {
    MMWindowRun *run = self.model.run;
    BOOL running = self.phase == MMWindowDockRunning;
    if (running) self.fix.accessibilityLabel = [@[@"Stop", self.count, run.step ?: @"a fix runs"] componentsJoinedByString:@", "];
    else if (self.phase == MMWindowDockEnded) self.fix.accessibilityLabel = run.endTitle ?: @"Fix Everything";
    else if (self.stillAtRest) self.fix.accessibilityLabel = [@"Fix Everything, " stringByAppendingString:[kNoFixes lowercaseString]];
    else self.fix.accessibilityLabel = [@"Fix Everything, " stringByAppendingString:MMWindowFixes(self.model.fixCount)];
    // VoiceOver hears the run move on: "Fix 3 of 7" is said when the count changes, not only drawn.
    NSString *said = running ? self.count : nil;
    if (said.length && ![said isEqualToString:_said] && self.window.isVisible)
        NSAccessibilityPostNotificationWithUserInfo(self.fix, NSAccessibilityAnnouncementRequestedNotification,
            @{NSAccessibilityAnnouncementKey: said, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
    _said = said;
    self.fix.enabled = running || (self.phase == MMWindowDockCalm && !self.stillAtRest);
    // "Fix 3 of 7" and Stop stand right of the button, on the first of the run's lines.
    self.stop.hidden = !running;
    if (running) {
        CGFloat lead = self.count.length ? MMWindowWidth([self countText]) + 10 : 0;
        CGFloat pill = MMWindowWidth(MMWindowText(self.stop.title, 12, NSFontWeightRegular, Under())) + 24;
        self.stop.frame = NSMakeRect(kRightX + lead, round(self.runTop), pill, 22);
    }
    [self syncBreath];
    self.needsDisplay = YES;
}

- (NSAttributedString *)countText { return MMWindowText(self.count, 12.5, NSFontWeightMedium, MMWindowColor(MMWindowInkText)); }

/// While a run plays: the count with Stop, 22 high, and the gains so far under it, as one block in the dock's middle.
- (CGFloat)runTop { return kDockMid - ([self gainText:11.5 dark:NO bright:NO] ? 22 + 4 + 16 : 22) / 2; }

- (void)drawRect:(NSRect)dirty {
    MMWindowCrisp();
    if (!self.model) return;
    [self drawMac];
    [self drawButton];
    [self drawRight];
    // A window that just came on screen has its layer only now, at its first drawing: the breath starts right after.
    if (!_breath && self.layer && self.wantsBreath) [self performSelector:@selector(syncBreath) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
}

#pragma mark Fix Everything

static NSColor *Orange(CGFloat g, CGFloat b, CGFloat a) { return [NSColor colorWithSRGBRed:1 green:g / 255.0 blue:b / 255.0 alpha:a]; }
static NSColor *Ink(void) { return [NSColor colorWithSRGBRed:43 / 255.0 green:20 / 255.0 blue:4 / 255.0 alpha:1]; }
static NSColor *Mint(CGFloat a) { return [NSColor colorWithSRGBRed:124 / 255.0 green:220 / 255.0 blue:164 / 255.0 alpha:a]; }
static NSBezierPath *Pill(NSRect r) { return [NSBezierPath bezierPathWithRoundedRect:r xRadius:r.size.height / 2 yRadius:r.size.height / 2]; }

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
    NSBezierPath *pill = Pill(NSMakeRect(kGlowPad, kGlowPad, kButton.size.width, kButton.size.height));
    // The outer glow breathes between 0.25 and 0.7 of its strength, once in 5 s. Still, it stands at 0.45.
    Glow(pill, Orange(140, 50, 0.6 * (hot ? 1 : part == 1 ? 0.25 : 0.45)), 20, 0);
    if (part == 2) {
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
        [NSColor.blackColor setFill]; [pill fill];
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationSourceOver;
    } else Glow(pill, hot ? Orange(130, 40, 0.55) : Orange(120, 40, 0.32), hot ? 16 : 10, hot ? 6 : 3);
    NSGraphicsContext.currentContext = was;
    return kept[hot][part] = rep;
}

/// A check, drawn in the rect: a calm mark for a button with nothing to run, and for a run that did all it set out to.
static void DrawCheck(NSRect r, NSColor *color, CGFloat width) {
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(NSMinX(r) + r.size.width * 0.2, NSMinY(r) + r.size.height * 0.52)];
    [p lineToPoint:NSMakePoint(NSMinX(r) + r.size.width * 0.42, NSMinY(r) + r.size.height * 0.74)];
    [p lineToPoint:NSMakePoint(NSMinX(r) + r.size.width * 0.8, NSMinY(r) + r.size.height * 0.28)];
    p.lineWidth = width; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
    [color setStroke]; [p stroke];
}

/// The vivid face of the button, with a light line along its top inside and a hair of an edge all round.
static void Face(NSRect b, NSColor *top, NSColor *bottom, BOOL bright) {
    NSBezierPath *pill = Pill(b);
    [[[NSGradient alloc] initWithStartingColor:top endingColor:bottom] drawInBezierPath:pill angle:90];
    [NSGraphicsContext saveGraphicsState];
    [pill addClip];
    NSBezierPath *line = Pill(NSOffsetRect(b, 0, 1));
    line.lineWidth = 1; [[NSColor colorWithWhite:1 alpha:bright ? 0.55 : 0.42] setStroke]; [line stroke];
    [NSGraphicsContext restoreGraphicsState];
    NSBezierPath *edge = Pill(NSInsetRect(b, 0.25, 0.25));
    edge.lineWidth = 0.5; [[NSColor colorWithWhite:1 alpha:bright ? 0.55 : 0.4] setStroke]; [edge stroke];
}

- (void)drawButton {
    NSRect b = kButton;
    BOOL still = self.stillAtRest, running = self.phase == MMWindowDockRunning, ended = self.phase == MMWindowDockEnded;
    BOOL hot = !still && !running && !ended && self.fix.hovered;
    NSColor *fixInk = MMWindowColor(MMWindowInkFix);
    [NSGraphicsContext saveGraphicsState];
    // Under the pointer the button lifts a point. As a run ends it is a touch larger, and settles.
    NSAffineTransform *move = [NSAffineTransform transform];
    double joy = ended ? self.glow : 0;
    if (hot) [move translateXBy:0 yBy:-1];
    if (joy > 0) { [move translateXBy:NSMidX(b) yBy:NSMidY(b)]; [move scaleBy:1 + 0.05 * joy]; [move translateXBy:-NSMidX(b) yBy:-NSMidY(b)]; }
    [move concat];
    NSBezierPath *pill = Pill(b);
    CGFloat mid = NSMidX(b), y = NSMidY(b), inner = b.size.width - 40;
    if (still) {
        // Nothing to run: the button rests, calm and whole, with a check and what a press would do: nothing.
        [[NSColor colorWithWhite:1 alpha:0.05] setFill]; [pill fill];
        NSBezierPath *edge = Pill(NSInsetRect(b, 0.5, 0.5));
        edge.lineWidth = 1; [Mint(MMWindowContrast() ? 0.6 : 0.3) setStroke]; [edge stroke];
        NSAttributedString *words = MMWindowText(kNoFixes, 13, NSFontWeightMedium, [NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.95 : 0.78]);
        CGFloat w = 18 + 8 + MMWindowWidth(words), x = round(mid - w / 2);
        NSRect mark = NSMakeRect(x, round(y - 9), 18, 18);
        [Mint(0.18) setFill]; [[NSBezierPath bezierPathWithOvalInRect:mark] fill];
        DrawCheck(NSInsetRect(mark, 3.5, 3.5), Mint(1), 1.6);
        MMWindowDraw(words, x + 26, y, -1);
    } else if (running) {
        // While it runs the button is dark, and fills with the button's own orange as the fixes land. The step stands
        // in it, and each new step's words rise in.
        Glow(pill, [fixInk colorWithAlphaComponent:0.16], 22, 0);
        [[NSColor colorWithSRGBRed:36 / 255.0 green:35 / 255.0 blue:46 / 255.0 alpha:1] setFill]; [pill fill];
        [[fixInk colorWithAlphaComponent:self.fix.hovered ? 0.16 : 0.1] setFill]; [pill fill];
        double p = MIN(MAX(self.progress, 0), 1);
        if (p > 0.002) {
            [NSGraphicsContext saveGraphicsState];
            [pill addClip];
            NSRect filled = NSMakeRect(NSMinX(b), NSMinY(b), round(b.size.width * p * 2) / 2, b.size.height);
            [[[NSGradient alloc] initWithStartingColor:Orange(178, 92, 0.62) endingColor:Orange(128, 52, 0.62)] drawInRect:filled angle:90];
            // The leading edge of the fill glows a little, while there is more to come.
            if (p < 0.998) [[[NSGradient alloc] initWithStartingColor:Orange(200, 130, 0) endingColor:Orange(214, 150, 0.7)]
                               drawInRect:NSMakeRect(NSMaxX(filled) - 16, NSMinY(b), 16, b.size.height) angle:0];
            [NSGraphicsContext restoreGraphicsState];
        }
        NSBezierPath *edge = Pill(NSInsetRect(b, 0.5, 0.5));
        edge.lineWidth = 1; [[fixInk colorWithAlphaComponent:MMWindowContrast() ? 0.9 : 0.6] setStroke]; [edge stroke];
        CGFloat size = 13, in = MIN(MAX(self.stepIn, 0), 1), rise = 6 * (1 - in);
        NSString *step = [self stepShown:&size];
        MMWindowDrawBlock(step, size, size, NSFontWeightMedium, [NSColor colorWithWhite:1 alpha:in], mid, y + rise, inner, 0, 0, 2 * MMWindowLineHeight(size) + 2 * fabs(rise));
    } else {
        // At rest a warm glow that breathes; brighter under the pointer; and a burst as a run ends, which fades.
        if (ended) {
            Glow(pill, Orange(150, 60, 0.5), 22, 0);
            if (joy > 0) Glow(pill, Orange(170, 80, 0.75 * joy), 46, 0);
            Glow(pill, Orange(130, 50, 0.32), 12, 4);
        } else {
            [RestGlow(hot, !hot && _breath ? 1 : 0) drawInRect:NSInsetRect(b, -kGlowPad, -kGlowPad) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        }
        if (ended) Face(b, Orange(210, 140, 1), Orange(150, 70, 1), YES);
        else if (hot) Face(b, Orange(192, 112, 1), Orange(138, 58, 1), YES);
        else Face(b, Orange(178, 92, 1), Orange(126, 48, 1), NO);
        if (ended) [self drawEnd:b];
        else {
            // "Fix Everything" and how many fixes a press runs, in a small capsule of its own.
            NSAttributedString *title = MMWindowText(@"Fix Everything", 14, NSFontWeightSemibold, Ink());
            NSAttributedString *n = MMWindowText(@(self.model.fixCount).stringValue, 12, NSFontWeightSemibold, Ink());
            CGFloat cap = MAX(MMWindowWidth(n) + 12, 22), w = MMWindowWidth(title) + 8 + cap, x = round(mid - w / 2);
            MMWindowDraw(title, x, y, -1);
            NSRect badge = NSMakeRect(x + w - cap, round(y - 10), cap, 20);
            [[Ink() colorWithAlphaComponent:hot ? 0.2 : 0.15] setFill]; [Pill(badge) fill];
            MMWindowDraw(n, NSMidX(badge), NSMidY(badge), 0);
        }
    }
    [NSGraphicsContext restoreGraphicsState];
}

/// The end on the face of the button: how the run ended, with a check when it did all it set out to, and under it
/// what came back.
- (void)drawEnd:(NSRect)b {
    MMWindowRun *run = self.model.run;
    NSString *title = run.endTitle.length ? run.endTitle : @"Done";
    BOOL whole = run.total > 0 && run.done >= run.total;
    NSAttributedString *gains = [self gainText:11 dark:YES bright:NO];
    if (gains && MMWindowWidth(gains) > b.size.width - 36) gains = [self gainText:10 dark:YES bright:NO];
    CGFloat size = MMWindowFitSize(title, 13.5, 11, NSFontWeightSemibold, b.size.width - 36 - (whole ? 20 : 0));
    NSAttributedString *t = MMWindowText(title, size, NSFontWeightSemibold, Ink());
    CGFloat mid = NSMidX(b), top = gains ? NSMidY(b) - 7.5 : NSMidY(b);
    CGFloat w = MMWindowWidth(t) + (whole ? 20 : 0), x = round(mid - w / 2);
    if (whole) DrawCheck(NSMakeRect(x, round(top - 7), 14, 14), Ink(), 1.8);
    MMWindowDraw(t, x + (whole ? 20 : 0), top, -1);
    if (gains) MMWindowDraw(gains, mid, NSMidY(b) + 9.5, 0);
}

- (NSString *)buttonWords {
    if (self.phase == MMWindowDockRunning) return self.stepWords;
    if (self.phase == MMWindowDockEnded) return self.model.run.endTitle.length ? self.model.run.endTitle : @"Done";
    return self.stillAtRest ? kNoFixes : @"Fix Everything";
}

/// The step as the button holds it: whole, on one or two lines, with the type stepped down as far as 10 points. A
/// step still too long, which only a very long name makes, shows its action alone, "Moving to the Trash", and no
/// name: never a cut one. The count stands beside the button, "Fix 3 of 7". VoiceOver's label holds the whole step.
- (NSString *)stepShown:(CGFloat *)size {
    MMWindowRun *run = self.model.run;
    NSString *step = run.step.length ? run.step : @"Fixing";
    for (CGFloat s = 13; s >= 10; s -= 0.5) if (MMWindowLines(step, s, NSFontWeightMedium, kButton.size.width - 40).count <= 2) { if (size) *size = s; return step; }
    if (size) *size = 13;
    return run.stepAction.length ? run.stepAction : @"Fixing";
}

- (NSString *)stepWords { return [self stepShown:NULL]; }

#pragma mark Right of the button

/// Right of the button: what a press gives back and which fix runs first; how far a run is, with Stop, and what came
/// back so far; how the run ended; or with nothing to run, what came back today. Each as one block in the dock's middle.
- (void)drawRight {
    NSColor *under = Under();
    CGFloat x = kRightX, width = kRightWidth;
    BOOL running = self.phase == MMWindowDockRunning, ended = self.phase == MMWindowDockEnded;
    if (running) {
        CGFloat top = self.runTop;
        if (self.count.length) MMWindowDraw([self countText], x, top + 11, -1);
        NSAttributedString *gains = [self gainText:11.5 dark:NO bright:NO];
        if (gains) MMWindowDraw(gains, x, top + 22 + 4 + 8, -1);
        return;
    }
    if (ended) {
        NSString *note = self.endNote;
        if (!note.length) return;
        NSAttributedString *a = [self wrapped:@[MMWindowText(note, [self endNoteSize:note], NSFontWeightRegular, under)]];
        CGFloat h = Height(a, width);
        MMWindowDrawIn(a, NSMakeRect(x, round(kDockMid - h / 2), width, h));
        return;
    }
    NSAttributedString *gains = [self gainText:11.5 dark:NO bright:self.fix.hovered];
    if (gains && MMWindowWidth(gains) > width) gains = [self gainText:10.5 dark:NO bright:self.fix.hovered];
    if (self.stillAtRest) {
        // Nothing to run: what came back today, when anything did.
        if (gains) MMWindowDraw(gains, x, kDockMid, -1);
        return;
    }
    // What a press runs first. One line as a rule; a long fix's name wraps under it, whole, in type stepped down.
    MMWindowFix *first = nil;
    for (MMWindowFix *f in self.model.fixes) if (!f.needsYou) { first = f; break; }
    NSInteger n = self.model.fixCount;
    CGFloat room = self.bounds.size.height - 10 - (gains ? 16 + 4 : 0), size = 11.5, h = 0;
    NSAttributedString *note = nil;
    for (; size >= 10; size -= 0.5) {
        NSMutableArray *runs = [NSMutableArray new];
        if (n > 1) [runs addObject:MMWindowText([MMWindowFixes(n) stringByAppendingString:@", "], size, NSFontWeightRegular, under)];
        [runs addObject:MMWindowText(first.title ?: @"", size, NSFontWeightMedium, UnderBold())];
        if (n > 1) [runs addObject:MMWindowText(@" first", size, NSFontWeightRegular, under)];
        note = [self wrapped:runs];
        h = Height(note, width);
        if (h <= room) break;
    }
    CGFloat total = (gains ? 16 + 4 : 0) + h, top = round(kDockMid - total / 2);
    if (gains) { MMWindowDraw(gains, x, top + 8, -1); top += 16 + 4; }
    MMWindowDrawIn(note, NSMakeRect(x, top, width, h));
}

/// Words for the place right of the button: left aligned, wrapped at spaces.
- (NSAttributedString *)wrapped:(NSArray<NSAttributedString *> *)runs {
    NSMutableAttributedString *s = [MMWindowJoin(runs) mutableCopy];
    NSMutableParagraphStyle *wrap = [NSMutableParagraphStyle new];
    wrap.lineBreakMode = NSLineBreakByWordWrapping;
    [s addAttribute:NSParagraphStyleAttributeName value:wrap range:NSMakeRange(0, s.length)];
    return s;
}

static CGFloat Height(NSAttributedString *a, CGFloat width) {
    return ceil([a boundingRectWithSize:NSMakeSize(width, 10000) options:NSStringDrawingUsesLineFragmentOrigin].size.height);
}

static CGFloat NoteHeight(NSString *note, CGFloat size) {
    NSMutableParagraphStyle *wrap = [NSMutableParagraphStyle new];
    wrap.lineBreakMode = NSLineBreakByWordWrapping;
    return Height([[NSAttributedString alloc] initWithString:note attributes:@{NSFontAttributeName: MMWindowFont(size, NSFontWeightRegular), NSParagraphStyleAttributeName: wrap}], kRightWidth);
}

- (CGFloat)endNoteSize:(NSString *)note { return NoteHeight(note, 11.5) <= kNoteRoom ? 11.5 : 10.5; }

/// How the run ended, as it is drawn: whole sentences only. A note too long for its place at 11.5 points is set at
/// 10.5. One still too long keeps first what says where removed things went, so its Skipped list is shortened, from
/// its end, to "Skipped 12 agents that ask you and more.", then left out, and only then do the last sentences go.
- (NSString *)endNote {
    NSString *note = self.model.run.endNote ?: @"";
    if (NoteHeight(note, 10.5) <= kNoteRoom) return note;
    NSString *skipped = nil;
    NSMutableArray<NSString *> *rest = [NSMutableArray new];
    for (NSString *part in [note componentsSeparatedByString:@". "]) {
        NSString *sentence = [part hasSuffix:@"."] ? part : [part stringByAppendingString:@"."];
        if (!skipped && [sentence hasPrefix:@"Skipped "]) skipped = sentence; else [rest addObject:sentence];
    }
    NSString *(^fit)(NSString *) = ^NSString *(NSString *first) {
        NSString *all = [(first ? [@[first] arrayByAddingObjectsFromArray:rest] : rest) componentsJoinedByString:@" "];
        return NoteHeight(all, 10.5) <= kNoteRoom ? all : nil;
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
