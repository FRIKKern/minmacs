// The window's controller, MMWindowController.h.
#import <stdatomic.h>
#import "Shell/MMWindowController.h"
#import "Shell/MMWindowFeed.h"
#import "Shell/MMFixRunner.h"
#import "Core/MMCore.h"

static const NSTimeInterval kEndShows = 4;               // an ended run stays on the model this long, then lets go

/// What the keep-awake expert answers. The shell links without Sources/Experts, so these are asked for by name.
@protocol MMWindowLidExpert <NSObject>
/// The menu's own toggle, on main: it asks first when the lid mode turns on, then changes it off main.
- (void)act:(NSString *)what key:(nullable NSString *)key;
/// The change itself, with its undo record. Never on main.
- (NSString *)set:(NSString *)what value:(id)value by:(NSString *)by;
@end

@implementation MMWindowController {
    id _token;                                           // main
    uint64_t _shown;                                     // main: the generation of the last model sent
    _Atomic uint64_t _wanted;                            // the newest generation asked for
    atomic_bool _open, _loginOn;
    // One run at a time. Main sets it at the press, before anything is queued, so a second press that lands right
    // behind the first finds it set. The window queue clears it when the run's end has arrived, or when no run began.
    atomic_bool _busy;
    void (^_afterRun)(void);                             // main: what waits for the run to end, such as a quit
    // Only on the window queue:
    MMSnapshot *_s;
    MMPerformance *_p;
    MMPerformanceLookBack *_lookBack;
    MMWindowRun *_run;
    MMFixRunner *_runner;
    NSDate *_endedAt;                                    // when the last run ended: a plan built before it is spent
}

static dispatch_queue_t Queue(void) { return MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED); }

- (BOOL)open { return atomic_load(&_open); }

- (void)setOpen:(BOOL)open {
    if (atomic_exchange(&_open, open) == open) return;
    if (!open) {
        [MMGraph.shared stopObserving:_token];
        _token = nil; _model = nil; _shown = 0;
        atomic_store(&_wanted, 0);
        // The run and its runner stay: a run under way ends on its own and then clears itself.
        dispatch_async(Queue(), ^{ self->_s = nil; self->_p = nil; self->_lookBack = nil; });
        return;
    }
    atomic_store(&_loginOn, [self.shell loginEnabled]);
    __weak MMWindowController *weak = self;
    _token = [MMGraph.shared observe:^(MMSnapshot *s) { [weak take:s]; }];
    MMSnapshot *now = MMGraph.shared.current;
    if (now) { [self take:now]; return; }
    // The first launch: no snapshot yet. The welcome needs none, so it is there with the window.
    MMWindowWelcome *welcome = MMWindowWelcomeNow(atomic_load(&_loginOn));
    if (!welcome) return;
    MMWindowModel *m = [MMWindowModel new];
    m.welcome = welcome;
    _model = m;
    if (self.onModel) self.onModel(m);
}

/// Main. One build per generation: a snapshot the window already holds or has asked for is not built again.
- (void)take:(MMSnapshot *)s {
    if (!self.open || !s || s.generation <= atomic_load(&_wanted)) return;
    atomic_store(&_wanted, s.generation);
    dispatch_async(Queue(), ^{
        // A newer snapshot came while this one waited, so this one is stale.
        if (!self.open || s.generation < atomic_load(&self->_wanted)) return;
        if (!self->_lookBack) self->_lookBack = [MMPerformanceLookBack read:MMGains.shared now:NSDate.date];
        self->_p = [MMPerformance from:s history:s.history lookBack:self->_lookBack];
        self->_s = s;
        [self send];
    });
}

/// The window queue. A model of the snapshot held, with the switches and the run as they are now. It builds no
/// MMPerformance, so a step of a run or a changed rule costs only the feed.
- (void)send {
    if (!_s || !_p || !self.open) return;
    MMWindowExtras *x = [MMWindowExtras readWithLogin:atomic_load(&_loginOn)];
    x.run = _run;
    x.welcome = MMWindowWelcomeNow(x.loginOn);
    MMWindowModel *m = MMWindowModelFrom(_s, _p, x);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.open || m.generation < self->_shown) return;
        self->_shown = m.generation; self->_model = m;
        if (self.onModel) self.onModel(m);
    });
}

- (void)sendSoon { dispatch_async(Queue(), ^{ [self send]; }); }

#pragma mark - MMWindowHost

- (BOOL)running { return atomic_load(&_busy); }

/// The window queue. The run is over, or none began. Whoever waited for it is told on main.
- (void)ended {
    atomic_store(&_busy, false);
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^then)(void) = self->_afterRun;
        self->_afterRun = nil;
        if (then) then();
    });
}

- (BOOL)stopRunThen:(void (^)(void))then {
    if (!atomic_load(&_busy)) return NO;
    _afterRun = [then copy];
    [self windowStopRun];
    return YES;
}

- (void)windowRunFixEverything {
    if (atomic_exchange(&_busy, true)) return;
    dispatch_async(Queue(), ^{
        // A plan built before the last run ended may name things that run already acted on. The press waits for a
        // snapshot built since, which the run's own rebuild brings.
        BOOL spent = self->_endedAt && (!self->_s.builtAt || [self->_s.builtAt compare:self->_endedAt] != NSOrderedDescending);
        MMPerformance *p = spent ? nil : self->_p;
        NSInteger n = 0;
        for (MMPerformanceFix *f in p.fixes) if (!f.needsYou) n++;
        if (!n) { [self ended]; return; }
        MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
        __weak MMWindowController *weak = self;
        // Progress comes on the runner's queue. The run is kept and sent from the window queue.
        runner.onProgress = ^(MMWindowRun *run) {
            dispatch_async(Queue(), ^{
                MMWindowController *me = weak;
                if (!me) return;
                me->_run = run;
                [me send];
                if (run.running) return;
                // What came back is in the gains log now, so the look-back is read again for the next build.
                me->_lookBack = nil;
                me->_endedAt = me->_runner.endedAt ?: NSDate.date;
                [me ended];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kEndShows * NSEC_PER_SEC)), Queue(), ^{
                    MMWindowController *later = weak;
                    if (!later || later->_run != run) return;
                    later->_run = nil;
                    [later send];
                });
            });
        };
        self->_runner = runner;
        [runner start];
    });
}

- (void)windowStopRun { dispatch_async(Queue(), ^{ [self->_runner stop]; }); }

- (void)windowSetRule:(NSString *)ruleID picked:(NSInteger)choice {
    if ([ruleID isEqualToString:MMWindowRemovalRuleID]) {
        if (choice < MMRemovalSmart || choice > MMRemovalDelete) return;
        dispatch_async(Queue(), ^{
            MMSetRemovalChoice((MMRemovalChoice)choice);
            [self send];
            // Each row's words follow the choice, so the experts build their findings again.
            [MMGraph.shared rebuild:@"window removal"];
        });
        return;
    }
    NSString *expert = MMWindowRuleExpert(ruleID);
    if (!expert || choice < MMModeIdle || choice > MMModeEager) return;
    dispatch_async(Queue(), ^{
        MMSetMode(expert, (MMMode)choice);
        [self send];
        // Each expert reads its mode when the graph prepares a snapshot, so its plan follows at the next build.
        [MMGraph.shared rebuild:@"window mode"];
    });
}

/// Start in the welcome, on main. This and the Settings switch are the only places the window changes the login item,
/// so nothing is added before the person answered. The prefs are written here, before anything else can build a
/// model, so no later model brings the welcome back.
- (void)windowWelcomeStart:(BOOL)openAtLogin removal:(NSInteger)removal {
    if (MMPrefBool(MMWindowWelcomedKey, NO)) return;
    MMWindowWelcomeDone(removal);
    // Only a change is asked for: a person whose answer is what the login item already is gets nothing touched.
    if ([self.shell loginEnabled] != openAtLogin) [self.shell setLogin:openAtLogin];
    atomic_store(&_loginOn, [self.shell loginEnabled]);
    dispatch_async(Queue(), ^{
        [self send];
        // Each row's words follow the removal choice, so the experts build their findings again.
        [MMGraph.shared rebuild:@"window welcome"];
    });
}

- (void)windowSetSwitch:(NSString *)switchID on:(BOOL)on {
    if ([switchID isEqualToString:@"login"]) {
        [self.shell setLogin:on];
        atomic_store(&_loginOn, [self.shell loginEnabled]);
        [self sendSoon];
        return;
    }
    if (![switchID isEqualToString:@"lid"]) return;
    id<MMWindowLidExpert> e = (id)MMExpertNamed(@"insomnia");
    if (!e) return;
    dispatch_async(Queue(), ^{
        // Read again here, off main, so a press on a switch that already moved does nothing.
        if ([MMWindowExtras readWithLogin:NO].lidOn == on) { [self send]; return; }
        if ([e respondsToSelector:@selector(act:key:)]) {
            // The expert's own toggle keeps its confirm, the one administrator prompt and its alert on failure.
            // It changes the setting on its own queue and tells nobody, so the switch is read again a little later.
            dispatch_async(dispatch_get_main_queue(), ^{
                [e act:@"lid" key:nil];
                for (NSNumber *wait in @[@1, @5])
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), Queue(), ^{ [self send]; });
            });
        } else if ([e respondsToSelector:@selector(set:value:by:)]) {
            (void)[e set:@"lid" value:@(on) by:@"manual"];
            [self send];
        }
    });
}

/// The shell's -applicationShouldTerminate: lets a run end its step first, so this never quits in the middle of one.
- (void)windowQuit { [NSApp terminate:nil]; }

@end
