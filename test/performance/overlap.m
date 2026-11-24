// Fix Everything's memory back with each process once. Included by performance.m, before main, and so by window.m.
// A stop of a dev server and a quit of the app that server rolls up into, such as Terminal, are two fixes. Each shows
// its own memory back, and the app's holds the server's, so their sum counted the server twice. The total is the
// union of the processes the fixes would end, each once: the servers' trees, then the app less what rolls up into it.

static const pid_t kOverlapApp = 70501, kOverlapServer = 70502, kOverlapChild = 70503, kOverlapOther = 70504;

/// Terminal, 800 MB of its own, holds a dev server of 200 MB whose watcher child holds 50: the app's cost is
/// 1050 MB, as MinMacs rolls up by parent. A second server, 100 MB, runs outside every app.
static void OverlapWorld(void) {
    Reset();
    Proc(kOverlapApp, 800 * MB); Proc(kOverlapServer, 200 * MB); Proc(kOverlapChild, 50 * MB); Proc(kOverlapOther, 100 * MB);
    gProcs[@(kOverlapServer)].ppid = kOverlapApp; gProcs[@(kOverlapChild)].ppid = kOverlapServer;
    gChildren[@(kOverlapApp)] = @[@(kOverlapServer)]; gChildren[@(kOverlapServer)] = @[@(kOverlapChild)];
    gFindings[@"locohost"] = @[
        Finding(@"locohost", @"server", @"term#dev", @":5173 vite in Terminal", Dir(@"term"), kOverlapServer, 250 * MB, 0, P(@"stop", MMReversibleRestart), nil),
        Finding(@"locohost", @"server", @"other#dev", @":4000 other", Dir(@"other"), kOverlapOther, 100 * MB, 0, P(@"stop", MMReversibleRestart), nil)];
    gFindings[@"minmacs"] = @[
        Finding(@"minmacs", @"app", @"com.apple.Terminal", @"Terminal", nil, kOverlapApp, 1050 * MB, 0, P(@"quit", MMReversibleRelaunch), nil)];
}

static MMPerformanceFix *FixOfKind(MMPerformance *p, NSString *kind) {
    for (MMPerformanceFix *f in p.fixes) if ([f.kind isEqualToString:kind]) return f;
    return nil;
}

static void PerformanceOverlap(void) {
    OverlapWorld();
    MMSnapshot *s = Snapshot(1000 * GB, 300 * GB, 1);
    __block MMPerformance *p;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ p = [MMPerformance from:s history:Hour(8 * GB) lookBack:nil]; });
    MMPerformanceFix *stop = FixOfKind(p, @"stop"), *quit = FixOfKind(p, @"quit");
    T(@"overlap: the stop and the quit are both fixes, each with its own memory back", @"350 1050",
      [NSString stringWithFormat:@"%llu %llu", stop.memoryBack / MB, quit.memoryBack / MB]);
    // The union: both servers' trees, 250 and 100, and the app's 1050 less the 250 of the server that rolls up into it.
    T(@"overlap: the total counts the server under the app once, the union of the pids", @"1150", @(p.memoryBackOnce / MB));
    T(@"overlap: and is less than the sum of the fixes", @"yes", YN(p.memoryBackOnce < stop.memoryBack + quit.memoryBack));
    T(@"overlap: --json carries it", @(p.memoryBackOnce), p.json[@"memoryBackOnce"]);

    // With no overlap the total is the sum, as in the busy world.
    Busy();
    MMSnapshot *b = Snapshot(1000 * GB, 300 * GB, 1);
    __block MMPerformance *q;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ q = [MMPerformance from:b history:Hour(8 * GB) lookBack:nil]; });
    uint64_t sum = 0;
    for (MMPerformanceFix *f in q.fixes) if (!f.needsYou) sum += f.memoryBack;
    T(@"overlap: with no process in two fixes the total is the sum", @(sum / MB), @(q.memoryBackOnce / MB));
}
