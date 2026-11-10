// The whole window as one view: the top line, the two sides with the middle between them, the dock, and the gear and
// power icons. It draws what the model holds. The gear turns the area under the top line into Settings and back.
#import "UI/Window/MMWindowParts.h"
#import "UI/MMFormat.h"

static const NSTimeInterval kBeat = 0.3, kEndHold = 4.0, kGlow = 0.9, kEase = 0.16;
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
    BOOL _letGo;                        // the end was shown long enough
    double _memoryShare, _diskShare, _memoryShown, _diskShown;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

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
- (void)layBand {
    CGFloat top = _model && !_model.asks.length ? kNoBand : kBand, W = MMWindowSize.width, H = MMWindowSize.height;
    if (_main.frame.origin.y == top) return;
    CGFloat lists = kLists + kBand - top;
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
    BOOL hadRun = _model.run != nil;
    _model = model;
    [self layBand];
    _rule.fillColor = MMWindowColor(MMWindowInkLine);
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
    _middle.row = row;
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
        _endSeen = nil; _letGo = NO;
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
    } else {
        // The end shows with a short glow, then the view lets go and the calm dock is back.
        NSTimeInterval age = _endSeen ? [now timeIntervalSinceDate:_endSeen] : 0;
        if (age >= kEndHold) _letGo = YES;
        _dock.phase = _letGo ? MMWindowDockCalm : MMWindowDockEnded;
        _dock.glow = _letGo || MMWindowReduceMotion() ? 0 : MAX(0, 1 - age / kGlow);
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
                                                                 _memoryShown != run.memoryBack || _diskShown != run.diskBack) : !_letGo);
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

- (void)opened { _stepped = nil; [self wake]; }

- (void)rest {
    [_timer invalidate]; _timer = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(unpoint) object:nil];
    [_left rest]; [_right rest];
    _hovered = nil;
    [self showPointed];
}

- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; if (!self.window) [self rest]; }

#pragma mark Settings in place

- (void)setShowsSettings:(BOOL)on {
    if (_showsSettings == on) return;
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
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *c) {
        c.duration = 0.16;
        comes.animator.alphaValue = 1; goes.animator.alphaValue = 0;
    } completionHandler:^{
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
        if ([key isEqualToString:@","]) { self.showsSettings = !self.showsSettings; return YES; }
        if ([key isEqualToString:@"q"]) { [self.host windowQuit]; return YES; }
    }
    return [super performKeyEquivalent:e];
}

- (void)keyDown:(NSEvent *)e {
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

    // The top line: what asks the person, with a white diamond, and a hairline under it. Settings keeps the hairline.
    // Nobody asks: no words, no hairline and no band. layBand gave its height to the lists.
    if (_model.asks.length) {
        MMWindowDrawDiamond(NSMakeRect(14, 11, 12, 12), NSColor.whiteColor);
        MMWindowDraw(MMWindowFit(_model.asks, 13, NSFontWeightMedium, MMWindowColor(MMWindowInkText), b.size.width - 60), 33, 17, -1);
    }
    if (_model.asks.length || self.showsSettings || !_model) {
        [MMWindowColor(MMWindowInkLine) setFill];
        NSRectFillUsingOperation(NSMakeRect(14, 34, b.size.width - 28, 1), NSCompositingOperationSourceOver);
    }
}

#pragma mark Words

+ (NSArray<NSString *> *)shownStrings:(MMWindowModel *)m {
    NSMutableArray<NSString *> *s = [NSMutableArray arrayWithArray:@[
        @"Fix Everything", @"Nothing to fix now", @"Press to stop", @"memory in use", @"disk free", @"memory back", @"disk back", @"so far",
        @"the last hour", @"an hour ago", @"now", @"The line fills in as the hour passes.", @"min ago", @"memory back today", @"disk back today", @"more above", @"about the same", @"more below", @"Its last hour",
        @"Settings", @"Each change applies at once.", @"Done", @"This Mac", @"Quit MinMacs"]];
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
    return s;
}

@end
