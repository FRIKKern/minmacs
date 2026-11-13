// The run of Fix Everything as the window shows it move: the two lines around the button and the gains follow the
// run's numbers, a step's words rise in, and the end shows with a burst and then lets go. One timer, which runs only
// while the window shows and something still moves.
#import "UI/Window/MMWindowViewParts.h"

// 195-a's times: a run's end shows for 2.9 s with a burst that
// settles over 1.8 s, the two lines follow their numbers about as its 0.9 s ease does, and a step's words rise in over 0.5 s.
static const NSTimeInterval kEndHold = 2.9, kGlow = 1.8, kEase = 0.2, kStepIn = 0.5;

@implementation MMWindowView (Run)

static double Share(uint64_t back, uint64_t planned) { return planned ? MIN(1.0, (double)back / (double)planned) : 0; }

/// Takes the run's numbers as the place the lines and the gains move toward.
- (void)followRun:(BOOL)hadRun {
    MMWindowRun *run = self.model.run;
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
    MMWindowRun *run = self.model.run;
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

- (void)runTick:(NSDate *)now {
    [self step:now ?: [NSDate date]];
    [self wake];
}

/// The timer runs only while the window shows and something moves or the end still shows.
- (void)wake {
    MMWindowRun *run = self.model.run;
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

@end
