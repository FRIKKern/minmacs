// The hourly points of the last days, MMHistoryWeek.h. Written from what MMHistory already holds, never sampled.
#import "Core/Graph/MMHistoryWeek.h"
#import "Core/Runtime/MMRuntime.h"
#import <stdatomic.h>

NSString *const MMHistoryWeekMemory = @"core.memory.used";
NSString *const MMHistoryWeekDisk = @"core.disk.free";

static atomic_uint gWrites, gMainWrites, gReads;
NSUInteger MMHistoryWeekWrites(void) { return atomic_load(&gWrites); }
NSUInteger MMHistoryWeekMainWrites(void) { return atomic_load(&gMainWrites); }
NSUInteger MMHistoryWeekReads(void) { return atomic_load(&gReads); }

static dispatch_queue_t Queue(void) { return MMQueue(@"core", @"history.week", QOS_CLASS_UTILITY); }

void MMHistoryWeekWrite(MMLog *log, NSTimeInterval hourStart, double memoryUsed, double diskFree, NSTimeInterval now) {
    if (!log) return;
    atomic_fetch_add(&gWrites, 1);
    if (NSThread.isMainThread) atomic_fetch_add(&gMainWrites, 1);
    NSDate *at = [NSDate dateWithTimeIntervalSince1970:hourStart];
    if (memoryUsed >= 0) [log addPoint:MMHistoryWeekMemory value:memoryUsed at:at bucket:3600];
    if (diskFree >= 0) [log addPoint:MMHistoryWeekDisk value:diskFree at:at bucket:3600];
    NSDate *keep = [NSDate dateWithTimeIntervalSince1970:now - MMHistoryWeekKeepDays * 86400.0];
    [log prunePoints:MMHistoryWeekMemory before:keep];
    [log prunePoints:MMHistoryWeekDisk before:keep];
}

MMHistoryHourDone MMHistoryWeekKeeper(MMLog *log) {
    return ^(NSTimeInterval hourStart, double memoryUsed, double diskFree) {
        // The graph queue hands it over mid-build. The write waits on its own queue, so the build never waits on SQLite.
        dispatch_async(Queue(), ^{
            MMLog *to = log ?: MMLog.shared;
            MMHistoryWeekWrite(to, hourStart, memoryUsed, diskFree, NSDate.date.timeIntervalSince1970);
        });
    };
}

void MMHistoryWeekStart(void) { MMHistory.shared.onHour = MMHistoryWeekKeeper(nil); }
void MMHistoryWeekStop(void) { MMHistory.shared.onHour = nil; }

NSArray *MMHistoryWeekHours(MMLog *log, NSString *series, NSTimeInterval now, NSInteger days, NSTimeInterval *firstAt) {
    NSInteger hours = MAX(days, 1) * 24;
    long long last = (long long)floor(now / 3600) - 1, first = last - hours + 1;
    if (firstAt) *firstAt = (NSTimeInterval)first * 3600;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:(NSUInteger)hours];
    for (NSInteger i = 0; i < hours; i++) [out addObject:NSNull.null];
    atomic_fetch_add(&gReads, 1);
    NSData *data = [log points:series since:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)first * 3600]];
    const MMTrendPoint *p = data.bytes;
    for (NSUInteger i = 0; i < data.length / sizeof *p; i++) {
        long long h = (long long)floor(p[i].at / 3600);
        if (h < first || h > last || p[i].value < 0) continue;
        out[(NSUInteger)(h - first)] = @((uint64_t)llround(p[i].value));
    }
    return out;
}

static id MB(id v) { return [v isKindOfClass:NSNumber.class] ? @(round([v doubleValue] / 1048576.0)) : NSNull.null; }

NSDictionary *MMHistoryWeekJSON(MMLog *log, NSTimeInterval now, NSInteger days) {
    NSTimeInterval from = 0;
    NSArray *memory = MMHistoryWeekHours(log, MMHistoryWeekMemory, now, days, &from), *disk = MMHistoryWeekHours(log, MMHistoryWeekDisk, now, days, NULL);
    NSMutableArray *memoryMB = [NSMutableArray new], *diskMB = [NSMutableArray new], *points = [NSMutableArray new];
    NSUInteger heldMemory = 0, heldDisk = 0;
    for (NSUInteger i = 0; i < memory.count; i++) {
        id m = MB(memory[i]), d = MB(disk[i]);
        [memoryMB addObject:m]; [diskMB addObject:d];
        heldMemory += m != NSNull.null; heldDisk += d != NSNull.null;
        if (m != NSNull.null || d != NSNull.null) [points addObject:@{@"at": @(from + i * 3600.0), @"memoryUsedMB": m, @"diskFreeMB": d}];
    }
    return @{@"days": @(MAX(days, 1)), @"hours": @(memory.count), @"stepSeconds": @3600, @"keepDays": @(MMHistoryWeekKeepDays),
             @"from": @(from), @"to": @(from + memory.count * 3600.0), @"memoryUsedMB": memoryMB, @"diskFreeMB": diskMB,
             @"held": @{@"memory": @(heldMemory), @"disk": @(heldDisk)}, @"points": points};
}
