// The welcome of the first launch, prototype 199-a "Welcome Then Menu": alone in the window, at the window's size.
//
//                     [mark]
//               Welcome to MinMacs
//        what MinMacs is, in two sentences
//   +------------------------------------------+
//   | Open at login                     (switch)|
//   +------------------------------------------+
//   | When MinMacs removes things               |
//   |  (o) Smart   what happens                 |
//   |  ( ) Trash   what happens                 |
//   |  ( ) Delete  what happens                 |
//   +------------------------------------------+
//        Both can be changed later in Settings.
//      fact        |      fact       |     fact
//                    [ Start ]
//
// It draws only what an MMWindowWelcome holds. Nothing is applied here: Start hands the two answers to onStart.
// The parts rise in one after the other when the window opens, and stand still under Reduce Motion. A button takes
// no press before it has landed, MMWindowTakesPresses.
// An answer the person has not touched follows the model, so a choice made elsewhere meanwhile shows. One they
// touched is theirs and stays, whatever a later model says.
#import "UI/Window/MMWindowParts.h"

static const CGFloat kColumn = 600, kSay = 520, kMark = 60, kFact = 280, kRise = 14, kExplainX = 92;
// Each part starts 0.05 s after the one above it and takes half a second to land, slowing as it does. The last one,
// Start, has landed 0.9 s after the window opened, and takes a press from then.
static const NSTimeInterval kStep = 0.05, kPart = 0.5, kArrive = 0.05 + 7 * 0.05 + 0.5;
const NSTimeInterval MMWindowWelcomeRise = kArrive;
enum { PartMark = 0, PartTitle, PartSay, PartLogin, PartRemoval, PartLater, PartFacts, PartStart, PartCount };

static NSColor *Soft(CGFloat alpha) { return [NSColor colorWithSRGBRed:0.92 green:0.92 blue:0.96 alpha:MMWindowContrast() ? MIN(1, alpha + 0.3) : alpha]; }
static NSColor *Accent(void) { return [NSColor colorWithSRGBRed:1 green:0.604 blue:0.302 alpha:1]; }

static NSAttributedString *Para(NSString *s, CGFloat size, NSFontWeight weight, NSColor *color, CGFloat line, NSTextAlignment align) {
    NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
    p.lineBreakMode = NSLineBreakByWordWrapping; p.alignment = align;
    p.minimumLineHeight = line; p.maximumLineHeight = line;
    return [[NSAttributedString alloc] initWithString:s ?: @"" attributes:@{
        NSFontAttributeName: MMWindowFont(size, weight), NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: p}];
}

static CGFloat Height(NSAttributedString *s, CGFloat width) {
    return ceil([s boundingRectWithSize:NSMakeSize(width, 2000) options:NSStringDrawingUsesLineFragmentOrigin].size.height);
}

static void DrawIn(NSAttributedString *s, NSRect r) { [s drawWithRect:r options:NSStringDrawingUsesLineFragmentOrigin]; }

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

#pragma mark The controls

typedef NS_ENUM(NSInteger, MMWelcomeKind) { MMWelcomeSwitch = 0, MMWelcomeOption, MMWelcomeStart };

/// The switch, one removal choice, or Start: a real button that draws itself, so a press, Space and VoiceOver work.
@interface MMWelcomeControl : NSButton
@property MMWelcomeKind kind;
@property (copy) NSString *label, *explain;
@property (nonatomic) BOOL on;
@property (nonatomic) CGFloat knob;                     // 0 off, 1 on: where the switch's knob sits
@property NSInteger index;
@property NSRect home;                                  // its frame once it has risen in
@end

/// The card of the three removal choices: one radio group to VoiceOver, named by the card's title.
@interface MMWelcomeGroup : MMWindowFlipped
@end
@implementation MMWelcomeGroup
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityRadioGroupRole; }
@end

@interface MMWindowWelcomeView ()
- (void)move:(NSInteger)by from:(NSInteger)index;
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

#pragma mark The welcome

@implementation MMWindowWelcomeView {
    MMWelcomeControl *_login, *_start;
    NSMutableArray<MMWelcomeControl *> *_options;
    MMWelcomeGroup *_group;             // holds the options, at the removal card's place
    NSRect _parts[PartCount];
    NSString *_built;
    BOOL _touchedLogin, _touchedRemoval;   // the person changed it here: it is theirs, and no later model moves it
    NSTimer *_timer;                    // runs only while the parts rise in or the knob slides
    NSDate *_arriving, *_stepped;       // when the rise began, nil once every part has landed
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _options = [NSMutableArray new];
        _arrival = 1;
        _login = [self control:MMWelcomeSwitch];
        _login.accessibilityRole = NSAccessibilityCheckBoxRole;
        _login.accessibilitySubrole = NSAccessibilitySwitchSubrole;
        _group = [[MMWelcomeGroup alloc] initWithFrame:NSZeroRect];
        [self addSubview:_group];
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
- (NSInteger)picked { for (MMWelcomeControl *o in _options) if (o.on) return o.index; return 0; }

- (void)setWelcome:(MMWindowWelcome *)w {
    _welcome = w;
    if (!w) return;
    // The cards are built again only when the words changed. What the person picked stays.
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@|%@|%d;", w.title, w.say, w.loginTitle, w.loginOnNote, w.loginOffNote, w.removalTitle, w.later, w.start, MMWindowContrast()];
    for (MMWindowChoice *c in w.removal) [sig appendFormat:@"%@=%@,", c.title, c.explain];
    for (MMWindowFact *f in w.facts) [sig appendFormat:@"%@=%@,", f.label, f.value];
    BOOL on = _touchedLogin ? self.loginOn : w.loginOn;
    NSInteger picked = _touchedRemoval ? self.picked : w.removalPicked;
    if ([sig isEqualToString:_built]) {
        // The same words. An answer the person left alone still follows the model.
        if (on != _login.on) { _login.on = on; [self sayLogin]; [self wake]; }
        for (MMWelcomeControl *o in _options) if (o.on != (o.index == picked)) { o.on = o.index == picked; o.needsDisplay = YES; }
        return;
    }
    _built = sig;
    NSInteger focus = -1;
    for (MMWelcomeControl *o in _options) { if (self.window.firstResponder == o) focus = o.index; [o removeFromSuperview]; }
    [_options removeAllObjects];
    _group.accessibilityLabel = w.removalTitle;
    for (NSInteger i = 0; i < (NSInteger)w.removal.count; i++) {
        MMWelcomeControl *o = [self control:MMWelcomeOption];
        [_group addSubview:o];
        o.index = i; o.label = w.removal[i].title; o.explain = w.removal[i].explain;
        o.accessibilityRole = NSAccessibilityRadioButtonRole;
        o.accessibilityLabel = [NSString stringWithFormat:@"%@, %@. %@", w.removalTitle, o.label, o.explain];
        o.on = i == picked;
        [_options addObject:o];
    }
    _login.label = w.loginTitle;
    _login.on = on;
    [self sayLogin];
    _start.label = w.start;
    _start.accessibilityLabel = w.start;
    NSMutableArray *read = [NSMutableArray arrayWithObjects:w.title, w.say, w.later, nil];
    for (MMWindowFact *f in w.facts) [read addObject:[NSString stringWithFormat:@"%@. %@", f.label, f.value]];
    self.accessibilityLabel = [read componentsJoinedByString:@" "];
    [self place];
    if (focus >= 0 && focus < (NSInteger)_options.count) [self.window makeFirstResponder:_options[focus]];
}

/// The switch says what its state means, in the card and to VoiceOver.
- (void)sayLogin {
    _login.explain = _login.on ? self.welcome.loginOnNote : self.welcome.loginOffNote;
    _login.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", self.welcome.loginTitle, _login.explain];
    _login.needsDisplay = YES;
}

/// Start by a press or by Return. Nothing happens while Start has not landed, or once the welcome is on its way out.
- (void)pressStart { if (self.welcome && self.onStart && MMWindowTakesPresses(_start)) self.onStart(self.loginOn, self.picked); }

- (void)pressed:(MMWelcomeControl *)c {
    if (c.kind == MMWelcomeStart) { [self pressStart]; return; }
    if (c.kind == MMWelcomeSwitch) { _touchedLogin = YES; c.on = !c.on; [self sayLogin]; [self wake]; return; }
    _touchedRemoval = YES;
    for (MMWelcomeControl *o in _options) { o.on = o == c; o.needsDisplay = YES; }
}

/// An arrow key on a choice: the pick and the keyboard go to the next or the one before, around the ends.
- (void)move:(NSInteger)by from:(NSInteger)index {
    NSInteger n = (NSInteger)_options.count;
    if (!n) return;
    MMWelcomeControl *to = _options[(NSUInteger)(((index + by) % n + n) % n)];
    [self pressed:to];
    [self.window makeFirstResponder:to];
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
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height, cx = round(W / 2), optionW = kColumn - 16;
    CGFloat sayH = Height([self sayText], kSay), options = 0, factsH = 0;
    for (MMWelcomeControl *o in _options) options += [MMWelcomeControl optionHeight:o.explain width:optionW] + 2;
    for (MMWindowFact *f in w.facts) factsH = MAX(factsH, 18 + 4 + Height([self factText:f], kFact - 36));
    CGFloat heights[PartCount] = {kMark, 36, sayH, 62, 14 + 19 + 9 + options + 8, 17, factsH, 46};
    CGFloat gaps[PartCount] = {0, 20, 10, 28, 10, 12, 28, 30};
    CGFloat total = 0;
    for (NSInteger i = 0; i < PartCount; i++) total += heights[i] + gaps[i];
    CGFloat y = floor((H - total) / 2);
    CGFloat widths[PartCount] = {kMark, kColumn, kSay, kColumn, kColumn, kColumn, kFact * MAX(1, (CGFloat)w.facts.count), 200};
    for (NSInteger i = 0; i < PartCount; i++) {
        y += gaps[i];
        _parts[i] = NSMakeRect(cx - round(widths[i] / 2), y, widths[i], heights[i]);
        y += heights[i];
    }
    _login.home = _parts[PartLogin];
    _start.home = _parts[PartStart];
    // The choices sit in the group, which sits at the card's place.
    CGFloat oy = 14 + 19 + 9;
    for (MMWelcomeControl *o in _options) {
        CGFloat oh = [MMWelcomeControl optionHeight:o.explain width:optionW];
        o.home = NSMakeRect(8, oy, optionW, oh);
        o.frame = o.home;
        oy += oh + 2;
    }
    [self settle];
}

- (NSArray<NSValue *> *)partFrames {
    NSMutableArray *out = [NSMutableArray new];
    for (NSInteger i = 0; i < PartCount; i++) [out addObject:[NSValue valueWithRect:_parts[i]]];
    return out;
}

- (NSArray<NSButton *> *)controls { return [[@[_login] arrayByAddingObjectsFromArray:_options] arrayByAddingObject:_start]; }

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
    CGFloat e = [self eased:PartRemoval];
    _group.frame = NSOffsetRect(_parts[PartRemoval], 0, round(kRise * (1 - e)));
    _group.alphaValue = e;
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
    [self part:PartRemoval draw:^(NSRect r) {
        NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:14 yRadius:14];
        [[NSColor colorWithWhite:1 alpha:0.055] setFill]; [card fill];
        [[NSColor colorWithWhite:1 alpha:contrast ? 0.4 : 0.12] setStroke]; card.lineWidth = 0.5; [card stroke];
        DrawIn(Para(w.removalTitle, 14.5, NSFontWeightMedium, NSColor.whiteColor, 19, NSTextAlignmentLeft), NSMakeRect(r.origin.x + 18, r.origin.y + 14, r.size.width - 36, 19));
    }];
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
