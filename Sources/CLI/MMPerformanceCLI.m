// `minmacs performance`: the Performance tab's model, Core/MMPerformance.h, as short numbers. It reads the snapshot and
// the gains table, and changes nothing but what every read of that table does. Memory and disk print apart.
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"

static NSString *Bytes(uint64_t n, BOOL memory) {
    return [NSByteCountFormatter stringFromByteCount:(long long)n
                                          countStyle:memory ? NSByteCountFormatterCountStyleMemory : NSByteCountFormatterCountStyleFile];
}

static NSString *Parts(MMPerformanceSideRing *r, BOOL memory) {
    NSMutableArray *a = [NSMutableArray new];
    for (NSString *k in r.order) [a addObject:[NSString stringWithFormat:@"%@ %@", k, Bytes([r.parts[k] unsignedLongLongValue], memory)]];
    return [a componentsJoinedByString:@", "];
}

int MMPerformanceVerb(MMArgs *a) {
    if (a.words.count) return [a usageError];
    MMSnapshot *s = a.snapshot;
    MMPerformance *p = [MMPerformance from:s history:a.inApp ? s.history : nil
                                  lookBack:[MMPerformanceLookBack read:MMGains.shared now:NSDate.date]];
    if (a.json) {
        NSMutableDictionary *j = [p.json mutableCopy];
        j[@"app"] = @(a.inApp);
        [a printJSON:j];
        return 0;
    }
    [a print:@"Memory  %@ used of %@: %@", Bytes(p.memory.used, YES), Bytes(p.memory.total, YES), Parts(p.memory, YES)];
    [a print:@"Disk    %@ used of %@, %@ free: %@", Bytes(p.disk.used, NO), Bytes(p.disk.total, NO),
             Bytes(p.disk.total - p.disk.used, NO), Parts(p.disk, NO)];
    if (p.needsYou) [a print:@"Needs you  %ld", (long)p.needsYou];
    NSInteger i = 0;
    for (MMPerformanceFix *f in p.fixes)
        [a print:@"%2ld  %-7@ memory %@, disk %@, %lu rows%@", (long)++i, f.kind, Bytes(f.memoryBack, YES), Bytes(f.diskBack, NO),
                 (unsigned long)f.rows.count, f.needsYou ? @", needs you" : @""];
    MMPerformanceLookBack *b = p.lookBack;
    [a print:@"Back    this week memory %@, disk %@; today memory %@, disk %@", Bytes(b.weekMemory, YES), Bytes(b.weekDisk, NO),
             Bytes(b.todayMemory, YES), Bytes(b.todayDisk, NO)];
    return 0;
}
