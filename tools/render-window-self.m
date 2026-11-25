// MinMacs itself as a row. The owner wrote: "We must see MinMacs itself in MinMacs as a process it takes seriously."
// These checks hold the made-up days "self", "self-cpu", "self-memory" and "self-wakeups": the row of MinMacs among the
// apps with its icon, memory, CPU and hour, its words judged against its own budgets, its story, and VoiceOver.
// tools/render.m includes this file after render-window-agents.m, whose helpers it uses. It is not built on its own.

static NSArray<NSArray *> *WindowSelfShots(void) {
    return @[@[@"self", @"main", @""], @[@"self", @"self-within", MMWindowSelfKey],
             @[@"self-cpu", @"self-over-cpu", MMWindowSelfKey], @[@"self-memory", @"self-over-memory", MMWindowSelfKey]];
}

static void WindowSelfChecks(void) {
    NSDictionary<NSString *, NSString *> *verdicts = @{@"self": @"within budget",
                                                      @"self-cpu": @"over its CPU budget: 0.92 % against 0.3 %",
                                                      @"self-memory": @"over its memory budget: 58 MB against 45 MB",
                                                      @"self-wakeups": @"over its wakeup budget: 1.42 a second against 1"};
    for (NSString *name in @[@"self", @"self-cpu", @"self-memory", @"self-wakeups"]) {
        MMWindowModel *m = MMWindowFixture(name);
        MMWindowRow *row = [m row:MMWindowSelfKey];
        MMWindowGroup *apps = m.memoryGroups[2];
        BOOL over = ![name isEqualToString:@"self"];
        // Among the apps where its size puts it, with its own memory, CPU and hour.
        NSUInteger at = [apps.rows indexOfObject:row];
        BOOL placed = at != NSNotFound && (at == 0 || apps.rows[at - 1].bytes >= row.bytes) && (at + 1 >= apps.rows.count || apps.rows[at + 1].bytes <= row.bytes);
        Check(row && row.own && [row.name isEqualToString:@"MinMacs"] && placed && row.bytes == [m.own[@"memory"][@"footprintBytes"] unsignedLongLongValue]
              && row.cpuPercent >= 0 && MMWindowHourSpan(row.hour, NULL, NULL, NULL) != nil,
              [NSString stringWithFormat:@"window %@: MinMacs is a row of Apps and helpers where its size puts it, with its memory, CPU and own hour", name],
              [NSString stringWithFormat:@"at %lu of %lu", (unsigned long)at, (unsigned long)apps.rows.count]);
        // Judged against its budgets: the state word, the line and the mark.
        NSString *line = [MMWindowRowSecondLine(row, 600) stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "];
        NSString *want = verdicts[name];
        NSString *wantLine = [[want substringToIndex:1].uppercaseString stringByAppendingString:[want substringFromIndex:1]];
        Check([row.state isEqualToString:over ? @"over" : @"in budget"] && row.attention == over && !row.needsYou && !row.inFix
              && [[[row factLabelled:@"Budget"].value stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "] isEqualToString:want] && [line isEqualToString:wantLine] && row.quiet == !over,
              [NSString stringWithFormat:@"window %@: its word, its line and its mark say %@", name, want],
              [NSString stringWithFormat:@"%@ / %@ / attention %d", row.state, line, row.attention]);
        // The word stands in the list beside its CPU and hour: a word too wide would give way to the name, rule 8.
        MMWindowRowColumns c;
        MMWindowRowName(row, MMWindowMemory, YES, NSMakeRect(5, 0, WindowLists(PolishView(name)).firstObject.bounds.size.width - 10, 24), &c);
        Check(!NSIsEmptyRect(c.state) && !NSIsEmptyRect(c.cpu) && !NSIsEmptyRect(c.hour),
              [NSString stringWithFormat:@"window %@: the list shows its word, CPU and hour beside its whole name", name], NSStringFromRect(c.state));
        // It stays, and says why, honestly.
        Check(row.fate.kind == MMWindowFateStays && [row.fate.lead isEqualToString:@"Stays."] && [row.fate.note isEqualToString:MMWindowSelfStays],
              [NSString stringWithFormat:@"window %@: it stays, as the app that watches whose cost is checked against its budget", name], row.fate.note ?: @"none");
        // Its memory counts in the ring's apps slice like any app's.
        uint64_t appsSlice = 0;
        for (MMWindowSlice *x in m.ring.memory) if ([x.group isEqualToString:@"apps"]) appsSlice = x.bytes;
        uint64_t sum = 0;
        for (MMWindowRow *r in apps.rows) if (r != row) sum += r.bytes;
        Check(appsSlice > 0, [NSString stringWithFormat:@"window %@: the ring's apps slice holds MinMacs's memory", name], [NSString stringWithFormat:@"%llu of %llu", appsSlice, sum]);
    }

    // Fix Everything never names it.
    MMWindowModel *cpu = MMWindowFixture(@"self-cpu");
    BOOL inAFix = NO;
    for (MMWindowFix *f in cpu.fixes) if ([f.key containsString:@"self"]) inAFix = YES;
    Check(!inAFix && ![cpu row:MMWindowSelfKey].inFix, @"window self: Fix Everything never names MinMacs, over budget or not", @"");

    // The story: each fact as `minmacs self` gives it.
    MMWindowView *v = PolishView(@"self-cpu");
    MMWindowMiddleView *middle = WordViews(v, MMWindowMiddleView.class).firstObject;
    v.pointedRow = MMWindowSelfKey;
    NSString *told = [[CachesDrawn(middle) componentsJoinedByString:@" | "] stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "];
    NSArray *facts = @[@"Stays.", @"It is the app that watches. Its cost is checked against its budget.", @"over its CPU budget: 0.92 % against 0.3 %",
                       @"1.40 % now, 0.92 % since launch, against 0.3 %", @"0.40 a second now, 0.35 a second since launch, against 1",
                       @"38 MB now, 44 MB at most, against 45 MB", @"0.36 % CPU, 41.6 s in all, each counted once it ended",
                       @"14 MB since launch", @"2.0.0, build 412", @"3 h 12 min", @"Its last hour"];
    NSMutableArray *missing = [NSMutableArray new];
    for (NSString *f in facts) if (![told containsString:f]) [missing addObject:f];
    Check(!missing.count && ![told containsString:@"…"] && ![told containsString:@"..."],
          @"window self: its story tells CPU, wakeups and memory against their budgets, the tools it ran, disk written, version and how long it ran, whole",
          [missing componentsJoinedByString:@", "]);
    v.pointedRow = nil;

    // VoiceOver reads it as any row: its group, name, word, memory and CPU.
    NSString *said = nil;
    for (MMWindowListView *l in WindowLists(v)) for (NSAccessibilityElement *el in l.accessibilityChildren)
        if ([el.accessibilityLabel containsString:@"MinMacs"]) said = el.accessibilityLabel;
    Check([said hasPrefix:@"Apps and helpers, MinMacs, over budget, 38 MB"] && [said containsString:@"CPU 1.4 percent"],
          @"window self: VoiceOver reads MinMacs as it reads any row", said ?: @"not read");
}
