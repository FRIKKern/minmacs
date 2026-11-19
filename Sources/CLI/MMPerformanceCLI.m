// `minmacs performance`: the Performance tab's model, Core/MMPerformance.h, as short numbers. It reads the snapshot and
// the gains table, and changes nothing but what every read of that table does. Memory and disk print apart.
// A worktree's size is not measured until its first walk ends. A number that holds such a worktree prints with the
// menu window's own words, UI/Window/MMWindowModel.h, issue #76: a part of the ring counts its measured rows "so far",
// or is "measuring" with none, and a fix gives back that much "or more", or is "not measured yet".
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"
#import "UI/Window/MMWindowModel.h"

static NSString *Bytes(uint64_t n, BOOL memory) {
    return [NSByteCountFormatter stringFromByteCount:(long long)n
                                          countStyle:memory ? NSByteCountFormatterCountStyleMemory : NSByteCountFormatterCountStyleFile];
}

static NSString *Parts(MMPerformanceSideRing *r, NSArray<MMPerformanceGroup *> *groups, BOOL memory) {
    NSMutableArray *a = [NSMutableArray new];
    for (NSString *k in r.order) {
        NSInteger count = 0, unmeasured = 0;
        for (MMPerformanceGroup *g in groups) if ([g.key isEqualToString:k]) { count = (NSInteger)g.rows.count; unmeasured = g.unmeasured; }
        [a addObject:[NSString stringWithFormat:@"%@ %@", k, MMWindowSumText(Bytes([r.parts[k] unsignedLongLongValue], memory), count, unmeasured)]];
    }
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
    [a print:@"Memory  %@ used of %@: %@", Bytes(p.memory.used, YES), Bytes(p.memory.total, YES), Parts(p.memory, p.memoryGroups, YES)];
    [a print:@"Disk    %@ used of %@, %@ free: %@", Bytes(p.disk.used, NO), Bytes(p.disk.total, NO),
             Bytes(p.disk.total - p.disk.used, NO), Parts(p.disk, p.diskGroups, NO)];
    if (p.needsYou) [a print:@"Needs you  %ld", (long)p.needsYou];
    NSInteger i = 0;
    for (MMPerformanceFix *f in p.fixes)
        [a print:@"%2ld  %-7@ memory %@, disk %@, %lu rows%@", (long)++i, f.kind, Bytes(f.memoryBack, YES),
                 MMWindowBackText(Bytes(f.diskBack, NO), f.diskBack == 0, f.diskPartial), (unsigned long)f.rows.count, f.needsYou ? @", needs you" : @""];
    MMPerformanceLookBack *b = p.lookBack;
    [a print:@"Back    this week memory %@, disk %@; today memory %@, disk %@", Bytes(b.weekMemory, YES), Bytes(b.weekDisk, NO),
             Bytes(b.todayMemory, YES), Bytes(b.todayDisk, NO)];
    return 0;
}
