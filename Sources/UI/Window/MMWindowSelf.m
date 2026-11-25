// The row of MinMacs itself, MMWindowModel.h. The owner: "We must see MinMacs itself in MinMacs as a process it takes
// seriously." So it is a row of Apps and helpers like any app of its size, with its memory and CPU, and its words judge
// it against its own budgets, docs/2.0/BENCH.md's, with no special pleading. It never goes with Fix Everything: it is
// the app that watches, and its line says so.
// Every number comes from one report, MMSelfCost.h's, which `minmacs self` prints too. This file holds no Core type:
// the report is plain values, so the feed and the render's made-up days make the row the same way.
#import "UI/Window/MMWindowModel.h"

NSString *const MMWindowSelfKey = @"self:minmacs";
NSString *const MMWindowSelfStays = @"It is the app that watches. Its cost is checked against its budget.";

static NSDictionary *Part(NSDictionary *r, NSString *key) { return [r[key] isKindOfClass:NSDictionary.class] ? r[key] : nil; }
static double Num(NSDictionary *d, NSString *key, double none) { return [d[key] isKindOfClass:NSNumber.class] ? [d[key] doubleValue] : none; }
static NSString *Str(id v) { return [v isKindOfClass:NSString.class] && [v length] ? v : nil; }

// A number and its unit never part at a line's end: they are joined by a no-break space, so a story's value that
// wraps never leaves "45" on one line and "MB" on the next.
static NSString *const kJoin = @"\u00a0";
static NSString *Joined(NSString *t) { return [t stringByReplacingOccurrencesOfString:@" " withString:kJoin]; }
/// A percent of one core as `minmacs self` says it: two decimals under 10.
static NSString *Pct(double v) { return [NSString stringWithFormat:v < 10 ? @"%.2f%@%%" : @"%.1f%@%%", v, kJoin]; }
/// A budget as it was set: "0.3", "1".
static NSString *Budget(double v) { return [NSString stringWithFormat:@"%g", v]; }
static NSString *Wakes(double v) { return [NSString stringWithFormat:@"%.2f", v]; }
static NSString *Mem(double bytes) { return Joined(MMWindowSizeText((uint64_t)MAX(bytes, 0), NO)); }

NSArray<NSString *> *MMWindowSelfOver(NSDictionary *report) {
    NSArray *over = [report[@"over"] isKindOfClass:NSArray.class] ? report[@"over"] : @[];
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSString *k in @[@"cpuSinceLaunch", @"idleWakeupsSinceLaunch", @"memoryNow"]) if ([over containsObject:k]) [out addObject:k];
    return out;
}

NSString *MMWindowSelfOverText(NSDictionary *report, NSString *over) {
    NSDictionary *all = Part(report, @"sinceLaunch"), *mem = Part(report, @"memory"), *b = Part(report, @"budgets");
    if ([over isEqualToString:@"cpuSinceLaunch"])
        return [NSString stringWithFormat:@"over its CPU budget: %@ against %@\u00a0%%", Pct(Num(all, @"cpuPercent", 0)), Budget(Num(b, @"cpuPercent", 0.3))];
    if ([over isEqualToString:@"idleWakeupsSinceLaunch"])
        return [NSString stringWithFormat:@"over its wakeup budget: %@ a second against %@", Wakes(Num(all, @"idleWakeupsPerSecond", 0)), Budget(Num(b, @"idleWakeupsPerSecond", 1))];
    if ([over isEqualToString:@"memoryNow"])
        return [NSString stringWithFormat:@"over its memory budget: %@ against %@", Mem(Num(mem, @"footprintBytes", 0)), Mem(Num(b, @"memoryBytes", 45.0 * 1048576))];
    return nil;
}

/// "CPU", "wakeup" and "memory": what each budget is called where several are named at once.
static NSString *BudgetName(NSString *over) {
    return [over hasPrefix:@"cpu"] ? @"CPU" : [over hasPrefix:@"idle"] ? @"wakeup" : @"memory";
}

/// The row's own line: "Within budget", one budget over in full, or the budgets over by name.
static NSString *Verdict(NSDictionary *report, NSArray<NSString *> *over) {
    if (!over.count) return @"within budget";
    if (over.count == 1) return MMWindowSelfOverText(report, over[0]);
    NSMutableArray *names = [NSMutableArray new];
    for (NSString *o in over) [names addObject:BudgetName(o)];
    NSString *last = names.lastObject;
    [names removeLastObject];
    return [NSString stringWithFormat:@"over its %@ and %@ budgets", [names componentsJoinedByString:@", "], last];
}

MMWindowRow *MMWindowSelfRow(NSDictionary *report, NSArray *hour, double cpuNow) {
    NSDictionary *now = Part(report, @"now"), *all = Part(report, @"sinceLaunch"), *mem = Part(report, @"memory");
    NSDictionary *disk = Part(report, @"disk"), *b = Part(report, @"budgets");
    NSArray<NSString *> *over = MMWindowSelfOver(report);
    MMWindowRow *row = [MMWindowRow new];
    row.key = MMWindowSelfKey; row.kind = MMWindowApp; row.own = YES;
    row.iconHint = @"no.guerrilla.minmacs"; row.name = @"MinMacs";
    row.bytes = (uint64_t)MAX(Num(mem, @"footprintBytes", 0), 0);
    // Its CPU now: the rate the report measured since the build before, else the pass's own reading of this process.
    row.cpuPercent = now ? Num(now, @"cpuPercent", -1) : cpuNow;
    row.hour = hour;
    row.attention = over.count > 0;
    // One quiet word, short enough to stand beside its CPU and hour in the list, rule 8: its line says the rest.
    row.state = over.count ? @"over" : @"in budget";
    row.stateInFull = over.count ? @"over budget" : @"within budget";
    // Calm when it is within its budgets and uses next to no CPU, as an app that does is.
    row.quiet = !over.count && row.cpuPercent >= 0 && row.cpuPercent < 0.5;

    NSMutableArray<MMWindowFact *> *facts = [NSMutableArray new];
    // The line: it stays, and why. Fix Everything never ends it: MinMacs cannot quit itself from its own button.
    MMWindowFact *stays = [MMWindowFact label:@"Stays" value:MMWindowSelfStays];
    [facts addObject:stays];
    NSString *verdict = Verdict(report, over);
    MMWindowFact *judged = [MMWindowFact label:@"Budget" value:verdict];
    judged.phrase = verdict;
    [facts addObject:judged];
    // Each budget beside what it is measured against.
    double cpuAll = Num(all, @"cpuPercent", -1);
    if (cpuAll >= 0) {
        NSString *v = [NSString stringWithFormat:@"%@ since launch, against %@\u00a0%%", Pct(cpuAll), Budget(Num(b, @"cpuPercent", 0.3))];
        if (now) v = [NSString stringWithFormat:@"%@ now, %@", Pct(Num(now, @"cpuPercent", 0)), v];
        [facts addObject:[MMWindowFact label:@"CPU" value:v]];
    }
    double wakeAll = Num(all, @"idleWakeupsPerSecond", -1);
    if (wakeAll >= 0) {
        NSString *v = [NSString stringWithFormat:@"%@ a second since launch, against %@", Wakes(wakeAll), Budget(Num(b, @"idleWakeupsPerSecond", 1))];
        if (now) v = [NSString stringWithFormat:@"%@ a second now, %@", Wakes(Num(now, @"idleWakeupsPerSecond", 0)), v];
        [facts addObject:[MMWindowFact label:@"Wakeups" value:v]];
    }
    if (mem) [facts addObject:[MMWindowFact label:@"Memory" value:[NSString stringWithFormat:@"%@ now, %@ at most, against %@",
                               Mem(Num(mem, @"footprintBytes", 0)), Mem(Num(mem, @"peakBytes", 0)), Mem(Num(b, @"memoryBytes", 45.0 * 1048576))]]];
    // The tools it ran, such as git: the kernel counts a child's CPU once the child has ended.
    double childSecs = Num(all, @"childCpuSeconds", -1);
    if (childSecs >= 0)
        [facts addObject:[MMWindowFact label:@"Tools it ran" value:[NSString stringWithFormat:@"%@ CPU, %.1f\u00a0s in all, each counted once it ended",
                                                                    Pct(Num(all, @"childCpuPercent", 0)), childSecs]]];
    double written = Num(disk, @"writtenBytes", -1);
    if (written >= 0) [facts addObject:[MMWindowFact label:@"Disk written" value:[Joined(MMWindowSizeText((uint64_t)written, YES)) stringByAppendingString:@" since launch"]]];
    NSString *version = Str(report[@"version"]), *build = Str(report[@"build"]);
    if (version) [facts addObject:[MMWindowFact label:@"Version" value:build ? [NSString stringWithFormat:@"%@, build %@", version, build] : version]];
    double up = Num(report, @"runningSeconds", -1);
    if (up >= 0) [facts addObject:MMWindowFactUp(up)];
    row.facts = facts;
    return row;
}

void MMWindowAddSelf(MMWindowModel *m, NSDictionary *report, NSArray *hour, double cpuNow) {
    if (!report) return;
    m.own = report;
    MMWindowRow *row = MMWindowSelfRow(report, hour, cpuNow);
    for (MMWindowGroup *g in m.memoryGroups) {
        if (![g.key isEqualToString:@"apps"]) continue;
        NSMutableArray<MMWindowRow *> *rows = [NSMutableArray arrayWithObject:row];
        for (MMWindowRow *r in g.rows) if (![r.key isEqualToString:MMWindowSelfKey]) [rows addObject:r];
        // Where an app of its size would go, by the group's own order: never held at the foot.
        g.rows = [rows sortedArrayUsingComparator:^NSComparisonResult(MMWindowRow *a, MMWindowRow *b) { return MMWindowRowOrder(a, b); }];
    }
    // Its memory counts in the ring's apps slice like any app's. The ring called it other until now, so it moves.
    MMWindowSlice *apps = nil, *other = nil;
    for (MMWindowSlice *x in m.ring.memory) {
        if ([x.group isEqualToString:@"apps"]) apps = x;
        if ([x.group isEqualToString:@"other"]) other = x;
    }
    if (apps && other) { uint64_t take = MIN(row.bytes, other.bytes); other.bytes -= take; apps.bytes += take; }
}
