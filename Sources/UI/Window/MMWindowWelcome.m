// The welcome of the first launch, prototype 199-a "Welcome Then Menu": alone in the window, at the window's size.
//
//                     [mark]
//               Welcome to MinMacs
//        what MinMacs is, in two sentences
//   +------------------------------------------+
//   | Open at login                     (switch)|
//        It can be changed later in Settings.
//      fact        |      fact       |     fact
//                    [ Start ]
//
// It draws only what an MMWindowWelcome holds. Nothing is applied here: Start hands the answer to onStart.
// There is no removal choice to ask for: everything MinMacs removes keeps a way back, Core/Act/MMRemoval.h.
// The parts rise in one after the other when the window opens, and stand still under Reduce Motion. A button takes
// no press before it has landed, MMWindowTakesPresses.
// An answer the person has not touched follows the model, so a change made elsewhere meanwhile shows. One they
// touched is theirs and stays, whatever a later model says.
#import "UI/Window/MMWindowWelcomeParts.h"

static const CGFloat kColumn = 600, kSay = 520, kMark = 60, kFact = 280, kRise = 14;
// Each part starts 0.05 s after the one above it and takes half a second to land, slowing as it does. The last one,
// Start, has landed 0.85 s after the window opened, and takes a press from then.
static const NSTimeInterval kStep = 0.05, kPart = 0.5, kArrive = 0.05 + 6 * 0.05 + 0.5;
const NSTimeInterval MMWindowWelcomeRise = kArrive;
enum { PartMark = 0, PartTitle, PartSay, PartLogin, PartLater, PartFacts, PartStart, PartCount };

/// The narrowest width that keeps the same number of lines, so two lines come out about as long as each other and no
/// word is left alone on the last one.
static CGFloat Balanced(NSAttributedString *s, CGFloat width) {
    CGFloat h = Height(s, width), w = width;
    while (w > 120 && Height(s, w - 6) <= h) w -= 6;
    return w;
}

/// Centered in r, with its lines balanced.
static void DrawBalanced(NSAttributedString *s, NSRect r) {
    CGFloat w = Balanced(s, r.size.width);
    DrawIn(s, NSMakeRect(round(NSMidX(r) - w / 2), r.origin.y, w, r.size.height));
}

#pragma mark The welcome

@implementation MMWindowWelcomeView {
    MMWelcomeControl *_login, *_start;
    NSRect _parts[PartCount];
    NSString *_built;
    BOOL _touchedLogin;                 // the person changed it here: it is theirs, and no later model moves it
    NSTimer *_timer;                    // runs only while the parts rise in or the knob slides
    NSDate *_arriving, *_stepped;       // when the rise began, nil once every part has landed
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _arrival = 1;
        _login = [self control:MMWelcomeSwitch];
        _login.accessibilityRole = NSAccessibilityCheckBoxRole;
        _login.accessibilitySubrole = NSAccessibilitySwitchSubrole;
        // Return presses Start through the window's view, -[MMWindowView keyDown:], so a hidden welcome takes no key.
        _start = [self control:MMWelcomeStart];
        self.accessibilityRole = NSAccessibilityGroupRole;
    }
    return self;
}

- (MMWelcomeControl *)control:(MMWelcomeKind)kind {
    MMWelcomeControl *c = [[MMWelcomeControl alloc] initWithFrame:NSZeroRect];
    c.kind = kind; c.title = @""; c.bordered = NO;
    [c setButtonType:NSButtonTypeMomentaryChange];
    c.target = self; c.action = @selector(pressed:);
    [self addSubview:c];
    return c;
}

- (BOOL)loginOn { return _login.on; }

- (void)setWelcome:(MMWindowWelcome *)w {
    _welcome = w;
    if (!w) return;
    // The parts are laid out again only when the words changed. What the person set stays.
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@|%d;", w.title, w.say, w.loginTitle, w.loginOnNote, w.loginOffNote, w.later, w.start, MMWindowContrast()];
    for (MMWindowFact *f in w.facts) [sig appendFormat:@"%@=%@,", f.label, f.value];
    BOOL on = _touchedLogin ? self.loginOn : w.loginOn;
    if ([sig isEqualToString:_built]) {
        // The same words. An answer the person left alone still follows the model.
        if (on != _login.on) { _login.on = on; [self sayLogin]; [self wake]; }
        return;
    }
    _built = sig;
    _login.label = w.loginTitle;
    _login.on = on;
    [self sayLogin];
    _start.label = w.start;
    _start.accessibilityLabel = w.start;
    NSMutableArray *read = [NSMutableArray arrayWithObjects:w.title, w.say, w.later, nil];
    for (MMWindowFact *f in w.facts) [read addObject:[NSString stringWithFormat:@"%@. %@", f.label, f.value]];
    self.accessibilityLabel = [read componentsJoinedByString:@" "];
    [self place];
}

/// The switch says what its state means, in the card and to VoiceOver.
- (void)sayLogin {
    _login.explain = _login.on ? self.welcome.loginOnNote : self.welcome.loginOffNote;
    _login.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", self.welcome.loginTitle, _login.explain];
    _login.needsDisplay = YES;
}

/// Start by a press or by Return. Nothing happens while Start has not landed, or once the welcome is on its way out.
- (void)pressStart { if (self.welcome && self.onStart && MMWindowTakesPresses(_start)) self.onStart(self.loginOn); }

- (void)pressed:(MMWelcomeControl *)c {
    if (c.kind == MMWelcomeStart) { [self pressStart]; return; }
    _touchedLogin = YES; c.on = !c.on; [self sayLogin]; [self wake];
}

#pragma mark Where each part sits

- (NSAttributedString *)sayText {
    NSMutableAttributedString *say = [Para(self.welcome.say, 15, NSFontWeightRegular, Soft(0.74), 23, NSTextAlignmentCenter) mutableCopy];
    // The button's name stands out, since it is the one thing to press later.
    NSRange r = [say.string rangeOfString:@"Fix Everything"];
    if (r.location != NSNotFound) [say addAttributes:@{NSFontAttributeName: MMWindowFont(15, NSFontWeightMedium), NSForegroundColorAttributeName: NSColor.whiteColor} range:r];
    return say;
}

- (NSAttributedString *)factText:(MMWindowFact *)f { return Para(f.value, 12.5, NSFontWeightRegular, Soft(0.58), 18, NSTextAlignmentCenter); }

/// One centered column, with the same room above the mark as below Start.
- (void)place {
    MMWindowWelcome *w = self.welcome;
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height, cx = round(W / 2);
    CGFloat sayH = Height([self sayText], kSay), factsH = 0;
    for (MMWindowFact *f in w.facts) factsH = MAX(factsH, 18 + 4 + Height([self factText:f], kFact - 36));
    CGFloat heights[PartCount] = {kMark, 36, sayH, 62, 17, factsH, 46};
    CGFloat gaps[PartCount] = {0, 20, 10, 28, 12, 28, 30};
    CGFloat total = 0;
    for (NSInteger i = 0; i < PartCount; i++) total += heights[i] + gaps[i];
    CGFloat y = floor((H - total) / 2);
    CGFloat widths[PartCount] = {kMark, kColumn, kSay, kColumn, kColumn, kFact * MAX(1, (CGFloat)w.facts.count), 200};
    for (NSInteger i = 0; i < PartCount; i++) {
        y += gaps[i];
        _parts[i] = NSMakeRect(cx - round(widths[i] / 2), y, widths[i], heights[i]);
        y += heights[i];
    }
    _login.home = _parts[PartLogin];
    _start.home = _parts[PartStart];
    [self settle];
}

- (NSArray<NSValue *> *)partFrames {
    NSMutableArray *out = [NSMutableArray new];
    for (NSInteger i = 0; i < PartCount; i++) [out addObject:[NSValue valueWithRect:_parts[i]]];
    return out;
}

- (NSArray<NSButton *> *)controls { return @[_login, _start]; }

#pragma mark Arriving

/// How far part i has come, 0 to 1: each starts kStep after the one above it and slows as it lands.
- (CGFloat)eased:(NSInteger)i {
    double u = MIN(1, MAX(0, (self.arrival * kArrive - (kStep + kStep * i)) / kPart));
    return 1 - pow(1 - u, 3);
}

- (void)setArrival:(CGFloat)arrival { _arrival = arrival; [self settle]; }

- (void)settle {
    for (MMWelcomeControl *c in @[_login, _start]) {
        CGFloat e = [self eased:c.kind == MMWelcomeSwitch ? PartLogin : PartStart];
        c.frame = NSOffsetRect(c.home, 0, round(kRise * (1 - e)));
        c.alphaValue = e;
    }
    self.needsDisplay = YES;
}

/// Right before the window comes on screen: the parts wait below their places, so the first frame is not the whole
/// welcome that then starts over.
- (void)willArrive { if (!MMWindowReduceMotion()) self.arrival = 0; }

- (void)arrive {
    [self.window recalculateKeyViewLoop];
    if (!self.window.isVisible || MMWindowReduceMotion()) { _arriving = nil; self.arrival = 1; return; }
    self.arrival = 0;
    _arriving = [NSDate date];
    [self wake];
}

- (void)wake {
    if (_timer || !self.window.isVisible) return;
    _stepped = [NSDate date];
    _timer = [NSTimer timerWithTimeInterval:1.0 / 60 target:self selector:@selector(frame:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)frame:(NSTimer *)t {
    NSDate *now = [NSDate date];
    NSTimeInterval dt = MIN(MAX([now timeIntervalSinceDate:_stepped], 0), 0.1);
    _stepped = now;
    BOOL moving = [_login slide:dt];
    if (_arriving) {
        self.arrival = MIN(1, [now timeIntervalSinceDate:_arriving] / kArrive);
        if (self.arrival >= 1) _arriving = nil; else moving = YES;
    }
    if (!moving || !self.window.isVisible) [self rest];
}

/// The window left, or nothing moves: no timer, every part in its place and the knob on its side.
- (void)rest {
    [_timer invalidate]; _timer = nil;
    _arriving = nil;
    if (self.arrival != 1) self.arrival = 1;
    _login.knob = _login.on ? 1 : 0;
}

- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if (!self.window) [self rest]; }

#pragma mark Drawing

- (void)part:(NSInteger)i draw:(void (^)(NSRect r))draw {
    CGFloat e = [self eased:i];
    if (e <= 0) return;
    CGContextRef c = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(c);
    if (e < 1) {
        CGContextTranslateCTM(c, 0, kRise * (1 - e));
        CGContextSetAlpha(c, e);
        CGContextBeginTransparencyLayer(c, NULL);
    }
    draw(_parts[i]);
    if (e < 1) CGContextEndTransparencyLayer(c);
    CGContextRestoreGState(c);
}

/// The mark: a soft tile with a warm glow under it, and MinMacs's M in a rounded square.
static void DrawMark(NSRect r) {
    NSPoint mid = NSMakePoint(NSMidX(r), NSMidY(r));
    if (!MMWindowContrast())
        [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:1 green:0.59 blue:0.31 alpha:0.2] endingColor:[NSColor colorWithSRGBRed:1 green:0.59 blue:0.31 alpha:0]]
            drawFromCenter:mid radius:0 toCenter:mid radius:r.size.width * 1.35 options:0];
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:r xRadius:17 yRadius:17];
    [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1 alpha:0.13] endingColor:[NSColor colorWithWhite:1 alpha:0.045]] drawInBezierPath:tile angle:90];
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.25, 0.25) xRadius:17 yRadius:17];
    edge.lineWidth = 0.5;
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.5 : 0.18] setStroke]; [edge stroke];
    // The glyph is drawn on a 16 point grid, as the prototype's.
    CGFloat s = 36.0 / 16, x = mid.x - 18, y = mid.y - 18;
    NSBezierPath *g = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x + 2 * s, y + 2 * s, 12 * s, 12 * s) xRadius:3.4 * s yRadius:3.4 * s];
    [g moveToPoint:NSMakePoint(x + 5 * s, y + 10.6 * s)];
    [g lineToPoint:NSMakePoint(x + 5 * s, y + 5.6 * s)];
    [g lineToPoint:NSMakePoint(x + 8 * s, y + 8.6 * s)];
    [g lineToPoint:NSMakePoint(x + 11 * s, y + 5.6 * s)];
    [g lineToPoint:NSMakePoint(x + 11 * s, y + 10.6 * s)];
    g.lineWidth = 1.15 * s; g.lineCapStyle = NSLineCapStyleRound; g.lineJoinStyle = NSLineJoinStyleRound;
    [NSColor.whiteColor setStroke]; [g stroke];
}

- (void)drawRect:(NSRect)dirty {
    MMWindowWelcome *w = self.welcome;
    if (!w) return;
    BOOL contrast = MMWindowContrast();
    [self part:PartMark draw:^(NSRect r) { DrawMark(r); }];
    [self part:PartTitle draw:^(NSRect r) {
        NSMutableAttributedString *t = [Para(w.title, 30, NSFontWeightSemibold, NSColor.whiteColor, 36, NSTextAlignmentCenter) mutableCopy];
        [t addAttribute:NSKernAttributeName value:@(-0.66) range:NSMakeRange(0, t.length)];
        DrawIn(t, r);
    }];
    [self part:PartSay draw:^(NSRect r) { DrawBalanced([self sayText], r); }];
    [self part:PartLater draw:^(NSRect r) { DrawIn(Para(w.later, 12, NSFontWeightRegular, Soft(0.46), 17, NSTextAlignmentCenter), r); }];
    [self part:PartFacts draw:^(NSRect r) {
        for (NSInteger i = 0; i < (NSInteger)w.facts.count; i++) {
            NSRect col = NSMakeRect(r.origin.x + i * kFact, r.origin.y, kFact, r.size.height);
            if (i > 0) {
                [[NSColor colorWithWhite:1 alpha:contrast ? 0.3 : 0.08] setFill];
                NSRectFillUsingOperation(NSMakeRect(col.origin.x, col.origin.y + 2, 1, col.size.height - 4), NSCompositingOperationSourceOver);
            }
            DrawIn(Para(w.facts[i].label, 13, NSFontWeightMedium, Soft(0.94), 18, NSTextAlignmentCenter), NSMakeRect(col.origin.x + 18, col.origin.y, kFact - 36, 18));
            DrawBalanced([self factText:w.facts[i]], NSMakeRect(col.origin.x + 18, col.origin.y + 22, kFact - 36, col.size.height - 22));
        }
    }];
}

@end
