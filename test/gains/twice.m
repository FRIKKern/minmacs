// What came back is counted once per process, in the gains log. Included by gains.m, before main.
// A fix that quits an app counts the tree of the app, and a dev server that runs in it is in that tree. When the
// server outlives the quit and a stop of it runs after, as in one Fix Everything, the server's memory came back once.
// gains.sh runs this mode in a home of its own, so the counts of the main checks hold. The "app" is a fixture
// process with one child, the "server"; the fake quit signals nothing, and only the stop ends the child.

/// An app finding as MinMacs makes it, for the fixture process at k.
static MMFinding *AppFinding(MMProcKey k) {
    return [MMFinding expert:gExpert kind:@"app" stableKey:[NSString stringWithFormat:@"fixture-app-%d", k.pid] build:^(MMFindingBuilder *b) {
        b.title = [NSString stringWithFormat:@"fixture app %d", k.pid];
        b.instanceKey = MMProcKeyString(k); b.procs = @[V(k)]; b.keepReasons = @[]; b.facts = @{};
        MMCost c = {0}; c.ramBytes = 1; c.cpuPercent = -1; b.cost = c;
        b.proposal = [MMProposal verb:@"quit" title:@"Quit" reversibility:MMReversibleRelaunch];
    }];
}

/// Starts the fixture with mb megabytes and one child with childMB, and waits until both footprints show them.
static MMProcKey SpawnWithChild(int mb, int childMB, MMProcKey *child) {
    pid_t pid = 0;
    char m[16], c[16]; snprintf(m, sizeof m, "%d", mb); snprintf(c, sizeof c, "%d", childMB);
    char *argv[] = { (char *)gFixture.fileSystemRepresentation, m, "60", c, NULL };
    *child = (MMProcKey){0, 0};
    if (posix_spawn(&pid, gFixture.fileSystemRepresentation, NULL, NULL, argv, environ) != 0) return (MMProcKey){0, 0};
    MMProcKey k = { pid, 0 };
    for (int i = 0; i < 50; i++) {
        usleep(100000);
        MMSample *s = MMSenses.shared.sampleNow;
        k = KeyOf(pid);
        NSNumber *kid = [s childrenOf:pid].firstObject;
        if (kid) *child = KeyOf(kid.intValue);
        if ([s proc:pid].footprint >= ((uint64_t)mb << 20) && kid && [s proc:kid.intValue].footprint >= ((uint64_t)childMB << 20)) break;
    }
    [gStarted addObject:V(k)];
    return k;
}

static void Twice(void) {
    MMGains *g = MMGains.shared;
    NSString *err = nil;
    MMProcKey server = {0, 0};
    MMProcKey app = SpawnWithChild(24, 40, &server);
    T(@"gains twice: the fixture app and the server under it run", @"yes yes", [NSString stringWithFormat:@"%@ %@",
      YN(MMProcAlive(app)), YN(server.pid > 0 && MMProcAlive(server))]);

    // The quit counts its whole tree, the server in it too. The fake quit ends nothing, so the server still runs.
    MMUndoRecord *quit = Run(Act(@"quit", AppFinding(app)), @"manual", &err);
    MMGain *q = [g gain:quit.rid];
    T(@"gains twice: the quit counts the app's tree, the server under it too", @"yes", YN(q && q.memoryBytes >= (64ull << 20)));
    T(@"gains twice: the server outlived the quit", @"yes", YN(MMProcAlive(server)));

    // The stop of that server ends it, and its memory was counted already.
    MMUndoRecord *stop = Run(Act(@"stop", ServerFinding(server, nil)), @"manual", &err);
    MMGain *s = [g gain:stop.rid];
    T(@"gains twice: the stop finished and wrote a row", @"yes", YN(stop.state == MMUndoDone && s != nil));
    T(@"gains twice: a process the quit counted counts no more", @"0", @(s.memoryBytes));
    NSDictionary *sum = [g summary:1 now:NSDate.date];
    T(@"gains twice: today's memory back is the union, the server once", @(q.memoryBytes), sum[@"today"][@"memoryBack"]);

    // A process that came after counts as ever.
    MMProcKey fresh = Spawn(16);
    MMGain *f = [g gain:Run(Act(@"stop", ServerFinding(fresh, nil)), @"manual", &err).rid];
    T(@"gains twice: a process no row counted counts in full", @"yes", YN(f.memoryBytes >= (16ull << 20)));
}
