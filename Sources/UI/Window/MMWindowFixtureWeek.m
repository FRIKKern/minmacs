// The render's made-up 7 days, MMWindowFixtureParts.h: the calm day with its strip on the 7 days, full, two days
// young, and with a gap of a night and a morning the Mac was off and an hour alone between two gaps.
// Nothing here is measured: memory rises by day and falls at night, and disk free falls a little each day.
#import "UI/Window/MMWindowFixtureParts.h"

/// A fixed hour, so every render draws the same days: midnight UTC at the start of 2026-11-22.
static const NSTimeInterval kFirstAt = 1795305600;

static NSArray *WeekValues(BOOL disk, double now, NSInteger heldFrom, NSIndexSet *gaps) {
    NSMutableArray *v = [NSMutableArray new];
    uint32_t seed = disk ? 7u : 3u;
    for (NSInteger i = 0; i < MMWindowWeekHours; i++) {
        seed = seed * 1664525u + 1013904223u;
        double noise = ((seed >> 8) & 0xFFFF) / 65535.0 - 0.5, left = (MMWindowWeekHours - 1 - i) / 24.0;
        if (i < heldFrom || [gaps containsIndex:(NSUInteger)i]) { [v addObject:NSNull.null]; continue; }
        // Memory: a working day's climb and a night's fall around the value now. Disk: 4 GB less free each day.
        double x = disk ? now + left * 4.0e9 + noise * 0.3e9
                        : now * (0.82 + 0.22 * sin((i % 24 - 8) / 24.0 * 2 * M_PI)) + noise * 0.6 * MMFixGB;
        [v addObject:@((uint64_t)MAX(x, 0))];
    }
    v[MMWindowWeekHours - 1] = @((uint64_t)now);
    return v;
}

void MMWindowFixtureWeek(MMWindowModel *m, NSString *name) {
    BOOL young = [name isEqualToString:@"week-young"], gap = [name isEqualToString:@"week-gap"];
    NSInteger from = young ? MMWindowWeekHours - 48 : 0;
    NSMutableIndexSet *gaps = [NSMutableIndexSet new];
    if (gap) {
        [gaps addIndexesInRange:NSMakeRange(70, 18)];          // a night and a morning, off
        [gaps addIndexesInRange:NSMakeRange(110, 3)];          // asleep, then one hour awake, then asleep again
        [gaps addIndexesInRange:NSMakeRange(114, 4)];
    }
    m.stripWeek = YES;
    MMWindowHour *memory = [MMWindowHour new], *disk = [MMWindowHour new];
    memory.side = MMWindowMemory; memory.title = MMWindowHourTitle(NO); memory.explain = MMWindowHourExplain(NO, m.ring.memoryTotal);
    disk.side = MMWindowDisk; disk.title = MMWindowHourTitle(YES); disk.explain = MMWindowHourExplain(YES, m.ring.diskTotal);
    memory.values = WeekValues(NO, (double)m.ring.memoryUsed, from, gaps);
    disk.values = WeekValues(YES, (double)m.ring.diskFree, from, gaps);
    memory.firstAt = disk.firstAt = kFirstAt;
    m.memoryWeek = memory; m.diskWeek = disk;
}
