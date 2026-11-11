// More checks for test/window/window.m, which includes this file: Fix Everything stopped inside a fix, an app that
// will not quit, and the window's controller. They use window.m's world, its fake experts and its helpers.
#import "Shell/MMWindowController.h"

/// Stop pressed inside a fix of two things: the first server stops, the second is never reached.
static void RunStoppedInside(void) {
    World();
    gFindings[@"locohost"] = [gFindings[@"locohost"] arrayByAddingObject:
        Finding(@"locohost", @"server", @"docs#dev", @":3002 Astro docs", Dir(@"docs"), 71004, 256 * MB, 0, P(@"stop", MMReversibleRestart),
                @{@"port": @3002, @"framework": @"Astro", @"project": @"docs", @"state": @"idle", @"lastActive": @(NSDate.date.timeIntervalSince1970 - 3600), @"uptimeSeconds": @7200})];
    Proc(71004, 256 * MB);
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMPerformanceFix *two = nil;
    for (MMPerformanceFix *f in p.fixes) if ([f.kind isEqualToString:@"stop"] && f.actions.count == 2) two = f;
    T(@"inside: the world has one fix that stops two servers", @"yes", YN(two != nil));
    if (!two) return;
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    __weak MMFixRunner *weak = runner;
    __block MMWindowRun *end = nil, *atStop = nil;
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    // The press on the button while the fix's first server stops.
    runner.onProgress = ^(MMWindowRun *r) {
        if (!r.running) { end = r; dispatch_semaphore_signal(ended); return; }
        if (!atStop && [r.step hasPrefix:@"Stopping :300"]) { atStop = r; [weak stop]; }
    };
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"inside: the run ends", @"yes", @"no"); return; }
    NSArray<NSString *> *ids = [two.actions valueForKeyPath:@"finding.findingID"];
    NSInteger ran = 0;
    for (NSString *x in ids) if ([gRan containsObject:x]) ran++;
    T(@"inside: one of the fix's two servers stopped, and the other was never reached", @"1", @(ran));
    T(@"inside: a fix stopped partway is not counted as done", @(atStop.done), @(end.done));
    NSInteger after = (NSInteger)p.fixes.count - 1 - (NSInteger)[p.fixes indexOfObject:two], own = 0;
    for (NSUInteger i = [p.fixes indexOfObject:two] + 1; i < p.fixes.count; i++) if (p.fixes[i].needsYou) own++;
    NSString *rest = after - own > 0 ? [NSString stringWithFormat:@" and %ld fix%@ you stopped", (long)(after - own), after - own == 1 ? @"" : @"es"] : @"";
    T(@"inside: the end note says what was not reached", @"yes", YN([end.endNote containsString:[@"1 thing in the fix you stopped partway" stringByAppendingString:rest]]));
    Info([NSString stringWithFormat:@"%@. %@", end.endTitle, end.endNote]);
    T(@"inside: the end title counts only whole fixes", [NSString stringWithFormat:@"%ld of 5 fixes done", (long)atStop.done], end.endTitle);
    uint64_t one = [gRan containsObject:@"locohost:server:app#dev"] ? 512 * MB : 256 * MB;
    T(@"inside: memory back grew by the one server that stopped", @(atStop.memoryBack + one), @(end.memoryBack));
    T(@"inside: no shown string names an old app or says for good", @"", Bad(@[end.endTitle ?: @"", end.endNote ?: @""]));
}

/// An app that will not quit: its action runs and fails. It gives no memory back, and the end says it is blocked.
static void RunRefused(void) {
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    [gRefuses addObject:@"minmacs:app:com.example.chat"];
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    __block MMWindowRun *end = nil;
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    runner.onProgress = ^(MMWindowRun *r) { if (!r.running) { end = r; dispatch_semaphore_signal(ended); } };
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"refused: the run ends", @"yes", @"no"); return; }
    NSString *chat = @"-";
    for (MMFixResult *x in runner.results) if ([x.name isEqualToString:@"Chat"]) chat = x.outcome;
    T(@"refused: the quit was asked for and failed", @"yes failed", [NSString stringWithFormat:@"%@ %@", YN([gRan containsObject:@"minmacs:app:com.example.chat"]), chat]);
    // The server outside the Wrap Up, plus the Wrap Up's server and helper. The app that stayed open gave nothing back.
    T(@"refused: memory back leaves out the app that did not quit", @(512 * MB + 364 * MB), @(end.memoryBack));
    T(@"refused: the fix is not done, and the end note says one is blocked", @"4 of 5 fixes done yes", [NSString stringWithFormat:@"%@ %@", end.endTitle, YN([end.endNote containsString:@"1 blocked"])]);
}

#pragma mark - The controller

@interface MMWindowController (WindowTest)
- (void)take:(MMSnapshot *)s;
@end

/// Runs the main run loop, where the controller hands over its models, until the block says yes.
static BOOL Spin(NSTimeInterval most, BOOL (^until)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:most];
    while (!until()) {
        if (end.timeIntervalSinceNow < 0) return NO;
        if (![NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]) usleep(2000);
    }
    return YES;
}

/// A snapshot of the world as it is now, with a generation of its own.
static MMSnapshot *SnapshotAt(uint64_t generation) {
    TSample *sample = [TSample new]; sample.at = NSDate.date; sample.generation = generation; sample.procs = gProcs; sample.children = gChildren;
    MMPower *power = MMPowerFrom(@{@"diskTotal": @(kDiskTotal), @"diskFree": @(kDiskFree), @"memoryPressure": @1, @"onAC": @YES});
    MMFacts *facts = [MMFacts generation:generation sample:(MMSample *)sample power:power agents:(NSArray *)gAgents sessions:(NSArray *)gSessions
                               worktrees:(NSArray *)gTrees clutter:@[] git:(NSDictionary *)gGit];
    MMSnapshot *s = [MMSnapshot snapshotFrom:facts experts:MMExperts() reviews:nil holds:nil];
    [s setValue:WorldHour() forKey:@"history"];
    WSource *src = [WSource new]; src.facts = s.facts;
    MMGraph.shared.source = src;
    return s;
}

static void Controller(void) {
    World();
    dispatch_queue_t window = MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED), fixes = MMQueue(@"core", @"fix-everything", QOS_CLASS_USER_INITIATED);
    void (^settle)(void) = ^{ dispatch_sync(window, ^{}); };
    MMWindowController *c = [MMWindowController new];
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };
    BOOL (^ended)(void) = ^BOOL { return !c.running && models.lastObject.run && !models.lastObject.run.running; };

    // Open and closed, and the order of generations.
    [c take:SnapshotAt(1)];
    settle();
    Spin(0.2, ^BOOL { return models.count > 0; });
    T(@"controller: closed, a snapshot builds no model", @"0 no", [NSString stringWithFormat:@"%lu %@", (unsigned long)models.count, YN(c.model != nil)]);
    [c setOpen:YES];
    [c take:SnapshotAt(2)];
    BOOL got = Spin(20, ^BOOL { return models.count == 1; });
    T(@"controller: open, a snapshot gives one model on main, with fixes to run", @"yes 2 yes", [NSString stringWithFormat:@"%@ %llu %@", YN(got),
      (unsigned long long)models.lastObject.generation, YN(models.lastObject.fixCount > 0 && c.model == models.lastObject)]);
    [c take:SnapshotAt(2)]; [c take:SnapshotAt(1)];
    settle();
    Spin(0.3, ^BOOL { return models.count > 1; });
    T(@"controller: a generation it already holds, or an older one, is not built again", @"1", @(models.count));
    T(@"controller: with no run under way, nothing waits for one", @"no no", [NSString stringWithFormat:@"%@ %@", YN(c.running), YN([c stopRunThen:^{}])]);

    // Two presses back to back. The runner's queue is held, so the first run cannot have begun when the second lands.
    dispatch_semaphore_t hold = dispatch_semaphore_create(0);
    dispatch_async(fixes, ^{ dispatch_semaphore_wait(hold, DISPATCH_TIME_FOREVER); });
    [c windowRunFixEverything]; [c windowRunFixEverything];
    settle();
    BOOL busy = c.running;
    dispatch_semaphore_signal(hold);
    got = Spin(60, ended);
    // A second runner would wait on the runner's queue behind the first. Let whatever is queued there run out.
    dispatch_sync(fixes, ^{});
    settle();
    Spin(0.3, ^BOOL { return NO; });
    NSUInteger ranOnce = gRan.count;
    T(@"controller: two presses back to back make one run, and each thing is acted on once", @"yes yes yes 0", [NSString stringWithFormat:@"%@ %@ %@ %lu",
      YN(busy), YN(got), YN(ranOnce > 0), (unsigned long)(ranOnce - [NSSet setWithArray:gRan].count)]);
    T(@"controller: the run's end reaches the window", @"5 fixes done", models.lastObject.run.endTitle);

    // The plan that was run is spent: a press on the same snapshot runs nothing.
    [c windowRunFixEverything];
    settle();
    Spin(0.3, ^BOOL { return NO; });
    T(@"controller: after a run, a press on the snapshot from before it runs nothing", @"no 0", [NSString stringWithFormat:@"%@ %lu", YN(c.running), (unsigned long)(gRan.count - ranOnce)]);

    // A snapshot built since the run ended can be run. Stop before the first step, and whoever waits is told at the end.
    [c take:SnapshotAt(3)];
    Spin(20, ^BOOL { return models.lastObject.generation == 3; });
    dispatch_async(fixes, ^{ dispatch_semaphore_wait(hold, DISPATCH_TIME_FOREVER); });
    [c windowRunFixEverything];
    __block BOOL told = NO, toldOnMain = NO;
    BOOL waits = [c stopRunThen:^{ told = YES; toldOnMain = NSThread.isMainThread; }];
    settle();
    BOOL early = told;
    dispatch_semaphore_signal(hold);
    got = Spin(60, ^BOOL { return told && ended() && models.lastObject.generation == 3 && models.lastObject.run.endTitle.length; });
    MMWindowRun *stopped = models.lastObject.run;
    T(@"controller: a stop asked while a run waits ends it before its first step", @"yes yes 0 0", [NSString stringWithFormat:@"%@ %@ %ld %lu",
      YN(waits), YN(got), (long)stopped.done, (unsigned long)(gRan.count - ranOnce)]);
    T(@"controller: what waited for the run is told on main, and only once it ended", @"no yes yes", [NSString stringWithFormat:@"%@ %@ %@", YN(early), YN(told), YN(toldOnMain)]);
    T(@"controller: the end note counts what was stopped", @"yes", YN([stopped.endNote containsString:@"you stopped"]));

    // The removal card writes Core's pref, never an expert's mode, and a choice that is not one of the three is ignored.
    MMMode before = MMModeFor(@"noonoo");
    [c windowSetRule:MMWindowRemovalRuleID picked:MMRemovalDelete];
    settle();
    NSString *picked = MMRemovalChoiceName(MMRemovalChoiceNow());
    [c windowSetRule:MMWindowRemovalRuleID picked:7];
    [c windowSetRule:MMWindowRemovalRuleID picked:-1];
    settle();
    T(@"controller: a press on the removal card sets the choice, and a number that is no choice changes nothing", @"delete delete yes", [NSString stringWithFormat:@"%@ %@ %@",
      picked, MMRemovalChoiceName(MMRemovalChoiceNow()), YN(MMModeFor(@"noonoo") == before)]);
    Spin(20, ^BOOL { return models.lastObject.settings.rules.lastObject.picked == MMRemovalDelete; });
    T(@"controller: the next model shows the pick", @"removal 2", [NSString stringWithFormat:@"%@ %ld", models.lastObject.settings.rules.lastObject.ruleID,
      (long)models.lastObject.settings.rules.lastObject.picked]);
    [c windowSetRule:MMWindowRemovalRuleID picked:MMRemovalSmart];
    settle();
    MMSetPref(MMRemovalKey, nil);

    // Closed again: the model goes, and a new snapshot builds nothing.
    NSUInteger had = models.count;
    [c setOpen:NO];
    [c take:SnapshotAt(4)];
    settle();
    Spin(0.3, ^BOOL { return NO; });
    T(@"controller: closing lets the model go and ends the building", @"no 0", [NSString stringWithFormat:@"%@ %lu", YN(c.model != nil), (unsigned long)(models.count - had)]);
}
