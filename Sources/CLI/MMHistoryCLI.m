// `minmacs history`: the last hour that Core holds in memory, from Graph/MMHistory.h.
// In the app it reads the copy the latest snapshot carries. A cold CLI has no hour, since the hour is in memory only.
// `minmacs history --days 7`: the hourly points of Graph/MMHistoryWeek.h, read from the log, so a cold CLI has them too.
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

/// The hours that hold a value, and how long ago the first of them began, as a line says it.
static NSString *Held(NSArray *values, NSString *name, BOOL disk) {
    NSInteger first = -1, n = 0, last = -1;
    for (NSInteger i = 0; i < (NSInteger)values.count; i++) if (values[i] != NSNull.null) { if (first < 0) first = i; last = i; n++; }
    if (!n) return [NSString stringWithFormat:@"%@: no hour kept yet.", name];
    NSString *now = [NSByteCountFormatter stringFromByteCount:[values[last] longLongValue]
                                                   countStyle:disk ? NSByteCountFormatterCountStyleFile : NSByteCountFormatterCountStyleMemory];
    return [NSString stringWithFormat:@"%@: %ld of %lu hours kept, the first %ld h ago, the newest %@.", name, (long)n,
            (unsigned long)values.count, (long)((NSInteger)values.count - first), now];
}

static int Week(MMArgs *a, NSString *d) {
    NSScanner *sc = [NSScanner scannerWithString:d];
    NSInteger days = 0;
    if (![sc scanInteger:&days] || !sc.isAtEnd || days < 1 || days > MMHistoryWeekKeepDays) {
        [a error:@"--days takes a whole number from 1 to %d", MMHistoryWeekKeepDays];
        return [a usageError];
    }
    MMLog *log = MMLog.shared;
    if (!log) { [a error:@"the log is not open yet"]; return 1; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (a.json) {
        NSMutableDictionary *j = [MMHistoryWeekJSON(log, now, days) mutableCopy];
        j[@"app"] = @(a.inApp);
        [a printJSON:j];
        return 0;
    }
    [a print:@"The last %ld day%@, one value an hour, kept in the log. An hour with none is one the Mac was off or asleep, or MinMacs was not running.",
             (long)days, days == 1 ? @"" : @"s"];
    [a print:@"%@", Held(MMHistoryWeekHours(log, MMHistoryWeekMemory, now, days, NULL), @"Memory used", NO)];
    [a print:@"%@", Held(MMHistoryWeekHours(log, MMHistoryWeekDisk, now, days, NULL), @"Disk free", YES)];
    return 0;
}

int MMHistoryVerb(MMArgs *a) {
    if (a.words.count) return [a usageError];
    NSString *days = [a option:@"--days"];
    if (days) return Week(a, days);
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
