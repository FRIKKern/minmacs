// The window's "+N memory" before a press, and what a run plans and gets back, with a server under an app in two
// fixes: each process counts once. Included by window.m, before main. The world is performance's OverlapWorld.

static void WindowOverlap(void) {
    OverlapWorld();
    gRan = [NSMutableArray new]; gNowKept = [NSMutableSet new]; gRefuses = [NSMutableSet new];
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, nil);
    uint64_t sum = 0;
    for (MMWindowFix *f in m.fixes) if (!f.needsYou) sum += f.memoryBack;
    T(@"overlap: each fix in the dock keeps its own memory back", @"1400", @(sum / MB));
    T(@"overlap: the window's memory back before a press counts the server under Terminal once", @"1150", @(m.memoryBack / MB));
    T(@"overlap: window --json gives the same", @(m.memoryBack), m.json[@"fixEverything"][@"memoryBack"]);

    // A run: the quit counts Terminal's tree, the server in it too, and the stop after counts that server no more.
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    __block MMWindowRun *end = nil;
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    runner.onProgress = ^(MMWindowRun *r) { if (!r.running) { end = r; dispatch_semaphore_signal(ended); } };
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"overlap: the run ends", @"yes", @"no"); return; }
    T(@"overlap: the run planned the union", @"1150", @(end.memoryPlanned / MB));
    T(@"overlap: what came back counts each process once", @"1150", @(end.memoryBack / MB));
    // The home is shared with the other modes, so read this run's own rows.
    uint64_t logged = 0;
    for (MMFixResult *x in runner.results) if (x.rid) logged += [MMGains.shared gain:x.rid].memoryBytes;
    T(@"overlap: and the gains log's rows of the run say the same", @"1150", @(logged / MB));
}
