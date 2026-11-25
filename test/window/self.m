// MinMacs itself as a row of the window, judged against its own budgets. Included by window.m, before main.
// The owner: "We must see MinMacs itself in MinMacs as a process it takes seriously." The reads are fixtures in the
// shape proc_pid_rusage gives, made into a report by Core's MMSelfReportWith, the function `minmacs self` prints from.
// No app starts: this process reads only its own accounting, once, through MMSelfOnBuild.

/// Act's own check before any signal, Sources/Core/Act/MMAct.m.
NSString *MMStopWhyNot(MMProcKey key);

static MMSelfRead SelfRead(double cpu, double wakes, uint64_t footprint, double running) {
    MMSelfRead r = {0};
    r.ok = YES; r.cpu = cpu; r.childCPU = 12.5; r.idleWakeups = wakes; r.interruptWakeups = 3 * running;
    r.footprint = footprint; r.peak = footprint + 9 * MB; r.read = 212000000; r.written = 14000000; r.logicalWritten = 18000000;
    r.running = running;
    return r;
}

/// A report of two reads 5 seconds apart, after `up` seconds, with CPU and wakeups since launch as given.
static NSDictionary *SelfReport(double cpuPercent, double wakesPerSecond, uint64_t footprint) {
    double up = 7200;
    MMSelfRead a = SelfRead(cpuPercent * (up - 5) / 100, wakesPerSecond * (up - 5), footprint, up - 5);
    MMSelfRead b = SelfRead(cpuPercent * up / 100, wakesPerSecond * up + 2, footprint, up);
    return MMSelfReportWith(4242, a, b, 5, @"2.0.0", @"412");
}

static MMWindowModel *SelfModel(MMSnapshot *s, MMPerformance *p, NSDictionary *own) {
    MMWindowExtras *x = [MMWindowExtras new];
    x.own = own;
    return MMWindowModelFrom(s, p, x);
}

/// The words with their no-break spaces read as spaces, so a check reads as the window does.
static NSString *Plain(NSString *t) { return [t stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "]; }

static id RoundTrip(id v) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:v options:NSJSONWritingSortedKeys error:nil];
    return d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
}

static void SelfRow(void) {
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);

    // Within every budget.
    NSDictionary *calm = SelfReport(0.21, 0.35, 38 * MB);
    MMWindowModel *m = SelfModel(s, p, calm);
    MMWindowRow *row = [m row:MMWindowSelfKey];
    MMWindowGroup *apps = m.memoryGroups[2];
    NSUInteger at = [apps.rows indexOfObject:row];
    T(@"self: the row of MinMacs is in Apps and helpers, with its name, icon and memory", @"apps MinMacs no.guerrilla.minmacs app 38",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %llu", apps.key, row.name, row.iconHint, MMWindowKindName(row.kind), row.bytes / MB]);
    BOOL bySize = at != NSNotFound && (at == 0 || MMWindowRowOrder(apps.rows[at - 1], row) == NSOrderedAscending)
                  && (at + 1 >= apps.rows.count || MMWindowRowOrder(row, apps.rows[at + 1]) == NSOrderedAscending);
    T(@"self: it sorts by its size among the apps, as any app row", @"yes", YN(bySize));
    T(@"self: its CPU is the rate now of the report", @"0.21", [NSString stringWithFormat:@"%.2f", row.cpuPercent]);
    T(@"self: within budget, a calm word and no mark", @"in budget within budget no no yes",
      [NSString stringWithFormat:@"%@ %@ %@ %@ %@", row.state, Plain([row factLabelled:@"Budget"].value), YN(row.attention), YN(row.needsYou), YN(row.quiet)]);
    T(@"self: it stays, and says why", @"Stays. It is the app that watches. Its cost is checked against its budget.",
      [NSString stringWithFormat:@"%@ %@", row.fate.lead, row.fate.note]);

    // Over each budget, said plainly, and marked as a row that needs attention.
    NSDictionary *cases = @{@"cpu": @[SelfReport(0.92, 0.35, 38 * MB), @"over its CPU budget: 0.92 % against 0.3 %"],
                            @"wakeups": @[SelfReport(0.21, 1.42, 38 * MB), @"over its wakeup budget: 1.42 a second against 1"],
                            @"memory": @[SelfReport(0.21, 0.35, 58 * MB), @"over its memory budget: 58 MB against 45 MB"],
                            @"all": @[SelfReport(0.92, 1.42, 58 * MB), @"over its CPU, wakeup and memory budgets"]};
    for (NSString *k in @[@"cpu", @"wakeups", @"memory", @"all"]) {
        MMWindowRow *r = [SelfModel(s, p, cases[k][0]) row:MMWindowSelfKey];
        T([NSString stringWithFormat:@"self: over its %@ budget, the word, the line and the mark say so", k],
          [NSString stringWithFormat:@"over|%@|yes|no|no", cases[k][1]],
          [NSString stringWithFormat:@"%@|%@|%@|%@|%@", r.state, Plain([r factLabelled:@"Budget"].value), YN(r.attention), YN(r.needsYou), YN(r.quiet)]);
    }
    // A rate now over a few seconds counts the window that draws it, so it is shown and not judged.
    NSDictionary *busyNow = MMSelfReportWith(4242, SelfRead(10, 100, 38 * MB, 7195), SelfRead(10.5, 100, 38 * MB, 7200), 5, @"2.0.0", nil);
    T(@"self: a busy few seconds now is shown, not judged", @"in budget yes",
      [NSString stringWithFormat:@"%@ %@", [SelfModel(s, p, busyNow) row:MMWindowSelfKey].state, YN([busyNow[@"over"] containsObject:@"cpuNow"])]);

    // It never goes with Fix Everything: no fix names it, and Act never stops MinMacs.
    MMWindowModel *over = SelfModel(s, p, cases[@"all"][0]);
    BOOL named = NO;
    for (MMPerformanceFix *f in p.fixes) for (NSString *k in f.rows) if ([k isEqualToString:MMWindowSelfKey]) named = YES;
    for (MMWindowFix *f in over.fixes) if ([f.key isEqualToString:MMWindowSelfKey]) named = YES;
    MMProcKey me = {getpid(), 0};
    T(@"self: Fix Everything never names it, and Act never stops MinMacs", @"no no MinMacs never signals itself",
      [NSString stringWithFormat:@"%@ %@ %@", YN(named), YN([over row:MMWindowSelfKey].inFix), MMStopWhyNot(me)]);
    T(@"self: Fix Everything's count and memory are the same with the row as without", @"yes",
      YN(over.fixCount == SelfModel(s, p, nil).fixCount && over.memoryBack == SelfModel(s, p, nil).memoryBack));

    // Its memory counts in the ring's apps slice, from what the ring called other.
    MMWindowModel *none = SelfModel(s, p, nil);
    uint64_t appsWith = 0, appsWithout = 0, otherWith = 0, otherWithout = 0;
    // The ring's rest is the slice of macOS and background, rest.m, where its categories stand.
    BOOL (^rest)(NSString *) = ^BOOL(NSString *g) { return [g isEqualToString:@"other"] || [g isEqualToString:MMWindowRestGroup]; };
    for (MMWindowSlice *x in m.ring.memory) { if ([x.group isEqualToString:@"apps"]) appsWith = x.bytes; if (rest(x.group)) otherWith = x.bytes; }
    for (MMWindowSlice *x in none.ring.memory) { if ([x.group isEqualToString:@"apps"]) appsWithout = x.bytes; if (rest(x.group)) otherWithout = x.bytes; }
    T(@"self: its memory counts in the ring's apps slice, taken from other", @"38 38",
      [NSString stringWithFormat:@"%llu %llu", (appsWith - appsWithout) / MB, (otherWithout - otherWith) / MB]);
    T(@"self: a model with no report, as a cold CLI makes, has no row of MinMacs", @"no null",
      [NSString stringWithFormat:@"%@ %@", YN([none row:MMWindowSelfKey] != nil), none.json[@"self"] == NSNull.null ? @"null" : @"a report"]);

    // The story's facts, each from the report.
    NSMutableArray *story = [NSMutableArray new];
    for (MMWindowFact *f in [m row:MMWindowSelfKey].storyFacts) [story addObject:[NSString stringWithFormat:@"%@: %@", f.label, Plain(f.value)]];
    T(@"self: the story tells its budget, CPU, wakeups, memory, the tools it ran, disk written, version and how long it ran",
      @"Budget: within budget | CPU: 0.21 % now, 0.21 % since launch, against 0.3 % | Wakeups: 0.75 a second now, 0.35 a second since launch, against 1 | "
       "Memory: 38 MB now, 47 MB at most, against 45 MB | Tools it ran: 0.17 % CPU, 12.5 s in all, each counted once it ended | "
       "Disk written: 14 MB since launch | Version: 2.0.0, build 412 | Running: 2 h",
      [story componentsJoinedByString:@" | "]);

    // --json carries the report `minmacs self --json` prints, whole, and the row's numbers are its numbers.
    NSDictionary *j = RoundTrip(m.json);
    NSDictionary *rowJ = nil;
    for (NSDictionary *g in j[@"memory"]) for (NSDictionary *r in g[@"rows"]) if ([r[@"key"] isEqual:MMWindowSelfKey]) rowJ = r;
    T(@"self: window --json's self is the report minmacs self --json prints", @"yes", YN([j[@"self"] isEqual:RoundTrip(calm)]));
    T(@"self: and its row's memory and CPU are the report's", @"yes yes yes",
      [NSString stringWithFormat:@"%@ %@ %@", YN([rowJ[@"bytes"] isEqual:j[@"self"][@"memory"][@"footprintBytes"]]),
       YN(fabs([rowJ[@"cpuPercent"] doubleValue] - [j[@"self"][@"now"][@"cpuPercent"] doubleValue]) < 0.06), YN([rowJ[@"own"] boolValue])]);

    // This process's own read, as a build makes it: one proc_pid_rusage, no now without an earlier read 1 s old or more.
    NSDictionary *first = MMSelfOnBuild(), *again = MMSelfOnBuild();
    T(@"self: a build's own read names this process, its version and budgets, and gives no rate it has not measured", @"yes yes no no",
      [NSString stringWithFormat:@"%@ %@ %@ %@", YN([first[@"pid"] intValue] == getpid()), YN([first[@"version"] length] > 0 && [first[@"budgets"][@"memoryBytes"] unsignedLongLongValue] == 45 * MB),
       YN(first[@"now"] != nil), YN(again[@"now"] != nil)]);
    T(@"self: the report has the keys minmacs self --json has had, and judges memory too", @"budgets disk memory now over pid runningSeconds sinceLaunch",
      [[[calm.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT (SELF IN %@)", @[@"version", @"build"]]] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);

    // Its own ring of the hour, kept by the graph build from this process's sample.
    MMHistory *h = [MMHistory new];
    MMHistoryTreeSample *t = [MMHistoryTreeSample new];
    t.kind = MMHistorySelf; t.key = (MMProcKey){getpid(), 1}; t.cpuPercent = 0.2; t.footprint = 38 * MB; t.label = @"MinMacs";
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    [h noteTrees:@[t] at:now];
    MMHistoryView *v = [h viewAt:now];
    T(@"self: the hour keeps a ring of MinMacs itself, apart from the agents and servers", @"self 38 0",
      [NSString stringWithFormat:@"%@ %.0f %lu", MMHistoryKindName(v.own.kind), [v.own minuteAt:59].megabytes, (unsigned long)v.trees.count]);
}
