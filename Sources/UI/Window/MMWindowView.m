// The whole window as one view: the top line, the two sides with the middle between them, the dock, and the gear and
// power icons. It draws what the model holds. The gear turns the area under the top line into Settings and back.
// Until the person pressed Start once, the welcome stands alone in the same window, MMWindowWelcome.m, and Start lets
// the menu fade up in its place.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

// 195-a's times: the graphs come back 0.26 s after the pointer leaves a row, a run's end shows for 2.9 s with a burst that
// settles over 1.8 s, the two lines follow their numbers about as its 0.9 s ease does, and a step's words rise in over 0.5 s.
static const NSTimeInterval kBeat = 0.26, kEndHold = 2.9, kGlow = 1.8, kEase = 0.2, kStepIn = 0.5;
// The top line's band when someone asks, and the bare edge when nobody does. The lists get the difference.
static const CGFloat kBand = 40, kNoBand = 12, kLists = 538;

@implementation MMWindowView {
    MMWindowFlipped *_main;
    MMWindowListView *_left, *_right;
    MMWindowMiddleView *_middle;
    MMWindowDockView *_dock;
    NSBox *_rule;
    MMWindowSettingsView *_settings;
    MMWindowButton *_gear, *_power;
    NSString *_hovered;                 // the row under the pointer
    NSTimer *_timer;                    // runs only while something moves and the window shows
    NSDate *_stepped, *_endSeen;        // the last step, and when this view first saw the run ended
    NSString *_stepWords;               // the step the button shows, and when it came
    NSDate *_stepCame;
    BOOL _letGo;                        // the end was shown long enough
    double _memoryShare, _diskShare, _memoryShown, _diskShown;
    MMWindowWelcomeView *_welcome;      // made the first time a model holds a welcome
    BOOL _started;                      // Start was pressed here: a model built before that brings no welcome back
    BOOL _looking;                      // no model came for a moment, so the window says it is taking its first look
    BOOL _quiet;                        // from Start until the menu has arrived and a moment more: only Quit takes a press
    NSInteger _flips;                   // fades between the menu and Settings under way
}

const NSTimeInterval MMWindowStartGuard = 0.6;

BOOL MMWindowTakesPresses(NSView *view) {
    if (!view) return NO;
    for (NSView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:MMWindowView.class]) return ![(MMWindowView *)v holdsBack:view];
        if (v.hidden || v.alphaValue < 1) return NO;
    }
    return YES;
}

/// What the window keeps from presses for now, though it is in the view tree and may even be drawn. Quit always works.
- (BOOL)holdsBack:(NSView *)view {
    if (view == _power) return NO;
    if (_quiet) return YES;
    return _flips > 0 && ([view isDescendantOf:_main] || [view isDescendantOf:_settings]);
}

/// A press lands only on what takes presses. Anything else under the pointer leaves the press with the window itself,
/// which does nothing with it.
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    return !hit || hit == self || MMWindowTakesPresses(hit) ? hit : self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
/// It holds the keyboard when no button does, but Tab never stops on it: there is nothing to see there.
- (BOOL)canBecomeKeyView { return NO; }

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:NSMakeRect(frame.origin.x, frame.origin.y, MMWindowSize.width, MMWindowSize.height)])) {
        CGFloat W = MMWindowSize.width, H = MMWindowSize.height;
        _main = [[MMWindowFlipped alloc] initWithFrame:NSMakeRect(0, 40, W, H - 40)];
        _left = [[MMWindowListView alloc] initWithFrame:NSMakeRect(0, 0, 320, 538)];
        _middle = [[MMWindowMiddleView alloc] initWithFrame:NSMakeRect(320, 0, 380, 538)];
        _right = [[MMWindowListView alloc] initWithFrame:NSMakeRect(700, 0, 320, 538)];
        _rule = [[NSBox alloc] initWithFrame:NSMakeRect(14, 545, W - 28, 1)];
        _rule.boxType = NSBoxCustom; _rule.borderWidth = 0; _rule.fillColor = MMWindowColor(MMWindowInkLine);
        _dock = [[MMWindowDockView alloc] initWithFrame:NSMakeRect(0, 551, W, 137)];
        _dock.fix.target = self; _dock.fix.action = @selector(pressFix:);
        _dock.stop.target = self; _dock.stop.action = @selector(pressFix:);
        for (NSView *v in @[_left, _middle, _right, _rule, _dock]) [_main addSubview:v];
        [self addSubview:_main];

        _settings = [[MMWindowSettingsView alloc] initWithFrame:NSMakeRect(0, 40, W, 662)];
        _settings.hidden = YES;
        [self addSubview:_settings];

        _gear = [MMWindowButton kind:MMWindowButtonGear title:@"Settings" target:self action:@selector(pressGear:)];
        _gear.frame = NSMakeRect(W - 62, 702, 26, 24);
        _gear.toolTip = @"Settings  ⌘,";
        _gear.accessibilityLabel = @"Settings, Command comma";
        _power = [MMWindowButton kind:MMWindowButtonPower title:@"Quit MinMacs" target:self action:@selector(pressPower:)];
        _power.frame = NSMakeRect(W - 32, 702, 26, 24);
        _power.toolTip = @"Quit MinMacs  ⌘Q";
        _power.accessibilityLabel = @"Quit MinMacs, Command Q";
        [self addSubview:_gear]; [self addSubview:_power];

        __weak typeof(self) me = self;
        _left.onPoint = ^(NSString *key) { [me point:key]; };
        _right.onPoint = ^(NSString *key) { [me point:key]; };
        _settings.onDone = ^{ me.showsSettings = NO; };
        MMWindowIconsOnLoad(^{ [me iconsLoaded]; });
    }
    return self;
}

/// The top line folds away when nobody asks. The window keeps its size: the lists grow by the band's height, and the
/// dock stays where it is.
- (CGFloat)bandTop { return _model && !_model.asks.length ? kNoBand : kBand; }

- (void)layBand {
    CGFloat top = self.bandTop, W = MMWindowSize.width, H = MMWindowSize.height;
    if (_main.frame.origin.y == top) return;
    CGFloat lists = kLists + kBand - top;
    _settings.frame = NSMakeRect(0, top, W, 702 - top);
    _main.frame = NSMakeRect(0, top, W, H - top);
    _left.frame = NSMakeRect(0, 0, 320, lists);
    _middle.frame = NSMakeRect(320, 0, 380, lists);
    _right.frame = NSMakeRect(700, 0, 320, lists);
    _rule.frame = NSMakeRect(14, lists + 7, W - 28, 1);
    _dock.frame = NSMakeRect(0, lists + 13, W, 137);
    self.needsDisplay = YES;
}

- (void)iconsLoaded { _left.needsDisplay = YES; _right.needsDisplay = YES; _middle.needsDisplay = YES; }

#pragma mark The model

- (void)setModel:(MMWindowModel *)model {
    // An older snapshot never replaces a newer one.
    if (_model && model && model.generation && model.generation < _model.generation) return;
    MMWindowWelcome *welcome = _started ? nil : model.welcome;
    if (model.welcome && model.generation == 0) {
        // Made before the first snapshot: only its welcome is real. What shows now stays, or nothing does.
        if (_started) return;
        model = _model;
        model.welcome = welcome;
    }
    BOOL hadRun = _model.run != nil;
    _model = model;
    [self showWelcome:welcome];
    if (_model) _looking = NO;
    [self layBand];
    _rule.fillColor = MMWindowColor(MMWindowInkLine);
    _rule.hidden = model == nil;
    _left.ring = model.ring; _right.ring = model.ring;
    _left.groups = model.memoryGroups;
    _right.groups = model.diskGroups;
    _middle.memoryHour = model.memoryHour;
    _middle.diskHour = model.diskHour;
    _dock.model = model;
    _settings.settings = model.settings;
    if (_hovered && ![model row:_hovered]) _hovered = nil;
    [self showPointed];
    [self followRun:hadRun];
    self.needsDisplay = YES;
}

#pragma mark The welcome

- (BOOL)showsWelcome { return _welcome && !_welcome.hidden; }
- (MMWindowWelcomeView *)welcomeView { return _welcome; }

/// The welcome alone: the lists, the dock, Settings and the gear are away until Start.
- (void)showWelcome:(MMWindowWelcome *)welcome {
    if (!welcome) {
        if (self.showsWelcome && !_started) { _welcome.hidden = YES; _main.hidden = self.showsSettings; _gear.hidden = NO; self.needsDisplay = YES; }
        return;
    }
    BOOL was = self.showsWelcome;
    if (!_welcome) {
        _welcome = [[MMWindowWelcomeView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
        __weak typeof(self) me = self;
        _welcome.onStart = ^(BOOL login, NSInteger removal) { [me start:login removal:removal]; };
        [self addSubview:_welcome positioned:NSWindowBelow relativeTo:_gear];
    }
    _welcome.welcome = welcome;
    if (was) return;
    if (self.showsSettings) self.showsSettings = NO;
    _welcome.hidden = NO; _welcome.alphaValue = 1;
    _main.hidden = YES; _gear.hidden = YES;
    self.needsDisplay = YES;
    if (self.window.isVisible) [_welcome arrive];
}

/// Start: the answers go to the host, the welcome leaves and the menu fades up in its place. With no numbers yet the
/// window says it is looking, and the lists and the hour lines fill in as they come.
- (void)start:(BOOL)login removal:(NSInteger)removal {
    if (_started) return;
    _started = YES;
    // A second press where Start was would land on the menu that arrives under it, Fix Everything among it.
    _quiet = YES;
    [self.host windowWelcomeStart:login removal:removal];
    _model.welcome = nil;
    if (!_model) _looking = YES;
    _gear.hidden = NO;
    _main.hidden = NO;
    [self.window makeFirstResponder:self];
    self.needsDisplay = YES;
    MMWindowWelcomeView *goes = _welcome;
    if (!self.window.isVisible || !self.layer || MMWindowReduceMotion()) { goes.hidden = YES; [self arriveSoon]; return; }
    _main.alphaValue = 0; _gear.alphaValue = 0;
    _main.frame = NSOffsetRect(_main.frame, 0, 10);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *c) {
        c.duration = 0.34;
        goes.animator.alphaValue = 0;
    } completionHandler:^{
        goes.hidden = YES;
        self.needsDisplay = YES;
        if (!self->_quiet) return;      // the window closed meanwhile, and -rest put everything in its place
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *c) {
            c.duration = 0.6;
            self->_main.animator.alphaValue = 1; self->_gear.animator.alphaValue = 1;
            // The band may have folded meanwhile, so the menu lands where it belongs now.
            CGFloat top = self.bandTop;
            self->_main.animator.frame = NSMakeRect(0, top, MMWindowSize.width, MMWindowSize.height - top);
        } completionHandler:^{ if (self->_quiet) [self arriveSoon]; }];
    }];
}

/// The menu is all there. It takes presses and keys a moment later, so a press meant for Start never reaches it.
- (void)arriveSoon {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(arrived) object:nil];
    [self performSelector:@selector(arrived) withObject:nil afterDelay:MMWindowStartGuard inModes:@[NSRunLoopCommonModes]];
}

- (void)arrived { _quiet = NO; [self.window recalculateKeyViewLoop]; }

/// The window closed between Start and the menu's arrival: the menu is simply there the next time.
- (void)settleStart {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(arrived) object:nil];
    if (!_quiet) return;
    _quiet = NO;
    _welcome.hidden = YES;
    _main.alphaValue = 1; _gear.alphaValue = 1;
    CGFloat top = self.bandTop;
    _main.frame = NSMakeRect(0, top, MMWindowSize.width, MMWindowSize.height - top);
}

/// No model came within a moment of opening: the window says so in one line, in place of an empty pane.
- (void)sayLooking { if (!_model && !self.showsWelcome) { _looking = YES; self.needsDisplay = YES; } }

- (void)setPointsAtFix:(BOOL)on { _pointsAtFix = on; [_dock.fix setHover:on]; }

- (void)setPointedRow:(NSString *)key {
    _pointedRow = [key copy];
    if (key) { [_left reveal:key]; [_right reveal:key]; }
    [self showPointed];
}

/// The middle shows the story of the row under the pointer, or of the row the render tool names.
- (void)showPointed {
    NSString *key = _hovered ?: _pointedRow;
    MMWindowRow *row = key ? [_model row:key] : nil;
    _left.hotKey = row.key; _right.hotKey = row.key;
    _middle.model = _model;
    _middle.row = row;
    _dock.pointed = row;
}

- (void)point:(NSString *)key {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(unpoint) object:nil];
    if (key) {
        if ([key isEqualToString:_hovered]) return;
        _hovered = [key copy];
        [self showPointed];
    } else if (_hovered) {
        // A short beat after the pointer leaves, the graphs come back.
        [self performSelector:@selector(unpoint) withObject:nil afterDelay:kBeat inModes:@[NSRunLoopCommonModes]];
    }
}

- (void)unpoint { _hovered = nil; [self showPointed]; }

#pragma mark The run

static double Share(uint64_t back, uint64_t planned) { return planned ? MIN(1.0, (double)back / (double)planned) : 0; }

/// Takes the run's numbers as the place the lines and the gains move toward.
- (void)followRun:(BOOL)hadRun {
    MMWindowRun *run = _model.run;
    if (!run) {
        _endSeen = nil; _letGo = NO; _stepWords = nil; _stepCame = nil;
        _memoryShare = _diskShare = _memoryShown = _diskShown = 0;
        _dock.phase = MMWindowDockCalm;
        [self push];
        return;
    }
    if (run.running) { _endSeen = nil; _letGo = NO; }
    else if (!_endSeen) _endSeen = [NSDate date];
    if (!hadRun || MMWindowReduceMotion()) {
        // The first frame of a run shows where it stands. Only later changes move.
        _memoryShare = Share(run.memoryBack, run.memoryPlanned); _diskShare = Share(run.diskBack, run.diskPlanned);
        _memoryShown = run.memoryBack; _diskShown = run.diskBack;
        _stepWords = run.step; _stepCame = nil;
    } else if (run.running && run.step != _stepWords && ![run.step isEqualToString:_stepWords]) {
        _stepWords = run.step; _stepCame = [NSDate date];
    }
    [self step:[NSDate date]];
    [self wake];
}

/// One step of the motion. Returns whether anything still moves or waits.
- (BOOL)step:(NSDate *)now {
    MMWindowRun *run = _model.run;
    if (!run) return NO;
    NSTimeInterval dt = _stepped ? MIN(MAX([now timeIntervalSinceDate:_stepped], 0), 0.1) : 1.0 / 60;
    _stepped = now;
    double k = MMWindowReduceMotion() ? 1 : 1 - exp(-dt / kEase);
    double tm = Share(run.memoryBack, run.memoryPlanned), td = Share(run.diskBack, run.diskPlanned);
    _memoryShare += (tm - _memoryShare) * k; _diskShare += (td - _diskShare) * k;
    _memoryShown += (run.memoryBack - _memoryShown) * k; _diskShown += (run.diskBack - _diskShown) * k;
    BOOL moving = fabs(tm - _memoryShare) > 0.002 || fabs(td - _diskShare) > 0.002 ||
                  fabs(run.memoryBack - _memoryShown) > 524288 || fabs(run.diskBack - _diskShown) > 524288;
    if (!moving) { _memoryShare = tm; _diskShare = td; _memoryShown = run.memoryBack; _diskShown = run.diskBack; }
    if (run.running) {
        _dock.phase = MMWindowDockRunning; _dock.glow = 0;
        double x = _stepCame && !MMWindowReduceMotion() ? MIN(MAX([now timeIntervalSinceDate:_stepCame] / kStepIn, 0), 1) : 1;
        _dock.stepIn = 1 - pow(1 - x, 3);
        if (x >= 1) _stepCame = nil; else moving = YES;
    } else {
        // The end shows with a short glow, then the view lets go and the calm dock is back.
        NSTimeInterval age = _endSeen ? [now timeIntervalSinceDate:_endSeen] : 0;
        if (age >= kEndHold) _letGo = YES;
        _dock.phase = _letGo ? MMWindowDockCalm : MMWindowDockEnded;
        _dock.glow = _letGo || MMWindowReduceMotion() ? 0 : pow(MAX(0, 1 - age / kGlow), 3);
        moving = moving || !_letGo;
    }
    [self push];
    return moving;
}

- (void)push {
    _dock.memoryShare = _memoryShare; _dock.diskShare = _diskShare;
    _dock.memoryShown = _memoryShown; _dock.diskShown = _diskShown;
}

- (void)tick:(NSDate *)now {
    [self step:now ?: [NSDate date]];
    [self wake];
}

/// The timer runs only while the window shows and something moves or the end still shows.
- (void)wake {
    MMWindowRun *run = _model.run;
    BOOL need = run && self.window.isVisible && (run.running ? (_memoryShare != Share(run.memoryBack, run.memoryPlanned) || _diskShare != Share(run.diskBack, run.diskPlanned) ||
                                                                 _memoryShown != run.memoryBack || _diskShown != run.diskBack || _stepCame != nil) : !_letGo);
    if (need && !_timer) {
        _timer = [NSTimer timerWithTimeInterval:1.0 / 60 target:self selector:@selector(frame:) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (!need && _timer) {
        [_timer invalidate]; _timer = nil;
    }
}

- (void)frame:(NSTimer *)t {
    if (![self step:[NSDate date]] || !self.window.isVisible) { [_timer invalidate]; _timer = nil; }
}

- (void)willOpen { if (self.showsWelcome) [_welcome willArrive]; }

- (void)opened {
    _stepped = nil;
    [self wake];
    if (self.showsWelcome) [_welcome arrive];
    else if (!_model) [self performSelector:@selector(sayLooking) withObject:nil afterDelay:0.6 inModes:@[NSRunLoopCommonModes]];
}

- (void)rest {
    [_timer invalidate]; _timer = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(unpoint) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sayLooking) object:nil];
    [_left rest]; [_right rest]; [_welcome rest];
    [self settleStart];
    _hovered = nil;
    [self showPointed];
}

- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if (!self.window) [self rest]; }

#pragma mark Settings in place

- (void)setShowsSettings:(BOOL)on {
    if (_showsSettings == on || (on && self.showsWelcome)) return;
    _showsSettings = on;
    _settings.host = self.host;
    _gear.lit = on;
    self.needsDisplay = YES;
    _gear.accessibilityValue = on ? @"on" : @"off";
    NSView *comes = on ? _settings : _main, *goes = on ? _main : _settings;
    if (on) { _hovered = nil; [self showPointed]; }
    BOOL fade = self.window.isVisible && self.layer && !MMWindowReduceMotion();
    comes.hidden = NO;
    if (!fade) { comes.alphaValue = 1; goes.alphaValue = 1; goes.hidden = YES; return; }
    comes.alphaValue = 0;
    // Neither side takes a press while it fades. The gear and the keys still do, and the last of them wins.
    _flips++;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *c) {
        c.duration = 0.16;
        comes.animator.alphaValue = 1; goes.animator.alphaValue = 0;
    } completionHandler:^{
        self->_flips--;
        // A second press during the fade wins.
        BOOL still = self.showsSettings == on;
        goes.hidden = still; goes.alphaValue = 1;
        if (!still) comes.hidden = YES;
    }];
}

#pragma mark Presses and keys

- (void)pressFix:(id)sender {
    if (_dock.phase == MMWindowDockRunning) [self.host windowStopRun];
    else if (_dock.phase == MMWindowDockCalm && _model.fixCount > 0) [self.host windowRunFixEverything];
}

- (void)pressGear:(id)sender { self.showsSettings = !self.showsSettings; }
- (void)pressPower:(id)sender { [self.host windowQuit]; }

- (BOOL)performKeyEquivalent:(NSEvent *)e {
    NSEventModifierFlags flags = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    // Only the key window's keys are the window's own. AppKit also offers a key no window took to every other window.
    if (self.window.isKeyWindow && (flags & ~NSEventModifierFlagCapsLock) == NSEventModifierFlagCommand) {
        NSString *key = e.charactersIgnoringModifiers.lowercaseString;
        // The welcome has no Settings behind it: its two choices are on it.
        if ([key isEqualToString:@","]) { if (!self.showsWelcome && !_quiet) self.showsSettings = !self.showsSettings; return YES; }
        if ([key isEqualToString:@"q"]) { [self.host windowQuit]; return YES; }
    }
    return [super performKeyEquivalent:e];
}

- (void)keyDown:(NSEvent *)e {
    // Return presses Start, wherever the keyboard is in the welcome.
    if (self.showsWelcome && !_started && (e.keyCode == 36 || e.keyCode == 76)) { [_welcome pressStart]; return; }
    // Until the menu has arrived no key reaches it, Tab among them. Escape still closes the window.
    if (_quiet && e.keyCode != 53) return;
    if (e.keyCode == 53 && self.window.isKeyWindow) [self cancelOperation:nil]; else [super keyDown:e];
}

/// Escape leaves Settings first, and closes the window when Settings does not show.
- (void)cancelOperation:(id)sender {
    if (!self.window.isKeyWindow) return;
    if (self.showsSettings) self.showsSettings = NO; else [self.window close];
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    if (self.drawsBacking) {
        // No blur is behind the glass in a render, so a dark desktop stands in for it.
        if (MMWindowContrast()) { [MMWindowColor(MMWindowInkBase) setFill]; NSRectFill(b); }
        else [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.13 green:0.11 blue:0.30 alpha:1]
                                            endingColor:[NSColor colorWithSRGBRed:0.27 green:0.13 blue:0.26 alpha:1]] drawInRect:b angle:55];
    }
    [MMWindowColor(MMWindowInkGlass) setFill];
    NSRectFillUsingOperation(b, NSCompositingOperationSourceOver);
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.25, 0.25) xRadius:12 yRadius:12];
    edge.lineWidth = 0.5;
    [[NSColor colorWithWhite:1 alpha:0.17] setStroke];
    [edge stroke];

    // The top line: what asks the person, a white diamond and a hairline. Nobody asks: none of them, and no band.
    if (_model.asks.length && !self.showsWelcome) {
        MMWindowDrawDiamond(NSMakeRect(14, 11, 12, 12), NSColor.whiteColor);
        MMWindowDraw(MMWindowFit(_model.asks, 13, NSFontWeightMedium, MMWindowColor(MMWindowInkText), b.size.width - 60), 33, 17, -1);
    }
    if (self.showsWelcome) return;
    if (!_model && _looking && !self.showsSettings)
        MMWindowDraw(MMWindowText(MMWindowLookingNote, 13, NSFontWeightRegular, MMWindowColor(MMWindowInkText2)), NSMidX(b), round(b.size.height * 0.42), 0);
    if (_model.asks.length || (!_model && (self.showsSettings || !_looking))) {
        [MMWindowColor(MMWindowInkLine) setFill];
        NSRectFillUsingOperation(NSMakeRect(14, 34, b.size.width - 28, 1), NSCompositingOperationSourceOver);
    }
}

#pragma mark Words

+ (NSArray<NSString *> *)shownStrings:(MMWindowModel *)m {
    NSMutableArray<NSString *> *s = [NSMutableArray arrayWithArray:@[
        @"Fix Everything", @"Stop", @"memory in use", @"disk free", @"memory back", @"disk back", @"so far",
        @"the last hour", @"an hour ago", @"now", @"The line fills in as the hour passes.", @"min ago", @"memory back today", @"disk back today", @"more above", @"about the same", @"more below", @"Its last hour", @"by memory", @"by disk", @"This disk", @"Memory", @"the whole number", @"Free", @"In use",
        @"By these holders", @"macOS and the rest", @"Asks you.", @"Goes with Fix Everything.", @"Stays.", @"After the fix", @"After all", @"memory, now", @"biggest", @"minutes",
        @"Settings", @"Each change applies at once.", @"Done", @"This Mac", @"Quit MinMacs", MMWindowLookingNote]];
    void (^add)(NSString *) = ^(NSString *x) { if (x.length) [s addObject:x]; };
    add(m.asks);
    for (MMWindowHour *h in @[m.memoryHour ?: [MMWindowHour new], m.diskHour ?: [MMWindowHour new]]) { add(h.title); add(h.explain); }
    for (NSArray<MMWindowGroup *> *side in @[m.memoryGroups, m.diskGroups]) for (MMWindowGroup *g in side) {
        add(g.title); add(g.emptyNote);
        for (MMWindowRow *r in g.rows) { add(r.name); add(r.state); for (MMWindowFact *f in r.facts) { add(f.label); add(f.value); } }
    }
    for (MMWindowFix *f in m.fixes) add(f.title);
    add(m.run.step); add(m.run.endTitle); add(m.run.endNote);
    for (MMWindowRule *r in m.settings.rules) { add(r.title); add(r.note); for (MMWindowChoice *c in r.choices) { add(c.title); add(c.explain); } }
    for (MMWindowSwitch *w in m.settings.switches) { add(w.title); add(w.note); }
    MMWindowWelcome *w = m.welcome;
    for (NSString *x in @[w.title ?: @"", w.say ?: @"", w.loginTitle ?: @"", w.loginOnNote ?: @"", w.loginOffNote ?: @"", w.removalTitle ?: @"", w.later ?: @"", w.start ?: @""]) add(x);
    for (MMWindowChoice *c in w.removal) { add(c.title); add(c.explain); }
    for (MMWindowFact *f in w.facts) { add(f.label); add(f.value); }
    return s;
}

@end
