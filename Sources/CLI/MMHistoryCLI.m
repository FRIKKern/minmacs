// `minmacs history`: the last hour that Core holds in memory, from Graph/MMHistory.h.
// In the app it reads the copy the latest snapshot carries. A cold CLI has no hour, since nothing is kept on disk.
#import "CLI/MMCLI.h"
#import "Core/MMCore.h"

static NSString *Last(MMHistoryRing *r, BOOL cpu) {
    if (!r) return nil;
    for (NSInteger i = MMHistoryMinutes - 1; i >= 0; i--) {
        MMHistoryMinute m = [r minuteAt:(NSUInteger)i];
        if (!m.passes) continue;
        return cpu ? [NSString stringWithFormat:@"%.0f %%", m.cpuPercent]
                   : [NSByteCountFormatter stringFromByteCount:(long long)(m.megabytes * 1048576.0) countStyle:NSByteCountFormatterCountStyleMemory];
    }
    return nil;
}

static NSUInteger Filled(MMHistoryRing *r) {
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < MMHistoryMinutes; i++) if ([r minuteAt:i].passes) n++;
    return n;
}

int MMHistoryVerb(MMArgs *a) {
    MMHistoryView *v = a.inApp ? (a.snapshot.history ?: MMHistory.shared.latest) : MMHistory.shared.latest;
    if (a.json) {
        NSMutableDictionary *j = [v.json mutableCopy];
        j[@"app"] = @(a.inApp);
        [a printJSON:j];
        return 0;
    }
    if (!a.inApp) { [a print:@"No app is running. The last hour lives in the app's memory only, so there is none to show."]; return 0; }
    NSUInteger agents = 0, servers = 0, gone = 0;
    for (MMHistoryRing *r in v.trees) {
        if (r.kind == MMHistoryAgent) agents++; else servers++;
        if (r.goneAt > 0) gone++;
    }
    [a print:@"The last hour: %lu of %d minutes filled, %lu rings of %d.", (unsigned long)Filled(v.mac), MMHistoryMinutes,
             (unsigned long)v.rings, MMHistoryMaxRings];
    NSString *cpu = Last(v.mac, YES), *mem = Last(v.mac, NO), *disk = Last(v.disk, NO);
    if (cpu) [a print:@"Mac: CPU %@, memory used %@.", cpu, mem];
    if (disk) [a print:@"Disk: %@ free.", disk];
    [a print:@"%lu agents and %lu servers, %lu of them gone. %lu subagents started.", (unsigned long)agents,
             (unsigned long)servers, (unsigned long)gone, (unsigned long)v.subagentStarts.count];
    return 0;
}
