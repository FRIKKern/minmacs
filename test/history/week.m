// The 7 days, Graph/MMHistoryWeek.h, for test/history/history.m, which includes this file. Every value is a fixture:
// Mac values noted by hand at times around now, and points written by hand. The log is the test home's own.

static NSString *Vals(NSArray *values, NSRange r) {
    NSMutableArray *a = [NSMutableArray new];
    for (NSUInteger i = r.location; i < NSMaxRange(r); i++)
        [a addObject:[values[i] isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%.0f", [values[i] doubleValue] / 1048576.0] : @"-"];
    return [a componentsJoinedByString:@","];
}

static NSUInteger Count(MMLog *log, NSString *series) { return [log points:series since:nil].length / sizeof(MMTrendPoint); }

static void Week(void) {
    NSString *path = [MMSupportDir() stringByAppendingPathComponent:@"minmacs.sqlite"];
    MMLog *log = [[MMLog alloc] initWithPath:path];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    long long H = (long long)floor(now / 3600);
    NSTimeInterval base = (H - 5) * 3600.0;            // five hours ago: hours 0 to 4, the last the one before now's
    dispatch_queue_t q = MMQueue(@"core", @"history.week", QOS_CLASS_UTILITY);

    // A store of its own, as a test makes, keeps nothing until it is given a keeper.
    MMHistory *bare = [MMHistory new];
    NSUInteger w0 = MMHistoryWeekWrites();
    [bare noteMacCPU:10 memoryUsed:1000ull << 20 diskFree:5000ull << 20 at:base + 60];
    [bare noteMacCPU:10 memoryUsed:1000ull << 20 diskFree:5000ull << 20 at:base + 3700];
    dispatch_sync(q, ^{});
    Check(@"week: a store with no keeper writes no point", @"0", @(MMHistoryWeekWrites() - w0));

    // Hour 0 has four minutes, hour 1 two, hour 2 none (the Mac slept), hour 3 one, hour 4 one, still under way.
    MMHistory *h = [MMHistory new];
    h.onHour = MMHistoryWeekKeeper(log);
    double at[] = {0, 1, 30, 59, 65, 100, 190, 242};
    uint64_t mem[] = {1000, 2000, 3000, 4000, 6000, 8000, 9000, 9500}, disk[] = {500, 500, 500, 500, 480, 470, 460, 450};
    __block NSUInteger mainNotes = 0;
    for (NSUInteger i = 0; i < 8; i++) {
        [h noteMacCPU:20 memoryUsed:mem[i] << 20 diskFree:(disk[i] * 1000) << 20 at:base + at[i] * 60 + 5];
        mainNotes += NSThread.isMainThread;
    }
    dispatch_sync(q, ^{});
    Check(@"week: one write for each hour that ended, none for the hour the Mac slept or the one under way", @"3", @(MMHistoryWeekWrites() - w0));
    Check(@"week: the notes came from main, and every write still ran off main, on the week's own queue", @"8 0", [NSString stringWithFormat:@"%lu %lu",
          (unsigned long)mainNotes, (unsigned long)MMHistoryWeekMainWrites()]);
    Check(@"week: one point an hour in each series", @"3 3", [NSString stringWithFormat:@"%lu %lu",
          (unsigned long)Count(log, MMHistoryWeekMemory), (unsigned long)Count(log, MMHistoryWeekDisk)]);
    NSTimeInterval first = 0;
    NSArray *memory = MMHistoryWeekHours(log, MMHistoryWeekMemory, now, 7, &first), *free = MMHistoryWeekHours(log, MMHistoryWeekDisk, now, 7, NULL);
    Check(@"week: 7 days of 24 hours, the newest the hour before now's", @"168 yes", [NSString stringWithFormat:@"%lu %@",
          (unsigned long)memory.count, first == (H - 168) * 3600.0 ? @"yes" : @"no"]);
    Check(@"week: each hour holds the mean of its filled minutes, and a gap where nothing was kept", @"2500,7000,-,9000,-", Vals(memory, NSMakeRange(163, 5)));
    Check(@"  and the disk side the same", @"500000,475000,-,460000,-", Vals(free, NSMakeRange(163, 5)));
    Check(@"  and every hour before the first is a gap", @"0", @(({ NSUInteger n = 0; for (NSUInteger i = 0; i < 163; i++) n += memory[i] != NSNull.null; n; })));

    // The same hour handed over twice replaces its point: INSERT OR REPLACE, bucketed by the hour.
    MMHistoryWeekWrite(log, base, 1234.0 * 1048576, -1, now);
    Check(@"week: a second write of one hour replaces its point", @"3 1234", [NSString stringWithFormat:@"%lu %@", (unsigned long)Count(log, MMHistoryWeekMemory),
          Vals(MMHistoryWeekHours(log, MMHistoryWeekMemory, now, 7, NULL), NSMakeRange(163, 1))]);

    // A restart: a new log on the same file reads the same points.
    MMLog *again = [[MMLog alloc] initWithPath:path];
    Check(@"week: the points outlive a restart", @"1234,7000,-,9000,-", Vals(MMHistoryWeekHours(again, MMHistoryWeekMemory, now, 7, NULL), NSMakeRange(163, 5)));

    // Pruning: points older than 8 days go at the next write, the ones inside stay, and another series is left alone.
    for (NSNumber *days in @[@9.5, @8.2]) [log addPoint:MMHistoryWeekMemory value:1 at:[NSDate dateWithTimeIntervalSince1970:now - days.doubleValue * 86400] bucket:3600];
    [log addPoint:MMHistoryWeekMemory value:1 at:[NSDate dateWithTimeIntervalSince1970:now - 7.8 * 86400] bucket:3600];
    [log addPoint:@"noonoo.disk.fixture" value:1 at:[NSDate dateWithTimeIntervalSince1970:now - 30 * 86400] bucket:86400];
    NSUInteger before = Count(log, MMHistoryWeekMemory);
    MMHistoryWeekWrite(log, base + 3 * 3600, 9000.0 * 1048576, 460000.0 * 1048576, now);
    Check(@"week: a write prunes the points past 8 days, keeps the 7.8-day-old one, and leaves another series alone", @"6 4 1",
          [NSString stringWithFormat:@"%lu %lu %lu", (unsigned long)before, (unsigned long)Count(log, MMHistoryWeekMemory), (unsigned long)Count(log, @"noonoo.disk.fixture")]);
    NSUInteger (^held)(NSArray *) = ^NSUInteger(NSArray *v) { NSUInteger n = 0; for (id x in v) n += x != NSNull.null; return n; };
    Check(@"  and 8 days still see the 7.8-day-old point, which 7 days leave out", @"4 3", [NSString stringWithFormat:@"%lu %lu",
          (unsigned long)held(MMHistoryWeekHours(log, MMHistoryWeekMemory, now, 8, NULL)), (unsigned long)held(MMHistoryWeekHours(log, MMHistoryWeekMemory, now, 7, NULL))]);

    // The JSON shape `minmacs history --days 7 --json` prints.
    NSDictionary *j = MMHistoryWeekJSON(log, now, 7);
    Check(@"week: the JSON's keys", @"days diskFreeMB from held hours keepDays memoryUsedMB points stepSeconds to",
          [[j.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);
    Check(@"  168 values a side, null for a gap, and only the kept hours in points", @"168 168 3 3 <null> 3",
          [NSString stringWithFormat:@"%lu %lu %@ %@ %@ %lu", (unsigned long)[j[@"memoryUsedMB"] count], (unsigned long)[j[@"diskFreeMB"] count], j[@"held"][@"memory"],
           j[@"held"][@"disk"], j[@"memoryUsedMB"][165], (unsigned long)[j[@"points"] count]]);
    Check(@"  a point says when and both sides", @"at diskFreeMB memoryUsedMB 1234", [NSString stringWithFormat:@"%@ %@",
          [[[[j[@"points"] firstObject] allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "], [j[@"points"] firstObject][@"memoryUsedMB"]]);
    Check(@"  it spans from the first hour to the hour now is in", @"yes", [j[@"to"] doubleValue] == H * 3600.0 && [j[@"from"] doubleValue] == (H - 168) * 3600.0 ? @"yes" : @"no");
}
